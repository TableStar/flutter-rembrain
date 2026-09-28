import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rembrain/core/db/database.dart';
import 'package:rembrain/core/db/database_provider.dart';
import 'package:rembrain/core/db/note_repo.dart';
import 'package:rembrain/core/db/note_repo_provider.dart';

AppDb makeTestDb() => AppDb(NativeDatabase.memory());

ProviderContainer makeContainer(AppDb db) {
  final container = ProviderContainer(
    overrides: [
      appDbProvider.overrideWithValue(db),
      noteRepoProvider.overrideWithValue(NoteRepo(db)),
    ],
  );

  return container;
}
