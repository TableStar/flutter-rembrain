import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rembrain/core/db/note_repo_provider.dart';

class QuickDumpBox extends ConsumerStatefulWidget {
  const QuickDumpBox({super.key});

  @override
  ConsumerState<QuickDumpBox> createState() {
    return _QuickDumpBoxState();
  }
}

class _QuickDumpBoxState extends ConsumerState<QuickDumpBox> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final content = _controller.text.trim();
    if (content.isEmpty || _sending) {
      return;
    }
    try {
      await ref.read(noteRepoProvider).insertNote(content);
      _controller.clear();
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('dumped')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('failed to save - text kept')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _controller.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(
                hintText: 'dump a thought.... #tag it if u likee',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: hasText && !_sending ? _send : null,
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}
