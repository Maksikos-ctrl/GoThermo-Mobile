import 'package:flutter/material.dart';

import '../models/message.dart';
import '../state/chat_controller.dart';
import '../theme.dart';
import '../util/gif_url.dart';
import '../util/time_format.dart';
import 'avatar.dart';
import 'avatar_color.dart';
import 'file_views.dart';
import 'markdown_text.dart';
import 'toast.dart';

/// One message in the chat: avatar and name (when [showHeader]), the content,
/// and the reactions under it.
class MessageRow extends StatelessWidget {
  const MessageRow({
    super.key,
    required this.message,
    required this.chat,
    required this.showHeader,
    this.onLongPress,
  });

  final Message message;
  final ChatController chat;
  final bool showHeader;
  final VoidCallback? onLongPress;

  bool get _mentionsMe =>
      message.user != chat.me && message.text.toLowerCase().contains('@${chat.me.toLowerCase()}');

  @override
  Widget build(BuildContext context) {
    if (message.isCall) return _CallLine(message: message, chat: chat);

    final sending = message.sendState == SendState.sending;
    final failed = message.sendState == SendState.failed;

    return Material(
      color: _mentionsMe ? Palette.accent.withAlpha(28) : Colors.transparent,
      child: InkWell(
        onLongPress: sending || failed ? null : onLongPress,
        child: Container(
          decoration: _mentionsMe
              ? BoxDecoration(border: Border(left: BorderSide(color: Palette.accent, width: 3)))
              : null,
          padding: EdgeInsets.fromLTRB(12, showHeader ? 8 : 1, 12, 1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 40,
                child: showHeader
                    ? Avatar(username: message.user, picture: chat.avatarOf(message.user), size: 40)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: sending ? 0.55 : 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showHeader) _header(),
                      _content(context),
                      if (message.reactions.isNotEmpty) _reactions(context),
                      if (failed) _failed(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Flexible(
            child: Text(
              message.user,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w700, color: avatarColor(message.user)),
            ),
          ),
          const SizedBox(width: 8),
          Text(clock(message.timestamp), style: TextStyle(color: Palette.textMuted, fontSize: 11.5)),
          if (message.isEdited) ...[
            const SizedBox(width: 6),
            Text('edited', style: TextStyle(color: Palette.textMuted, fontSize: 11.5)),
          ],
        ],
      ),
    );
  }

  Widget _content(BuildContext context) {
    if (message.isFile) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: message.isImageFile
            ? ChatImage(chat: chat, message: message)
            : FileChip(chat: chat, message: message),
      );
    }
    final gif = gifUrlOf(message.text);
    if (gif != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: GifView(url: gif, heroTag: 'gif-${message.stableKey}'),
      );
    }
    final body = MarkdownText(text: message.text, me: chat.me);
    if (message.isPost) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: BoxDecoration(
          color: Palette.bgSecondary,
          borderRadius: BorderRadius.circular(10),
          border: Border(left: BorderSide(color: Palette.accent, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'POST',
              style: TextStyle(fontSize: 10.5, letterSpacing: 1.1, color: Color(0xFFB4BBFF), fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            body,
          ],
        ),
      );
    }
    return body;
  }

  Widget _reactions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 5, bottom: 2),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final entry in message.reactions.entries)
            _ReactionChip(
              emoji: entry.key,
              people: entry.value,
              mine: entry.value.contains(chat.me),
              onTap: () async {
                final error = await chat.react(message, entry.key);
                if (context.mounted) toastIfError(context, error);
              },
              onLongPress: () => showToast(context, '${entry.value.join(', ')} reacted with ${entry.key}'),
            ),
        ],
      ),
    );
  }

  Widget _failed() {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 15, color: Palette.danger),
          const SizedBox(width: 4),
          Text('Not sent', style: TextStyle(color: Palette.danger, fontSize: 12)),
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => chat.retry(message),
            child: const Text('Retry'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: Palette.textMuted,
            ),
            onPressed: () => chat.discard(message),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.emoji,
    required this.people,
    required this.mine,
    required this.onTap,
    required this.onLongPress,
  });

  final String emoji;
  final List<String> people;
  final bool mine;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: mine ? Palette.accent.withAlpha(60) : Palette.bgTertiary,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: mine ? Palette.accent : Palette.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 5),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                child: Text(
                  '${people.length}',
                  key: ValueKey<int>(people.length),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: mine ? const Color(0xFFD0D5FF) : Palette.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallLine extends StatelessWidget {
  const _CallLine({required this.message, required this.chat});

  final Message message;
  final ChatController chat;

  @override
  Widget build(BuildContext context) {
    final who = message.user == chat.me ? 'You' : message.user;
    late final IconData icon;
    late final String text;
    var color = Palette.textMuted;
    switch (message.callStatus) {
      case 'declined':
        icon = Icons.call_end;
        text = '$who - call declined';
        color = Palette.danger;
      case 'cancelled':
        icon = Icons.phone_missed;
        text = '$who - call cancelled';
      default:
        icon = Icons.call;
        text = '$who - call, ${callLength(message.callDuration)}';
        color = Palette.success;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Palette.bgSecondary,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Palette.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(text, style: TextStyle(fontSize: 12.5, color: Palette.textMuted)),
              const SizedBox(width: 8),
              Text(clock(message.timestamp), style: TextStyle(fontSize: 11, color: Palette.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The chip row under a message-less day: "Today", "Yesterday", "12 November".
class DayChip extends StatelessWidget {
  const DayChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(child: Divider(indent: 16, endIndent: 10)),
          Text(label, style: TextStyle(color: Palette.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
          const Expanded(child: Divider(indent: 10, endIndent: 16)),
        ],
      ),
    );
  }
}
