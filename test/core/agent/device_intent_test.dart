import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/core/agent/device_intent.dart';

void main() {
  group('catches what caused the original report', () {
    // "i told it to write something ... it says it did but when i go to the
    // shell and ls nothing is there." These are the messages that must not
    // silently waste a turn in a chat with no device tools.
    for (final message in [
      'write a python script in my working directory',
      'list my files',
      'run ls in my terminal',
      'install ripgrep',
      'clone the repo and build it',
      'scan my local network',
      'what is running on this phone',
      'set up a project on my device',
    ]) {
      test('"$message"', () => expect(looksLikeDeviceRequest(message), isTrue));
    }
  });

  group('leaves ordinary conversation alone', () {
    // A chip that appears on every third message is one people learn to
    // ignore, which costs the true positives too.
    for (final message in [
      'how do i install ripgrep on debian',
      'explain how git clone works',
      'what is the difference between apt and apk',
      'write me a poem about terminals',
      'can you explain what chmod does',
      'why is my code slow',
      'what does this error mean',
      'is there a way to speed this up',
      'summarise this article',
      'hi',
    ]) {
      test('"$message"', () => expect(looksLikeDeviceRequest(message), isFalse));
    }
  });

  test('asking HOW is a question, asking to DO it is a job', () {
    // The single most useful discriminator, and the one most likely to
    // misfire if it were not checked first.
    expect(looksLikeDeviceRequest('install docker'), isTrue);
    expect(looksLikeDeviceRequest('how do i install docker'), isFalse);

    expect(looksLikeDeviceRequest('run the tests'), isTrue);
    expect(looksLikeDeviceRequest('how can i run the tests'), isFalse);
  });

  test('a shell verb mid-sentence is discussion, not an instruction', () {
    // "we should probably install it eventually" is not a request to act.
    expect(
      looksLikeDeviceRequest('we should probably install it eventually'),
      isFalse,
    );
    expect(looksLikeDeviceRequest('the build step runs after that'), isFalse);
  });

  test('trivial input is never a device request', () {
    expect(looksLikeDeviceRequest(''), isFalse);
    expect(looksLikeDeviceRequest('   '), isFalse);
    expect(looksLikeDeviceRequest('ok'), isFalse);
  });

  test('case and surrounding whitespace do not matter', () {
    expect(looksLikeDeviceRequest('  RUN the tests  '), isTrue);
    expect(looksLikeDeviceRequest('List My Files'), isTrue);
  });
}
