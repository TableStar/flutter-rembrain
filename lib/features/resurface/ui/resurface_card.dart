import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rembrain/core/db/note_repo_provider.dart';
import 'package:rembrain/core/utils/date_format.dart';
import 'package:rembrain/features/resurface/resurface_providers.dart';

class ResurfaceCard extends ConsumerWidget {
  const ResurfaceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(resurfaceDismissedProvider)) {
      return const SizedBox.shrink();
    }

    final pickAsync = ref.watch(resurfacePickProvider);
    return pickAsync.when(
      data: (note) {
        if (note == null) return const SizedBox.shrink();
        return Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'you wrote this ${daysAgoLabel(note.createdAt)} — still relevant?',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  note.content,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => _forget(context, ref, note.id),
                      child: const Text('forget'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () async {
                        await ref
                            .read(noteRepoProvider)
                            .setArchived(note.id, true);
                        ref.read(resurfaceDismissedProvider.notifier).dismiss();
                      },
                      child: const Text('archive'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => ref
                          .read(resurfaceDismissedProvider.notifier)
                          .dismiss(),
                      child: const Text('keep'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
      error: (e, _) => const SizedBox.shrink(),
      loading: () => const SizedBox.shrink(),
    );
  }

  Future<void> _forget(BuildContext context, WidgetRef ref, int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: const Text('forget this note foreva?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('cancel'),
          ),
          TextButton(
            key: const Key('confirm-delete'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('forget'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(noteRepoProvider).deleteNote(id);
      ref.read(resurfaceDismissedProvider.notifier).dismiss();
    }
  }
}
