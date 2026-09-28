import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rembrain/core/db/database.dart';
import 'package:rembrain/core/db/database_provider.dart';
import 'package:rembrain/core/db/note_repo.dart';
import 'package:rembrain/core/db/note_repo_provider.dart';
import 'package:rembrain/core/router/app_router.dart';
import 'package:rembrain/features/ui/home_screen.dart';
import 'package:rembrain/features/ui/notes_list_screen.dart';
import 'package:rembrain/features/ui/settings_screen.dart';

void main() {
  testWidgets('bottom nav switches between tabs', (tester) async {
    // in-memory DB: the router builds HomeScreen, which from Task 8 reads the
    // repository — the real AppDb() would hit path_provider (no plugin in tests)
    final db = AppDb(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [appDbProvider.overrideWithValue(db)],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: container.read(appRouterProvider),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // assert screen types, not placeholder text — later tasks replace bodies
    expect(find.byType(HomeScreen), findsOneWidget);

    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    expect(find.byType(NotesListScreen), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('renders seeded notes, live-updates on insert', (tester) async {
    final db = AppDb(NativeDatabase.memory());
    final repo = NoteRepo(db);
    await repo.insertNote('alpha note');
    final container = ProviderContainer(
      overrides: [
        appDbProvider.overrideWithValue(db),
        noteRepoProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: NotesListScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('alpha note'), findsOneWidget);

    await repo.insertNote('beta note');
    await tester.pumpAndSettle();
    expect(find.text('beta note'), findsOneWidget);
  });

  testWidgets('shows empty state when no notes', (tester) async {
    final db = AppDb(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        appDbProvider.overrideWithValue(db),
        noteRepoProvider.overrideWithValue(NoteRepo(db)),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: NotesListScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('nothing yet — dump your first thought'), findsOneWidget);
  });
}
