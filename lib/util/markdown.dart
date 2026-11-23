/// What a piece of message text is, after reading the simple markup the web
/// and desktop apps understand.
enum SpanKind { text, bold, italic, strike, code, codeBlock, link, mention }

class MdSpan {
  const MdSpan(this.kind, this.text);

  final SpanKind kind;
  final String text;

  @override
  bool operator ==(Object other) => other is MdSpan && other.kind == kind && other.text == text;

  @override
  int get hashCode => Object.hash(kind, text);

  @override
  String toString() => 'MdSpan($kind, "$text")';
}

// Order matters: the first rule that matches at a position wins.
final _rules = <(SpanKind, RegExp)>[
  (SpanKind.codeBlock, RegExp(r'```([\s\S]+?)```')),
  (SpanKind.code, RegExp(r'`([^`\n]+)`')),
  (SpanKind.bold, RegExp(r'\*\*([^*\n]+?)\*\*')),
  (SpanKind.strike, RegExp(r'~~([^~\n]+?)~~')),
  (SpanKind.italic, RegExp(r'(?<![\w*])\*(?!\s)([^*\n]+?)(?<!\s)\*(?![\w*])')),
  (SpanKind.italic, RegExp(r'(?<![\w_])_(?!\s)([^_\n]+?)(?<!\s)_(?![\w_])')),
  (SpanKind.link, RegExp(r'https?://[^\s<>()]+[^\s<>().,;:!?]')),
  (SpanKind.mention, RegExp(r'(?<![\w@])@[A-Za-z0-9.\-]+')),
];

/// Splits [input] into styled spans. Never throws; text with no markup comes
/// back as one plain span.
List<MdSpan> parseMarkdown(String input) {
  final out = <MdSpan>[];
  var rest = input;
  while (rest.isNotEmpty) {
    Match? best;
    SpanKind? bestKind;
    for (final (kind, re) in _rules) {
      final m = re.firstMatch(rest);
      if (m == null) continue;
      if (best == null || m.start < best.start) {
        best = m;
        bestKind = kind;
      }
    }
    if (best == null || bestKind == null) {
      out.add(MdSpan(SpanKind.text, rest));
      break;
    }
    if (best.start > 0) out.add(MdSpan(SpanKind.text, rest.substring(0, best.start)));
    final inner = best.groupCount >= 1 ? (best.group(1) ?? best.group(0)!) : best.group(0)!;
    out.add(MdSpan(bestKind, bestKind == SpanKind.link || bestKind == SpanKind.mention ? best.group(0)! : inner));
    rest = rest.substring(best.end);
  }
  return out;
}
