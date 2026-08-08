import 'package:flutter_test/flutter_test.dart';
import 'package:cyberneurova_mobile/features/prompts/data/models/prompt_model.dart';

void main() {
  group('PromptModel.normalize', () {
    test('maps backend `name` onto the required `title` (no crash)', () {
      // Backend stores the label under `name`; the old direct `title` cast threw
      // "Null is not a subtype of String" and blanked the Custom Prompts screen.
      final m = PromptModel.fromJson(PromptModel.normalize({
        'id': 'p1',
        'name': 'My prompt',
        'content': 'Do the thing',
      }));
      expect(m.title, 'My prompt');
      expect(m.id, 'p1');
      expect(m.content, 'Do the thing');
    });

    test('prefers an explicit `title` when present', () {
      final m = PromptModel.fromJson(PromptModel.normalize({
        'id': 'p2',
        'title': 'Explicit',
        'name': 'Fallback',
        'content': 'x',
      }));
      expect(m.title, 'Explicit');
    });

    test('coalesces drifted id keys and never leaves required fields null', () {
      final m = PromptModel.fromJson(PromptModel.normalize({
        '_id': 'mongo123',
        'name': 'n',
      }));
      expect(m.id, 'mongo123');
      expect(m.content, ''); // defaulted, not null → no throw
    });
  });
}
