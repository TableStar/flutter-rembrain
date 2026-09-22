import 'package:rembrain/core/db/database_provider.dart';
import 'package:rembrain/core/db/note_repo.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'note_repo_provider.g.dart';

@Riverpod(keepAlive: true)
NoteRepo noteRepo(Ref ref) => NoteRepo(ref.watch(appDbProvider));
