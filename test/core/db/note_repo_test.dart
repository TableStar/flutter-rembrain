import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rembrain/core/db/database.dart';
import 'package:rembrain/core/db/note_repo.dart';

void main() {
  late AppDb db;
  late NoteRepo repo;

  setUp(() {
    db = AppDb(NativeDatabase.memory());
    repo = NoteRepo(db);
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
