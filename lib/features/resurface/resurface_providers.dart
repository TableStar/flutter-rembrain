import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rembrain/core/db/database.dart';
import 'package:rembrain/core/db/note_repo_provider.dart';
import 'package:rembrain/features/resurface/resurface_logic.dart';

final resurfacePickProvider = FutureProvider.autoDispose<Note?>((ref) async {
  final candidates = await ref.watch(noteRepoProvider).resurfaceCandidates();
  if (candidates.isEmpty) return null;

  final pick = pickWeighted(
    candidates,
    candidates.map((e) => e.createdAt).toList(),
    DateTime.now(),
    Random(),
  );
  await ref.read(noteRepoProvider).markResurfaced(pick.id);
  return pick;
});

class ResurfaceDismissed extends Notifier<bool> {
  @override
  bool build() => false;

  void dismiss() => state = true;
}

final resurfaceDismissedProvider = NotifierProvider<ResurfaceDismissed, bool>(
  ResurfaceDismissed.new,
);
