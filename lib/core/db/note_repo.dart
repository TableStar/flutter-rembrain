import 'package:drift/drift.dart';
import 'package:rembrain/core/db/database.dart';

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

  Future<Note> insertNote(String content, {String? title}) async {
    final id = await _db
        .into(_db.notes)
        .insert(NotesCompanion.insert(content: content, title: Value(title)));
    return (_db.select(_db.notes)..where((n) => n.id.equals(id))).getSingle();
  }

  Stream<Note?> watchNote(int id) {
    return (_db.select(
      _db.notes,
    )..where((n) => n.id.equals(id))).watchSingleOrNull();
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
}
