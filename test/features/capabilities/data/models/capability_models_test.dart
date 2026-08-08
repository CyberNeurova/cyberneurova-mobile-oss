import 'package:flutter_test/flutter_test.dart';
import 'package:cyberneurova_mobile/features/capabilities/data/models/capability_models.dart';

// Sahachiel: CapabilityListResponse.fromJson reads either the `skills` or
// `tools` key and used `as List` / `as Map` casts. A wrong-typed list or a
// non-map entry crashed the whole Capabilities screen. Lock the key handling
// + the defensive fallbacks + the model defaults the tier badge relies on.
void main() {
  group('CapabilityListResponse.fromJson', () {
    test('reads the skills key', () {
      final r = CapabilityListResponse.fromJson({
        'skills': [
          {'id': 'web', 'name': 'Web search', 'enabled': true},
        ],
      }, 'skills');
      expect(r.items, hasLength(1));
      expect(r.items.first.id, 'web');
      expect(r.items.first.enabled, isTrue);
    });

    test('/skills maps isEnabled + category onto enabled + type', () {
      // Real contract: skills use isEnabled/category, tools use enabled/type.
      // Before the fix every skill rendered OFF with a null category.
      final r = CapabilityListResponse.fromJson({
        'skills': [
          {
            'id': 'web',
            'name': 'Web search',
            'category': 'research',
            'isEnabled': true,
          },
        ],
      }, 'skills');
      expect(r.items.single.enabled, isTrue);
      expect(r.items.single.type, 'research');
    });

    test('reads the tools key with model defaults', () {
      final r = CapabilityListResponse.fromJson({
        'tools': [
          {'id': 't1', 'name': 'Tool'},
        ],
      }, 'tools');
      expect(r.items, hasLength(1));
      expect(r.items.first.requiredTier, 'free'); // default
      expect(r.items.first.accessible, isTrue); // default
      expect(r.items.first.enabled, isFalse); // default
    });

    test('returns empty when the key is missing or not a list', () {
      expect(CapabilityListResponse.fromJson({}, 'skills').items, isEmpty);
      expect(
        CapabilityListResponse.fromJson({'skills': 'nope'}, 'skills').items,
        isEmpty,
      );
    });

    test('skips non-map entries instead of throwing', () {
      final r = CapabilityListResponse.fromJson({
        'skills': [
          {'id': 'a'},
          null,
          42,
          {'id': 'b'},
        ],
      }, 'skills');
      expect(r.items.map((i) => i.id).toList(), ['a', 'b']);
    });
  });
}
