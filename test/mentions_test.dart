import 'package:flutter_test/flutter_test.dart';
import 'package:gothermo_mobile/util/markdown.dart';
import 'package:gothermo_mobile/util/mentions.dart';

void main() {
  group('typing a mention', () {
    test('finds the @ before the cursor', () {
      expect(mentionAt('@', 1), const MentionQuery('', 0));
      expect(mentionAt('hi @an', 6), const MentionQuery('an', 3));
      expect(mentionAt('hi @an and', 6), const MentionQuery('an', 3)); // cursor in the middle
      expect(mentionAt('line\n@b', 7), const MentionQuery('b', 5));
    });

    test('not inside an email, after a word, or once the name is done', () {
      expect(mentionAt('mail a@b', 8), isNull);
      expect(mentionAt('hi @ann ', 8), isNull);
      expect(mentionAt('hi', 2), isNull);
      expect(mentionAt('x', 5), isNull);
    });

    test('suggestions start with what was typed, in order, at most six', () {
      const names = ['Ann', 'anna', 'bob', 'Anton', 'cy', 'an1', 'an2', 'an3', 'an4'];
      expect(mentionSuggestions(names, 'an'), ['Ann', 'anna', 'Anton', 'an1', 'an2', 'an3']);
      expect(mentionSuggestions(names, ''), ['Ann', 'anna', 'bob', 'Anton', 'cy', 'an1']);
      expect(mentionSuggestions(names, 'zz'), isEmpty);
      expect(mentionSuggestions(names, 'BO'), ['bob']);
    });

    test('picking one fills the name, adds a space and keeps the rest', () {
      final q = mentionAt('hi @an and more', 6)!;
      final r = applyMention('hi @an and more', 6, q, 'anna');
      expect(r.text, 'hi @anna  and more');
      expect(r.cursor, 9);
      final end = applyMention('@b', 2, mentionAt('@b', 2)!, 'bob');
      expect(end.text, '@bob ');
      expect(end.cursor, 5);
    });
  });

  group('who is addressed', () {
    test('the same rule as the server', () {
      expect(mentionsUser('hello @ann', 'ann'), isTrue);
      expect(mentionsUser('@ann, hi', 'ann'), isTrue);
      expect(mentionsUser('thanks @Ann!', 'ann'), isTrue);
      expect(mentionsUser('@annabel hi', 'ann'), isFalse);
      expect(mentionsUser('mail x@ann.io', 'ann'), isFalse);
      expect(mentionsUser('no one', 'ann'), isFalse);
      expect(mentionsUser('@ann', ''), isFalse);
    });
  });

  group('highlighting', () {
    test('only real people are highlighted when names are known', () {
      final spans = parseMarkdown('hi @ann and @nobody', known: {'ann', 'bob'});
      expect(spans, [
        const MdSpan(SpanKind.text, 'hi '),
        const MdSpan(SpanKind.mention, '@ann'),
        const MdSpan(SpanKind.text, ' and @nobody'),
      ]);
    });

    test('without a list every @word is a mention, and names stop at a dot', () {
      expect(parseMarkdown('@x').single, const MdSpan(SpanKind.mention, '@x'));
      expect(parseMarkdown('ok @ann.'), [
        const MdSpan(SpanKind.text, 'ok '),
        const MdSpan(SpanKind.mention, '@ann'),
        const MdSpan(SpanKind.text, '.'),
      ]);
    });
  });
}
