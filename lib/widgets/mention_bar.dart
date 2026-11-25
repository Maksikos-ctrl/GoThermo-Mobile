import 'package:flutter/material.dart';

import '../util/mentions.dart';

/// A row of names above a text field: shows who matches the "@word" being typed
/// and fills the name in when one is tapped.
class MentionBar extends StatefulWidget {
  const MentionBar({super.key, required this.controller, required this.mentionable, this.focus});

  final TextEditingController controller;
  final List<String> mentionable;
  final FocusNode? focus;

  @override
  State<MentionBar> createState() => _MentionBarState();
}

class _MentionBarState extends State<MentionBar> {
  MentionQuery? _query;
  List<String> _names = const [];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_update);
  }

  @override
  void didUpdateWidget(MentionBar old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_update);
      widget.controller.addListener(_update);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_update);
    super.dispose();
  }

  void _update() {
    final text = widget.controller.text;
    final sel = widget.controller.selection;
    final q = sel.isValid && sel.isCollapsed ? mentionAt(text, sel.baseOffset) : null;
    final list = q == null ? const <String>[] : mentionSuggestions(widget.mentionable, q.query);
    if (q == _query && list.length == _names.length) return;
    setState(() {
      _query = q;
      _names = list;
    });
  }

  void _pick(String name) {
    final q = _query;
    if (q == null) return;
    final c = widget.controller;
    final r = applyMention(c.text, c.selection.baseOffset, q, name);
    c.value = TextEditingValue(text: r.text, selection: TextSelection.collapsed(offset: r.cursor));
    widget.focus?.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    if (_names.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView(
        key: const Key('mention-list'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        children: [
          for (final name in _names)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                key: Key('mention-$name'),
                label: Text('@$name'),
                visualDensity: VisualDensity.compact,
                onPressed: () => _pick(name),
              ),
            ),
        ],
      ),
    );
  }
}
