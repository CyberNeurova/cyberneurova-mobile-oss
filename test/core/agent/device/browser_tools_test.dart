import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/core/agent/device/tools/browser_tools.dart';

void main() {
  group('isPrivateDestination', () {
    // The load-bearing decision in the whole tool: get it wrong one way and
    // every public page needs authorising, which makes the browser useless.
    // Get it wrong the other way and browsing to 192.168.1.1 skips the check
    // the scan tools enforce.

    test('a public site is not something to authorise', () {
      expect(isPrivateDestination('example.com'), isFalse);
      expect(isPrivateDestination('docs.flutter.dev'), isFalse);
      expect(isPrivateDestination('93.184.216.34'), isFalse);
      // Deliberately: a public IP that merely LOOKS like a private one.
      expect(isPrivateDestination('11.0.0.1'), isFalse);
      expect(isPrivateDestination('172.15.0.1'), isFalse);
      expect(isPrivateDestination('172.32.0.1'), isFalse);
      expect(isPrivateDestination('192.169.0.1'), isFalse);
    });

    test('the user\'s own network goes through scope', () {
      expect(isPrivateDestination('192.168.1.1'), isTrue);
      expect(isPrivateDestination('10.0.0.5'), isTrue);
      expect(isPrivateDestination('172.16.0.1'), isTrue);
      expect(isPrivateDestination('172.31.255.254'), isTrue);
      expect(isPrivateDestination('127.0.0.1'), isTrue);
      expect(isPrivateDestination('169.254.1.1'), isTrue);
      // Carrier-grade NAT: ordinary on a mobile network, and the phone's own
      // neighbours live there.
      expect(isPrivateDestination('100.64.0.1'), isTrue);
      expect(isPrivateDestination('100.127.255.1'), isTrue);
      // …but 100.x outside 64–127 is public address space.
      expect(isPrivateDestination('100.63.0.1'), isFalse);
      expect(isPrivateDestination('100.128.0.1'), isFalse);
    });

    test('local names count as the local network', () {
      expect(isPrivateDestination('localhost'), isTrue);
      expect(isPrivateDestination('router.local'), isTrue);
      expect(isPrivateDestination('NAS.LOCAL'), isTrue);
    });

    test('anything unparseable is treated as sensitive, not as public', () {
      // Failing open here would be a way around the scope check.
      expect(isPrivateDestination(''), isTrue);
      expect(isPrivateDestination('   '), isTrue);
    });
  });
}
