import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// One model an endpoint is serving.
class LocalModel {
  const LocalModel({required this.id, this.sizeBytes});

  final String id;

  /// Ollama reports it; llama-server and LM Studio do not.
  final int? sizeBytes;
}

/// What a probe found.
class LocalEndpoint {
  const LocalEndpoint({
    required this.baseUrl,
    required this.models,
    this.answered = true,
    this.flavour,
  });

  const LocalEndpoint.none(this.baseUrl)
      : models = const [],
        answered = false,
        flavour = null;

  /// The endpoint replied like a model server but is serving nothing.
  ///
  /// A real state, not an edge case: a fresh Ollama answers /v1/models with an
  /// empty list until you pull something. Folding it into "not answering" told
  /// the user to check their network when the actual fix is `ollama pull`.
  const LocalEndpoint.empty(this.baseUrl, {this.flavour})
      : models = const [],
        answered = true;

  /// Base URL WITHOUT a trailing slash, e.g. `http://127.0.0.1:8080`.
  final String baseUrl;

  final List<LocalModel> models;

  /// Whether anything answered at all, regardless of what it is serving.
  final bool answered;

  /// Which server this looks like — shown to the user so they can tell one
  /// running instance from another when several are up.
  final String? flavour;

  /// Answered AND has something to run. This is the bar for offering it.
  bool get isUsable => answered && models.isNotEmpty;

  /// Up, but with nothing loaded. Deserves its own message.
  bool get isEmpty => answered && models.isEmpty;
}

/// Finding a local or LAN model server.
///
/// ## Why this shape
///
/// Nothing here runs a model. It finds one that is already running and speaks
/// the OpenAI API, which is what every practical local runtime already does —
/// `llama-server`, Ollama, LM Studio, vLLM. The app already talks that
/// protocol, so "use a local model" reduces to "point at a different base URL"
/// rather than to a second inference stack inside the app.
///
/// That covers the two cases people actually have today: a server they started
/// inside their own distro on this phone, and one running on their laptop on
/// the same network. Bundling a runtime is a further step, and it plugs into
/// exactly this seam when it lands.
///
/// ## Offline by construction
///
/// A model on 127.0.0.1 needs no internet at all, and one on the LAN needs no
/// internet either. That is the whole point for someone whose connection is
/// metered or absent — and it is only possible because the work happens on the
/// user's own device and network.
class LocalLlm {
  const LocalLlm._();

  /// Ports worth trying before asking the user to type anything.
  ///
  /// Ordered by what someone on a phone is most likely to be running. These
  /// are the defaults the projects themselves ship, so a user who followed any
  /// quick-start is found without configuring anything.
  static const List<({int port, String flavour})> knownPorts = [
    (port: 8080, flavour: 'llama.cpp'),
    (port: 11434, flavour: 'Ollama'),
    (port: 1234, flavour: 'LM Studio'),
    (port: 8000, flavour: 'vLLM'),
    (port: 5000, flavour: 'text-generation-webui'),
  ];

  /// Normalises whatever the user typed into a base URL we can use.
  ///
  /// People paste `localhost:11434`, `http://1.2.3.4:8080/v1/`, and
  /// `192.168.1.5`. All three should work — refusing them on a phone keyboard
  /// is a good way to make a feature unusable.
  static String? normalizeBaseUrl(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (!s.contains('://')) s = 'http://$s';

    final uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty) return null;

    // Strip a trailing /v1 — we append it ourselves, and pasting the full
    // OpenAI base URL is the most natural thing to do.
    var path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (path.endsWith('/v1')) path = path.substring(0, path.length - 3);

    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port$path';
  }

  /// Asks [baseUrl] what models it has.
  ///
  /// Never throws: an endpoint that is not there is an ordinary answer, and
  /// every caller has to render it either way.
  static Future<LocalEndpoint> probe(
    String baseUrl, {
    Duration timeout = const Duration(seconds: 4),
    HttpClient? client,
  }) async {
    final normalized = normalizeBaseUrl(baseUrl);
    if (normalized == null) return LocalEndpoint.none(baseUrl);

    final http = client ?? HttpClient()
      ..connectionTimeout = timeout;

    try {
      final uri = Uri.parse('$normalized/v1/models');
      final req = await http.getUrl(uri).timeout(timeout);
      final res = await req.close().timeout(timeout);
      if (res.statusCode != 200) return LocalEndpoint.none(normalized);

      final body = await res
          .transform(const Utf8Decoder(allowMalformed: true))
          .join()
          .timeout(timeout);

      final flavour = flavourForPort(Uri.parse(normalized).port);
      final models = parseModels(body);
      // A 200 from /v1/models means a model server is there. Whether it has
      // anything loaded is a different question with a different answer.
      if (models.isEmpty) {
        return LocalEndpoint.empty(normalized, flavour: flavour);
      }
      return LocalEndpoint(
        baseUrl: normalized,
        models: models,
        flavour: flavour,
      );
    } on TimeoutException {
      return LocalEndpoint.none(normalized);
    } on SocketException {
      // Nothing listening. The overwhelmingly common case while sweeping
      // ports, and not worth distinguishing from any other refusal.
      return LocalEndpoint.none(normalized);
    } on HttpException {
      return LocalEndpoint.none(normalized);
    } on FormatException {
      return LocalEndpoint.none(normalized);
    } finally {
      if (client == null) http.close(force: true);
    }
  }

  /// Tries [knownPorts] on the loopback interface, in parallel.
  ///
  /// In parallel because a sweep done serially spends five timeouts before
  /// admitting nothing is there, and on a phone that reads as the app being
  /// broken. Returns every endpoint that answered — several can be, and
  /// picking for the user would be guessing.
  static Future<List<LocalEndpoint>> discoverLocal({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final results = await Future.wait([
      for (final p in knownPorts)
        probe('http://127.0.0.1:${p.port}', timeout: timeout),
    ]);
    // Empty servers are included: "Ollama is up, pull a model" is far more
    // useful than silence, and the user can act on it.
    return [for (final r in results) if (r.answered) r];
  }

  /// Parses an OpenAI `/v1/models` body.
  ///
  /// Tolerant on purpose: Ollama, llama-server and LM Studio all return the
  /// same envelope with different extras, and a strict parser would reject
  /// two of the three over a field nobody reads.
  static List<LocalModel> parseModels(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return const [];
      final data = decoded['data'];
      if (data is! List) return const [];
      final out = <LocalModel>[];
      for (final entry in data) {
        if (entry is! Map) continue;
        final id = entry['id'];
        if (id is! String || id.isEmpty) continue;
        final size = entry['size'];
        out.add(LocalModel(
          id: id,
          sizeBytes: size is int ? size : null,
        ));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static String? flavourForPort(int port) {
    for (final p in knownPorts) {
      if (p.port == port) return p.flavour;
    }
    return null;
  }
}
