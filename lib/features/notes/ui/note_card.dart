import 'package:flutter/material.dart';
import 'package:rembrain/core/db/database.dart';
import 'package:rembrain/core/utils/date_format.dart';

class NoteCard extends StatelessWidget {
  const NoteCard({super.key, required this.note, this.onTap});

  final Note note;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        onTap: onTap,
        title: Text(
          note.title ?? note.content,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(daysAgoLabel(note.createdAt)),
      ),
    );
  }
}
