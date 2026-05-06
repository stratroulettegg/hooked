import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../../features/catches/ai/ai_quick_add_sheet.dart';
import '../../features/catches/voice/voice_quick_add_sheet.dart';
import '../widgets/quick_add_sheet.dart';

/// Der zentrale Plus-FAB mit Satelliten-Menü (Liste + Mikro).
/// Wird im Haupt-Router UND auf allen Secondary-Screens verwendet,
/// damit der Footer überall identisch aussieht.
class AppQuickAddFab extends StatefulWidget {
  const AppQuickAddFab({super.key});

  @override
  State<AppQuickAddFab> createState() => _AppQuickAddFabState();
}

class _AppQuickAddFabState extends State<AppQuickAddFab>
    with SingleTickerProviderStateMixin {
  static const double _fabSize = 64;
  static const double _satRadius = 96;
  static const double _satSize = 64;

  final GlobalKey _fabKey = GlobalKey();
  late final AnimationController _ctrl;
  OverlayEntry? _entry;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _entry?.remove();
    _entry = null;
    _ctrl.dispose();
    super.dispose();
  }

  bool get _isOpen => _entry != null;

  void _toggle() {
    if (_isOpen) {
      _close();
    } else {
      _open();
    }
  }

  void _open() {
    final fabCtx = _fabKey.currentContext;
    if (fabCtx == null) return;
    final box = fabCtx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final anchor = box.localToGlobal(
        Offset(box.size.width / 2, box.size.height / 2));
    HapticFeedback.lightImpact();
    _entry = OverlayEntry(
      builder: (_) => _FabFanOverlay(
        animation: _ctrl,
        anchor: anchor,
        satRadius: _satRadius,
        satSize: _satSize,
        onScrimTap: _close,
        onListTap: () async {
          await _closeAnimated();
          if (mounted) QuickAddSheet.show(context);
        },
        onMicTap: () async {
          await _closeAnimated();
          if (mounted) VoiceQuickAddSheet.show(context);
        },
        onAiTap: () async {
          await _closeAnimated();
          if (mounted) AiQuickAddSheet.show(context);
        },
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_entry!);
    _ctrl.forward(from: 0);
    setState(() {});
  }

  Future<void> _closeAnimated() async {
    if (_entry == null) return;
    try {
      await _ctrl.reverse();
    } catch (_) {}
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() {});
  }

  void _close() {
    unawaited(_closeAnimated());
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: _fabKey,
      width: _fabSize,
      height: _fabSize,
      child: Material(
        color: ApexColors.primary,
        shape: const CircleBorder(),
        elevation: 6,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _toggle,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => Center(
              child: Transform.rotate(
                angle: _ctrl.value * math.pi * 0.75,
                child: const Icon(Icons.add, size: 32, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FabFanOverlay extends StatelessWidget {
  const _FabFanOverlay({
    required this.animation,
    required this.anchor,
    required this.satRadius,
    required this.satSize,
    required this.onScrimTap,
    required this.onListTap,
    required this.onMicTap,
    required this.onAiTap,
  });

  final Animation<double> animation;
  final Offset anchor;
  final double satRadius;
  final double satSize;
  final VoidCallback onScrimTap;
  final VoidCallback onListTap;
  final VoidCallback onMicTap;
  final VoidCallback onAiTap;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t =
            Curves.easeOutBack.transform(animation.value.clamp(0.0, 1.0));
        final scrimAlpha =
            (animation.value * 130).clamp(0.0, 130.0).toInt();
        // Drei Positionen: links (135°), mitte (90° = direkt oben), rechts (45°)
        final dxDiag = math.cos(math.pi / 4) * satRadius * t;
        final dyDiag = math.sin(math.pi / 4) * satRadius * t;
        final leftPos  = Offset(anchor.dx - dxDiag, anchor.dy - dyDiag);
        final centerPos = Offset(anchor.dx, anchor.dy - satRadius * t);
        final rightPos = Offset(anchor.dx + dxDiag, anchor.dy - dyDiag);
        return SizedBox(
          width: media.size.width,
          height: media.size.height,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onScrimTap,
                  child:
                      Container(color: Colors.black.withAlpha(scrimAlpha)),
                ),
              ),
              _FabSatellite(
                center: leftPos,
                size: satSize,
                scale: t.clamp(0.0, 1.0),
                opacity: animation.value.clamp(0.0, 1.0),
                icon: Icons.list_alt,
                background: ApexColors.primary,
                foreground: Colors.white,
                onTap: onListTap,
              ),
              _FabSatellite(
                center: centerPos,
                size: satSize,
                scale: t.clamp(0.0, 1.0),
                opacity: animation.value.clamp(0.0, 1.0),
                icon: Icons.auto_awesome,
                background: ApexColors.strike,
                foreground: Colors.white,
                onTap: onAiTap,
              ),
              _FabSatellite(
                center: rightPos,
                size: satSize,
                scale: t.clamp(0.0, 1.0),
                opacity: animation.value.clamp(0.0, 1.0),
                icon: Icons.mic,
                background: ApexColors.primary,
                foreground: Colors.white,
                onTap: onMicTap,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FabSatellite extends StatelessWidget {
  const _FabSatellite({
    required this.center,
    required this.size,
    required this.scale,
    required this.opacity,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final Offset center;
  final double size;
  final double scale;
  final double opacity;
  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final left = center.dx - size / 2;
    final top = center.dy - size / 2;
    return Positioned(
      left: left,
      top: top,
      width: size,
      height: size,
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale,
          child: Material(
            color: background,
            shape: const CircleBorder(),
            elevation: 8,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Center(
                child: Icon(icon, color: foreground, size: 30),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
