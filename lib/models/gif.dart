import 'json.dart';

/// One GIF search result: a small preview and the link that gets posted.
class Gif {
  const Gif({required this.id, required this.title, required this.url, required this.preview});

  final String id;
  final String title;
  final String url;
  final String preview;

  factory Gif.fromJson(Map<String, dynamic> j) => Gif(
        id: str(j['id']),
        title: str(j['title']),
        url: str(j['url']),
        preview: str(j['preview']),
      );
}
