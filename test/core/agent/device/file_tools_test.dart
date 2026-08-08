import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:cyberneurova_mobile/core/agent/device/authorized_scope.dart';
import 'package:cyberneurova_mobile/core/agent/device/device_capabilities.dart';
import 'package:cyberneurova_mobile/core/agent/device/device_executor.dart';
import 'package:cyberneurova_mobile/core/agent/device/shell_session.dart';
import 'package:cyberneurova_mobile/core/agent/device/tools/file_tools.dart';

/// The file tools are the agent's only durable memory between turns, and they
/// share the session sandbox with `cd`. Both properties are worth locking.
void main() {
  late Directory root;
  late ShellSession session;
  late DeviceToolContext ctx;

  DeviceToolContext makeCtx() => DeviceToolContext(
        capabilities: DeviceCapabilities(
          platform: 'android',
          osVersion: 'test',
          present: DeviceCapabilities.pureDartBaseline,
        ),
        scope: const AuthorizedScope.empty(),
        localSubnetCidrs: const [],
        onProgress: (_) {},
        isCancelled: () => false,
      );

  setUp(() {
    root = Directory.systemTemp.createTempSync('cn_files_test');
    session = ShellSession(rootDir: root.path);
    ctx = makeCtx();
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  group('file_write / file_read round-trip', () {
    test('writes, creates parent dirs, and reads back', () async {
      final write = await FileWriteTool(session: session).run(
        {'path': 'scans/2026/report.md', 'content': '# Findings\nport 22 open'},
        ctx,
      );
      expect(write.ok, isTrue);
      expect(write.artifacts.single['type'], 'file');

      final read = await FileReadTool(session: session)
          .run({'path': 'scans/2026/report.md'}, ctx);
      expect(read.ok, isTrue);
      expect(read.output, contains('port 22 open'));
    });

    test('append adds rather than replaces', () async {
      final tool = FileWriteTool(session: session);
      await tool.run({'path': 'log.txt', 'content': 'first\n'}, ctx);
      await tool.run({'path': 'log.txt', 'content': 'second\n', 'append': true}, ctx);

      final read =
          await FileReadTool(session: session).run({'path': 'log.txt'}, ctx);
      expect(read.output, contains('first'));
      expect(read.output, contains('second'));
    });

    test('read honours an offset/limit line window', () async {
      await FileWriteTool(session: session).run(
        {'path': 'lines.txt', 'content': List.generate(20, (i) => 'line$i').join('\n')},
        ctx,
      );
      final read = await FileReadTool(session: session)
          .run({'path': 'lines.txt', 'offset_lines': 5, 'limit_lines': 3}, ctx);
      expect(read.output, contains('line5'));
      expect(read.output, contains('line7'));
      expect(read.output, isNot(contains('line8')));
    });

    test('reading a missing file fails cleanly', () async {
      final read =
          await FileReadTool(session: session).run({'path': 'nope.txt'}, ctx);
      expect(read.ok, isFalse);
      expect(read.error, contains('No such file'));
    });
  });

  group('sandbox boundary', () {
    test('refuses to write outside the session root', () async {
      final res = await FileWriteTool(session: session)
          .run({'path': '../escaped.txt', 'content': 'nope'}, ctx);
      expect(res.ok, isFalse);
      expect(res.error, contains('outside the session directory'));
      expect(File(p.join(root.parent.path, 'escaped.txt')).existsSync(), isFalse);
    });

    test('refuses to read an absolute path outside the root', () async {
      final res = await FileReadTool(session: session)
          .run({'path': p.join(Directory.systemTemp.path, 'anything.txt')}, ctx);
      expect(res.ok, isFalse);
      expect(res.error, contains('outside the session directory'));
    });
  });

  group('file_list', () {
    test('lists files and directories, defaulting to the shared cwd', () async {
      await FileWriteTool(session: session)
          .run({'path': 'scans/a.txt', 'content': 'x'}, ctx);

      // Move the shared session — file_list with no path must follow it.
      expect(session.changeDirectory('scans'), isNull);
      final res = await FileListTool(session: session).run({}, ctx);

      expect(res.ok, isTrue);
      expect(res.output, contains('a.txt'));
      expect(res.summary, contains('1 file(s)'));
    });

    test('reports an empty directory rather than failing', () async {
      Directory(p.join(root.path, 'empty')).createSync();
      final res =
          await FileListTool(session: session).run({'path': 'empty'}, ctx);
      expect(res.ok, isTrue);
      expect(res.output, contains('empty directory'));
    });
  });
}
