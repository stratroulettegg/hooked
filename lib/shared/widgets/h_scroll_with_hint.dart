import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Horizontaler ScrollView mit Pfeil-Indikator am Rand.
/// → wenn mehr Inhalt rechts, ← wenn am rechten Ende angekommen.
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
    // Wenn Inhalt komplett sichtbar (atStart & atEnd), kein Hinweis nötig
    final showRight = !_atEnd;
    final showLeft = !_atStart;

    return Stack(
      children: [
        SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          padding: widget.padding,
          child: widget.child,
        ),
        // Rechts: → (noch mehr) oder ← (Ende erreicht)
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          child: IgnorePointer(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: (showRight || _atEnd) && !(_atStart && _atEnd) ? 1.0 : 0.0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          c.surface.withAlpha(0),
                          c.surface,
                        ],
                      ),
                    ),
                  ),
                  Container(
                    color: c.surface,
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      _atEnd ? Icons.chevron_left : Icons.chevron_right,
                      size: 16,
                      color: c.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Links: ← (zurückscrollen möglich)
        if (showLeft && !_atEnd)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: showLeft ? 1.0 : 0.0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      color: c.surface,
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.chevron_left,
                        size: 16,
                        color: c.textMuted,
                      ),
                    ),
                    Container(
                      width: 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            c.surface,
                            c.surface.withAlpha(0),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
