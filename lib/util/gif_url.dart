/// A message that is nothing but a Giphy media link is shown as the picture.
/// Only https links on giphy.com hosts ever become an image. The same rule as
/// the web and desktop apps.
String? gifUrlOf(String text) {
  final t = text.trim();
  if (t.isEmpty || t.length > 400 || RegExp(r'\s').hasMatch(t)) return null;
  final uri = Uri.tryParse(t);
  if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) return null;
  final host = uri.host.toLowerCase();
  if (!(host == 'giphy.com' || host.endsWith('.giphy.com'))) return null;
  if (!RegExp(r'\.(gif|webp)$', caseSensitive: false).hasMatch(uri.path)) return null;
  return uri.toString();
}
