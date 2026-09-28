import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rembrain/features/notes/notes_provider.dart';
import 'package:rembrain/features/notes/ui/note_card.dart';

class NotesListScreen extends ConsumerWidget {
  const NotesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(noteListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Notes list')),
      body: notesAsync.when(
        data: (notes) => notes.isEmpty
            ? const Center(child: Text('nothing yet — dump your first thought'))
            : ListView.builder(
                itemCount: notes.length,
                itemBuilder: (_, i) => NoteCard(note: notes[i]),
              ),
        error: (e, _) => Center(child: Text('error: $e')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
