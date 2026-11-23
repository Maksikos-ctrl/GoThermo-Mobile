import 'package:flutter/material.dart';

import '../theme.dart';
import '../util/emoji_data.dart';

/// The emoji grid with its category tabs.
class EmojiPanel extends StatefulWidget {
  const EmojiPanel({super.key, required this.onPick, this.onBackspace});

  final ValueChanged<String> onPick;

  /// When given, a backspace button is shown (used under the message box).
  final VoidCallback? onBackspace;

  @override
  State<EmojiPanel> createState() => _EmojiPanelState();
}

class _EmojiPanelState extends State<EmojiPanel> {
  int _group = 0;

  @override
  Widget build(BuildContext context) {
    final group = emojiGroups[_group];
    return Column(
      children: [
        SizedBox(
          height: 46,
          child: Row(
            children: [
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  itemCount: emojiGroups.length,
                  itemBuilder: (context, i) {
                    final selected = i == _group;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => setState(() => _group = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected ? Palette.accent.withAlpha(60) : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(emojiGroups[i].icon, style: const TextStyle(fontSize: 20)),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (widget.onBackspace != null)
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.backspace_outlined, size: 20),
                  onPressed: widget.onBackspace,
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: GridView.builder(
              key: ValueKey<int>(_group),
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 46),
              itemCount: group.emojis.length,
              itemBuilder: (context, i) {
                final e = group.emojis[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => widget.onPick(e),
                  child: Center(child: Text(e, style: const TextStyle(fontSize: 26))),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// A sheet with the emoji panel; resolves with the chosen emoji.
Future<String?> showEmojiSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SizedBox(
      height: MediaQuery.sizeOf(sheetContext).height * 0.55,
      child: EmojiPanel(onPick: (e) => Navigator.pop(sheetContext, e)),
    ),
  );
}
