import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import '../util/markdown.dart';

/// Message text with the simple markup the web app supports: **bold**,
/// *italic*, ~~strike~~, `code`, code blocks, links and @mentions.
class MarkdownText extends StatefulWidget {
  const MarkdownText({super.key, required this.text, required this.me, this.known, this.style});

  final String text;

  /// The signed-in person: a mention of them is highlighted.
  final String me;

  /// Lower-case names of real people; only those are highlighted. Null
  /// highlights every "@word".
  final Set<String>? known;
  final TextStyle? style;

  @override
  State<MarkdownText> createState() => _MarkdownTextState();
}

class _MarkdownTextState extends State<MarkdownText> {
  final List<TapGestureRecognizer> _taps = [];

  void _clearTaps() {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
  }

  @override
  void dispose() {
    _clearTaps();
    super.dispose();
  }

  Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } on Object {
      // nothing can open it; ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    _clearTaps();
    final base = (widget.style ?? Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
        .copyWith(color: Palette.textPrimary, height: 1.3);
    final blocks = <Widget>[];
    var inline = <InlineSpan>[];

    void flush() {
      if (inline.isEmpty) return;
      blocks.add(Text.rich(TextSpan(style: base, children: inline)));
      inline = <InlineSpan>[];
    }

    for (final s in parseMarkdown(widget.text, known: widget.known)) {
      switch (s.kind) {
        case SpanKind.text:
          inline.add(TextSpan(text: s.text));
        case SpanKind.bold:
          inline.add(TextSpan(text: s.text, style: const TextStyle(fontWeight: FontWeight.w700)));
        case SpanKind.italic:
          inline.add(TextSpan(text: s.text, style: const TextStyle(fontStyle: FontStyle.italic)));
        case SpanKind.strike:
          inline.add(TextSpan(text: s.text, style: const TextStyle(decoration: TextDecoration.lineThrough)));
        case SpanKind.code:
          inline.add(TextSpan(
            text: s.text,
            style: TextStyle(fontFamily: 'monospace', backgroundColor: Palette.bgTertiary, fontSize: 13.5),
          ));
        case SpanKind.link:
          final tap = TapGestureRecognizer()..onTap = () => _open(s.text);
          _taps.add(tap);
          inline.add(TextSpan(
            text: s.text,
            style: const TextStyle(color: Color(0xFF8E9AFF), decoration: TextDecoration.underline),
            recognizer: tap,
          ));
        case SpanKind.mention:
          final mine = s.text.substring(1).toLowerCase() == widget.me.toLowerCase();
          inline.add(TextSpan(
            text: s.text,
            style: TextStyle(
              color: const Color(0xFFB4BBFF),
              fontWeight: FontWeight.w600,
              backgroundColor: mine ? Palette.accent.withAlpha(70) : Palette.accent.withAlpha(36),
            ),
          ));
        case SpanKind.codeBlock:
          flush();
          blocks.add(Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Palette.bgTertiary,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Palette.border),
            ),
            child: Text(
              s.text.trim(),
              style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: Palette.textPrimary),
            ),
          ));
      }
    }
    flush();

    if (blocks.length == 1) return blocks.first;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: blocks);
  }
}
