import 'package:flutter_test/flutter_test.dart';
import 'package:gothermo_mobile/util/emoji_data.dart';
import 'package:gothermo_mobile/util/gif_url.dart';
import 'package:gothermo_mobile/util/markdown.dart';
import 'package:gothermo_mobile/util/mime.dart';
import 'package:gothermo_mobile/util/time_format.dart';

void main() {
  group('gifUrlOf', () {
    test('accepts a giphy media link', () {
      expect(gifUrlOf('https://media2.giphy.com/media/abc/giphy.gif'), 'https://media2.giphy.com/media/abc/giphy.gif');
      expect(gifUrlOf('  https://i.giphy.com/x.webp '), 'https://i.giphy.com/x.webp');
    });

    test('refuses everything else', () {
      expect(gifUrlOf('http://media.giphy.com/x.gif'), isNull);
      expect(gifUrlOf('https://evil.com/x.gif'), isNull);
      expect(gifUrlOf('https://evilgiphy.com/x.gif'), isNull);
      expect(gifUrlOf('https://media.giphy.com/x.png'), isNull);
      expect(gifUrlOf('look https://media.giphy.com/x.gif'), isNull);
      expect(gifUrlOf('https://user@media.giphy.com/x.gif'), isNull);
      expect(gifUrlOf(''), isNull);
    });
  });

  group('parseMarkdown', () {
    test('plain text stays one span', () {
      expect(parseMarkdown('hello there'), [const MdSpan(SpanKind.text, 'hello there')]);
    });

    test('bold, italic, strike and code', () {
      expect(parseMarkdown('a **b** c'), [
        const MdSpan(SpanKind.text, 'a '),
        const MdSpan(SpanKind.bold, 'b'),
        const MdSpan(SpanKind.text, ' c'),
      ]);
      expect(parseMarkdown('*hi*'), [const MdSpan(SpanKind.italic, 'hi')]);
      expect(parseMarkdown('_hi_'), [const MdSpan(SpanKind.italic, 'hi')]);
      expect(parseMarkdown('~~no~~'), [const MdSpan(SpanKind.strike, 'no')]);
      expect(parseMarkdown('use `go test`'), [
        const MdSpan(SpanKind.text, 'use '),
        const MdSpan(SpanKind.code, 'go test'),
      ]);
    });

    test('code blocks keep their markup untouched', () {
      final spans = parseMarkdown('```\n**not bold**\n```');
      expect(spans.length, 1);
      expect(spans.first.kind, SpanKind.codeBlock);
      expect(spans.first.text, contains('**not bold**'));
    });

    test('links lose the trailing punctuation', () {
      expect(parseMarkdown('see https://x.io/a, ok'), [
        const MdSpan(SpanKind.text, 'see '),
        const MdSpan(SpanKind.link, 'https://x.io/a'),
        const MdSpan(SpanKind.text, ', ok'),
      ]);
    });

    test('mentions, but not inside an email address', () {
      expect(parseMarkdown('hi @ann!'), [
        const MdSpan(SpanKind.text, 'hi '),
        const MdSpan(SpanKind.mention, '@ann'),
        const MdSpan(SpanKind.text, '!'),
      ]);
      expect(parseMarkdown('mail a@b.io'), [const MdSpan(SpanKind.text, 'mail a@b.io')]);
    });

    test('snake_case words and lone stars are not italic', () {
      expect(parseMarkdown('my_var_name'), [const MdSpan(SpanKind.text, 'my_var_name')]);
      expect(parseMarkdown('2 * 3 * 4'), [const MdSpan(SpanKind.text, '2 * 3 * 4')]);
    });

    test('never loses text', () {
      const input = 'x **a** y `b` z ~~c~~ https://u.io @me *d* _e_ end';
      final back = parseMarkdown(input).map((s) => s.text).join();
      expect(back.replaceAll(' ', ''), contains('end'));
      expect(parseMarkdown('').isEmpty, isTrue);
    });
  });

  group('time formats', () {
    final now = DateTime(2026, 11, 12, 15, 30);

    test('clock', () => expect(clock(DateTime(2026, 1, 1, 7, 5)), '07:05'));

    test('day labels', () {
      expect(dayLabel(DateTime(2026, 11, 12, 1), now), 'Today');
      expect(dayLabel(DateTime(2026, 11, 11, 23), now), 'Yesterday');
      expect(dayLabel(DateTime(2026, 3, 2), now), '2 March');
      expect(dayLabel(DateTime(2025, 12, 31), now), '31 December 2025');
    });

    test('short stamps', () {
      expect(shortStamp(DateTime(2026, 11, 12, 9, 1), now), '09:01');
      expect(shortStamp(DateTime(2026, 11, 11, 9, 1), now), 'Yesterday');
      expect(shortStamp(DateTime(2026, 11, 3, 9, 1), now), '3 Nov');
    });

    test('file sizes', () {
      expect(fileSize(512), '512 B');
      expect(fileSize(2048), '2.0 KB');
      expect(fileSize(20 * 1024), '20 KB');
      expect(fileSize(3 * 1024 * 1024), '3.0 MB');
    });

    test('call length', () => expect(callLength(65), '1:05'));
  });

  group('mime', () {
    test('from the file name', () {
      expect(mimeFromName('Cat.PNG'), 'image/png');
      expect(mimeFromName('notes.txt'), 'text/plain');
      expect(mimeFromName('archive.tar.gz'), 'application/octet-stream');
      expect(mimeFromName('noext'), 'application/octet-stream');
      expect(mimeFromName('trailing.'), 'application/octet-stream');
    });

    test('file kinds', () {
      expect(fileKindOf('image/jpeg', 'a.jpg'), FileKind.image);
      expect(fileKindOf('', 'a.pdf'), FileKind.pdf);
      expect(fileKindOf('application/zip', 'a'), FileKind.archive);
      expect(fileKindOf('', 'a.bin'), FileKind.other);
    });

    test('splits a data url', () {
      final parts = splitDataUrl('data:image/png;base64,AAAA');
      expect(parts?.mime, 'image/png');
      expect(parts?.base64, 'AAAA');
      expect(splitDataUrl('nope'), isNull);
    });
  });

  group('emoji', () {
    test('every group has emojis and none is repeated inside a group', () {
      for (final g in emojiGroups) {
        expect(g.emojis, isNotEmpty);
        expect(g.emojis.toSet().length, g.emojis.length, reason: g.name);
      }
    });

    test('the quick reactions are real emojis', () {
      expect(quickReactions.length, 6);
    });

    test('dropLastGrapheme removes a whole emoji', () {
      expect(dropLastGrapheme('hi'), 'h');
      expect(dropLastGrapheme(''), '');
      expect(dropLastGrapheme('a😀'), 'a');
      expect(dropLastGrapheme('a❤️'), 'a');
      expect(dropLastGrapheme('a👍🏽'), 'a');
      expect(dropLastGrapheme('a❤️\u200d🔥'), 'a');
    });
  });
}
