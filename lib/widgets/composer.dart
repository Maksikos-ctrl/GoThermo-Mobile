import 'package:flutter/material.dart';

import '../theme.dart';
import '../util/emoji_data.dart';
import '../util/mentions.dart';
import 'emoji_panel.dart';

/// What the "+" menu offers.
enum AttachChoice { gallery, camera, file }

/// The message box: attach, text, emoji, GIF and send.
class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.hint,
    required this.onSend,
    required this.onAttach,
    this.onGif,
    this.onTyping,
    this.mentionable = const [],
  });

  final String hint;
  final ValueChanged<String> onSend;
  final ValueChanged<AttachChoice> onAttach;

  /// Null hides the GIF button (the server has no GIF key).
  final VoidCallback? onGif;

  /// Called while the person types.
  final VoidCallback? onTyping;

  /// Names offered when the person types "@".
  final List<String> mentionable;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  bool _emoji = false;
  bool _hasText = false;
  MentionQuery? _mention;
  List<String> _suggestions = const [];

  @override
  void initState() {
    super.initState();
    _text.addListener(() {
      final has = _text.text.trim().isNotEmpty;
      if (has) widget.onTyping?.call();
      if (has != _hasText) setState(() => _hasText = has);
      _updateMention();
    });
    _focus.addListener(() {
      if (_focus.hasFocus && _emoji) setState(() => _emoji = false);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _updateMention() {
    final sel = _text.selection;
    final q = sel.isValid && sel.isCollapsed ? mentionAt(_text.text, sel.baseOffset) : null;
    final list = q == null ? const <String>[] : mentionSuggestions(widget.mentionable, q.query);
    final same = q == _mention && list.length == _suggestions.length;
    if (same) return;
    setState(() {
      _mention = q;
      _suggestions = list;
    });
  }

  void _pickMention(String name) {
    final q = _mention;
    if (q == null) return;
    final cursor = _text.selection.baseOffset;
    final r = applyMention(_text.text, cursor, q, name);
    _text.value = TextEditingValue(text: r.text, selection: TextSelection.collapsed(offset: r.cursor));
    _focus.requestFocus();
  }

  void _send() {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    widget.onSend(body);
    _text.clear();
  }

  void _toggleEmoji() {
    if (_emoji) {
      setState(() => _emoji = false);
      _focus.requestFocus();
    } else {
      _focus.unfocus();
      setState(() => _emoji = true);
    }
  }

  void _insert(String emoji) {
    final value = _text.value;
    final sel = value.selection;
    final start = sel.isValid ? sel.start : value.text.length;
    final end = sel.isValid ? sel.end : value.text.length;
    _text.value = TextEditingValue(
      text: value.text.replaceRange(start, end, emoji),
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  void _backspace() {
    final value = _text.value;
    final sel = value.selection;
    if (sel.isValid && !sel.isCollapsed) {
      _insert('');
      return;
    }
    final cursor = sel.isValid ? sel.start : value.text.length;
    final before = dropLastGrapheme(value.text.substring(0, cursor));
    _text.value = TextEditingValue(
      text: before + value.text.substring(cursor),
      selection: TextSelection.collapsed(offset: before.length),
    );
  }

  Future<void> _attach() async {
    final choice = await showModalBottomSheet<AttachChoice>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Photo from gallery'),
              onTap: () => Navigator.pop(sheetContext, AttachChoice.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(sheetContext, AttachChoice.camera),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('File'),
              onTap: () => Navigator.pop(sheetContext, AttachChoice.file),
            ),
          ],
        ),
      ),
    );
    if (choice != null) widget.onAttach(choice);
  }

  @override
  Widget build(BuildContext context) {
    const none = InputBorder.none;
    return Material(
      color: Palette.bgSecondary,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_suggestions.isNotEmpty)
              SizedBox(
                height: 44,
                child: ListView(
                  key: const Key('mention-list'),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  children: [
                    for (final name in _suggestions)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          key: Key('mention-$name'),
                          label: Text('@$name'),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _pickMention(name),
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    key: const Key('attach'),
                    tooltip: 'Attach',
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: _attach,
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Palette.bgTertiary,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: Palette.border),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextField(
                              key: const Key('message-field'),
                              controller: _text,
                              focusNode: _focus,
                              minLines: 1,
                              maxLines: 5,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: InputDecoration(
                                hintText: widget.hint,
                                filled: false,
                                isDense: true,
                                border: none,
                                enabledBorder: none,
                                focusedBorder: none,
                                disabledBorder: none,
                                errorBorder: none,
                                focusedErrorBorder: none,
                                contentPadding: const EdgeInsets.fromLTRB(16, 11, 4, 11),
                              ),
                            ),
                          ),
                          IconButton(
                            key: const Key('emoji'),
                            tooltip: 'Emoji',
                            visualDensity: VisualDensity.compact,
                            icon: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 160),
                              child: Icon(
                                _emoji ? Icons.keyboard_alt_outlined : Icons.emoji_emotions_outlined,
                                key: ValueKey<bool>(_emoji),
                              ),
                            ),
                            onPressed: _toggleEmoji,
                          ),
                          if (widget.onGif != null)
                            IconButton(
                              key: const Key('gif'),
                              tooltip: 'GIF',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.gif_box_outlined),
                              onPressed: widget.onGif,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedScale(
                    scale: _hasText ? 1 : 0.85,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutBack,
                    child: IconButton.filled(
                      key: const Key('send'),
                      tooltip: 'Send',
                      onPressed: _hasText ? _send : null,
                      icon: const Icon(Icons.arrow_upward_rounded),
                    ),
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _emoji
                  ? SizedBox(
                      height: 280,
                      child: EmojiPanel(onPick: _insert, onBackspace: _backspace),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}
