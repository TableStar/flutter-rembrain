import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rembrain/features/notes/ui/quick_dump_box.dart';

import '../../helpers.dart';

void main() {
  testWidgets('inserts note, clears field, shows snackbar', (tester) async {
    final db = makeTestDb();
    final container = makeContainer(db);
    addTearDown(container.dispose);
    addTearDown(db.close);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: QuickDumpBox())),
      ),
    );

    await tester.enterText(find.byType(TextField), 'my first dump');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    final notes = await db.select(db.notes).get();
    expect(notes, hasLength(1));
    expect(notes.single.content, 'my first dump');
    expect(find.text('my first dump'), findsNothing);
    expect(find.text('dumped'), findsOneWidget);
  });

  testWidgets("empty content keeps send disabled", (tester) async {
    final db = makeTestDb();
    final container = makeContainer(db);
    addTearDown(container.dispose);
    addTearDown(db.close);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: QuickDumpBox())),
      ),
    );

    final send = tester.widget<IconButton>(find.byType(IconButton));
    expect(send.onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'x');
    await tester.pump();
    final sendEnabled = tester.widget<IconButton>(find.byType(IconButton));

    expect(sendEnabled.onPressed, isNotNull);
  });
}
