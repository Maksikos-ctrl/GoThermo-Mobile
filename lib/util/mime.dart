const _byExtension = <String, String>{
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'pdf': 'application/pdf',
  'txt': 'text/plain',
  'md': 'text/markdown',
  'csv': 'text/csv',
  'json': 'application/json',
  'zip': 'application/zip',
  'mp3': 'audio/mpeg',
  'wav': 'audio/wav',
  'm4a': 'audio/mp4',
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  'doc': 'application/msword',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
};

/// The media type to tell the server for a file, from its name.
String mimeFromName(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return 'application/octet-stream';
  return _byExtension[name.substring(dot + 1).toLowerCase()] ?? 'application/octet-stream';
}

/// Which icon family a file gets in the list.
enum FileKind { image, pdf, audio, video, archive, text, other }

FileKind fileKindOf(String mime, String name) {
  final m = mime.isNotEmpty ? mime : mimeFromName(name);
  if (m.startsWith('image/')) return FileKind.image;
  if (m == 'application/pdf') return FileKind.pdf;
  if (m.startsWith('audio/')) return FileKind.audio;
  if (m.startsWith('video/')) return FileKind.video;
  if (m == 'application/zip') return FileKind.archive;
  if (m.startsWith('text/') || m == 'application/json') return FileKind.text;
  return FileKind.other;
}

/// Decodes a `data:<mime>;base64,<data>` URL into its parts, or null.
({String mime, String base64})? splitDataUrl(String dataUrl) {
  if (!dataUrl.startsWith('data:')) return null;
  final comma = dataUrl.indexOf(',');
  if (comma < 0) return null;
  final head = dataUrl.substring(5, comma);
  final semi = head.indexOf(';');
  final mime = semi < 0 ? head : head.substring(0, semi);
  return (mime: mime.isEmpty ? 'application/octet-stream' : mime, base64: dataUrl.substring(comma + 1));
}
