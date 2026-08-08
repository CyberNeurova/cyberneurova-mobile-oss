import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/core/agent/agent_frame.dart';
import 'package:cyberneurova_mobile/core/agent/agent_transcript.dart';
import 'package:cyberneurova_mobile/core/agent/run_store.dart';

void main() {
  late Directory dir;
  late RunStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('cn_run_store');
    store = RunStore(dir);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  AgentTranscript transcriptWith(List<AgentFrame> frames) {
    final t = AgentTranscript();
    for (final f in frames) {
      t.apply(f);
    }
    return t;
  }

  test('nothing to save leaves no file behind', () async {
    await store.save('chat-1', transcript: AgentTranscript());
    expect(await store.load('chat-1'), isNull);
    expect(dir.listSync(), isEmpty);
  });

  test('a finished tool call survives a restart', () async {
    final t = transcriptWith([
      const AgentToolCall(
          callId: 'c1', tool: 'file_write', input: {'path': 'a.txt'}),
      const AgentToolResult(callId: 'c1', ok: true, summary: 'Wrote 5 chars'),
    ]);

    await store.save('chat-1', runId: 'run-9', transcript: t);
    final back = await store.load('chat-1');

    expect(back, isNotNull);
    expect(back!.runId, 'run-9');
    expect(back.cards.single.tool, 'file_write');
    expect(back.cards.single.summary, 'Wrote 5 chars');
    expect(back.cards.single.state, ToolCardState.succeeded);
    expect(back.cards.single.input['path'], 'a.txt');
  });

  test('a call still running is restored as interrupted, not running', () async {
    // The process died. Showing it as running would put a spinner on screen
    // that can never stop, and imply work is happening that is not.
    final t = transcriptWith([
      const AgentToolCall(callId: 'c1', tool: 'net_scan', input: {}),
    ]);

    await store.save('chat-1', runId: 'r', transcript: t);
    final back = await store.load('chat-1');

    expect(back!.cards.single.state, ToolCardState.failed);
    expect(back.cards.single.error, contains('Interrupted'));
  });

  test('a failure keeps its reason', () async {
    final t = transcriptWith([
      const AgentToolCall(callId: 'c1', tool: 'shell_exec', input: {}),
      const AgentToolResult(
          callId: 'c1', ok: false, error: 'exit 127: not found'),
    ]);

    await store.save('chat-1', runId: 'r', transcript: t);
    final back = await store.load('chat-1');

    expect(back!.cards.single.state, ToolCardState.failed);
    expect(back.cards.single.error, 'exit 127: not found');
  });

  test('chats do not see each other', () async {
    final t = transcriptWith(
        [const AgentToolCall(callId: 'c1', tool: 'file_read', input: {})]);
    await store.save('chat-1', runId: 'r1', transcript: t);

    expect(await store.load('chat-2'), isNull);
  });

  test('a corrupt file degrades to no history, never to a crash', () async {
    // A chat that will not open is far worse than a chat with no tool history.
    File('${dir.path}/run_chat-1.json').writeAsStringSync('{not json');
    expect(await store.load('chat-1'), isNull);
  });

  test('a file from a future version is ignored rather than guessed at', () async {
    File('${dir.path}/run_chat-1.json')
        .writeAsStringSync(jsonEncode({'v': 99, 'cards': []}));
    expect(await store.load('chat-1'), isNull);
  });

  test('saving again replaces, and clearing removes', () async {
    final t = transcriptWith(
        [const AgentToolCall(callId: 'c1', tool: 'dns_query', input: {})]);
    await store.save('chat-1', runId: 'r', transcript: t);
    expect(await store.load('chat-1'), isNotNull);

    await store.clear('chat-1');
    expect(await store.load('chat-1'), isNull);
  });
}
