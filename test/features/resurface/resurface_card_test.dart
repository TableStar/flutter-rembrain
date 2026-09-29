import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rembrain/core/db/database.dart';
import 'package:rembrain/core/db/database_provider.dart';
import 'package:rembrain/core/db/note_repo.dart';
import 'package:rembrain/core/db/note_repo_provider.dart';
import 'package:rembrain/features/resurface/ui/resurface_card.dart';

void main() {
  Future<(AppDb, ProviderContainer)> setup(WidgetTester tester) async {
    final db = AppDb(NativeDatabase.memory());
    final repo = NoteRepo(db);
    await repo.insertNote('old thought');
    final container = ProviderContainer(
      overrides: [
        appDbProvider.overrideWithValue(db),
        noteRepoProvider.overrideWithValue(repo),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: ResurfaceCard())),
      ),
    );
    await tester.pumpAndSettle();
    return (db, container);
  }

  testWidgets('shows pick with keep/archive/forget', (tester) async {
    final (db, container) = await setup(tester);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    expect(find.textContaining('you wrote this'), findsOneWidget);
    expect(find.text('keep'), findsOneWidget);
    expect(find.text('archive'), findsOneWidget);
    expect(find.text('forget'), findsOneWidget);
  });

  testWidgets('keep dismisses card this session', (tester) async {
    final (db, container) = await setup(tester);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    await tester.tap(find.text('keep'));
    await tester.pump();
    expect(find.textContaining('you wrote this'), findsNothing);
  });

  testWidgets('forget requires confirm then deletes and dismiss', (
    tester,
  ) async {
    final (db, container) = await setup(tester);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    await tester.tap(find.text('forget'));
    await tester.pumpAndSettle();
    expect(find.text('forget this note foreva?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('confirm-delete')));
    await tester.pumpAndSettle();

    expect(await db.select(db.notes).get(), isEmpty);
    expect(find.textContaining('you wrote this'), findsNothing);
  });

  testWidgets('archives hides note from candidates and dismisses', (
    tester,
  ) async {
    final (db, container) = await setup(tester);
    final repo = container.read(noteRepoProvider);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    await tester.tap(find.text('archive'));
    await tester.pumpAndSettle();

    final notes = await db.select(db.notes).get();
    expect(notes.single.isArchived, isTrue);
    expect(await repo.resurfaceCandidates(), isEmpty);
    expect(find.textContaining('you wrote this'), findsNothing);
  });
}
