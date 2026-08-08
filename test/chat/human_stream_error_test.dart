import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/features/chat/presentation/providers/chat_provider.dart';

void main() {
  group('humanStreamError', () {
    test('never returns a raw Dart exception', () {
      // The failure bubble renders this verbatim. The bug this replaces put
      // "TimeoutException after 0:05:00.000000: No stream event" in front of
      // a user.
      final errors = <Object>[
        TimeoutException('No stream event', const Duration(minutes: 5)),
        const SocketException('Connection reset'),
        const HttpException('bad'),
        DioException(
          requestOptions: RequestOptions(path: '/agent/run'),
          type: DioExceptionType.connectionError,
        ),
        DioException(
          requestOptions: RequestOptions(path: '/agent/run'),
          type: DioExceptionType.badResponse,
        ),
        StateError('boom'),
        'a bare string',
      ];
      for (final e in errors) {
        final msg = humanStreamError(e);
        expect(msg, isNot(contains('Exception')), reason: '$e');
        expect(msg, isNot(contains('Error:')), reason: '$e');
        expect(msg, isNot(contains('0:05:00')), reason: '$e');
        // Reads as a sentence, not a token.
        expect(msg.trim(), endsWith('.'), reason: '$e');
        expect(msg.length, greaterThan(20), reason: '$e');
      }
    });

    test('a stalled run says nothing was changed', () {
      // The user's next question is always "did it half-do something?" —
      // answer it in the bubble rather than making them go and look.
      expect(
        humanStreamError(
            TimeoutException('No stream event', const Duration(minutes: 5))),
        kStalledRunReason,
      );
      expect(kStalledRunReason, contains('Nothing was changed'));
    });

    test('the half-finished stall does not claim nothing happened', () {
      // The stall usually lands right after a device tool reports back, so
      // this is the common case. Saying "nothing was changed" there is a wrong
      // answer about the user's own files.
      expect(kStalledRunPartialReason, isNot(contains('Nothing was changed')));
      expect(kStalledRunPartialReason.toLowerCase(), contains('already run'));
      expect(kStalledRunPartialReason, isNot(kStalledRunReason));
    });

    test('the stall reason is not the step-limit reason', () {
      // The failure bubble offers Continue when it sees the step-limit text.
      // A stalled run has nothing to continue from, so these must not collide.
      expect(kStalledRunReason, isNot(kStepLimitReason));
      expect(kStalledRunReason.startsWith(kStepLimitReason), isFalse);
      expect(kStepLimitReason.startsWith(kStalledRunReason), isFalse);
    });

    test('network failures tell the user to check the network', () {
      expect(
        humanStreamError(const SocketException('reset')).toLowerCase(),
        contains('network'),
      );
      expect(
        humanStreamError(DioException(
          requestOptions: RequestOptions(path: '/agent/run'),
          type: DioExceptionType.connectionTimeout,
        )).toLowerCase(),
        contains('network'),
      );
    });
  });
}
