import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rembrain/core/db/database_provider.dart';
import 'package:rembrain/core/db/note_repo.dart';

final noteRepoProvider = Provider<NoteRepo>(
  (ref) => NoteRepo(ref.watch(appDbProvider)),
);
