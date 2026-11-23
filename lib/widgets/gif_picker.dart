import 'dart:async';

import 'package:flutter/material.dart';

import '../api/rpc_client.dart';
import '../models/gif.dart';
import '../state/chat_controller.dart';
import '../theme.dart';
import 'motion.dart';

/// Opens the GIF search; resolves with the link of the chosen GIF.
Future<String?> showGifPicker(BuildContext context, ChatController chat) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => GifPicker(chat: chat),
  );
}

class GifPicker extends StatefulWidget {
  const GifPicker({super.key, required this.chat});

  final ChatController chat;

  @override
  State<GifPicker> createState() => _GifPickerState();
}

class _GifPickerState extends State<GifPicker> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<Gif> _gifs = const [];
  bool _loading = true;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(text.trim()));
  }

  Future<void> _search(String q) async {
    final mine = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final found = await widget.chat.api.searchGifs(widget.chat.token, q);
      if (!mounted || mine != _request) return;
      setState(() {
        _gifs = found;
        _loading = false;
      });
    } on RpcException catch (e) {
      if (!mounted || mine != _request) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.72;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                key: const Key('gif-search'),
                controller: _query,
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Search GIFs',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
              ),
            ),
            Expanded(child: _results()),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('Powered by GIPHY', style: TextStyle(color: Palette.textMuted, fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _results() {
    if (_loading) {
      return GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.all(12),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [for (var i = 0; i < 8; i++) const Skeleton(height: 120, radius: 12)],
      );
    }
    if (_error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)));
    }
    if (_gifs.isEmpty) {
      return Center(child: Text('Nothing found', style: TextStyle(color: Palette.textMuted)));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.25,
      ),
      itemCount: _gifs.length,
      itemBuilder: (context, i) {
        final g = _gifs[i];
        return PopIn(
          rise: 8,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.pop(context, g.url),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                g.preview.isEmpty ? g.url : g.preview,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : const Skeleton(height: 120, radius: 12),
                errorBuilder: (context, error, stack) => ColoredBox(
                  color: Palette.bgTertiary,
                  child: Center(child: Icon(Icons.broken_image_outlined, color: Palette.textMuted)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
