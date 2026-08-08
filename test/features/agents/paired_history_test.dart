import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cyberneurova_mobile/core/agent/device/linux/paired_devices.dart';
import 'package:cyberneurova_mobile/features/agents/presentation/widgets/paired_history.dart';

void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

  PairedDevice device({
    String id = 'phone-1',
    String name = 'SM-A546E',
    String? uid = '2000',
    Duration age = const Duration(days: 40),
  }) =>
      PairedDevice(
        id: id,
        name: name,
        uid: uid,
        firstPairedAt: DateTime.now().subtract(age),
        lastConnectedAt: DateTime.now(),
      );

  testWidgets('names the device and what it was granted', (tester) async {
    await tester.pumpWidget(wrap(
      PairedHistory(devices: [device()], onForget: (_) {}),
    ));

    expect(find.text('SM-A546E'), findsOneWidget);
    // The uid is the difference between "can install apps" and "can do
    // anything", and reviewing a grant should not require reconnecting to
    // find out which one was said yes to.
    expect(find.textContaining('uid 2000'), findsOneWidget);
  });

  testWidgets('dates it from when the grant was MADE', (tester) async {
    await tester.pumpWidget(wrap(
      PairedHistory(
        devices: [device(age: const Duration(days: 40))],
        onForget: (_) {},
      ),
    ));

    // "paired 1 months ago" — recognising when you made it is the point, not
    // when you last used it.
    expect(find.textContaining('paired 1 months ago'), findsOneWidget);
  });

  testWidgets('an unknown uid is omitted rather than shown as null',
      (tester) async {
    await tester.pumpWidget(wrap(
      PairedHistory(devices: [device(uid: null)], onForget: (_) {}),
    ));

    expect(find.textContaining('uid'), findsNothing);
    expect(find.textContaining('paired'), findsOneWidget);
  });

  testWidgets('says that Forget is not a revocation', (tester) async {
    // The half-revocation people assume is a full one: our note goes, the key
    // Android holds does not.
    await tester.pumpWidget(wrap(
      PairedHistory(devices: [device()], onForget: (_) {}),
    ));

    expect(
      find.textContaining('To revoke the access itself'),
      findsOneWidget,
    );
  });

  testWidgets('Forget reports which device', (tester) async {
    String? forgotten;
    await tester.pumpWidget(wrap(
      PairedHistory(
        devices: [device(id: 'a', name: 'A'), device(id: 'b', name: 'B')],
        onForget: (id) => forgotten = id,
      ),
    ));

    await tester.tap(find.text('Forget').last);
    await tester.pump();

    expect(forgotten, 'b');
  });

  testWidgets('several devices each get a row', (tester) async {
    await tester.pumpWidget(wrap(
      PairedHistory(
        devices: [
          device(id: 'a', name: 'Phone A'),
          device(id: 'b', name: 'Phone B'),
          device(id: 'c', name: 'Phone C'),
        ],
        onForget: (_) {},
      ),
    ));

    expect(find.text('Phone A'), findsOneWidget);
    expect(find.text('Phone C'), findsOneWidget);
    expect(find.text('Forget'), findsNWidgets(3));
  });
}
