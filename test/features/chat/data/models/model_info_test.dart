import 'package:flutter_test/flutter_test.dart';
import 'package:cyberneurova_mobile/features/chat/data/models/model_info.dart';

// Locks the /models capability + budget fields and
// the "absent block reads as off" contract the UI gating relies on.
// Originally authored by @Sahachiel in PR #14.
void main() {
  group('ModelInfo capabilities', () {
    test('parses capabilities + budget metadata and exposes getters', () {
      final m = ModelInfo.fromJson({
        'id': 'neurova-pro',
        'name': 'Neurova Pro',
        'capabilities': {
          'vision': true,
          'fileUpload': true,
          'reasoning': false,
        },
        'contextWindow': 128000,
        'maxOutputTokens': 8192,
        'charsPerToken': 3.5,
      });

      expect(m.supportsVision, isTrue);
      expect(m.supportsFileUpload, isTrue);
      expect(m.supportsReasoning, isFalse);
      expect(m.contextWindow, 128000);
      expect(m.maxOutputTokens, 8192);
      expect(m.charsPerToken, 3.5);
    });

    test('an absent capabilities block reads as all-off (no false enable)', () {
      final m = ModelInfo.fromJson({'id': 'tiny-neurova', 'name': 'Tiny'});

      expect(m.capabilities, isNull);
      expect(m.supportsVision, isFalse);
      expect(m.supportsFileUpload, isFalse);
      expect(m.supportsReasoning, isFalse);
      expect(m.available, isTrue);
      expect(m.contextWindow, isNull);
    });

    test('a partial capabilities block only enables what is set', () {
      final m = ModelInfo.fromJson({
        'id': 'm',
        'name': 'M',
        'capabilities': {'vision': true},
      });

      expect(m.supportsVision, isTrue);
      expect(m.supportsFileUpload, isFalse);
      expect(m.supportsReasoning, isFalse);
    });

    test('charsPerToken tolerates an integer JSON number', () {
      final m = ModelInfo.fromJson({
        'id': 'm',
        'name': 'M',
        'charsPerToken': 4,
      });
      expect(m.charsPerToken, 4.0);
    });
  });

  group('ModelsResponse', () {
    test('parses models / locked / defaultModel', () {
      final r = ModelsResponse.fromJson({
        'models': [
          {
            'id': 'a',
            'name': 'A',
            'capabilities': {'fileUpload': true},
          },
        ],
        'locked': [
          {'id': 'b', 'name': 'B'},
        ],
        'defaultModel': 'a',
      });

      expect(r.models, hasLength(1));
      expect(r.models.first.supportsFileUpload, isTrue);
      expect(r.locked, hasLength(1));
      expect(r.locked.first.supportsFileUpload, isFalse);
      expect(r.defaultModel, 'a');
    });
  });
}
