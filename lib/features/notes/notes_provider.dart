import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rembrain/core/db/database.dart';
import 'package:rembrain/core/db/note_repo_provider.dart';

final noteListProvider = StreamProvider<List<Note>>((ref) {
  return ref.watch(noteRepoProvider).watchNotes();
});
