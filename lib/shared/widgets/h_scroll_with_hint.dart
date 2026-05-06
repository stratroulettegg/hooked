import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Horizontaler ScrollView mit Pfeil-Indikator.
/// Der Pfeil sitzt AUSSERHALB des ScrollView – Chips werden durch
/// ClipRect sauber abgeschnitten, kein Overlay nötig.
/// → wenn mehr Inhalt rechts, ← wenn am rechten Ende.
class HScrollWithHint extends StatefulWidget {
  const HScrollWithHint({
    super.key,
    required this.child,
    this.padding,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  State<HScrollWithHint> createState() => _HScrollWithHintState();
}

class _HScrollWithHintState extends State<HScrollWithHint> {
  final _controller = ScrollController();
  bool _atStart = true;
  bool _atEnd = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_controller.hasClients) _onScroll();
    });
  }

  void _onScroll() {
    final pos = _controller.position;
    final atStart = pos.pixels <= 0.5;
    final atEnd = pos.pixels >= pos.maxScrollExtent - 0.5;
    if (atStart != _atStart || atEnd != _atEnd) {
      setState(() {
        _atStart = atStart;
        _atEnd = atEnd;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final allVisible = _atStart && _atEnd;

    return Row(
      children: [
        Expanded(
          child: ClipRect(
            child: SingleChildScrollView(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              padding: widget.padding,
              child: widget.child,
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          child: allVisible
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(
                    _atEnd ? Icons.chevron_left : Icons.chevron_right,
                    size: 16,
                    color: c.textMuted,
                  ),
                ),
        ),
      ],
    );
  }
}
