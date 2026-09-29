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

  test('exclude archived notes', () async {
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
