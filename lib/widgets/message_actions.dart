import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/message.dart';
import '../state/chat_controller.dart';
import '../theme.dart';
import '../util/emoji_data.dart';
import '../util/gif_url.dart';
import 'emoji_panel.dart';
import 'toast.dart';

/// The sheet that opens when you long-press a message: react, copy, edit, delete.
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
          if (mine)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Palette.danger),
              title: const Text('Delete', style: TextStyle(color: Palette.danger)),
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
              child: const Text('Delete', style: TextStyle(color: Palette.danger)),
            ),
          ],
        ),
      );
      if (sure != true) return;
      final deleteError = await chat.delete(m);
      if (context.mounted) toastIfError(context, deleteError);
  }
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

enum _Kind { react, more, copy, edit, delete }

class _Action {
  const _Action._(this.kind, this.emoji);

  const _Action.react(String emoji) : this._(_Kind.react, emoji);
  const _Action.more() : this._(_Kind.more, '');
  const _Action.copy() : this._(_Kind.copy, '');
  const _Action.edit() : this._(_Kind.edit, '');
  const _Action.delete() : this._(_Kind.delete, '');

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
