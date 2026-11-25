/// @mentions, with the same rules as the web app and the server.

/// What the person is typing after an "@".
class MentionQuery {
  const MentionQuery(this.query, this.start);

  /// The letters typed so far ("an" for "@an").
  final String query;

  /// Where the "@" sits in the text.
  final int start;

  @override
  bool operator ==(Object other) => other is MentionQuery && other.query == query && other.start == start;

  @override
  int get hashCode => Object.hash(query, start);
}

final _typing = RegExp(r'(?:^|\s)@([a-zA-Z0-9_]*)$');

/// The mention being typed right before [cursor], or null.
MentionQuery? mentionAt(String text, int cursor) {
  if (cursor < 0 || cursor > text.length) return null;
  final m = _typing.firstMatch(text.substring(0, cursor));
  if (m == null) return null;
  final query = m.group(1)!;
  return MentionQuery(query, cursor - query.length - 1);
}

/// Up to [limit] names that start with what was typed, in the order given.
List<String> mentionSuggestions(Iterable<String> names, String query, {int limit = 6}) {
  final q = query.toLowerCase();
  return names.where((n) => n.toLowerCase().startsWith(q)).take(limit).toList();
}

/// Puts [name] in place of the typed mention and adds a space after it.
({String text, int cursor}) applyMention(String text, int cursor, MentionQuery q, String name) {
  final before = text.substring(0, q.start);
  final after = text.substring(cursor);
  final inserted = '@$name ';
  return (text: before + inserted + after, cursor: before.length + inserted.length);
}

/// True when [text] addresses [username]: the "@" starts a word and the name
/// ends the word or is followed by . , ! ?
bool mentionsUser(String text, String username) {
  if (username.isEmpty) return false;
  final re = RegExp(r'(?:^|\s)@' + RegExp.escape(username) + r'(?:\s|$|[.,!?])', caseSensitive: false);
  return re.hasMatch(text);
}
