import 'dart:io';

import 'package:cyberneurova_mobile/core/agent/device/authorized_scope.dart';
import 'package:cyberneurova_mobile/core/agent/device/device_capabilities.dart';
import 'package:cyberneurova_mobile/core/agent/device/device_executor.dart';
import 'package:cyberneurova_mobile/core/agent/device/shell_session.dart';
import 'package:cyberneurova_mobile/core/agent/device/tools/file_tools.dart';
import 'package:flutter_test/flutter_test.dart';

/// file_write used to report only "Wrote 2431 chars → notes.md". Before
/// trusting an edit you want to see what changed, so the tool now returns a
/// diff. These drive the tool directly rather than through a model, because
/// whether a given model chooses to call it is a separate question.
void main() {
  late Directory tmp;
  late FileWriteTool tool;
  late DeviceToolContext ctx;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('cn_write_diff');
    tool = FileWriteTool(
      session: ShellSession(rootDir: tmp.path, homeDir: tmp.path),
    );
    ctx = DeviceToolContext(
      capabilities: const DeviceCapabilities(
        platform: 'test',
        osVersion: '1',
        present: {DeviceCapability.fileSandbox},
      ),
      scope: const AuthorizedScope.empty(),
      localSubnetCidrs: const [],
      onProgress: (_) {},
      isCancelled: () => false,
    );
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<String> write(String path, String content, {bool append = false}) async {
    final r = await tool.run(
      {'path': path, 'content': content, 'append': append},
      ctx,
    );
    expect(r.ok, isTrue, reason: r.summary);
    return r.output ?? '';
  }

  test('editing a line shows both the old and the new', () async {
    await write('config.yaml', 'port:8080\nhost:local\ndebug:false\n');
    final out = await write('config.yaml', 'port:8080\nhost:local\ndebug:true\n');

    expect(out, contains('- debug:false'));
    expect(out, contains('+ debug:true'));
    // Untouched lines must not appear as changes.
    expect(out, isNot(contains('- port:8080')));
  });

  test('creating a new file reports the path, not a diff against nothing',
      () async {
    final out = await write('fresh.txt', 'hello\n');
    // A brand-new file has no before-state worth diffing; the card should
    // still say something useful.
    expect(out, isNotEmpty);
  });

  test('append diffs against the whole file, not the fragment', () async {
    await write('log.txt', 'one\ntwo\n');
    final out = await write('log.txt', 'three\n', append: true);

    expect(out, contains('+ three'));
    // `one` survived; it must not read as removed.
    expect(out, isNot(contains('- one')));
  });

  test('rewriting a file with identical content shows no change', () async {
    const body = 'same\ncontent\n';
    await write('x.txt', body);
    final out = await write('x.txt', body);
    expect(out, isNot(contains('+ ')));
    expect(out, isNot(contains('- ')));
  });

  test('the file really is written, diff or not', () async {
    await write('real.txt', 'a\nb\n');
    await write('real.txt', 'a\nc\n');
    expect(File('${tmp.path}/real.txt').readAsStringSync(), 'a\nc\n');
  });
}
