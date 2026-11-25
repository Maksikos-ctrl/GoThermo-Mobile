import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/message.dart';
import '../screens/thread_screen.dart';
import 'motion.dart';
import '../state/chat_controller.dart';
import '../theme.dart';
import '../util/emoji_data.dart';
import '../util/gif_url.dart';
import '../util/report_reasons.dart';
import 'emoji_panel.dart';
import 'toast.dart';

/// The sheet that opens when you long-press a message: react, thread, pin,
/// decisions, copy, edit, delete or report.
Future<void> showMessageActions(BuildContext context, ChatController chat, Message m) async {
  final mine = m.user == chat.me;
  final canEdit = mine && !m.isFile && !m.isCall && gifUrlOf(m.text) == null;
  final action = await showModalBottomSheet<_Action>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final e in quickReactions)
                  _QuickReaction(
                    emoji: e,
                    selected: m.reactions[e]?.contains(chat.me) ?? false,
                    onTap: () => Navigator.pop(sheetContext, _Action.react(e)),
                  ),
                IconButton.filledTonal(
                  tooltip: 'More reactions',
                  icon: const Icon(Icons.add_reaction_outlined),
                  onPressed: () => Navigator.pop(sheetContext, const _Action.more()),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (!m.isCall && m.threadId.isEmpty)
            ListTile(
              key: const Key('action-thread'),
              leading: const Icon(Icons.forum_outlined),
              title: const Text('Reply in thread'),
              onTap: () => Navigator.pop(sheetContext, const _Action.thread()),
            ),
          if (!m.isCall && m.threadId.isEmpty)
            ListTile(
              key: const Key('action-pin'),
              leading: Icon(chat.isPinned(m.channel, m.id) ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(chat.isPinned(m.channel, m.id) ? 'Unpin message' : 'Pin message'),
              onTap: () => Navigator.pop(sheetContext, const _Action.pin()),
            ),
          if (!m.isCall && m.threadId.isEmpty)
            ListTile(
              key: const Key('action-decision'),
              leading: const Icon(Icons.checklist_outlined),
              title: const Text('Add to decisions'),
              onTap: () => Navigator.pop(sheetContext, const _Action.decision()),
            ),
          if (m.text.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Copy text'),
              onTap: () => Navigator.pop(sheetContext, const _Action.copy()),
            ),
          if (canEdit)
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () => Navigator.pop(sheetContext, const _Action.edit()),
            ),
          if (!mine && !m.isCall)
            ListTile(
              key: const Key('action-report'),
              leading: Icon(Icons.flag_outlined, color: Palette.danger),
              title: Text('Report message', style: TextStyle(color: Palette.danger)),
              onTap: () => Navigator.pop(sheetContext, const _Action.report()),
            ),
          if (mine)
            ListTile(
              leading: Icon(Icons.delete_outline, color: Palette.danger),
              title: Text('Delete', style: TextStyle(color: Palette.danger)),
              onTap: () => Navigator.pop(sheetContext, const _Action.delete()),
            ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;

  switch (action.kind) {
    case _Kind.react:
      final reactError = await chat.react(m, action.emoji);
      if (context.mounted) toastIfError(context, reactError);
    case _Kind.more:
      final emoji = await showEmojiSheet(context);
      if (emoji == null) return;
      final moreError = await chat.react(m, emoji);
      if (context.mounted) toastIfError(context, moreError);
    case _Kind.thread:
      await Navigator.of(context).push(riseRoute<void>(ThreadScreen(chat: chat, parent: m)));
    case _Kind.pin:
      final pinError = chat.isPinned(m.channel, m.id) ? await chat.unpin(m) : await chat.pin(m);
      if (context.mounted) toastIfError(context, pinError);
    case _Kind.decision:
      final kind = await showDialog<String>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('Add to decisions'),
          children: [
            SimpleDialogOption(
              key: const Key('kind-decision'),
              onPressed: () => Navigator.pop(dialogContext, 'decision'),
              child: const Text('A decision'),
            ),
            SimpleDialogOption(
              key: const Key('kind-task'),
              onPressed: () => Navigator.pop(dialogContext, 'task'),
              child: const Text('A task'),
            ),
          ],
        ),
      );
      if (kind == null) return;
      final markError = await chat.markDecision(m, kind);
      if (context.mounted) {
        if (markError == null) {
          showToast(context, kind == 'task' ? 'Added as a task' : 'Added as a decision');
        } else {
          toastIfError(context, markError);
        }
      }
    case _Kind.report:
      final reason = await _askReason(context);
      if (reason == null) return;
      final reportError = await chat.report(m, reason);
      if (context.mounted) {
        if (reportError == null) {
          showToast(context, 'Report sent. Thank you');
        } else {
          toastIfError(context, reportError);
        }
      }
    case _Kind.copy:
      await Clipboard.setData(ClipboardData(text: m.text));
      if (context.mounted) showToast(context, 'Copied');
    case _Kind.edit:
      final text = await _askText(context, 'Edit message', m.text);
      if (text == null) return;
      final editError = await chat.edit(m, text);
      if (context.mounted) toastIfError(context, editError);
    case _Kind.delete:
      final sure = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Delete this message?'),
          content: const Text('It will disappear for everyone.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text('Delete', style: TextStyle(color: Palette.danger)),
            ),
          ],
        ),
      );
      if (sure != true) return;
      final deleteError = await chat.delete(m);
      if (context.mounted) toastIfError(context, deleteError);
  }
}

Future<String?> _askReason(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: const Text('Report this message'),
      children: [
        for (final r in reportReasons)
          SimpleDialogOption(
            key: Key('reason-${r.id}'),
            onPressed: () => Navigator.pop(dialogContext, r.id),
            child: Text(r.label),
          ),
      ],
    ),
  );
}

Future<String?> _askText(BuildContext context, String title, String initial) {
  final field = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        key: const Key('edit-field'),
        controller: field,
        autofocus: true,
        minLines: 1,
        maxLines: 6,
        textCapitalization: TextCapitalization.sentences,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(dialogContext, field.text), child: const Text('Save')),
      ],
    ),
  );
}

enum _Kind { react, more, copy, edit, delete, thread, pin, decision, report }

class _Action {
  const _Action._(this.kind, this.emoji);

  const _Action.react(String emoji) : this._(_Kind.react, emoji);
  const _Action.more() : this._(_Kind.more, '');
  const _Action.copy() : this._(_Kind.copy, '');
  const _Action.edit() : this._(_Kind.edit, '');
  const _Action.delete() : this._(_Kind.delete, '');
  const _Action.thread() : this._(_Kind.thread, '');
  const _Action.pin() : this._(_Kind.pin, '');
  const _Action.decision() : this._(_Kind.decision, '');
  const _Action.report() : this._(_Kind.report, '');

  final _Kind kind;
  final String emoji;
}

class _QuickReaction extends StatelessWidget {
  const _QuickReaction({required this.emoji, required this.selected, required this.onTap});

  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? Palette.accent.withAlpha(70) : Colors.transparent,
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 24)),
      ),
    );
  }
}

/// The sheet for a reply in a thread: react, copy, and for your own replies edit and delete.
Future<void> showReplyActions(BuildContext context, ChatController chat, Message reply) async {
  final mine = reply.user == chat.me;
  final canEdit = mine && !reply.isFile && gifUrlOf(reply.text) == null;
  final action = await showModalBottomSheet<_Action>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final e in quickReactions)
                  _QuickReaction(
                    emoji: e,
                    selected: reply.reactions[e]?.contains(chat.me) ?? false,
                    onTap: () => Navigator.pop(sheetContext, _Action.react(e)),
                  ),
                IconButton.filledTonal(
                  tooltip: 'More reactions',
                  icon: const Icon(Icons.add_reaction_outlined),
                  onPressed: () => Navigator.pop(sheetContext, const _Action.more()),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (reply.text.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Copy text'),
              onTap: () => Navigator.pop(sheetContext, const _Action.copy()),
            ),
          if (canEdit)
            ListTile(
              key: const Key('reply-edit'),
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () => Navigator.pop(sheetContext, const _Action.edit()),
            ),
          if (mine)
            ListTile(
              key: const Key('reply-delete'),
              leading: Icon(Icons.delete_outline, color: Palette.danger),
              title: Text('Delete', style: TextStyle(color: Palette.danger)),
              onTap: () => Navigator.pop(sheetContext, const _Action.delete()),
            ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;

  switch (action.kind) {
    case _Kind.react:
      toastIfError(context, await chat.reactToReply(reply, action.emoji));
    case _Kind.more:
      final emoji = await showEmojiSheet(context);
      if (emoji == null || !context.mounted) return;
      toastIfError(context, await chat.reactToReply(reply, emoji));
    case _Kind.copy:
      await Clipboard.setData(ClipboardData(text: reply.text));
      if (context.mounted) showToast(context, 'Copied');
    case _Kind.edit:
      final text = await _askText(context, 'Edit reply', reply.text);
      if (text == null || !context.mounted) return;
      toastIfError(context, await chat.editReply(reply, text));
    case _Kind.delete:
      final sure = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Delete this reply?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text('Delete', style: TextStyle(color: Palette.danger)),
            ),
          ],
        ),
      );
      if (sure != true || !context.mounted) return;
      toastIfError(context, await chat.deleteReply(reply));
    case _Kind.thread:
    case _Kind.pin:
    case _Kind.decision:
    case _Kind.report:
      break;
  }
}
