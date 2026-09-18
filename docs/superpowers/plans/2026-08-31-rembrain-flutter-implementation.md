# Rembrain (Flutter) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **NEVER run `git commit` / `git add`. The human commits manually. Do not touch git.**

**Goal:** Local-only Android note app: dump thoughts, `#hashtag` tags, age-weighted resurfacing, archive/delete — built phase-by-phase as a Flutter learning vehicle.

**Architecture:** Feature-first, 2 layers (`data/` + `ui/`, no domain layer). drift (SQLite) is the single source of truth; `watch()` streams push changes into Riverpod StreamProviders which feed the UI. Pure logic (tag parsing, weighted pick) lives in plain Dart functions, unit-tested without Flutter.

**Tech Stack:** Flutter 3.47 / Dart 3.13, flutter_riverpod + riverpod_annotation (codegen), drift + drift_dev (codegen), go_router, shared_preferences.

## Global Constraints

- Android only. Do not add/adjust web/desktop platform targets.
- Local SQLite only. No network calls, no auth, no server anywhere in this plan.
- No soft delete: hard delete + confirm dialog.
- `content` is stored verbatim — hashtags are parsed for the tag relation, never stripped from stored text.
- Tags are case-insensitive: normalized to lowercase before storage.
- Material 3, dark-first theme.
- Tap targets ≥ 44px; primary actions thumb-reachable; no horizontal scroll at 375px.
- Schema reserves `aiTitle` / `aiContent` columns now (nullable, unused) — AI phase must not need a migration.
- Codegen: run `dart run build_runner build --delete-conflicting-outputs` after any change to drift tables or `@riverpod` functions. Never hand-edit `.g.dart` files.
- Every task ends green: `flutter analyze` → "No issues found!", `flutter test` → "All tests passed!".
- drift stores `DateTime` as unix **seconds**. Two writes in the same second share a timestamp: every `createdAt`/`lastResurfacedAt` ordering needs an `id` tiebreaker, and tests must never assert sub-second timestamp deltas.
- **No commits. The human commits when they choose.**

## File Map (final state)

```
lib/
  main.dart                          Task 3
  app.dart                           Task 3   (RembrainApp: MaterialApp.router + theme)
  core/
    db/
      tables.dart                    Task 2   (Notes, Tags, NoteTags drift tables)
      database.dart                  Task 2   (AppDb @DriftDatabase, connection)
      database_provider.dart         Task 2   (appDbProvider)
      note_repository.dart           Task 4   (all DB queries; Task 9 adds tag sync)
      note_repository_provider.dart  Task 4
    router/
      app_router.dart                Task 3
    theme/
      app_theme.dart                 Task 3
    utils/
      date_format.dart               Task 6
  features/
    notes/
      data/                          (empty marker — repository lives in core/db per single-DB design; delete this dir if you prefer)
      ui/
        home_screen.dart             Task 5
        quick_dump_box.dart          Task 5
        notes_list_screen.dart       Task 6
        note_card.dart               Task 6
        note_detail_screen.dart      Task 11
        note_edit_screen.dart        Task 12
        tag_chip.dart                Task 10
      notes_providers.dart           Task 5   (final: filteredNotes, tags, notesFilter, noteById)
    resurface/
      resurface_logic.dart           Task 7   (pure weighted pick)
      resurface_providers.dart       Task 8
      ui/resurface_card.dart         Task 8
    settings/
      settings_providers.dart        Task 14
      ui/settings_screen.dart        Task 14
test/
  core/db/database_test.dart         Task 2
  core/db/note_repository_test.dart  Task 4, 9
  core/db/resurface_queries_test.dart Task 8
  features/notes/quick_dump_box_test.dart   Task 5
  features/notes/notes_list_screen_test.dart Task 6
  features/notes/note_detail_screen_test.dart Task 11
  features/notes/note_edit_screen_test.dart  Task 12
  features/resurface/resurface_logic_test.dart Task 7
  features/resurface/resurface_card_test.dart  Task 8
  features/notes/tag_util_test.dart    Task 9
  features/settings/settings_screen_test.dart  Task 14
  helpers.dart                        Task 5  (test container with in-memory DB)
lib/features/notes/data/tag_util.dart  Task 9  (pure tag parsing)
```

> Naming note: `tag_util.dart` is app-specific business logic (not a generic helper), so it lives in the notes feature, not `core/utils/`.

---

## Phase 0 — Foundation

### Task 1: Dependencies + codegen pipeline

**Files:**
- Modify: `pubspec.yaml` (via flutter pub add — do not hand-edit versions)

**Interfaces:**
- Produces: a project where `dart run build_runner build --delete-conflicting-outputs` works and all later task versions resolve.

- [ ] **Step 1: Add runtime dependencies**

```bash
flutter pub add flutter_riverpod riverpod_annotation go_router drift sqlite3_flutter_libs path_provider path shared_preferences
```

Expected: pubspec.yaml updated, `flutter pub get` runs clean.

- [ ] **Step 2: Add dev dependencies**

```bash
flutter pub add -d riverpod_generator drift_dev build_runner
```

- [ ] **Step 3: Verify toolchain**

```bash
flutter analyze
```

Expected: `No issues found!` (scaffold code). Codegen not yet exercised — Task 2 verifies it.

- [ ] **Step 4: Human commits (optional, yours to run)**

### Task 2: Drift schema — tables, database, provider

**Files:**
- Create: `lib/core/db/tables.dart`
- Create: `lib/core/db/database.dart`
- Create: `lib/core/db/database_provider.dart`
- Test: `test/core/db/database_test.dart`

**Interfaces:**
- Produces: `AppDb` class; generated row classes `Note`, `Tag`, `NoteTag`; generated `_$AppDb`; `appDbProvider` (keepAlive, closes DB on dispose). All later tasks use these exact names.

> **Learn:** drift = Prisma-for-Dart. You declare tables as Dart classes, build_runner generates a type-safe query client. Row class names are the singular of table class names (`Notes` → `Note`). Every column getter ends in `()` — that's drift's column-builder DSL.

- [ ] **Step 1: Write the failing test**

`test/core/db/database_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rembrain/core/db/database.dart';

void main() {
  late AppDb db;

  setUp(() {
    db = AppDb(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  test('inserts a note with defaults and reads it back', () async {
    final id = await db.into(db.notes).insert(
          const NotesCompanion.insert(content: 'hello #world'),
        );

    final note = await (db.select(db.notes)..where((n) => n.id.equals(id))).getSingle();

    expect(note.content, 'hello #world');
    expect(note.isArchived, false);
    expect(note.resurfaceCount, 0);
    expect(note.lastResurfacedAt, isNull);
    expect(note.createdAt, isNotNull);
  });

  test('note_tags cascade on note delete', () async {
    final noteId = await db.into(db.notes).insert(
          const NotesCompanion.insert(content: 'n'),
        );
    final tagId = await db.into(db.tags).insert(const TagsCompanion.insert(name: 'a'));
    await db.into(db.noteTags).insert(
          NoteTagsCompanion.insert(noteId: noteId, tagId: tagId),
        );

    await (db.delete(db.notes)..where((n) => n.id.equals(noteId))).go();

    final links = await db.select(db.noteTags).get();
    expect(links, isEmpty);
  });

  test('tags name is unique', () async {
    await db.into(db.tags).insert(const TagsCompanion.insert(name: 'dup'));
    await expectLater(
      db.into(db.tags).insert(const TagsCompanion.insert(name: 'dup')),
      throwsA(anything),
    );
  });
}
```

- [ ] **Step 2: Create tables + database (implementation)**

`lib/core/db/tables.dart`:

```dart
import 'package:drift/drift.dart';

class Notes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get content => text()();
  TextColumn get title => text().nullable()();
  TextColumn get aiTitle => text().nullable()();      // reserved for AI phase
  TextColumn get aiContent => text().nullable()();    // reserved for AI phase
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  IntColumn get resurfaceCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastResurfacedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

class Tags extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().unique()();
}

class NoteTags extends Table {
  IntColumn get noteId => integer().references(Notes, #id)();
  IntColumn get tagId => integer().references(Tags, #id)();

  @override
  Set<Column> get primaryKey => {noteId, tagId};
}
```

`lib/core/db/database.dart`:

```dart
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Notes, Tags, NoteTags])
class AppDb extends _$AppDb {
  // ONE unnamed constructor — optional positional executor:
  // AppDb() → real device file, AppDb(NativeDatabase.memory()) → tests.
  // Dart forbids two unnamed constructors per class.
  AppDb([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 1;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'rembrain.sqlite'));
    return NativeDatabase(file);
  });
}
```

`lib/core/db/database_provider.dart`:

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'database.dart';

part 'database_provider.g.dart';

@Riverpod(keepAlive: true)
AppDb appDb(Ref ref) {
  final db = AppDb();
  ref.onDispose(db.close);
  return db;
}
```

> In tests we construct `AppDb(NativeDatabase.memory())` directly and override `appDbProvider` — the `_openConnection()` file path is only used by the default constructor in `main.dart`.

- [ ] **Step 3: Run codegen**

```bash
dart run build_runner build --delete-conflicting-outputs
```

Expected: succeeds, generates `database.g.dart` and `database_provider.g.dart`. If it reports errors in the test file about missing names, that's expected until generation completes — rerun analyze after.

- [ ] **Step 4: Run tests**

```bash
flutter test test/core/db/database_test.dart
```

Expected: All tests passed. (If sqlite3 is missing on host, install system `sqlite` — Arch ships it; Android gets it via `sqlite3_flutter_libs`.)

- [ ] **Step 5: `flutter analyze` → No issues found!**

### Task 3: Theme, router, bottom-nav skeleton

**Files:**
- Create: `lib/core/theme/app_theme.dart`
- Create: `lib/core/router/app_router.dart`
- Create: `lib/features/notes/ui/home_screen.dart` (placeholder)
- Create: `lib/features/notes/ui/notes_list_screen.dart` (placeholder)
- Create: `lib/features/settings/ui/settings_screen.dart` (placeholder)
- Create: `lib/app.dart`
- Modify: `lib/main.dart`
- Test: `test/features/notes/notes_list_screen_test.dart` (nav smoke test)

**Interfaces:**
- Produces: `appThemeProvider` (ThemeData dark + light), `appRouterProvider` (go_router), `RembrainApp` widget. Routes: `/` (Home), `/notes`, `/settings`, `/notes/:id` (detail, Task 11), `/notes/:id/edit` (edit, Task 12). Placeholder screens export `HomeScreen`, `NotesListScreen`, `SettingsScreen` — later tasks replace bodies, keep names.

> **Learn:** go_router = React Router. `StatefulShellRoute.indexedStack` gives each bottom-nav tab its own navigator so state survives tab switches — the idiomatic Material 3 `NavigationBar` pattern.

- [ ] **Step 1: Write the failing test**

`test/features/notes/notes_list_screen_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rembrain/core/db/database.dart';
import 'package:rembrain/core/db/database_provider.dart';
import 'package:rembrain/core/router/app_router.dart';
import 'package:rembrain/features/notes/ui/home_screen.dart';
import 'package:rembrain/features/notes/ui/notes_list_screen.dart';
import 'package:rembrain/features/settings/ui/settings_screen.dart';

void main() {
  testWidgets('bottom nav switches between tabs', (tester) async {
    // in-memory DB: the router builds HomeScreen, which from Task 8 reads the
    // repository — the real AppDb() would hit path_provider (no plugin in tests)
    final db = AppDb(NativeDatabase.memory());
    final container = ProviderContainer(overrides: [
      appDbProvider.overrideWithValue(db),
    ]);
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
```

- [ ] **Step 2: Implement theme, router, screens, app**

`lib/core/theme/app_theme.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_theme.g.dart';

@riverpod
ThemeData darkTheme(Ref ref) => ThemeData(useMaterial3: true, brightness: Brightness.dark);

@riverpod
ThemeData lightTheme(Ref ref) => ThemeData(useMaterial3: true, brightness: Brightness.light);
```

`lib/core/router/app_router.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/notes/ui/home_screen.dart';
import '../../features/notes/ui/notes_list_screen.dart';
import '../../features/settings/ui/settings_screen.dart';

part 'app_router.g.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => ScaffoldWithNav(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/notes', builder: (_, __) => const NotesListScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
          ]),
        ],
      ),
    ],
  );
}

class ScaffoldWithNav extends StatelessWidget {
  const ScaffoldWithNav({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(
          i,
          initialLocation: i == shell.currentIndex,
        ),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.notes_outlined), selectedIcon: Icon(Icons.notes), label: 'Notes'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
```

Placeholders (replace bodies in later tasks, keep class names):

`lib/features/notes/ui/home_screen.dart`:

```dart
import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Rembrain')));
  }
}
```

`lib/features/notes/ui/notes_list_screen.dart`:

```dart
import 'package:flutter/material.dart';

class NotesListScreen extends StatelessWidget {
  const NotesListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Notes list')));
  }
}
```

`lib/features/settings/ui/settings_screen.dart`:

```dart
import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Settings placeholder')));
  }
}
```

`lib/app.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rembrain/core/router/app_router.dart';
import 'package:rembrain/core/theme/app_theme.dart';

class RembrainApp extends ConsumerWidget {
  const RembrainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'Rembrain',
      theme: ref.watch(lightThemeProvider),
      darkTheme: ref.watch(darkThemeProvider),
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
```

`lib/main.dart` (replace whole file):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  runApp(const ProviderScope(child: RembrainApp()));
}
```

- [ ] **Step 3: Codegen + tests + analyze**

```bash
dart run build_runner build --delete-conflicting-outputs
flutter test test/features/notes/notes_list_screen_test.dart
flutter analyze
```

Expected: test passes, `No issues found!`

- [ ] **Step 4: Run on device once** — `flutter run` with phone connected. Verify: 3 tabs switch, dark theme.

---

## Phase 1 — Dump + Notes list

### Task 4: Note repository (data layer)

**Files:**
- Create: `lib/core/db/note_repository.dart`
- Create: `lib/core/db/note_repository_provider.dart`
- Test: `test/core/db/note_repository_test.dart`

**Interfaces:**
- Consumes: `AppDb` schema (Task 2).
- Produces: `NoteRepository` with exact signatures:

```dart
Stream<List<Note>> watchNotes();                      // newest first
Future<Note> insertNote(String content, {String? title});
Stream<Note?> watchNote(int id);
Future<void> updateNote(int id, {required String content, String? title});
Future<void> deleteNote(int id);
Future<void> setArchived(int id, bool archived);
Future<Note> markResurfaced(int id);                  // count+1, set lastResurfacedAt=now, returns row
```

plus `noteRepositoryProvider` (keepAlive).

> **Learn:** repository = your `Eloquent`-equivalent boundary. UI never touches `AppDb` directly, only this class — so phase 3's tag sync and a future AI hook have one place to live.

- [ ] **Step 1: Write the failing test**

`test/core/db/note_repository_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rembrain/core/db/database.dart';
import 'package:rembrain/core/db/note_repository.dart';

void main() {
  late AppDb db;
  late NoteRepository repo;

  setUp(() {
    db = AppDb(NativeDatabase.memory());
    repo = NoteRepository(db);
  });

  tearDown(() async => db.close());

  test('insertNote returns created row, newest first in watchNotes', () async {
    final a = await repo.insertNote('first');
    final b = await repo.insertNote('second');

    final list = await repo.watchNotes().first;
    expect(list.map((n) => n.id), [b.id, a.id]);
    expect(list.first.content, 'second');
  });

  test('updateNote changes content', () async {
    final n = await repo.insertNote('before');
    await repo.updateNote(n.id, content: 'after');

    final after = (await repo.watchNote(n.id).first)!;
    expect(after.content, 'after');
  });

  test('setArchived toggles flag', () async {
    final n = await repo.insertNote('x');
    await repo.setArchived(n.id, true);
    expect((await repo.watchNote(n.id).first)!.isArchived, isTrue);
  });

  test('markResurfaced bumps count and timestamp', () async {
    final n = await repo.insertNote('x');
    final updated = await repo.markResurfaced(n.id);
    expect(updated.resurfaceCount, 1);
    expect(updated.lastResurfacedAt, isNotNull);
  });

  test('deleteNote removes row', () async {
    final n = await repo.insertNote('x');
    await repo.deleteNote(n.id);
    expect(await repo.watchNote(n.id).first, isNull);
  });
}
```

- [ ] **Step 2: Implement repository**

`lib/core/db/note_repository.dart`:

```dart
import 'package:drift/drift.dart';

import 'database.dart';

class NoteRepository {
  NoteRepository(this._db);

  final AppDb _db;

  Stream<List<Note>> watchNotes() {
    return (_db.select(_db.notes)
          ..orderBy([
            (n) => OrderingTerm.desc(n.createdAt),
            (n) => OrderingTerm.desc(n.id), // tiebreaker: DateTime stores seconds
          ]))
        .watch();
  }

  Future<Note> insertNote(String content, {String? title}) async {
    final id = await _db.into(_db.notes).insert(
          NotesCompanion.insert(content: content, title: Value(title)),
        );
    return (_db.select(_db.notes)..where((n) => n.id.equals(id))).getSingle();
  }

  Stream<Note?> watchNote(int id) {
    return (_db.select(_db.notes)..where((n) => n.id.equals(id)))
        .watchSingleOrNull();
  }

  Future<void> updateNote(int id, {required String content, String? title}) {
    return (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        content: Value(content),
        title: Value(title),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteNote(int id) {
    return (_db.delete(_db.notes)..where((n) => n.id.equals(id))).go();
  }

  Future<void> setArchived(int id, bool archived) {
    return (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(isArchived: Value(archived), updatedAt: Value(DateTime.now())),
    );
  }

  Future<Note> markResurfaced(int id) async {
    // Companion.custom keeps the increment in SQL (no read-modify-write race)
    // and stays on drift's core API, so watch() streams are notified.
    await (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion.custom(
        resurfaceCount: _db.notes.resurfaceCount + const Constant(1),
        lastResurfacedAt: Value(DateTime.now()),
      ),
    );
    return (_db.select(_db.notes)..where((n) => n.id.equals(id))).getSingle();
  }
}
```

`lib/core/db/note_repository_provider.dart`:

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'database_provider.dart';
import 'note_repository.dart';

part 'note_repository_provider.g.dart';

@Riverpod(keepAlive: true)
NoteRepository noteRepository(Ref ref) =>
    NoteRepository(ref.watch(appDbProvider));
```

- [ ] **Step 3: Codegen, tests, analyze**

```bash
dart run build_runner build --delete-conflicting-outputs
flutter test test/core/db/
flutter analyze
```

Expected: all pass.

### Task 5: Quick dump box + Home screen + notes list provider

**Files:**
- Create: `lib/features/notes/notes_providers.dart`
- Create: `lib/features/notes/ui/quick_dump_box.dart`
- Modify: `lib/features/notes/ui/home_screen.dart` (real body)
- Test: `test/helpers.dart`
- Test: `test/features/notes/quick_dump_box_test.dart`

**Interfaces:**
- Consumes: `noteRepositoryProvider` (Task 4).
- Produces:
  - `@riverpod Stream<List<Note>> notesList(Ref ref)` → `notesListProvider`
  - `QuickDumpBox` widget — multiline field + send IconBtn; on insert success clears field + shows snackbar "dumped"; on failure shows error snackbar and KEEPS text.
  - `HomeScreen` = `QuickDumpBox` at top (SafeArea, padding 16).
  - `test/helpers.dart` → `ProviderContainer makeContainer(AppDb db)` helper used by all widget tests from now on.

> **Learn:** `TextEditingController` is Flutter's controlled-input (like React's `value`+`onChange`, but imperative: you own a controller object and dispose it). A `ConsumerStatefulWidget` is what you use when a widget holds controllers + reads providers.

- [ ] **Step 1: Write the failing test**

`test/helpers.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rembrain/core/db/database.dart';
import 'package:rembrain/core/db/database_provider.dart';
import 'package:rembrain/core/db/note_repository.dart';
import 'package:rembrain/core/db/note_repository_provider.dart';

AppDb makeTestDb() => AppDb(NativeDatabase.memory());

ProviderContainer makeContainer(AppDb db) {
  final container = ProviderContainer(overrides: [
    appDbProvider.overrideWithValue(db),
    noteRepositoryProvider.overrideWithValue(NoteRepository(db)),
  ]);
  return container;
}
```

`test/features/notes/quick_dump_box_test.dart`:

```dart
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

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: QuickDumpBox())),
      ),
    );

    await tester.enterText(find.byType(TextField), 'my first dump');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    final notes = await db.select(db.notes).get();
    expect(notes, hasLength(1));
    expect(notes.single.content, 'my first dump');
    expect(find.text('my first dump'), findsNothing); // cleared
    expect(find.text('dumped'), findsOneWidget);     // snackbar
  });

  testWidgets('empty content keeps send disabled', (tester) async {
    final db = makeTestDb();
    final container = makeContainer(db);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: QuickDumpBox())),
      ),
    );

    // IconButton exists but is disabled until text appears
    final send = tester.widget<IconButton>(find.byIcon(Icons.send));
    expect(send.onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'x');
    await tester.pump();
    final sendEnabled =
        tester.widget<IconButton>(find.byIcon(Icons.send));
    expect(sendEnabled.onPressed, isNotNull);
  });
}
```

- [ ] **Step 2: Implement provider + widget + screen**

`lib/features/notes/notes_providers.dart`:

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/db/database.dart';
import '../../core/db/note_repository_provider.dart';

part 'notes_providers.g.dart';

@riverpod
Stream<List<Note>> notesList(Ref ref) =>
    ref.watch(noteRepositoryProvider).watchNotes();
```

`lib/features/notes/ui/quick_dump_box.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/note_repository_provider.dart';

class QuickDumpBox extends ConsumerStatefulWidget {
  const QuickDumpBox({super.key});

  @override
  ConsumerState<QuickDumpBox> createState() => _QuickDumpBoxState();
}

class _QuickDumpBoxState extends ConsumerState<QuickDumpBox> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final content = _controller.text.trim();
    if (content.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(noteRepositoryProvider).insertNote(content);
      _controller.clear();
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('dumped')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('failed to save — text kept')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _controller.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(
                hintText: 'dump a thought… #tag it if you like',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            // 48px — meets ≥44px tap target constraint
            onPressed: hasText && !_sending ? _send : null,
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}
```

`lib/features/notes/ui/home_screen.dart` (replace body):

```dart
import 'package:flutter/material.dart';

import 'quick_dump_box.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(child: Column(children: [QuickDumpBox()])),
    );
  }
}
```

- [ ] **Step 3: Codegen, tests, analyze, device check**

```bash
dart run build_runner build --delete-conflicting-outputs
flutter test test/features/notes/quick_dump_box_test.dart
flutter analyze
```

Then `flutter run`: dump a thought on the phone, see the snackbar.

### Task 6: Notes list screen with live cards

**Files:**
- Create: `lib/core/utils/date_format.dart`
- Create: `lib/features/notes/ui/note_card.dart`
- Modify: `lib/features/notes/ui/notes_list_screen.dart` (real body)
- Test: `test/features/notes/notes_list_screen_test.dart` (add list test, keep nav test)

**Interfaces:**
- Consumes: `notesListProvider` (Task 5).
- Produces: `NoteCard` (shows content preview max 3 lines, `daysAgoLabel(createdAt)`); `daysAgoLabel(DateTime)` in `core/utils/date_format.dart` (also used by resurface card, Task 8). Empty state text: `nothing yet — dump your first thought`.

- [ ] **Step 1: Write the failing test** (append to `test/features/notes/notes_list_screen_test.dart`):

```dart
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rembrain/core/db/database.dart';
import 'package:rembrain/core/db/database_provider.dart';
import 'package:rembrain/core/db/note_repository.dart';
import 'package:rembrain/core/db/note_repository_provider.dart';
import 'package:rembrain/features/notes/ui/notes_list_screen.dart';

void main() {
  // ...existing nav test stays...

  testWidgets('renders seeded notes, live-updates on insert', (tester) async {
    final db = AppDb(NativeDatabase.memory());
    final repo = NoteRepository(db);
    await repo.insertNote('alpha note');
    final container = ProviderContainer(overrides: [
      appDbProvider.overrideWithValue(db),
      noteRepositoryProvider.overrideWithValue(repo),
    ]);
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

    // live update without rebuild — the drift watch() payoff
    await repo.insertNote('beta note');
    await tester.pumpAndSettle();
    expect(find.text('beta note'), findsOneWidget);
  });

  testWidgets('shows empty state when no notes', (tester) async {
    final db = AppDb(NativeDatabase.memory());
    final container = ProviderContainer(overrides: [
      appDbProvider.overrideWithValue(db),
      noteRepositoryProvider.overrideWithValue(NoteRepository(db)),
    ]);
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
```

- [ ] **Step 2: Implement**

`lib/core/utils/date_format.dart`:

```dart
String daysAgoLabel(DateTime d) {
  final days = DateTime.now().difference(d).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  return '$days days ago';
}
```

`lib/features/notes/ui/note_card.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../core/db/database.dart';
import '../../../core/utils/date_format.dart';

class NoteCard extends StatelessWidget {
  const NoteCard({super.key, required this.note, this.onTap});

  final Note note;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        onTap: onTap,
        title: Text(
          note.title ?? note.content,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(daysAgoLabel(note.createdAt)),
      ),
    );
  }
}
```

`lib/features/notes/ui/notes_list_screen.dart` (replace body):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'note_card.dart';
import '../notes_providers.dart';

class NotesListScreen extends ConsumerWidget {
  const NotesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(notesListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Notes list')),
      body: notesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('error: $e')),
        data: (notes) => notes.isEmpty
            ? const Center(child: Text('nothing yet — dump your first thought'))
            : ListView.builder(
                itemCount: notes.length,
                itemBuilder: (_, i) => NoteCard(note: notes[i]),
              ),
      ),
    );
  }
}
```

- [ ] **Step 3: Run tests + analyze**

```bash
dart run build_runner build --delete-conflicting-outputs
flutter test test/features/notes/notes_list_screen_test.dart
flutter analyze
```

Expected: pass. Device check: dump on Home, switch to Notes tab — the note is already there (watch stream).

---

## Phase 2 — Resurface

### Task 7: Pure weighted-pick logic

**Files:**
- Create: `lib/features/resurface/resurface_logic.dart`
- Test: `test/features/resurface/resurface_logic_test.dart`

**Interfaces:**
- Produces (Task 8 consumes):

```dart
/// Picks one item, weight = age in days + 1 (linear; older = more likely).
/// items and createdAt must be same length, non-empty.
/// `now` is injected so tests are deterministic forever — never call
/// DateTime.now() inside; the caller passes it.
T pickWeighted<T>(
  List<T> items,
  List<DateTime> createdAt,
  DateTime now,
  Random rng,
);
```

Throws `ArgumentError` on empty input / length mismatch.

> **Learn:** this is why we keep logic pure — no drift, no Flutter, no mocks needed. `Random` and `now` injected = deterministic tests (seed it, pin the clock).

- [ ] **Step 1: Write the failing test**

`test/features/resurface/resurface_logic_test.dart`:

```dart
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:rembrain/features/resurface/resurface_logic.dart';

void main() {
  final now = DateTime(2026, 9, 15);

  DateTime daysAgo(int d) => now.subtract(Duration(days: d));

  test('throws on empty or mismatched input', () {
    expect(() => pickWeighted([], [], now, Random(1)), throwsArgumentError);
    expect(
        () => pickWeighted(['a'], [daysAgo(1), daysAgo(2)], now, Random(1)),
        throwsArgumentError);
  });

  test('never picks excluded / always returns a member', () {
    final items = ['a', 'b', 'c'];
    final picked = {
      for (var i = 0; i < 200; i++)
        pickWeighted(
            items, [daysAgo(1), daysAgo(10), daysAgo(100)], now, Random(i)),
    };
    expect(picked.difference(items.toSet()), isEmpty);
  });

  test('older notes picked more often (fixed clock, seeded rng)', () {
    final items = ['young', 'old'];
    var oldPicks = 0;
    for (var i = 0; i < 1000; i++) {
      final pick =
          pickWeighted(items, [daysAgo(1), daysAgo(99)], now, Random(i));
      if (pick == 'old') oldPicks++;
    }
    // weights: young=2, old=100 → old ≈ 98%. Generous floor guards flakiness.
    expect(oldPicks, greaterThan(900));
  });

  test('single candidate returns it', () {
    expect(pickWeighted(['only'], [daysAgo(5)], now, Random(1)), 'only');
  });
}
```

- [ ] **Step 2: Implement**

`lib/features/resurface/resurface_logic.dart`:

```dart
import 'dart:math';

/// Weighted random pick: weight = days since createdAt + 1 (linear).
/// Older notes are proportionally more likely. Pure function — no IO,
/// no clock reads; `now` comes from the caller.
T pickWeighted<T>(
  List<T> items,
  List<DateTime> createdAt,
  DateTime now,
  Random rng,
) {
  if (items.isEmpty || items.length != createdAt.length) {
    throw ArgumentError('items and createdAt must be non-empty and same length');
  }
  final weights = createdAt
      .map((c) => now.difference(c).inDays + 1)
      .map((w) => w < 1 ? 1 : w) // future-dated notes still eligible
      .toList();
  final total = weights.reduce((a, b) => a + b);
  var roll = rng.nextInt(total);
  for (var i = 0; i < items.length; i++) {
    roll -= weights[i];
    if (roll < 0) return items[i];
  }
  return items.last; // unreachable for valid input; satisfies the analyzer
}
```

- [ ] **Step 3: Run test**

```bash
flutter test test/features/resurface/resurface_logic_test.dart
```

Expected: all pass.

### Task 8: Resurface provider + card on Home

**Files:**
- Modify: `lib/core/db/note_repository.dart` (add `resurfaceCandidates()`)
- Create: `lib/features/resurface/resurface_providers.dart`
- Create: `lib/features/resurface/ui/resurface_card.dart`
- Modify: `lib/features/notes/ui/home_screen.dart` (add card above dump box)
- Test: `test/core/db/resurface_queries_test.dart`, `test/features/resurface/resurface_card_test.dart`

**Interfaces:**
- Consumes: `pickWeighted` (Task 7), `NoteRepository` (Task 4).
- Produces:
  - `NoteRepository.resurfaceCandidates()` → `Future<List<Note>>`: non-archived, excluding the most-recently-resurfaced note (if any).
  - `@riverpod Future<Note?> resurfacePick(Ref ref)` → `resurfacePickProvider`: picks one via `pickWeighted`, marks it resurfaced, null when no candidates. One-shot per watch — NOT a stream — so marking a note resurfaced cannot re-trigger the pick (spec: one resurface per app open; Keep flag hides the card afterwards anyway).
  - `ResurfaceCard` widget: shows content preview + `daysAgoLabel`; actions **Keep** (dismisses card this session — `resurfaceDismissedProvider` flag in `resurface_providers.dart`), **Archive** (calls `setArchived(id, true)`), **Forget** (confirm dialog → `deleteNote(id)`).

- [ ] **Step 1: Failing repository test**

`test/core/db/resurface_queries_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rembrain/core/db/database.dart';
import 'package:rembrain/core/db/note_repository.dart';

void main() {
  late AppDb db;
  late NoteRepository repo;

  setUp(() {
    db = AppDb(NativeDatabase.memory());
    repo = NoteRepository(db);
  });

  tearDown(() async => db.close());

  test('excludes archived notes', () async {
    final a = await repo.insertNote('active');
    final b = await repo.insertNote('archived');
    await repo.setArchived(b.id, true);

    final candidates = await repo.resurfaceCandidates();
    expect(candidates.map((n) => n.id), [a.id]);
  });

  test('excludes most recently resurfaced note', () async {
    final a = await repo.insertNote('a');
    final b = await repo.insertNote('b');

    await repo.markResurfaced(a.id);

    final candidates = await repo.resurfaceCandidates();
    expect(candidates.map((n) => n.id), contains(b.id));
    expect(candidates.map((n) => n.id), isNot(contains(a.id)));
  });

  test('previous note eligible again when another gets resurfaced', () async {
    final a = await repo.insertNote('a');
    final b = await repo.insertNote('b');
    await repo.markResurfaced(a.id);

    await repo.markResurfaced(b.id);

    final candidates = await repo.resurfaceCandidates();
    expect(candidates.map((n) => n.id), contains(a.id));
  });
}
```

- [ ] **Step 2: Implement `resurfaceCandidates`** (append to `NoteRepository`):

```dart
  Future<List<Note>> resurfaceCandidates() async {
    // most recently resurfaced note (if any) sits this round out — core API,
    // so no raw SQL and no customSelect row mapping
    final lastResurfaced = await (_db.select(_db.notes)
          ..where((n) => n.isArchived.equals(false) & n.lastResurfacedAt.isNotNull())
          ..orderBy([
            (n) => OrderingTerm.desc(n.lastResurfacedAt),
            (n) => OrderingTerm.desc(n.id), // tiebreaker: DateTime stores seconds
          ])
          ..limit(1))
        .getSingleOrNull();

    final query = _db.select(_db.notes);
    if (lastResurfaced == null) {
      query.where((n) => n.isArchived.equals(false));
    } else {
      query.where((n) => n.isArchived.equals(false) & n.id.equals(lastResurfaced.id).not());
    }
    return query.get();
  }
```

- [ ] **Step 3: Implement providers + card**

`lib/features/resurface/resurface_providers.dart`:

```dart
import 'dart:math';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/db/database.dart';
import '../../core/db/note_repository_provider.dart';
import 'resurface_logic.dart';

part 'resurface_providers.g.dart';

/// One pick per app open (spec §6). One-shot query, not a stream:
/// markResurfaced writes to the same rows a stream would watch, which
/// would re-trigger the pick forever. autoDispose → fresh pick next open.
@riverpod
Future<Note?> resurfacePick(Ref ref) async {
  final candidates =
      await ref.watch(noteRepositoryProvider).resurfaceCandidates();
  if (candidates.isEmpty) return null;

  final pick = pickWeighted(
    candidates,
    candidates.map((n) => n.createdAt).toList(),
    DateTime.now(),
    Random(),
  );
  await ref.read(noteRepositoryProvider).markResurfaced(pick.id);
  return pick;
}

/// Session flag: Keep hides the card until next app start.
@riverpod
class ResurfaceDismissed extends _$ResurfaceDismissed {
  @override
  bool build() => false;

  void dismiss() => state = true;
}
```

`lib/features/resurface/ui/resurface_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/date_format.dart';
import '../resurface_providers.dart';

class ResurfaceCard extends ConsumerWidget {
  const ResurfaceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(resurfaceDismissedProvider)) return const SizedBox.shrink();

    final pickAsync = ref.watch(resurfacePickProvider);
    return pickAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
      data: (note) {
        if (note == null) return const SizedBox.shrink();
        return Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'you wrote this ${daysAgoLabel(note.createdAt)} — still relevant?',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  note.content,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => _forget(context, ref, note.id),
                      child: const Text('forget'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () async {
                        await ref
                            .read(noteRepositoryProvider)
                            .setArchived(note.id, true);
                        ref.read(resurfaceDismissedProvider.notifier).dismiss();
                      },
                      child: const Text('archive'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () =>
                          ref.read(resurfaceDismissedProvider.notifier).dismiss(),
                      child: const Text('keep'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _forget(BuildContext context, WidgetRef ref, int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: const Text('forget this note forever?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('cancel'),
          ),
          TextButton(
            key: const Key('confirm-delete'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('forget'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(noteRepositoryProvider).deleteNote(id);
      ref.read(resurfaceDismissedProvider.notifier).dismiss();
    }
  }
}
```

`lib/features/notes/ui/home_screen.dart` (replace):

```dart
import 'package:flutter/material.dart';

import '../../resurface/ui/resurface_card.dart';
import 'quick_dump_box.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              ResurfaceCard(),
              QuickDumpBox(),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Widget test for the card**

`test/features/resurface/resurface_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rembrain/core/db/database.dart';
import 'package:rembrain/core/db/database_provider.dart';
import 'package:rembrain/core/db/note_repository.dart';
import 'package:rembrain/core/db/note_repository_provider.dart';
import 'package:rembrain/features/resurface/ui/resurface_card.dart';

void main() {
  Future<(AppDb, ProviderContainer)> setup(WidgetTester tester) async {
    final db = AppDb(NativeDatabase.memory());
    final repo = NoteRepository(db);
    await repo.insertNote('old thought');
    final container = ProviderContainer(overrides: [
      appDbProvider.overrideWithValue(db),
      noteRepositoryProvider.overrideWithValue(repo),
    ]);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ResurfaceCard())),
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

  testWidgets('forget requires confirm then deletes and dismisses', (tester) async {
    final (db, container) = await setup(tester);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    await tester.tap(find.text('forget'));
    await tester.pumpAndSettle();
    expect(find.text('forget this note forever?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('confirm-delete')));
    await tester.pumpAndSettle();

    expect(await db.select(db.notes).get(), isEmpty);
    expect(find.textContaining('you wrote this'), findsNothing);
  });

  testWidgets('archive hides note from candidates and dismisses', (tester) async {
    final (db, container) = await setup(tester);
    final repo = NoteRepository(db);
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
```

- [ ] **Step 5: Full phase gate**

```bash
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter analyze
```

Expected: all green. Device: seed nothing → no card; dump a note → restart app → card shows it; keep/archive/forget behave.

---

## Phase 3 — Tags

### Task 9: Tag parsing + sync on save

**Files:**
- Create: `lib/features/notes/data/tag_util.dart`
- Modify: `lib/core/db/note_repository.dart` (tag sync inside `insertNote`/`updateNote` via shared `_syncTags`)
- Test: `test/features/notes/tag_util_test.dart`, extend `test/core/db/note_repository_test.dart`

**Interfaces:**
- Produces:
  - `Set<String> parseTags(String content)` — `#` + `[a-zA-Z0-9_]{1,32}`, lowercased, deduped; `#` alone / trailing `#` ignored.
  - Repository behavior change: `insertNote`/`updateNote` now also sync tags from content (create tags on demand, link, prune orphan tags with zero notes). Same signatures as Task 4 — callers unaffected.

> **Learn:** spec decision made concrete — hashtags inline in content, no tag picker at dump time. Content stored verbatim; parsing is derived data.

- [ ] **Step 1: Failing pure test**

`test/features/notes/tag_util_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rembrain/features/notes/data/tag_util.dart';

void main() {
  test('extracts tags, lowercased, deduped', () {
    expect(parseTags('hello #World and #flutter #World'), {'world', 'flutter'});
  });

  test('ignores bare # and trailing #', () {
    expect(parseTags('# and stuff #'), isEmpty);
  });

  test('allows underscore and digits, caps at 32 chars', () {
    expect(parseTags('#snake_case_1'), {'snake_case_1'});
    expect(parseTags('#${'a' * 33}'), isEmpty);
    expect(parseTags('#${'a' * 32}'), {'a' * 32});
  });

  test('no tags when none present', () {
    expect(parseTags('plain note'), isEmpty);
  });
}
```

- [ ] **Step 2: Implement**

`lib/features/notes/data/tag_util.dart`:

```dart
final _tagRegex = RegExp(r'#([a-zA-Z0-9_]{1,32})');

/// Extracts #hashtag tokens: `#` + 1-32 letters/digits/underscores.
/// Lowercased, deduped. Bare `#` or overlong tokens are ignored.
Set<String> parseTags(String content) =>
    _tagRegex.allMatches(content).map((m) => m.group(1)!.toLowerCase()).toSet();
```

- [ ] **Step 3: Failing repository tests** (append to `test/core/db/note_repository_test.dart`):

```dart
  test('insertNote syncs tags from content', () async {
    final n = await repo.insertNote('note about #Dart and #drift');

    final tags = await db.select(db.tags).get();
    expect(tags.map((t) => t.name), containsAll(['dart', 'drift']));

    final links = await db.select(db.noteTags).get();
    expect(links, hasLength(2));

    final linked = await repo.tagsForNote(n.id);
    expect(linked.map((t) => t.name).toSet(), {'dart', 'drift'});
  });

  test('updateNote re-syncs tags and prunes orphans', () async {
    final n = await repo.insertNote('has #oldtag');
    await repo.updateNote(n.id, content: 'now #newtag');

    final tags = await db.select(db.tags).get();
    expect(tags.map((t) => t.name), ['newtag']); // oldtag pruned

    final linked = await repo.tagsForNote(n.id);
    expect(linked.map((t) => t.name), ['newtag']);
  });

  test('shared tags survive one note editing them away', () async {
    final a = await repo.insertNote('#shared here');
    final b = await repo.insertNote('#shared also');
    await repo.updateNote(a.id, content: 'no tag now');

    final tags = await db.select(db.tags).get();
    expect(tags.map((t) => t.name), ['shared']); // still used by b
    expect((await repo.tagsForNote(b.id)).map((t) => t.name), ['shared']);
    expect(await repo.tagsForNote(a.id), isEmpty);
  });
```

Add to `NoteRepository` interface now (test references it):

```dart
Future<List<Tag>> tagsForNote(int noteId);
```

- [ ] **Step 4: Implement sync in repository** (modify `note_repository.dart` — add to imports):

```dart
import 'package:rembrain/features/notes/data/tag_util.dart';
```

(Use package imports consistently — relative paths break when files move.)

Replace `insertNote` and `updateNote` bodies to delegate, and add privates:

```dart
  Future<Note> insertNote(String content, {String? title}) {
    return _db.transaction(() async {
      final id = await _db.into(_db.notes).insert(
            NotesCompanion.insert(content: content, title: Value(title)),
          );
      await _syncTags(id, content);
      return (_db.select(_db.notes)..where((n) => n.id.equals(id))).getSingle();
    });
  }

  Future<void> updateNote(int id, {required String content, String? title}) {
    return _db.transaction(() async {
      await (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
        NotesCompanion(
          content: Value(content),
          title: Value(title),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _syncTags(id, content);
    });
  }

  Future<List<Tag>> tagsForNote(int noteId) {
    final query = _db.select(_db.noteTags).join([
      innerJoin(_db.tags, _db.tags.id.equalsExp(_db.noteTags.tagId)),
    ])
      ..where(_db.noteTags.noteId.equals(noteId));
    return query.map((row) => row.readTable(_db.tags)).get();
  }

  Future<void> _syncTags(int noteId, String content) async {
    final wanted = parseTags(content).toList()..sort();

    // create missing tags, link them. NoteTags has only PK columns, so
    // insertOrIgnore is the right mode — an upsert would have nothing to SET.
    for (final name in wanted) {
      final existing = await (_db.select(_db.tags)
            ..where((t) => t.name.equals(name)))
          .getSingleOrNull();
      final tagId = existing?.id ??
          await _db.into(_db.tags).insert(TagsCompanion.insert(name: name));
      await _db.into(_db.noteTags).insert(
            NoteTagsCompanion.insert(noteId: noteId, tagId: tagId),
            mode: InsertMode.insertOrIgnore,
          );
    }

    // remove links this note no longer wants
    if (wanted.isEmpty) {
      await (_db.delete(_db.noteTags)
            ..where((nt) => nt.noteId.equals(noteId)))
          .go();
    } else {
      await (_db.delete(_db.noteTags)..where(
            (nt) => nt.noteId.equals(noteId) & nt.tagId.isNotInQuery(
              _db.select(_db.tags)..where((t) => t.name.isIn(wanted)),
            ),
          ))
          .go();
    }

    // prune orphan tags (no links anywhere). customUpdate + updates: so
    // watchTags() streams re-emit after the prune.
    await _db.customUpdate(
      'DELETE FROM tags WHERE id NOT IN (SELECT tag_id FROM note_tags)',
      updates: {_db.tags},
    );
  }
```

> `_syncTags` does one lookup per tag (N+1). Fine here — a note has a handful of tags. If a note ever carries dozens, switch to `INSERT OR IGNORE` for all names + one `WHERE name IN (...)` re-select.

- [ ] **Step 5: Run all tests + analyze**

```bash
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter analyze
```

Expected: green. Device: dump `learned #flutter today` → snackbar; note saved with tags (verify visually in phase-3 UI next task).

### Task 10: Tag chips + filter by tag + search

**Files:**
- Create: `lib/features/notes/ui/tag_chip.dart`
- Modify: `lib/features/notes/notes_providers.dart` (filtered list)
- Modify: `lib/features/notes/ui/notes_list_screen.dart` (search field + filter chips)
- Modify: `lib/core/db/note_repository.dart` (add `watchTags()`, filtered `watchNotes`)
- Test: extend `test/features/notes/notes_list_screen_test.dart`

**Interfaces:**
- Produces:
  - `TagChip` — small rounded chip, label only.
  - `NoteRepository.watchTags()` → `Stream<List<Tag>>`; `watchNotes({String? search, int? tagId})` — search = LIKE on content+title, tagId filters by link.
  - `@riverpod Stream<List<Tag>> tags(Ref ref)` → `tagsProvider`
  - `@riverpod class NotesFilter extends _$NotesFilter` → state `{String search; int? tagId}` (record or small class — use a record `(String, int?)` for simplicity), methods `setSearch`, `toggleTag`.
  - `@riverpod Stream<List<Note>> filteredNotes(Ref ref)` → `filteredNotesProvider` (Notes list screen switches to this; the old `notesListProvider` from Task 5 is deleted — filtered with empty filter is the same query).

- [ ] **Step 1: Failing repository test** (append to `test/core/db/note_repository_test.dart`):

```dart
  test('watchNotes filters by search and tag', () async {
    final a = await repo.insertNote('flutter widgets #flutter');
    final b = await repo.insertNote('drift database #drift');

    expect((await repo.watchNotes(search: 'flutter').first).map((n) => n.id), [a.id]);
    expect((await repo.watchNotes(search: 'DATABASE').first).map((n) => n.id), [b.id]);

    final tag = (await repo.watchTags().first).singleWhere((t) => t.name == 'drift');
    expect((await repo.watchNotes(tagId: tag.id).first).map((n) => n.id), [b.id]);
    expect((await repo.watchNotes().first), hasLength(2));
  });

  test('watchTags lists all tags', () async {
    await repo.insertNote('#a and #b');
    final tags = await repo.watchTags().first;
    expect(tags.map((t) => t.name).toSet(), {'a', 'b'});
  });
```

- [ ] **Step 2: Implement repository additions**

```dart
  Stream<List<Tag>> watchTags() =>
      (_db.select(_db.tags)..orderBy([(t) => OrderingTerm.asc(t.name))]).watch();

  Stream<List<Note>> watchNotes({String? search, int? tagId}) {
    // build where-expression first: drift's SimpleSelectStatement takes
    // join/where once each, so compose them before applying
    Expression<bool>? whereExpr;
    if (tagId != null) {
      whereExpr = _db.noteTags.tagId.equals(tagId);
    }
    if (search != null && search.isNotEmpty) {
      final pattern = '%$search%';
      final searchExpr =
          _db.notes.content.like(pattern) | _db.notes.title.like(pattern);
      whereExpr = whereExpr == null ? searchExpr : (whereExpr & searchExpr);
    }

    final query = _db.select(_db.notes);
    if (tagId != null) {
      query.join([
        innerJoin(_db.noteTags, _db.noteTags.noteId.equalsExp(_db.notes.id)),
      ]);
    }
    if (whereExpr != null) {
      query.where(whereExpr);
    }
    query.orderBy([
      (n) => OrderingTerm.desc(n.createdAt),
      (n) => OrderingTerm.desc(n.id), // tiebreaker: DateTime stores seconds
    ]);
    return query.watch();
  }
```

> Note: the tag join cannot produce duplicate rows here because `noteTags` PK is `(noteId, tagId)`.

- [ ] **Step 3: Failing widget test** (append to `test/features/notes/notes_list_screen_test.dart`):

```dart
  testWidgets('filter chips and search narrow the list', (tester) async {
    final db = AppDb(NativeDatabase.memory());
    final repo = NoteRepository(db);
    await repo.insertNote('flutter thing #flutter');
    await repo.insertNote('drift thing #drift');
    final container = ProviderContainer(overrides: [
      appDbProvider.overrideWithValue(db),
      noteRepositoryProvider.overrideWithValue(repo),
    ]);
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
    expect(find.text('flutter thing #flutter'), findsOneWidget);
    expect(find.text('drift thing #drift'), findsOneWidget);

    // tap the drift filter chip
    await tester.tap(find.text('#drift'));
    await tester.pumpAndSettle();
    expect(find.text('flutter thing #flutter'), findsNothing);
    expect(find.text('drift thing #drift'), findsOneWidget);

    // tap again to clear
    await tester.tap(find.text('#drift'));
    await tester.pumpAndSettle();
    expect(find.text('drift thing #drift'), findsOneWidget);
    expect(find.text('flutter thing #flutter'), findsOneWidget);
  });
```

- [ ] **Step 4: Implement providers, chip, screen**

`lib/features/notes/ui/tag_chip.dart`:

```dart
import 'package:flutter/material.dart';

class TagChip extends StatelessWidget {
  const TagChip({super.key, required this.label, this.selected, this.onTap});

  final String label;
  final bool? selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FilterChip(
        label: Text('#$label'),
        selected: selected ?? false,
        onSelected: onTap != null ? (_) => onTap!() : null,
      ),
    );
  }
}
```

`lib/features/notes/notes_providers.dart` (full replacement):

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/db/database.dart';
import '../../core/db/note_repository_provider.dart';

part 'notes_providers.g.dart';

@riverpod
Stream<List<Tag>> tags(Ref ref) => ref.watch(noteRepositoryProvider).watchTags();

typedef NotesFilterState = ({String search, int? tagId});

@riverpod
class NotesFilter extends _$NotesFilter {
  @override
  NotesFilterState build() => (search: '', tagId: null);

  void setSearch(String value) => state = (search: value, tagId: state.tagId);
  void toggleTag(int id) =>
      state = (search: state.search, tagId: state.tagId == id ? null : id);
}

@riverpod
Stream<List<Note>> filteredNotes(Ref ref) {
  final filter = ref.watch(notesFilterProvider);
  return ref
      .watch(noteRepositoryProvider)
      .watchNotes(search: filter.search, tagId: filter.tagId);
}
```

`lib/features/notes/ui/notes_list_screen.dart` (full replacement):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'note_card.dart';
import 'tag_chip.dart';
import '../notes_providers.dart';

class NotesListScreen extends ConsumerWidget {
  const NotesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(filteredNotesProvider);
    final tagsAsync = ref.watch(tagsProvider);
    final filter = ref.watch(notesFilterProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Notes list')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              onChanged: (v) =>
                  ref.read(notesFilterProvider.notifier).setSearch(v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'search notes',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: tagsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (tags) => Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final tag in tags)
                    TagChip(
                      label: tag.name,
                      selected: filter.tagId == tag.id,
                      onTap: () => ref
                          .read(notesFilterProvider.notifier)
                          .toggleTag(tag.id),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: notesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('error: $e')),
              data: (notes) => notes.isEmpty
                  ? const Center(
                      child: Text('nothing yet — dump your first thought'))
                  : ListView.builder(
                      itemCount: notes.length,
                      itemBuilder: (_, i) => NoteCard(note: notes[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Phase gate**

```bash
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter analyze
```

---

## Phase 4 — Detail, Edit, Archive/Delete

### Task 11: Note detail screen + navigation from list

**Files:**
- Modify: `lib/core/router/app_router.dart` (route `/notes/:id`)
- Create: `lib/features/notes/ui/note_detail_screen.dart`
- Modify: `lib/features/notes/ui/note_card.dart` (wire onTap)
- Modify: `lib/features/notes/notes_providers.dart` (`noteByIdProvider`)
- Test: new `test/features/notes/note_detail_screen_test.dart` (detail body + tap-navigates)

**Interfaces:**
- Consumes: `NoteRepository.watchNote` (Task 4), `tagsForNote` (Task 9).
- Produces: route `/notes/:id` → `NoteDetailScreen`; `@riverpod Stream<Note?> noteById(Ref ref, int id)` → family provider `noteByIdProvider(id)`; detail screen shows full content, tag chips (static), `daysAgoLabel(createdAt)`, and (Task 12) edit / archive / delete actions in the AppBar.

- [ ] **Step 1: Failing test** (new file `test/features/notes/note_detail_screen_test.dart`):

```dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rembrain/core/db/database.dart';
import 'package:rembrain/core/db/database_provider.dart';
import 'package:rembrain/core/db/note_repository.dart';
import 'package:rembrain/core/db/note_repository_provider.dart';
import 'package:rembrain/core/router/app_router.dart';
import 'package:rembrain/features/notes/ui/note_detail_screen.dart';

void main() {
  testWidgets('shows content and tags of the note', (tester) async {
    final db = AppDb(NativeDatabase.memory());
    final repo = NoteRepository(db);
    final note = await repo.insertNote('full body text #dart #drift');
    final container = ProviderContainer(overrides: [
      appDbProvider.overrideWithValue(db),
      noteRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: NoteDetailScreen(noteId: note.id),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('full body text #dart #drift'), findsOneWidget);
    expect(find.text('#dart'), findsOneWidget);
    expect(find.text('#drift'), findsOneWidget);
    expect(find.textContaining('days ago'), findsWidgets);
  });

  testWidgets('tapping a note card navigates to detail', (tester) async {
    final db = AppDb(NativeDatabase.memory());
    final repo = NoteRepository(db);
    await repo.insertNote('tappable note');
    final container = ProviderContainer(overrides: [
      appDbProvider.overrideWithValue(db),
      noteRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    final router = container.read(appRouterProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    router.go('/notes'); // start on the Notes tab, not Home
    await tester.pumpAndSettle();

    await tester.tap(find.text('tappable note'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteDetailScreen), findsOneWidget);
  });
}
```

(add imports: `package:rembrain/core/router/app_router.dart`)

- [ ] **Step 2: Implement**

Add to `notes_providers.dart`:

```dart
@riverpod
Stream<Note?> noteById(Ref ref, int id) =>
    ref.watch(noteRepositoryProvider).watchNote(id);
```

Add to `app_router.dart` inside the `/notes` branch routes (before closing bracket of that GoRoute's routes list — convert the notes branch route to use `routes:`):

```dart
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/notes',
              builder: (_, __) => const NotesListScreen(),
              routes: [
                GoRoute(
                  path: ':id',
                  builder: (_, state) => NoteDetailScreen(
                    noteId: int.parse(state.pathParameters['id']!),
                  ),
                ),
              ],
            ),
          ]),
```

`lib/features/notes/ui/note_detail_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/date_format.dart';
import '../../../core/db/database.dart';
import '../notes_providers.dart';
import 'tag_chip.dart';

class NoteDetailScreen extends ConsumerWidget {
  const NoteDetailScreen({super.key, required this.noteId});

  final int noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final noteAsync = ref.watch(noteByIdProvider(noteId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('note'),
        actions: [
          // edit/archive/delete wired in Task 12
        ],
      ),
      body: noteAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('error: $e')),
        data: (note) {
          if (note == null) {
            return const Center(child: Text('note not found'));
          }
          return FutureBuilder<List<Tag>>(
            future: ref.read(noteRepositoryProvider).tagsForNote(note.id),
            builder: (context, snapshot) {
              final tags = snapshot.data ?? const <Tag>[];
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (note.title != null)
                      Text(note.title!,
                          style: Theme.of(context).textTheme.titleLarge),
                    Text(
                      'created ${daysAgoLabel(note.createdAt)} · '
                      'resurfaced ${note.resurfaceCount}×',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      children: tags
                          .map((t) => TagChip(label: t.name))
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Text(note.content),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
```

Wire tap in `note_card.dart` — change signature use at call site (`notes_list_screen.dart` itemBuilder):

```dart
NoteCard(
  note: notes[i],
  onTap: () => context.push('/notes/${notes[i].id}'),
)
```

(`NoteCard` already accepts `onTap` from Task 6. `notes_list_screen.dart` needs `import 'package:go_router/go_router.dart';` for `context.push`.)

- [ ] **Step 3: Run tests + analyze** (codegen for the family provider):

```bash
dart run build_runner build --delete-conflicting-outputs
flutter test test/features/notes/
flutter analyze
```

### Task 12: Edit screen (validation, live tag preview)

**Files:**
- Modify: `lib/core/router/app_router.dart` (routes `/notes/:id/edit`)
- Create: `lib/features/notes/ui/note_edit_screen.dart`
- Modify: `lib/features/notes/ui/note_detail_screen.dart` (edit action)
- Test: `test/features/notes/note_edit_screen_test.dart`

**Interfaces:**
- Consumes: `noteByIdProvider`, `NoteRepository.updateNote`, `parseTags`.
- Produces: `NoteEditScreen({required int noteId})` — edit-only. Create happens via the dump box on Home (spec §4's Create screen is subsumed). Fields: title (optional), content (required, 1–10000 chars). Live `Wrap` of `TagChip`s previewing `parseTags(content)`. Save → repo call → `context.pop()`. Validation errors inline under fields.

- [ ] **Step 1: Failing test**

`test/features/notes/note_edit_screen_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rembrain/core/db/database.dart';
import 'package:rembrain/core/db/database_provider.dart';
import 'package:rembrain/core/db/note_repository.dart';
import 'package:rembrain/core/db/note_repository_provider.dart';
import 'package:rembrain/features/notes/ui/note_edit_screen.dart';

void main() {
  testWidgets('prefills, validates, updates, pops on save', (tester) async {
    final db = AppDb(NativeDatabase.memory());
    final repo = NoteRepository(db);
    final note = await repo.insertNote('original');
    final container = ProviderContainer(overrides: [
      appDbProvider.overrideWithValue(db),
      noteRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    // minimal router: _save uses go_router's context.pop(), which needs a
    // real stack. Start on a stub detail route, push edit like the app does.
    final router = GoRouter(
      initialLocation: '/notes/${note.id}',
      routes: [
        GoRoute(
          path: '/notes/:id',
          builder: (_, __) => const Scaffold(body: Text('back on detail')),
          routes: [
            GoRoute(
              path: 'edit',
              builder: (_, __) => NoteEditScreen(noteId: note.id),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    router.push('/notes/${note.id}/edit');
    await tester.pumpAndSettle();

    expect(find.text('original'), findsOneWidget);

    // cleared content shows validation error, no write
    await tester.enterText(find.byKey(const Key('content-field')), '');
    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();
    expect(find.text('content is required'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('content-field')), 'edited #x');
    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();

    expect(find.text('back on detail'), findsOneWidget); // popped
    final rows = await db.select(db.notes).get();
    expect(rows.single.content, 'edited #x');
    final tags = await repo.tagsForNote(note.id);
    expect(tags.map((t) => t.name), ['x']);
  });
}
```

- [ ] **Step 2: Implement**

`lib/features/notes/ui/note_edit_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/note_repository_provider.dart';
import '../data/tag_util.dart';
import '../notes_providers.dart';
import 'tag_chip.dart';

class NoteEditScreen extends ConsumerStatefulWidget {
  const NoteEditScreen({super.key, required this.noteId});

  final int noteId;

  @override
  ConsumerState<NoteEditScreen> createState() => _NoteEditScreenState();
}

class _NoteEditScreenState extends ConsumerState<NoteEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  bool _loaded = false;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final repo = ref.read(noteRepositoryProvider);
    final content = _contentController.text.trim();
    final title =
        _titleController.text.trim().isEmpty ? null : _titleController.text.trim();
    await repo.updateNote(widget.noteId, content: content, title: title);
    if (mounted) context.pop();
  }

  String? _validateContent(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return 'content is required';
    if (value.length > 10000) return 'max 10000 characters';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // ref.listen (not a read/when in build) — prefill is a side effect, it
    // must not run during build
    ref.listen(noteByIdProvider(widget.noteId), (_, next) {
      final note = next.value;
      if (note != null && !_loaded) {
        _loaded = true;
        setState(() {
          _contentController.text = note.content;
          _titleController.text = note.title ?? '';
        });
      }
    });

    final tags = parseTags(_contentController.text);

    return Scaffold(
      appBar: AppBar(title: const Text('edit note')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'title (optional)'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('content-field'),
              controller: _contentController,
              minLines: 6,
              maxLines: 12,
              validator: _validateContent,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'content',
                hintText: 'use #tags inline',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 4,
              children: tags.map((t) => TagChip(label: t)).toList(),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _save,
              child: const Text('save'),
            ),
          ],
        ),
      ),
    );
  }
}
```

Route + detail AppBar action:

In `app_router.dart`, extend the `:id` route:

```dart
                GoRoute(
                  path: ':id',
                  builder: (_, state) => NoteDetailScreen(
                    noteId: int.parse(state.pathParameters['id']!),
                  ),
                  routes: [
                    GoRoute(
                      path: 'edit',
                      parentNavigatorKey: _rootNavigatorKey,
                      builder: (_, state) => NoteEditScreen(
                        noteId: int.parse(state.pathParameters['id']!),
                      ),
                    ),
                  ],
                ),
```

In `note_detail_screen.dart` AppBar actions (replacing the Task 11 comment):

```dart
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => context.push('/notes/$noteId/edit'),
          ),
        ],
```

- [ ] **Step 3: Phase gate**

```bash
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter analyze
```

### Task 13: Archive/unarchive + delete actions on detail

**Files:**
- Modify: `lib/features/notes/ui/note_detail_screen.dart`
- Test: extend `test/features/notes/note_detail_screen_test.dart`

**Interfaces:**
- Consumes: `NoteRepository.setArchived`, `deleteNote` (Task 4).
- Produces: AppBar overflow menu on detail: **Archive/Unarchive** (label depends on `isArchived`), **Delete** (confirm dialog "delete this note forever?" → `deleteNote` → `context.pop()` to list). Archived notes show an `archived` badge on detail + note card subtitle suffix.

- [ ] **Step 1: Failing test** (append to `note_detail_screen_test.dart`; add `import 'package:go_router/go_router.dart';` to that file):

```dart
  testWidgets('delete requires confirm then pops', (tester) async {
    final db = AppDb(NativeDatabase.memory());
    final repo = NoteRepository(db);
    final note = await repo.insertNote('doomed');
    final container = ProviderContainer(overrides: [
      appDbProvider.overrideWithValue(db),
      noteRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    // delete pops back to the list, so the detail must sit on a real router
    // stack — MaterialApp(home:) has nothing to pop and no GoRouter
    final router = GoRouter(
      initialLocation: '/notes',
      routes: [
        GoRoute(
          path: '/notes',
          builder: (_, __) => const Scaffold(body: Text('back on list')),
        ),
        GoRoute(
          path: '/notes/:id',
          builder: (_, state) => NoteDetailScreen(
            noteId: int.parse(state.pathParameters['id']!),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    router.push('/notes/${note.id}');
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('delete'));
    await tester.pumpAndSettle();
    expect(find.text('delete this note forever?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('confirm-delete')));
    await tester.pumpAndSettle();

    expect(await db.select(db.notes).get(), isEmpty);
    expect(find.text('back on list'), findsOneWidget); // popped
  });

  testWidgets('archive toggles and badge shows', (tester) async {
    final db = AppDb(NativeDatabase.memory());
    final repo = NoteRepository(db);
    final note = await repo.insertNote('to archive');
    final container = ProviderContainer(overrides: [
      appDbProvider.overrideWithValue(db),
      noteRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: NoteDetailScreen(noteId: note.id)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('archive'));
    await tester.pumpAndSettle();

    expect(find.text('archived'), findsOneWidget);
  });
```

- [ ] **Step 2: Implement** — replace detail AppBar actions with a menu:

```dart
      appBar: AppBar(
        title: const Text('note'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => context.push('/notes/$noteId/edit'),
          ),
          PopupMenuButton<String>(
            onSelected: (action) async {
              final note = ref.read(noteByIdProvider(noteId)).value;
              if (note == null) return;
              switch (action) {
                case 'archive':
                  await ref
                      .read(noteRepositoryProvider)
                      .setArchived(note.id, !note.isArchived);
                case 'delete':
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      content: const Text('delete this note forever?'),
                      actions: [
                        TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          child: const Text('cancel'),
                        ),
                        TextButton(
                          key: const Key('confirm-delete'),
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(true),
                          child: const Text('delete'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true && context.mounted) {
                    await ref.read(noteRepositoryProvider).deleteNote(note.id);
                    if (context.mounted) context.pop();
                  }
              }
            },
            itemBuilder: (menuContext) {
              final note =
                  ref.read(noteByIdProvider(noteId)).value;
              return [
                PopupMenuItem(
                  value: 'archive',
                  child: Text(note?.isArchived ?? false
                      ? 'unarchive'
                      : 'archive'),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('delete'),
                ),
              ];
            },
          ),
        ],
      ),
```

Add badge in the detail body (above the date line):

```dart
                    if (note.isArchived)
                      const Chip(label: Text('archived')),
```

- [ ] **Step 3: Phase gate**

```bash
flutter test
flutter analyze
flutter run   # full manual pass on device
```

Manual device pass: dump → detail → edit → archive → unarchive → delete. All offline, restart keeps data.

---

## Phase 5 — Settings

### Task 14: Theme toggle with persistence

**Files:**
- Create: `lib/features/settings/settings_providers.dart`
- Modify: `lib/features/settings/ui/settings_screen.dart` (real body)
- Modify: `lib/app.dart` (consume theme controller)
- Test: `test/features/settings/settings_screen_test.dart`

**Interfaces:**
- Consumes: `shared_preferences`.
- Produces: `@riverpod class ThemeModeController extends _$ThemeModeController` — state `ThemeMode` (default `ThemeMode.dark`), `Future<void> set(ThemeMode)` persists `mode.name` under key `themeMode` in SharedPreferences; loads persisted value on build. `app.dart` switches `themeMode: ref.watch(themeModeControllerProvider)`. Settings screen: three-choice `SegmentedButton<ThemeMode>` (system / light / dark).

> **Learn:** `shared_preferences` = localStorage equivalent. In widget tests you must call `SharedPreferences.setMockInitialValues({})` first — that's Flutter's mocked-plugin pattern.

- [ ] **Step 1: Failing test**

`test/features/settings/settings_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rembrain/features/settings/settings_providers.dart';
import 'package:rembrain/features/settings/ui/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('defaults to dark, toggle persists to light', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(themeModeControllerProvider), ThemeMode.dark);

    await tester.tap(find.text('light'));
    await tester.pumpAndSettle();
    expect(container.read(themeModeControllerProvider), ThemeMode.light);

    // persisted
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('themeMode'), 'light');
  });

  testWidgets('loads persisted value on start', (tester) async {
    SharedPreferences.setMockInitialValues({'themeMode': 'light'});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(themeModeControllerProvider), ThemeMode.light);
  });
}
```

- [ ] **Step 2: Implement**

`lib/features/settings/settings_providers.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'settings_providers.g.dart';

@Riverpod(keepAlive: true)
class ThemeModeController extends _$ThemeModeController {
  bool _loadedFromDisk = false;

  @override
  ThemeMode build() {
    _load();
    return ThemeMode.dark;
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    final stored = sp.getString('themeMode');
    // guard on a flag, not on state == default: a user tap that happens
    // before the load finishes must win over the persisted value
    if (stored != null && !_loadedFromDisk) {
      _loadedFromDisk = true;
      state = ThemeMode.values.byName(stored);
    }
  }

  Future<void> set(ThemeMode mode) async {
    _loadedFromDisk = true;
    state = mode;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('themeMode', mode.name);
  }
}
```

`lib/features/settings/ui/settings_screen.dart` (replace):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('theme'),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('system')),
              ButtonSegment(value: ThemeMode.light, label: Text('light')),
              ButtonSegment(value: ThemeMode.dark, label: Text('dark')),
            ],
            selected: {mode},
            onSelectionChanged: (selection) => ref
                .read(themeModeControllerProvider.notifier)
                .set(selection.first),
          ),
        ],
      ),
    );
  }
}
```

`lib/app.dart` — change theme wiring:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rembrain/core/router/app_router.dart';
import 'package:rembrain/core/theme/app_theme.dart';
import 'package:rembrain/features/settings/settings_providers.dart';

class RembrainApp extends ConsumerWidget {
  const RembrainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'Rembrain',
      theme: ref.watch(lightThemeProvider),
      darkTheme: ref.watch(darkThemeProvider),
      themeMode: ref.watch(themeModeControllerProvider),
      routerConfig: router,
    );
  }
}
```

- [ ] **Step 3: Final gate**

```bash
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter analyze
flutter run
```

Expected: everything green; on device, theme toggle persists across app restarts.

---

## Deviations from spec

- **Home FAB dropped** (spec §4 said "FAB alternative for dump"): the quick dump box is always visible on Home; a FAB duplicating it adds noise, not function. Re-add if the box ever becomes collapsible.
- **NoteEditScreen create mode cut** (spec §4 said "Create/Edit"): the dump box is the create path; a create-mode edit screen would duplicate it and had no wired entry point. `NoteEditScreen` is edit-only (`noteId` required). Restore create mode if a richer composer is ever needed.
- **Settings "export stub" dropped** (spec §4): spec §2 already puts export out of scope; a dead button teaches nothing. Task 14 ships theme toggle only.
- **Tag case normalization** (spec §3 said nothing about case): tags lowercased before storage — otherwise `#Dart` and `#dart` are two tags. Spec §6's parse rule made case-insensitive explicit here.

## Completion Checklist (maps to spec §10)

- [ ] Dump → list → resurface → tag → edit → archive → delete all work offline on device
- [ ] Data survives app restart (file-backed SQLite)
- [ ] `flutter test` all green, `flutter analyze` clean
- [ ] You can explain every file in `lib/` — ask yourself per file: what does it do, who consumes it, what breaks if I delete it?

## Deferred (not in this plan)

- AI cleanup phase (service interface + endpoint swap) — needs its own spec/plan when DeepSeek-vs-alternative decision lands.
- Voice input (`speech_to_text`), export, FTS5 search.
