import 'package:flutter/material.dart';

import '../models/extras.dart';
import '../state/chat_controller.dart';
import '../theme.dart';
import '../util/time_format.dart';
import '../widgets/toast.dart';

/// Decisions and tasks marked in one channel.
class DecisionsScreen extends StatefulWidget {
  const DecisionsScreen({super.key, required this.chat, required this.channel});

  final ChatController chat;
  final String channel;

  @override
  State<DecisionsScreen> createState() => _DecisionsScreenState();
}

class _DecisionsScreenState extends State<DecisionsScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final error = await widget.chat.loadDecisions(widget.channel);
    if (!mounted) return;
    setState(() => _loading = false);
    toastIfError(context, error);
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    return Scaffold(
      appBar: AppBar(title: const Text('Decisions & tasks')),
      body: ListenableBuilder(
        listenable: chat,
        builder: (context, _) {
          final all = chat.decisionsOf(widget.channel);
          if (all.isEmpty) {
            return Center(
              child: _loading
                  ? const CircularProgressIndicator(strokeWidth: 2)
                  : Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'No decisions or tasks yet.\nLong-press a message and choose Add to decisions.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Palette.textMuted),
                      ),
                    ),
            );
          }
          final open = all.where((d) => d.isTask && !d.done).toList();
          final decisions = all.where((d) => !d.isTask).toList();
          final done = all.where((d) => d.isTask && d.done).toList();
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              if (open.isNotEmpty) _section('Tasks'),
              for (final d in open) _tile(context, d),
              if (decisions.isNotEmpty) _section('Decisions'),
              for (final d in decisions) _tile(context, d),
              if (done.isNotEmpty) _section('Done'),
              for (final d in done) _tile(context, d),
            ],
          );
        },
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(color: Palette.textMuted, fontSize: 11.5, letterSpacing: 1, fontWeight: FontWeight.w700),
        ),
      );

  Widget _tile(BuildContext context, Decision d) {
    final chat = widget.chat;
    return ListTile(
      key: Key('decision-${d.messageId}'),
      leading: d.isTask
          ? Checkbox(
              key: Key('done-${d.messageId}'),
              value: d.done,
              onChanged: (v) async {
                final error = await chat.setDecisionDone(d, v ?? false);
                if (context.mounted) toastIfError(context, error);
              },
            )
          : Icon(Icons.gavel_outlined, color: Palette.accent),
      title: Text(
        d.text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(decoration: d.done ? TextDecoration.lineThrough : null, color: d.done ? Palette.textMuted : null),
      ),
      subtitle: Text(
        [
          if (d.author.isNotEmpty) 'by ${d.author}',
          if (d.assignee.isNotEmpty) 'for ${d.assignee}',
          if (d.done && d.doneBy.isNotEmpty) 'done by ${d.doneBy}',
          clock(d.at),
        ].join(' · '),
        style: TextStyle(color: Palette.textMuted, fontSize: 12),
      ),
      trailing: IconButton(
        key: Key('remove-${d.messageId}'),
        tooltip: 'Remove',
        icon: const Icon(Icons.close),
        onPressed: () async {
          final error = await chat.removeDecision(d);
          if (context.mounted) toastIfError(context, error);
        },
      ),
    );
  }
}
