import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Vollbild-Overlay-Animation für den Doppel-Tap auf einen Feed-Post.
///
/// `progress` läuft von 0..1 — extern getrieben durch einen
/// `AnimationController`. `isLike: true` → rotes Herz mit Funken steigt
/// nach oben, `isLike: false` → gebrochenes Herz fällt.
class LikeBurst extends StatelessWidget {
  const LikeBurst({super.key, required this.progress, required this.isLike});

  final double progress; // 0..1
  final bool isLike;

  static const _color = ApexColors.scoreLow; // Rot
  static const _shadows = [
    Shadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 6)),
  ];

  @override
  Widget build(BuildContext context) {
    final v = progress.clamp(0.0, 1.0);
    return Stack(
      fit: StackFit.expand,
      children: [
        // Hauptherz.
        Center(child: _mainHeart(v)),
        // Funken nur beim Like.
        if (isLike) ..._sparks(v),
      ],
    );
  }

  Widget _mainHeart(double v) {
    if (isLike) {
      // Pop-in (0–0.25), Wobble (0.25–0.55), Drift+Fade (0.55–1).
      final popT = (v / 0.25).clamp(0.0, 1.0);
      final pop = Curves.easeOutBack.transform(popT);
      final wobble = v > 0.25 && v < 0.6
          ? math.sin((v - 0.25) * 18) * 0.06
          : 0.0;
      final scale = pop + wobble;
      final driftY = v > 0.55 ? -((v - 0.55) / 0.45) * 70 : 0.0;
      final opacity = v < 0.7 ? 1.0 : (1.0 - (v - 0.7) / 0.3);
      return Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, driftY),
          child: Transform.scale(
            scale: scale,
            child: const Icon(
              Icons.favorite,
              size: 150,
              color: _color,
              shadows: _shadows,
            ),
          ),
        ),
      );
    }
    // Unlike: gebrochenes Herz fällt + rotiert.
    final popT = (v / 0.2).clamp(0.0, 1.0);
    final pop = Curves.easeOutBack.transform(popT);
    final fall = v > 0.3 ? Curves.easeIn.transform((v - 0.3) / 0.7) * 90 : 0.0;
    final rot = v > 0.3 ? (v - 0.3) * 0.8 : 0.0;
    final opacity = v < 0.6 ? 1.0 : (1.0 - (v - 0.6) / 0.4);
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, fall),
        child: Transform.rotate(
          angle: rot,
          child: Transform.scale(
            scale: pop,
            child: const Icon(
              Icons.heart_broken_rounded,
              size: 130,
              color: Colors.white70,
              shadows: _shadows,
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _sparks(double v) {
    if (v < 0.05) return const [];
    const count = 8;
    final t = ((v - 0.05) / 0.95).clamp(0.0, 1.0);
    final widgets = <Widget>[];
    for (var i = 0; i < count; i++) {
      final angle = (i / count) * math.pi * 2 - math.pi / 2;
      // Funken steigen leicht (negativ y dominiert) und fächern sich auf.
      final radius = 110.0 * Curves.easeOutCubic.transform(t);
      final dx = math.cos(angle) * radius;
      final dy = math.sin(angle) * radius - 30 * t; // zus. Drift nach oben
      final scale = (1.0 - t) * 0.9 + 0.1;
      final opacity = (1.0 - t).clamp(0.0, 1.0);
      final rot = t * (i.isEven ? 2 : -2);
      widgets.add(Positioned.fill(
        child: Center(
          child: Transform.translate(
            offset: Offset(dx, dy),
            child: Opacity(
              opacity: opacity,
              child: Transform.rotate(
                angle: rot,
                child: Transform.scale(
                  scale: scale,
                  child: const Icon(
                    Icons.favorite,
                    size: 36,
                    color: _color,
                    shadows: [
                      Shadow(
                        color: Colors.black54,
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
    }
    return widgets;
  }
}
