import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rembrain/core/db/database.dart';
import 'package:rembrain/core/db/database_provider.dart';
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
}
