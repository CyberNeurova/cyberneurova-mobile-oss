import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/features/agents/presentation/providers/agent_session_provider.dart';

/// The bug these guard: the control channel read the session for the run id,
/// while the session watched the channel to send with. Riverpod threw
/// `CircularDependencyError` the moment a device result was posted, the outbox
/// retried forever, and the user saw "Couldn't reach the agent" — for a run
/// that had already written the file correctly on the phone.
///
/// It presented as a network failure and was reported to the backend as a
/// possible server 4xx. Nothing about the symptom pointed at a provider graph,
/// which is why the shape is pinned by a test rather than left to review.
void main() {
  group('run id holder', () {
    test('is readable without building the session', () {
      // This is the assertion that matters. The holder must depend on nothing:
      // reintroduce a session read and this fails immediately, because the
      // session pulls in the device executor and the chat list, which need
      // platform plugins a unit test does not have.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(runIdHolderProvider('chat-1')).value, isNull);
    });

    test('is per chat, so two runs cannot address each other', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(runIdHolderProvider('a')).value = 'run-a';

      expect(container.read(runIdHolderProvider('a')).value, 'run-a');
      expect(container.read(runIdHolderProvider('b')).value, isNull);
    });

    // The other half — that `apply(frame, runId:)` fills the holder, and that a
    // frame WITHOUT one leaves the last known id alone rather than stranding
    // the next device result — needs the whole session graph and therefore the
    // plugin layer. It is verified on the device instead: a real run posts its
    // device_result and the tool card completes.
  });
}
