import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/features/chat/data/repositories/chat_repository.dart';

void main() {
  group('isProgressFrame', () {
    test('drops heartbeats', () {
      // The exact shape observed on device, 2026-08-05.
      expect(
        isProgressFrame({
          'type': 'heartbeat',
          'ts': 1234,
          'session_id': 's',
          'run_id': 'r',
          'seq': 4,
        }),
        isFalse,
      );
    });

    test('keeps every frame that means something happened', () {
      // A heartbeat resets Stream.timeout, so anything wrongly classified as a
      // heartbeat would be invisible AND would keep a dead run spinning. These
      // are the four the server opened the stalled run with, plus the ones that
      // carry the actual work.
      for (final type in [
        'run_started',
        'system',
        'render_hint',
        'assistant',
        'partial',
        'tool_call',
        'tool_result',
        'workspace_change',
        'approval_request',
        'result',
        'done',
        'run_finished',
        'error',
      ]) {
        expect(isProgressFrame({'type': type}), isTrue, reason: type);
      }
    });

    test('an unknown type is kept, not dropped', () {
      // Filtering is a denylist on purpose: a new frame type the client does
      // not understand yet still proves the run is moving, and silently
      // dropping it would re-create the hang this fixes.
      expect(isProgressFrame({'type': 'something_new'}), isTrue);
      expect(isProgressFrame(const {}), isTrue);
    });
  });
}
