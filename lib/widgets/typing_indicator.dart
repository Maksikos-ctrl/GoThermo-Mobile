import 'package:flutter/material.dart';

import '../state/typing_label.dart';
import '../theme.dart';

/// "Anna is typing…" with three bouncing dots. It always keeps its height so
/// the chat does not jump when someone starts or stops typing.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key, required this.names});

  final List<String> names;

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _wave;

  @override
  void initState() {
    super.initState();
    _wave = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
    if (widget.names.isNotEmpty) _wave.repeat();
  }

  @override
  void didUpdateWidget(TypingIndicator old) {
    super.didUpdateWidget(old);
    if (widget.names.isNotEmpty && !_wave.isAnimating) {
      _wave.repeat();
    } else if (widget.names.isEmpty && _wave.isAnimating) {
      _wave.stop();
    }
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  double _lift(int i) {
    // Each dot is a little behind the one before it.
    final t = (_wave.value - i * 0.15) % 1.0;
    return t < 0.4 ? -(1 - (t / 0.2 - 1).abs()) * 4 : 0;
  }

  @override
  Widget build(BuildContext context) {
    final label = typingLabel(widget.names);
    return SizedBox(
      key: const ValueKey<String>('typing'),
      height: 24,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: label.isEmpty ? 0 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              AnimatedBuilder(
                animation: _wave,
                builder: (context, _) => Row(
                  children: [
                    for (var i = 0; i < 3; i++)
                      Transform.translate(
                        offset: Offset(0, _lift(i)),
                        child: Container(
                          width: 5,
                          height: 5,
                          margin: const EdgeInsets.only(right: 3),
                          decoration: BoxDecoration(color: Palette.textMuted, shape: BoxShape.circle),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Palette.textMuted, fontStyle: FontStyle.italic),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
