import 'dart:convert';

/// The run-protocol frames the client understands.
///
/// This file is the **client half of the contract** with `cyberneurova_core`.
/// Core owns the agent loop, tool dispatch, permission evaluation and
/// compaction (see `docs/ENGINE.md`); the app subscribes to the frames below
/// and renders them. Nothing here executes anything.
///
/// Three rules govern parsing, and all three exist because the schema will
/// drift ahead of the client:
///
/// 1. **Unknown frame types are ignored, never fatal.** A backend that starts
///    emitting a new frame must not break every shipped app version.
/// 2. **Unknown fields are preserved** on [AgentToolCall.input] so a generic
///    renderer can still show them.
/// 3. **Every field is defensively typed.** A string where an int was
///    expected degrades that one field, not the frame.
sealed class AgentFrame {
  const AgentFrame();

  /// Monotonic per-run sequence number. The client tracks the highest value
  /// it has processed so a reconnect can ask the server to replay from there
  /// rather than restarting the run.
  int? get seq;

  /// Parses one decoded frame. Returns null for anything unrecognised —
  /// callers should skip, not throw.
  static AgentFrame? tryParse(Map<String, dynamic> json) {
    final type = json['type'];
    if (type is! String) return null;
    final seq = _asInt(json['seq']);

    switch (type) {
      case 'assistant_delta':
        final text = _asString(json['text']) ?? _asString(json['content']);
        if (text == null) return null;
        return AgentAssistantDelta(text: text, seq: seq);

      case 'tool_call':
        final id = _asString(json['call_id']) ?? _asString(json['id']);
        final name = _asString(json['tool']) ?? _asString(json['name']);
        if (id == null || name == null) return null;
        return AgentToolCall(
          callId: id,
          tool: name,
          input: _asMap(json['input']) ?? _asMap(json['args']) ?? const {},
          title: _asString(json['title']),
          // Which side runs this. "device" means the phone executes it and
          // posts a device_tool_result back — that is what keeps LAN work
          // (and load) off the server.
          executor: _asString(json['executor']) ?? 'server',
          seq: seq,
        );

      case 'approval_request':
      case 'can_use_tool':
        final id = _asString(json['call_id']) ??
            _asString(json['tool_use_id']) ??
            _asString(json['id']);
        final name = _asString(json['tool']) ?? _asString(json['tool_name']);
        if (id == null || name == null) return null;
        return AgentApprovalRequest(
          callId: id,
          tool: name,
          input: _asMap(json['input']) ?? const {},
          rationale: _asString(json['rationale']) ??
              _asString(json['decision_reason']) ??
              _asString(json['description']),
          risk: _asString(json['risk']),
          seq: seq,
        );

      case 'tool_progress':
        final id = _asString(json['call_id']) ?? _asString(json['tool_use_id']);
        if (id == null) return null;
        return AgentToolProgress(
          callId: id,
          text: _asString(json['text']) ?? _asString(json['output']) ?? '',
          seq: seq,
        );

      case 'tool_result':
        final id = _asString(json['call_id']) ?? _asString(json['tool_use_id']);
        if (id == null) return null;
        return AgentToolResult(
          callId: id,
          ok: json['ok'] is bool
              ? json['ok'] as bool
              : _asString(json['status']) != 'error',
          summary: _asString(json['summary']),
          output: _asString(json['output']),
          error: _asString(json['error']),
          artifacts: _asArtifacts(json['artifacts']),
          seq: seq,
        );

      // The deployed shape. A tool's OUTCOME does not arrive as a top-level
      // `tool_result` — it arrives as a `tool_result` BLOCK inside a `user`
      // frame, the way the upstream message format carries it:
      //
      //   {"type":"user","message":{"content":[
      //     {"type":"tool_result","tool_use_id":"…","is_error":true,
      //      "content":"<tool_use_error>…</tool_use_error>"}]}}
      //
      // We only handled the top-level form, so every server-executed tool's
      // result was dropped on the floor. Device tools hid it: they reflect
      // their own result locally, so those cards completed and the gap only
      // showed on tools that ran server-side — where the card sat with no
      // outcome and, for a refusal, no reason.
      case 'user':
        final message = json['message'];
        if (message is! Map) return null;
        final content = message['content'];
        if (content is! List) return null;

        for (final block in content) {
          if (block is! Map) continue;
          if (block['type'] != 'tool_result') continue;
          final id = _asString(block['tool_use_id']) ??
              _asString(block['call_id']);
          if (id == null) continue;

          final isError = block['is_error'] == true;
          final body = _toolResultText(block['content']);
          return AgentToolResult(
            callId: id,
            ok: !isError,
            // The upstream wraps failures in `<tool_use_error>…</tool_use_error>`.
            // Unwrapped here rather than at render time, so every consumer —
            // card, transcript, saved run — sees the same string.
            error: isError ? _unwrapToolError(body) : null,
            output: isError ? null : body,
            seq: seq,
          );
        }
        return null;

      case 'run_finished':
      case 'done':
        return AgentRunFinished(
          reason: _asString(json['reason']) ?? _asString(json['finish_reason']),
          seq: seq,
        );

      case 'error':
        return AgentError(
          message: _asString(json['message']) ?? 'Something went wrong.',
          code: _asString(json['code']),
          seq: seq,
        );
    }
    return null;
  }
}

/// A chunk of assistant prose. Appended to the current assistant message.
final class AgentAssistantDelta extends AgentFrame {
  const AgentAssistantDelta({required this.text, this.seq});
  final String text;
  @override
  final int? seq;
}

/// The model committed to a tool call. A card appears immediately — the
/// executor starts work as the call streams in rather than waiting for the
/// whole turn to be planned.
final class AgentToolCall extends AgentFrame {
  const AgentToolCall({
    required this.callId,
    required this.tool,
    required this.input,
    this.title,
    this.executor = 'server',
    this.seq,
  });
  final String callId;
  final String tool;

  /// `device` | `container` | `server`. Only `device` causes local
  /// execution; anything else is the server's problem and the client just
  /// renders progress.
  final String executor;

  bool get runsOnDevice => executor == 'device';

  /// Raw arguments, kept whole. The generic card renders whatever is here,
  /// so a tool the client has never heard of still displays usefully.
  final Map<String, dynamic> input;

  /// Optional server-supplied display title, preferred over a derived one.
  final String? title;
  @override
  final int? seq;
}

/// The policy engine returned `ask`. The run pauses until the user responds.
final class AgentApprovalRequest extends AgentFrame {
  const AgentApprovalRequest({
    required this.callId,
    required this.tool,
    required this.input,
    this.rationale,
    this.risk,
    this.seq,
  });
  final String callId;
  final String tool;
  final Map<String, dynamic> input;

  /// Why approval is needed, in the policy engine's words.
  final String? rationale;

  /// Free-form severity hint ("low" | "medium" | "high"), used for accent
  /// colour only — never to decide whether to ask.
  final String? risk;
  @override
  final int? seq;
}

/// Incremental output from a running tool. Appended to a bounded tail.
final class AgentToolProgress extends AgentFrame {
  const AgentToolProgress({
    required this.callId,
    required this.text,
    this.seq,
  });
  final String callId;
  final String text;
  @override
  final int? seq;
}

final class AgentToolResult extends AgentFrame {
  const AgentToolResult({
    required this.callId,
    required this.ok,
    this.summary,
    this.output,
    this.error,
    this.artifacts = const [],
    this.seq,
  });
  final String callId;
  final bool ok;

  /// One-line result the card collapses to. The full [output] stays
  /// available behind an expand.
  final String? summary;
  final String? output;
  final String? error;
  final List<AgentArtifact> artifacts;
  @override
  final int? seq;
}

final class AgentRunFinished extends AgentFrame {
  const AgentRunFinished({this.reason, this.seq});
  final String? reason;
  @override
  final int? seq;
}

final class AgentError extends AgentFrame {
  const AgentError({required this.message, this.code, this.seq});
  final String message;
  final String? code;
  @override
  final int? seq;
}

/// A file or object a tool produced. Rendered as a tappable chip.
class AgentArtifact {
  const AgentArtifact({
    required this.name,
    this.url,
    this.mimeType,
    this.sizeBytes,
  });

  final String name;
  final String? url;
  final String? mimeType;
  final int? sizeBytes;

  static AgentArtifact? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final name = _asString(m['name']) ?? _asString(m['path']);
    if (name == null || name.isEmpty) return null;
    return AgentArtifact(
      name: name,
      url: _asString(m['url']),
      mimeType: _asString(m['mime_type']) ?? _asString(m['mimeType']),
      sizeBytes: _asInt(m['size_bytes']) ?? _asInt(m['size']),
    );
  }
}

// ─── Defensive coercion ──────────────────────────────────────────────────────

String? _asString(Object? v) => v is String ? v : null;

int? _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

Map<String, dynamic>? _asMap(Object? v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  if (v is String && v.isNotEmpty) {
    // Some backends double-encode tool input as a JSON string.
    try {
      final decoded = jsonDecode(v);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
  }
  return null;
}

List<AgentArtifact> _asArtifacts(Object? v) {
  if (v is! List) return const [];
  return [
    for (final e in v)
      if (AgentArtifact.tryParse(e) case final a?) a,
  ];
}


/// A tool_result's `content`, which is a string on some frames and a list of
/// typed blocks on others.
String? _toolResultText(Object? raw) {
  if (raw is String) return raw.trim().isEmpty ? null : raw;
  if (raw is List) {
    final buf = StringBuffer();
    for (final b in raw) {
      if (b is Map && b['text'] is String) buf.write(b['text']);
    }
    final joined = buf.toString();
    return joined.trim().isEmpty ? null : joined;
  }
  return null;
}

/// Strips the `<tool_use_error>` wrapper the upstream puts around failures.
String? _unwrapToolError(String? raw) {
  if (raw == null) return null;
  final m = RegExp(r'<tool_use_error>([\s\S]*?)</tool_use_error>').firstMatch(raw);
  final text = (m?.group(1) ?? raw).trim();
  return text.isEmpty ? null : text;
}
