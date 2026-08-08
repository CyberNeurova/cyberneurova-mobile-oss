import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A per-row failure must not revert the whole list.
///
/// Found SEVEN times in one sweep — capabilities (skills and tools), projects,
/// prompts, sessions, research and memory all wrote the same thing:
///
/// ```dart
/// Future<void> delete(String id) async {
///   final current = state.valueOrNull ?? [];
///   state = AsyncData(current.where((p) => p.id != id).toList());
///   try {
///     await repo.delete(id);
///   } catch (_) {
///     state = AsyncData(current);   // <-- restores EVERYTHING
///     rethrow;
///   }
/// }
/// ```
///
/// Each row is its own request and these screens let you act on several
/// without waiting, so a late failure undid changes the server had already
/// accepted: a deleted row reappears, a toggled switch springs back, a revoked
/// memory returns. The user is told their change did not happen when it did.
///
/// ## The discriminator
///
/// Restoring the whole snapshot is CORRECT for a whole-list operation —
/// `clearAll` and `revokeAllOthers` replace the entire list, so putting the
/// entire list back is their proper undo. A guard that cannot tell those apart
/// would flag correct code and get ignored.
///
/// The reliable signal turned out to be the method signature: an operation
/// that acts on ONE row takes that row's id as a parameter, and a whole-list
/// operation takes none. `deleteOne(String id)` and `toggle(String id, bool
/// enabled)` are per-row; `clearAll()` and `revokeAllOthers()` are not.
///
/// So: a method WITH parameters that captures state before a `try` and
/// restores that capture inside `catch` is the bug. Use `restoreAt` from
/// `shared/collections/optimistic_revert.dart` instead.
List<String> findWholesaleReverts(String path, List<String> lines) {
  final offenders = <String>[];
  final methodStart = RegExp(r'^  [A-Za-z_][\w<>?,\s]*\s+(\w+)\(');
  final capture = RegExp(r'final\s+(\w+)\s*=\s*state\b');
  final restore = RegExp(r'^\s*state\s*=\s*(?:AsyncData\()?(\w+)\s*[);]');

  final starts = <int>[];
  for (var i = 0; i < lines.length; i++) {
    if (methodStart.hasMatch(lines[i])) starts.add(i);
  }

  for (var s = 0; s < starts.length; s++) {
    final from = starts[s];
    final to = s + 1 < starts.length ? starts[s + 1] : lines.length;
    final body = lines.sublist(from, to);

    // Signature may wrap; take everything up to the opening brace.
    final sigEnd = body.indexWhere((l) => l.contains('{'));
    if (sigEnd < 0) continue;
    final signature = body.sublist(0, sigEnd + 1).join(' ');
    final params = RegExp(r'\(([^)]*)\)').firstMatch(signature)?.group(1) ?? '';
    // No parameters means the operation cannot be about one row.
    if (params.trim().isEmpty) continue;

    final tryAt = body.indexWhere((l) => l.trim().startsWith('try {'));
    if (tryAt < 0) continue;

    final captured = <String>{};
    for (var i = 0; i < tryAt; i++) {
      final m = capture.firstMatch(body[i]);
      if (m != null) captured.add(m.group(1)!);
    }
    if (captured.isEmpty) continue;

    for (var i = tryAt; i < body.length; i++) {
      if (lines[from + i].trimLeft().startsWith('//')) continue;
      final m = restore.firstMatch(body[i]);
      if (m != null && captured.contains(m.group(1))) {
        offenders.add('$path:${from + i + 1}  ${body[i].trim()}');
      }
    }
  }
  return offenders;
}

void main() {
  // Verbatim shapes from the seven sites, so the detector is measured against
  // the real thing rather than against an idea of it.
  const perRowDelete = [
    '  Future<void> delete(String id) async {',
    '    final current = state.valueOrNull ?? [];',
    '    state = AsyncData(current.where((p) => p.id != id).toList());',
    '    try {',
    '      await ref.read(projectRepositoryProvider).delete(id);',
    '    } catch (_) {',
    '      state = AsyncData(current);',
    '      rethrow;',
    '    }',
    '  }',
  ];

  const wholeListClear = [
    '  Future<void> clearAll() async {',
    '    final current = state.valueOrNull;',
    '    if (current == null) return;',
    '    state = AsyncData((memories: const [], count: 0));',
    '    try {',
    '      await ref.read(memoryRepositoryProvider).clearAll();',
    '    } catch (_) {',
    '      state = AsyncData(current);',
    '      rethrow;',
    '    }',
    '  }',
  ];

  const fixedPerRow = [
    '  Future<void> delete(String id) async {',
    '    final current = state.valueOrNull ?? [];',
    '    final wasAt = positionOf(current, (p) => p.id == id);',
    '    if (wasAt < 0) return;',
    '    final removed = current[wasAt];',
    '    state = AsyncData(current.where((p) => p.id != id).toList());',
    '    try {',
    '      await ref.read(projectRepositoryProvider).delete(id);',
    '    } catch (_) {',
    '      state = AsyncData(restoreAt(state.valueOrNull ?? current, removed, wasAt));',
    '      rethrow;',
    '    }',
    '  }',
  ];

  test('the detector catches the shape that shipped seven times', () {
    expect(findWholesaleReverts('x.dart', perRowDelete), hasLength(1));
  });

  test('it leaves the whole-list undo alone', () {
    // clearAll() takes no parameters, so restoring the whole snapshot is its
    // correct undo, not a bug. A guard that flagged this would be noise.
    expect(findWholesaleReverts('x.dart', wholeListClear), isEmpty);
  });

  test('it accepts the fixed form', () {
    expect(findWholesaleReverts('x.dart', fixedPerRow), isEmpty);
  });

  test('no per-row operation in lib/ reverts wholesale', () {
    final offenders = <String>[];
    for (final file
        in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      if (file.path.endsWith('.g.dart') ||
          file.path.endsWith('.freezed.dart')) {
        continue;
      }
      offenders.addAll(findWholesaleReverts(file.path, file.readAsLinesSync()));
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Revert only the affected row — use restoreAt() from '
          'shared/collections/optimistic_revert.dart:\n'
          '${offenders.join('\n')}',
    );
  });
}
