import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/core/agent/neurova_home.dart';

void main() {
  late Directory dir;
  late NeurovaHome home;
  late LocalChatStore store;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('cn_neurova_home');
    home = NeurovaHome(dir.path);
    await home.ensure();
    store = LocalChatStore(home);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  StoredTurn turn(String id, {String role = 'user'}) => StoredTurn(
        id: id,
        role: role,
        content: 'text of $id',
        createdAt: DateTime.utc(2026, 9, 1, 12),
      );

  Map<String, Object?> row(String id, {Object? at = '2026-09-01T12:00:00Z'}) =>
      {'id': id, 'role': 'assistant', 'content': 'text of $id', 'at': at};

  /// Files in chats/ that are not the live chat file — the set-aside copies.
  List<File> setAside(String chatId) => [
        for (final f in home.chats.listSync().whereType<File>())
          if (f.uri.pathSegments.last.startsWith('$chatId.json.unreadable-')) f,
      ];

  test('a save loads back, and a readable file is left where it is', () async {
    await store.save('chat-1', [turn('u1'), turn('a1', role: 'assistant')]);

    final back = await store.load('chat-1');

    expect(back.map((t) => t.id), ['u1', 'a1']);
    expect(back.last.role, 'assistant');
    expect(back.last.content, 'text of a1');
    expect(back.last.createdAt, DateTime.utc(2026, 9, 1, 12));
    expect(setAside('chat-1'), isEmpty);
  });

  test('a missing file is no history, and nothing is created for it', () async {
    expect(await store.load('chat-1'), isEmpty);
    expect(home.chats.listSync(), isEmpty);
  });

  test('one malformed turn costs that turn, not the conversation', () async {
    // A single non-string `at` used to throw out of the load loop, and the
    // whole chat read as empty.
    home.chatFile('chat-1').writeAsStringSync(jsonEncode({
          'v': 1,
          'chat_id': 'chat-1',
          'turns': [
            row('m1'),
            row('m2', at: {'when': 'yesterday'}),
            {'id': 42, 'role': 'user', 'content': 'id is not a string'},
            'not a turn at all',
            row('m3'),
          ],
        }));

    final back = await store.load('chat-1');

    expect(back.map((t) => t.id), ['m1', 'm2', 'm3']);
    // A timestamp it cannot read keeps the text and falls back to the epoch.
    expect(back[1].content, 'text of m2');
    expect(back[1].createdAt, DateTime.fromMillisecondsSinceEpoch(0));
    expect(setAside('chat-1'), isEmpty);
  });

  test('an epoch timestamp is read as milliseconds; a missing one is epoch 0',
      () async {
    final missing = row('m3')..remove('at');
    home.chatFile('chat-1').writeAsStringSync(jsonEncode({
          'v': 1,
          'turns': [
            row('m1', at: 1727000000000),
            row('m2', at: 1727000000000.0),
            missing,
            row('m4', at: 1e300),
          ],
        }));

    final back = await store.load('chat-1');

    expect(back.map((t) => t.id), ['m1', 'm2', 'm3', 'm4']);
    final epoch = DateTime.fromMillisecondsSinceEpoch(1727000000000);
    expect(back[0].createdAt, epoch);
    expect(back[1].createdAt, epoch);
    expect(back[2].createdAt, DateTime.fromMillisecondsSinceEpoch(0));
    // Out of DateTime's range: the turn stays, its timestamp does not.
    expect(back[3].createdAt, DateTime.fromMillisecondsSinceEpoch(0));
  });

  // Every shape below used to load as "no history" and then be written over
  // by the next save. The bytes must survive under the set-aside name.
  final unreadable = <String, List<int>>{
    'a truncated file': utf8.encode(
        '{"v": 1, "chat_id": "chat-1", "turns": [{"id": "m1", "role": "us'),
    'a file from another version': utf8.encode(jsonEncode({
      'v': 2,
      'turns': [row('m1')],
    })),
    'a file without a version': utf8.encode(jsonEncode({
      'turns': [row('m1')],
    })),
    'a turns field that is not a list': utf8.encode(jsonEncode({
      'v': 1,
      'turns': {'m1': row('m1')},
    })),
    'JSON that is not an object': utf8.encode(jsonEncode([row('m1')])),
    // Cut inside a multi-byte character: readAsString itself throws.
    'a file that is not UTF-8': [
      ...utf8.encode('{"v": 1, "turns": [{"content": "caf'),
      0xC3,
    ],
  };

  for (final MapEntry(key: name, value: bytes) in unreadable.entries) {
    test('$name is set aside, and the next save does not write over it',
        () async {
      home.chatFile('chat-1').writeAsBytesSync(bytes);

      expect(await store.load('chat-1'), isEmpty);

      final kept = setAside('chat-1');
      expect(kept, hasLength(1));
      expect(kept.single.readAsBytesSync(), bytes);
      expect(home.chatFile('chat-1').existsSync(), isFalse);

      // What _persistLocally does on the next prompt.
      await store.save('chat-1', [turn('u-new')]);

      expect(kept.single.readAsBytesSync(), bytes);
      final fresh = await store.load('chat-1');
      expect(fresh.map((t) => t.id), ['u-new']);
      expect(setAside('chat-1'), hasLength(1));
    });
  }

  test('an empty save after an unreadable load does not delete the copy',
      () async {
    // save([]) deletes the chat file; with the file moved aside first there
    // is nothing of the old conversation left for it to delete.
    final bytes = utf8.encode(jsonEncode({'v': 2, 'turns': []}));
    home.chatFile('chat-1').writeAsBytesSync(bytes);

    await store.load('chat-1');
    await store.save('chat-1', const []);

    expect(setAside('chat-1').single.readAsBytesSync(), bytes);
  });

  test('setting aside twice keeps both copies', () async {
    // Two in the same second would share a timestamp, and a rename onto an
    // existing name replaces it on POSIX.
    home.chatFile('chat-1').writeAsStringSync('{first');
    await store.load('chat-1');
    home.chatFile('chat-1').writeAsStringSync('{second');
    await store.load('chat-1');

    final kept = setAside('chat-1').map((f) => f.readAsStringSync()).toSet();
    expect(kept, {'{first', '{second'});
  });

  test('setting one chat aside leaves the others alone', () async {
    await store.save('chat-2', [turn('u1')]);
    home.chatFile('chat-1').writeAsStringSync('{not json');

    await store.load('chat-1');

    expect(setAside('chat-2'), isEmpty);
    expect((await store.load('chat-2')).map((t) => t.id), ['u1']);
  });

  test('overlapping loads of an unreadable file do not leave saves blocked',
      () async {
    // Overlapping loads race to move the same file aside. The losers' rename
    // fails — on POSIX because the file is already gone, on Windows also
    // while another load still has it open — and once blocked the save was
    // skipped even though the file was already out of the way: the new turns
    // were dropped and no chat file was left. Several rounds, because the
    // interleaving differs from run to run.
    for (var round = 0; round < 20; round++) {
      final id = 'race$round';
      home.chatFile(id).writeAsStringSync('{not json');

      await Future.wait([for (var i = 0; i < 8; i++) store.load(id)]);
      await store.save(id, [turn('u1')]);

      expect(home.chatFile(id).existsSync(), isTrue, reason: 'round $round');
    }
  });
}
