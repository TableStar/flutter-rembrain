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
    final id = await db
        .into(db.notes)
        .insert(NotesCompanion.insert(content: "hello #world"));

    final note = await (db.select(
      db.notes,
    )..where((n) => n.id.equals(id))).getSingle();

    expect(note.content, 'hello #world');
    expect(note.isArchived, false);
    expect(note.resurfaceCount, 0);
    expect(note.lastResurfacedAt, isNull);
    expect(note.createdAt, isNotNull);
  });

  test('note_tags cascade on note delete', () async {
    final noteId = await db
        .into(db.notes)
        .insert(NotesCompanion.insert(content: 'n'));
    final tagId = await db
        .into(db.tags)
        .insert(TagsCompanion.insert(name: 'a'));
    await db
        .into(db.noteTags)
        .insert(NoteTagsCompanion.insert(noteId: noteId, tagId: tagId));

    await (db.delete(db.notes)..where((n) => n.id.equals(noteId))).go();

    final links = await db.select(db.noteTags).get();
    expect(links, isEmpty);
  });

  test('tags name is unique', () async {
    await db.into(db.tags).insert(TagsCompanion.insert(name: 'dup'));
    await expectLater(
      db.into(db.tags).insert(TagsCompanion.insert(name: 'dup')),
      throwsA(anything),
    );
  });
}
