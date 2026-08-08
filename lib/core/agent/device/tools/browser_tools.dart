import 'package:cyberneurova_mobile/core/agent/device/agent_browser.dart';
import 'package:cyberneurova_mobile/core/agent/device/device_capabilities.dart';
import 'package:cyberneurova_mobile/core/agent/device/device_executor.dart';

/// Whether [host] is somewhere scope has an opinion about.
///
/// ## The distinction this encodes
///
/// Scope exists to stop the agent sending packets at infrastructure the user
/// did not authorise. That is about the user's LAN and named targets — not
/// about reading a public web page, which is the same act as a web search and
/// which no one expects to whitelist a domain for.
///
/// So the rule is by DESTINATION, not by tool: a private, loopback or
/// link-local address is a probe of the user's own network and goes through
/// the scope check exactly as `http_probe` would. A public hostname does not.
///
/// Getting this backwards either makes the browser useless (every page needs
/// authorising) or makes it a hole (browse to 192.168.1.1 and skip the check
/// the scan tools enforce).
bool isPrivateDestination(String host) {
  final h = host.trim().toLowerCase();
  if (h.isEmpty) return true; // unparseable: treat as sensitive, not as public
  if (h == 'localhost' || h.endsWith('.local') || h.endsWith('.localhost')) {
    return true;
  }

  final parts = h.split('.');
  if (parts.length != 4) return false; // a name, not an IPv4 literal
  final octets = <int>[];
  for (final p in parts) {
    final v = int.tryParse(p);
    if (v == null || v < 0 || v > 255) return false;
    octets.add(v);
  }

  final [a, b, _, _] = octets;
  return a == 10 ||
      a == 127 ||
      (a == 172 && b >= 16 && b <= 31) ||
      (a == 192 && b == 168) ||
      (a == 169 && b == 254) ||
      (a == 100 && b >= 64 && b <= 127); // CGNAT, common on mobile networks
}

/// Opens a page in the real browser and reads it.
///
/// The value over `http_probe` is JavaScript: a large share of the web returns
/// an empty shell and builds its content in script, so a raw GET reports "this
/// page is blank" for a page a person can plainly read. This one runs the
/// scripts, then returns what the page actually says.
///
/// The user can watch it happen and take over — same browser, same cookies.
class BrowserOpenTool implements DeviceTool {
  BrowserOpenTool({AgentBrowser? browser})
      : _browser = browser ?? AgentBrowser.instance;

  final AgentBrowser _browser;

  @override
  String get name => 'browser_open';

  @override
  Set<DeviceCapability> get requires => {DeviceCapability.httpClient};

  /// Deliberately null: the executor's blanket scope check would refuse every
  /// public URL, since an empty scope means "this device only". The check is
  /// applied below, to private destinations only — see [isPrivateDestination].
  @override
  String? get targetArgKey => null;

  @override
  bool targetIsRange(Map<String, dynamic> args) => false;

  @override
  Future<DeviceToolResult> run(
    Map<String, dynamic> args,
    DeviceToolContext context,
  ) async {
    final raw = (args['url'] as String?)?.trim() ?? '';
    if (raw.isEmpty) return const DeviceToolResult.failure('url is required');

    // A bare host is the common case coming out of a scan result, so default
    // the scheme rather than making the model remember to add it.
    final uri = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
    if (uri == null || uri.host.isEmpty) {
      return DeviceToolResult.failure('Not a usable URL: $raw');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return DeviceToolResult.failure(
        'Only http and https can be opened, not "${uri.scheme}".',
      );
    }

    if (isPrivateDestination(uri.host)) {
      final verdict = context.scope
          .check(uri.host, localSubnetCidrs: context.localSubnetCidrs);
      if (!verdict.isAllowed) {
        return DeviceToolResult.failure(
          '${verdict.reason} ${uri.host} is on a private network, so it needs '
          'to be in the session scope before I open it.',
        );
      }
    }

    context.onProgress('Opening $uri');
    final error = await _browser.open(uri.toString());
    if (context.isCancelled()) {
      return const DeviceToolResult.failure('Cancelled.');
    }
    if (error != null) {
      return DeviceToolResult.failure('Could not load $uri — $error');
    }

    final landed = _browser.currentUrl.value ?? uri.toString();
    final title = _browser.title.value ?? '';
    final text = await _browser.readText();
    final links = (args['links'] as bool?) ?? false
        ? await _browser.readLinks()
        : const <({String text, String href})>[];

    final buf = StringBuffer();
    if (title.isNotEmpty) buf.writeln('TITLE: $title');
    // Reported because a redirect is information: a login wall, a consent
    // interstitial and a country redirect all look like a successful load
    // until you notice the URL changed.
    if (landed != uri.toString()) buf.writeln('LANDED ON: $landed');
    buf
      ..writeln()
      ..writeln(text.isEmpty ? '(the page rendered no readable text)' : text);

    if (links.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('LINKS:');
      for (final l in links) {
        buf.writeln('- ${l.text} → ${l.href}');
      }
    }

    return DeviceToolResult(
      ok: true,
      summary: title.isEmpty ? landed : title,
      output: buf.toString().trimRight(),
    );
  }
}
