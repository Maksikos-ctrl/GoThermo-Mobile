import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../api/rpc_client.dart';
import '../models/message.dart';
import '../state/chat_controller.dart';
import '../theme.dart';
import '../util/mime.dart';
import '../util/time_format.dart';
import 'motion.dart';
import 'toast.dart';

/// A picture shared in the chat. Tap to see it full screen.
class ChatImage extends StatefulWidget {
  const ChatImage({super.key, required this.chat, required this.message});

  final ChatController chat;
  final Message message;

  @override
  State<ChatImage> createState() => _ChatImageState();
}

class _ChatImageState extends State<ChatImage> {
  late Future<Uint8List> _bytes = widget.chat.fileBytes(widget.message.fileId);

  void _retry() => setState(() => _bytes = widget.chat.fileBytes(widget.message.fileId));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snap) {
        if (snap.hasError) {
          return InkWell(
            onTap: _retry,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 220,
              height: 120,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Palette.bgTertiary,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Palette.border),
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh, color: Palette.textMuted),
                  SizedBox(height: 6),
                  Text('Tap to load again', style: TextStyle(color: Palette.textMuted, fontSize: 12)),
                ],
              ),
            ),
          );
        }
        final bytes = snap.data;
        if (bytes == null) return const Skeleton(width: 220, height: 150, radius: 12);
        final tag = 'img-${widget.message.stableKey}';
        return GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => ImageViewerScreen.memory(bytes, heroTag: tag)),
          ),
          child: Hero(
            tag: tag,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260, maxHeight: 300),
                child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A GIF in the chat (a Giphy link shown as the picture).
class GifView extends StatelessWidget {
  const GifView({super.key, required this.url, required this.heroTag});

  final String url;
  final String heroTag;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => ImageViewerScreen.network(url, heroTag: heroTag)),
      ),
      child: Hero(
        tag: heroTag,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260, maxHeight: 260),
            child: Image.network(
              url,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : const Skeleton(width: 220, height: 150, radius: 12),
              errorBuilder: (context, error, stack) => Container(
                width: 220,
                height: 80,
                alignment: Alignment.center,
                color: Palette.bgTertiary,
                child: const Text('GIF could not be loaded', style: TextStyle(color: Palette.textMuted)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

IconData _iconFor(FileKind kind) {
  switch (kind) {
    case FileKind.image:
      return Icons.image_outlined;
    case FileKind.pdf:
      return Icons.picture_as_pdf_outlined;
    case FileKind.audio:
      return Icons.audiotrack_outlined;
    case FileKind.video:
      return Icons.videocam_outlined;
    case FileKind.archive:
      return Icons.folder_zip_outlined;
    case FileKind.text:
      return Icons.description_outlined;
    case FileKind.other:
      return Icons.insert_drive_file_outlined;
  }
}

/// A file that is not a picture: name and size, tap to open or share it.
class FileChip extends StatefulWidget {
  const FileChip({super.key, required this.chat, required this.message});

  final ChatController chat;
  final Message message;

  @override
  State<FileChip> createState() => _FileChipState();
}

class _FileChipState extends State<FileChip> {
  bool _busy = false;

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    final m = widget.message;
    try {
      final bytes = await widget.chat.fileBytes(m.fileId);
      final dir = await getTemporaryDirectory();
      final name = (m.fileName.isEmpty ? 'file' : m.fileName).replaceAll(RegExp(r'[\\/]'), '_');
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path, mimeType: m.mimeType.isEmpty ? null : m.mimeType)]);
    } on RpcException catch (e) {
      if (mounted) showToast(context, e.message);
    } on Object {
      if (mounted) showToast(context, 'Could not open the file');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _open,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Palette.bgTertiary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Palette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Palette.accent.withAlpha(50),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_iconFor(fileKindOf(m.mimeType, m.fileName)), color: const Color(0xFFB4BBFF)),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.fileName.isEmpty ? 'File' : m.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(fileSize(m.fileSize), style: const TextStyle(color: Palette.textMuted, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.ios_share, size: 20, color: Palette.textMuted),
          ],
        ),
      ),
    );
  }
}

/// A picture on its own, full screen, pinch to zoom.
class ImageViewerScreen extends StatelessWidget {
  const ImageViewerScreen.memory(Uint8List this.bytes, {super.key, required this.heroTag}) : url = null;

  const ImageViewerScreen.network(String this.url, {super.key, required this.heroTag}) : bytes = null;

  final Uint8List? bytes;
  final String? url;
  final String heroTag;

  @override
  Widget build(BuildContext context) {
    final image = bytes != null
        ? Image.memory(bytes!, fit: BoxFit.contain)
        : Image.network(url!, fit: BoxFit.contain);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Hero(tag: heroTag, child: image),
        ),
      ),
    );
  }
}
