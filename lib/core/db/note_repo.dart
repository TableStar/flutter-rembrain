import 'package:drift/drift.dart';
import 'package:rembrain/core/db/database.dart';
import 'package:rembrain/features/notes/data/tag_util.dart';

class NoteRepo {
  NoteRepo(this._db);

  final AppDb _db;

  Stream<List<Note>> watchNotes() {
    return (_db.select(_db.notes)..orderBy([
          (n) => OrderingTerm.desc(n.createdAt),
          (n) => OrderingTerm.desc(n.id),
        ]))
        .watch();
  }

  Future<Note> insertNote(String content, {String? title}) {
    return _db.transaction(() async {
      final id = await _db
          .into(_db.notes)
          .insert(NotesCompanion.insert(content: content, title: Value(title)));
      await _syncTags(id, content);
      return (_db.select(_db.notes)..where((n) => n.id.equals(id))).getSingle();
    });
  }

  Stream<Note?> watchNote(int id) {
    return (_db.select(
      _db.notes,
    )..where((n) => n.id.equals(id))).watchSingleOrNull();
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

  Future<void> deleteNote(int id) {
    return (_db.delete(_db.notes)..where((n) => n.id.equals(id))).go();
  }

  Future<void> setArchived(int id, bool archived) {
    return (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        isArchived: Value(archived),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<Note> markResurfaced(int id) async {
    // Companion.custom keeps the increment in SQL (no read-modify-write race)
    // and stays on drift's core API, so watch() streams are notified.
    // eh?? eh explain?
    await (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion.custom(
        resurfaceCount: _db.notes.resurfaceCount + const Constant(1),
        lastResurfacedAt: Variable(DateTime.now()),
      ),
    );
    return (_db.select(_db.notes)..where((n) => n.id.equals(id))).getSingle();
  }

  Future<List<Note>> resurfaceCandidates() async {
    final lastResurfaced =
        await (_db.select(_db.notes)
              ..where(
                (n) =>
                    n.isArchived.equals(false) & n.lastResurfacedAt.isNotNull(),
              )
              ..orderBy([
                (n) => OrderingTerm.desc(n.lastResurfacedAt),
                (n) => OrderingTerm.desc(n.id),
              ])
              ..limit(1))
            .getSingleOrNull();
    final query = _db.select(_db.notes);
    if (lastResurfaced == null) {
      query.where((n) => n.isArchived.equals(false));
    } else {
      query.where(
        (n) =>
            n.isArchived.equals(false) & n.id.equals(lastResurfaced.id).not(),
      );
    }
    return query.get();
  }

  Future<List<Tag>> tagsForNote(int noteId) {
    final query = _db.select(_db.noteTags).join([
      innerJoin(_db.tags, _db.tags.id.equalsExp(_db.noteTags.tagId)),
    ])..where(_db.noteTags.noteId.equals(noteId));
    return query.map((row) => row.readTable(_db.tags)).get();
  }

  Future<void> _syncTags(int noteId, String content) async {
    final wanted = parseTags(content).toList()..sort();
    final wantedIds = <int>[];

    for (final name in wanted) {
      final existing = await (_db.select(
        _db.tags,
      )..where((tbl) => tbl.name.equals(name))).getSingleOrNull();

      final tagId =
          existing?.id ??
          await _db.into(_db.tags).insert(TagsCompanion.insert(name: name));
      wantedIds.add(tagId);
      await _db
          .into(_db.noteTags)
          .insert(
            NoteTagsCompanion.insert(noteId: noteId, tagId: tagId),
            mode: InsertMode.insertOrIgnore,
          );
    }

    if (wanted.isEmpty) {
      await (_db.delete(
        _db.noteTags,
      )..where((tbl) => tbl.noteId.equals(noteId))).go();
    } else {
      await (_db.delete(_db.noteTags)..where(
            (tbl) => tbl.noteId.equals(noteId) & tbl.tagId.isNotIn(wantedIds),
          ))
          .go();
    }

    await _db.customUpdate(
      "DELETE FROM tags WHERE id NOT IN (SELECT tag_id FROM note_tags)",
      updates: {_db.tags},
    );
  }
}
