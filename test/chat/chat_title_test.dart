import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_title.dart';

void main() {
  group('titleFromMessage', () {
    test('uses the ask as written', () {
      expect(titleFromMessage('list the files in the current directory'),
          'List the files in the current directory');
    });

    test('stops at the first sentence', () {
      expect(titleFromMessage('create clock.html. make it dark and big'),
          'Create clock.html');
    });

    test('keeps a short question whole', () {
      expect(titleFromMessage('are you local?'), 'Are you local');
    });

    test('takes the first line of a multi-line ask', () {
      expect(
        titleFromMessage('scan my network\nthen write the results to a file'),
        'Scan my network',
      );
    });

    test('truncates on a word boundary', () {
      final t = titleFromMessage(
          'please investigate the latest OpenSSH vulnerabilities and write a '
          'short summary of each one to a file');
      expect(t.length, lessThanOrEqualTo(46));
      expect(t, endsWith('…'));
      expect(t, isNot(contains('  ')));
      // Never cuts mid-word.
      expect(t.replaceAll('…', '').trim().split(' ').last.length,
          greaterThan(1));
    });

    test('never leaves a comma before the ellipsis', () {
      final t = titleFromMessage(
          'set up the project structure, then install the dependencies and run');
      expect(t, isNot(contains(',…')));
    });

    test('skips a leading code fence', () {
      expect(
        titleFromMessage('```dart\nvoid main() {}\n```\nexplain this'),
        'Explain this',
      );
    });

    test('strips markdown furniture', () {
      expect(titleFromMessage('## **Fix** the `parser`'), 'Fix the parser');
    });

    test('empty and whitespace-only messages produce no title', () {
      expect(titleFromMessage(''), '');
      expect(titleFromMessage('   \n  '), '');
    });

    test('a message that is only a code fence produces no title', () {
      expect(titleFromMessage('```\nsome code\n```'), '');
    });
  });

  group('isUnusableTitle', () {
    test('punctuation-only titles are unusable', () {
      // The Research list showed a session called "??" — non-empty, and
      // meaningless. `isEmpty` alone did not catch it.
      expect(isUnusableTitle('??'), isTrue);
      expect(isUnusableTitle('...'), isTrue);
      expect(isUnusableTitle('  -- '), isTrue);
    });

    test('placeholders are unusable', () {
      expect(isUnusableTitle(''), isTrue);
      expect(isUnusableTitle('New Chat'), isTrue);
      expect(isUnusableTitle('Untitled'), isTrue);
    });

    test('real titles are kept', () {
      expect(isUnusableTitle('Scan my network'), isFalse);
      expect(isUnusableTitle('hello.py'), isFalse);
      expect(isUnusableTitle('4271'), isFalse);
    });

    test('non-Latin titles are kept — the check is unicode-aware', () {
      // Dart's \w is ASCII, so an ASCII-only check would have discarded these.
      // Several memories on this account are already in Chinese.
      expect(isUnusableTitle('用户正在进行后端开发'), isFalse);
      expect(isUnusableTitle('مرحبا'), isFalse);
      expect(isUnusableTitle('Привет'), isFalse);
    });

    test('sessionDisplayTitle uses it', () {
      expect(sessionDisplayTitle('??'), 'Untitled session');
      expect(sessionDisplayTitle('Scan my network'), 'Scan my network');
    });
  });

  group('isGreetingOrLowSignal', () {
    test('bare greetings are low-signal (title from the NEXT message)', () {
      for (final g in [
        'hey',
        'Hey!',
        'hi',
        'hi there',
        'hello',
        'hellooo',
        'yo',
        'sup',
        'howdy',
        'good morning',
        'Good afternoon.',
        'good evening 👋',
        "what's up",
        'wassup',
        'how are you?',
        'hey team',
        'hi everyone',
      ]) {
        expect(isGreetingOrLowSignal(g), isTrue, reason: 'greeting: "$g"');
      }
    });

    test('filler openers are low-signal', () {
      for (final f in ['ok', 'okay', 'test', 'testing', 'thanks', 'thx']) {
        expect(isGreetingOrLowSignal(f), isTrue, reason: 'filler: "$f"');
      }
    });

    test('a real ask is NOT low-signal — even one starting with a greeting',
        () {
      expect(isGreetingOrLowSignal("what's the capital of France?"), isFalse);
      expect(isGreetingOrLowSignal('hey, help me write a regex'), isFalse);
      expect(isGreetingOrLowSignal('hello world program in rust'), isFalse);
      expect(isGreetingOrLowSignal('hi'), isTrue); // but a bare "hi" is
    });
  });

  group('titleFromMessage strips a leading greeting', () {
    test('greeting + ask titles from the ask', () {
      expect(titleFromMessage("hey, what's the capital of France?"),
          "What's the capital of France");
      expect(titleFromMessage('good morning — help me debug this crash'),
          'Help me debug this crash');
      expect(titleFromMessage('hi there, write a haiku about the sea'),
          'Write a haiku about the sea');
    });

    test('a greeting-only message yields no title', () {
      expect(titleFromMessage('hey'), '');
      expect(titleFromMessage('good morning!'), '');
    });

    test('a normal ask is untouched by the greeting strip', () {
      expect(titleFromMessage('write a haiku about the sea'),
          'Write a haiku about the sea');
    });
  });
}
