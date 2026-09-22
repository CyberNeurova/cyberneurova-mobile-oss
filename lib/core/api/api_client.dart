import 'dart:io';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cyberneurova_mobile/core/constants/api_constants.dart';
import 'package:cyberneurova_mobile/core/api/interceptors/auth_interceptor.dart';
import 'package:cyberneurova_mobile/core/api/interceptors/error_interceptor.dart';
import 'package:cyberneurova_mobile/core/api/interceptors/mobile_context_interceptor.dart';
import 'package:cyberneurova_mobile/core/errors/app_exception.dart';
import 'package:cyberneurova_mobile/core/storage/secure_storage.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  final storage = ref.watch(secureStorageProvider);
  // Tell the interceptor how to keep the synchronous token mirror
  // current after a transparent refresh (401 → /auth/refresh → retry).
  // Without this, image widgets keep the pre-refresh Bearer and 401
  // until the user does something that re-enters AuthRepository.
  return ApiClient(
    storage: storage,
    onAccessTokenChanged: (token) =>
        ref.read(currentAccessTokenProvider.notifier).state = token,
  );
});

class ApiClient {
  ApiClient({required SecureStorage storage, void Function(String?)? onAccessTokenChanged}) {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: ApiConstants.connectTimeout,
        receiveTimeout: ApiConstants.receiveTimeout,
        sendTimeout: ApiConstants.sendTimeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          // Load-bearing: tells the backend to skip Turnstile, apply
          // mobile rate-limit buckets, skip CSRF, return JSON errors.
          'X-Client-Type': 'mobile',
        },
      ),
    );

    // Say who we are.
    //
    // Active sessions listed this phone as "Browser", alongside three other
    // "Browser" rows — on the one screen whose job is letting a user spot a
    // session that is not theirs. The server names sessions from the
    // User-Agent, and ours was Dart's default, which its parser does not know.
    //
    // `X-Client-Type: mobile` is already sent and already tells the server
    // this is the app, so the naming is theirs to fix too (outbox 060) — but
    // sending a User-Agent that identifies the app and platform is correct
    // regardless, and it is what their parser actually reads.
    _dio.interceptors.add(
      InterceptorsWrapper(onRequest: (options, handler) async {
        options.headers['User-Agent'] = await _userAgent();
        handler.next(options);
      }),
    );

    _dio.interceptors.addAll([
      AuthInterceptor(
        storage: storage,
        dio: _dio,
        onAccessTokenChanged: onAccessTokenChanged,
      ),
      MobileContextInterceptor(),
      ErrorInterceptor(),
    ]);
  }

  late final Dio _dio;

  /// Throws the inner [AppException] (set by [ErrorInterceptor]) instead
  /// of the wrapping [DioException], so `e.toString()` in the UI yields
  /// a clean human-readable message.
  Never _rethrow(DioException e) {
    if (e.error is AppException) throw e.error as AppException;
    throw e;
  }

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.get<T>(path,
          queryParameters: queryParameters, options: options);
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.post<T>(path,
          data: data,
          queryParameters: queryParameters,
          options: options);
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
    Options? options,
  }) async {
    try {
      return await _dio.patch<T>(path, data: data, options: options);
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Options? options,
  }) async {
    try {
      return await _dio.delete<T>(path, data: data, options: options);
    } on DioException catch (e) {
      _rethrow(e);
    }
  }

  /// Returns a raw stream of NDJSON lines. Each line is a complete JSON
  /// object: `{"type":"token","content":"..."}`.
  ///
  /// **UTF-8 handling:** chunk boundaries can split multi-byte sequences
  /// (emoji is 4 bytes; accented chars are 2). We buffer raw bytes until
  /// we hit a newline (0x0A), then decode the line as UTF-8. Previous
  /// implementation used `String.fromCharCodes(chunk)` which interprets
  /// bytes as Latin-1 — produced "ð" mojibake instead of "😊".
  Stream<String> stream(String path, {dynamic data}) async* {
    final Response<ResponseBody> response;
    try {
      response = await _dio.post<ResponseBody>(
        path,
        data: data,
        // Force a fresh TCP socket per call. Dio keeps connections alive
        // by default which is normally good — but the chat-team's NDJSON
        // /complete endpoint returns empty on the second call when the
        // connection is reused. Cheap experiment to see if it unblocks
        // the second-message-fails bug while we wait for server-side
        // investigation.
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Connection': 'close'},
        ),
      );
    } on DioException catch (e) {
      _rethrow(e);
    }

    final byteBuffer = <int>[];
    await for (final chunk in response.data!.stream) {
      byteBuffer.addAll(chunk);
      while (true) {
        final newlineIdx = byteBuffer.indexOf(0x0A);
        if (newlineIdx == -1) break;
        final lineBytes = byteBuffer.sublist(0, newlineIdx);
        byteBuffer.removeRange(0, newlineIdx + 1);
        try {
          final line = utf8.decode(lineBytes, allowMalformed: true).trim();
          if (line.isNotEmpty) yield line;
        } catch (_) {
          // Skip a single malformed line rather than killing the stream.
        }
      }
    }
    if (byteBuffer.isNotEmpty) {
      final tail = utf8.decode(byteBuffer, allowMalformed: true).trim();
      if (tail.isNotEmpty) yield tail;
    }
  }

  /// Returns parsed Server-Sent Events (`event:`/`data:` framing), for the
  /// bot-section `/bot/stream` endpoint. Distinct from [stream] (NDJSON): SSE
  /// separates events with a blank line and prefixes payload lines with
  /// `data:` — which may span several lines (joined with `\n`). `:`-comment
  /// keepalive lines and `id:`/`retry:` fields are ignored; only `event:` and
  /// `data:` are surfaced.
  ///
  /// Byte-buffered like [stream] so multi-byte UTF-8 split across chunk
  /// boundaries decodes correctly. It's a GET (the stream is read-only) and
  /// yields until the socket closes or errors — reconnection (resume from the
  /// last seq) is the caller's job.
  Stream<SseEvent> streamSse(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async* {
    final Response<ResponseBody> response;
    try {
      response = await _dio.get<ResponseBody>(
        path,
        queryParameters: queryParameters,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Accept': 'text/event-stream'},
        ),
      );
    } on DioException catch (e) {
      _rethrow(e);
    }

    final byteBuffer = <int>[];
    String? eventName;
    final dataLines = <String>[];

    await for (final chunk in response.data!.stream) {
      byteBuffer.addAll(chunk);
      while (true) {
        final nl = byteBuffer.indexOf(0x0A);
        if (nl == -1) break;
        final lineBytes = byteBuffer.sublist(0, nl);
        byteBuffer.removeRange(0, nl + 1);
        var line = utf8.decode(lineBytes, allowMalformed: true);
        if (line.endsWith('\r')) line = line.substring(0, line.length - 1);

        if (line.isEmpty) {
          // Blank line = event boundary. Emit what we've accumulated.
          if (dataLines.isNotEmpty) {
            yield SseEvent(event: eventName, data: dataLines.join('\n'));
          }
          eventName = null;
          dataLines.clear();
          continue;
        }
        if (line.startsWith(':')) continue; // comment / keepalive
        final idx = line.indexOf(':');
        final field = idx == -1 ? line : line.substring(0, idx);
        var value = idx == -1 ? '' : line.substring(idx + 1);
        if (value.startsWith(' ')) value = value.substring(1);
        if (field == 'event') {
          eventName = value;
        } else if (field == 'data') {
          dataLines.add(value);
        }
        // id / retry ignored.
      }
    }
    // Flush a trailing event that had no closing blank line.
    if (dataLines.isNotEmpty) {
      yield SseEvent(event: eventName, data: dataLines.join('\n'));
    }
  }
}

/// One parsed Server-Sent Event. [data] is the concatenated `data:` payload
/// (usually a JSON object); [event] is the optional `event:` name.
class SseEvent {
  const SseEvent({this.event, required this.data});
  final String? event;
  final String data;
}

/// `CyberNeurova/1.0.1 (Android 16)` — resolved once and reused.
///
/// Deliberately not a browser-shaped string: pretending to be Chrome is how
/// you end up in the "Browser" bucket in the first place.
Future<String> _userAgent() async => _cachedUserAgent ??= await _buildUserAgent();
String? _cachedUserAgent;

Future<String> _buildUserAgent() async {
  final os = Platform.isAndroid
      ? 'Android'
      : Platform.isIOS
          ? 'iOS'
          : Platform.operatingSystem;
  try {
    final info = await PackageInfo.fromPlatform();
    return 'CyberNeurova/${info.version}+${info.buildNumber} ($os)';
  } catch (_) {
    // Never let a missing plugin stop a request going out.
    return 'CyberNeurova ($os)';
  }
}
