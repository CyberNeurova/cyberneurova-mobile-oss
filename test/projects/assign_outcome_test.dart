import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/shared/widgets/app_drawer.dart';

void main() {
  group('assignOutcome', () {
    test('adding nothing does not read like success', () {
      // The bug: the server accepted the request and stored no chats, and the
      // sheet said "Added 0 chats to Project 1" — true, and indistinguishable
      // from it having worked.
      final msg = assignOutcome(added: 0, failed: 0, projectName: 'Project 1');
      expect(msg, isNot(contains('Added 0')));
      expect(msg.toLowerCase(), contains('nothing was added'));
      expect(msg, contains('Project 1'));
    });

    test('singular and plural', () {
      expect(
        assignOutcome(added: 1, failed: 0, projectName: 'Work'),
        'Added 1 chat to "Work"',
      );
      expect(
        assignOutcome(added: 3, failed: 0, projectName: 'Work'),
        'Added 3 chats to "Work"',
      );
    });

    test('a partial failure reports both halves', () {
      final msg = assignOutcome(added: 2, failed: 1, projectName: 'Work');
      expect(msg, contains('2'));
      expect(msg, contains('1 failed'));
    });

    test('a total failure says so without a count of zero', () {
      final msg = assignOutcome(added: 0, failed: 4, projectName: 'Work');
      expect(msg, isNot(contains('Added 0')));
      expect(msg, contains('Work'));
    });
  });
}
