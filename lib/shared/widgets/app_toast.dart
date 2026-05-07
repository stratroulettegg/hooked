import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Overlay-basierter Toast.
///
/// Im Gegensatz zu `ScaffoldMessenger.showSnackBar` hängt dieser Toast nicht
/// am `Scaffold`, sondern am Root-Overlay — der `floatingActionButton` wird
/// dadurch **nicht** mitgeschoben. Ideal für die Shell mit Plus-Button.
///
/// Verwendung:
/// ```dart
/// AppToast.show(context, 'Account gelöscht.');
/// AppToast.error(context, 'Speichern fehlgeschlagen', code: 'unknown');
/// ```
class AppToast {
  AppToast._();

  static OverlayEntry? _current;
  static Timer? _timer;

  /// Zeigt einen neutralen Toast (am unteren Bildschirmrand).
  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    IconData? icon,
    Color? accent,
  }) {
    _showInternal(
      context,
      message: message,
      duration: duration,
      icon: icon,
      accent: accent,
    );
  }

  /// Erfolgs-Toast (grün, Haken).
  static void success(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    _showInternal(
      context,
      message: message,
      duration: duration,
      icon: Icons.check_circle_rounded,
      accent: const Color(0xFF00D4AA),
    );
  }

  /// Fehler-Toast (orange/rot). Optional `code` wird klein in Klammern
  /// angehängt — hilft beim Debuggen ohne den User zu erschlagen.
  static void error(
    BuildContext context,
    String message, {
    String? code,
    Duration duration = const Duration(seconds: 5),
  }) {
    final text = code != null && code.isNotEmpty ? '$message ($code)' : message;
    _showInternal(
      context,
      message: text,
      duration: duration,
      icon: Icons.error_outline_rounded,
      accent: const Color(0xFFFF6B35),
    );
  }

  static void _showInternal(
    BuildContext context, {
    required String message,
    required Duration duration,
    IconData? icon,
    Color? accent,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    // Vorherigen Toast sofort entfernen, damit sich nichts staut.
    _dismiss();

    final entry = OverlayEntry(
      builder: (ctx) => _ToastWidget(
        message: message,
        duration: duration,
        icon: icon,
        accent: accent,
        onDismiss: _dismiss,
      ),
    );
    _current = entry;
    overlay.insert(entry);

    _timer = Timer(duration + const Duration(milliseconds: 320), _dismiss);
  }

  static void _dismiss() {
    _timer?.cancel();
    _timer = null;
    _current?.remove();
    _current = null;
  }
}

class _ToastWidget extends StatefulWidget {
  const _ToastWidget({
    required this.message,
    required this.duration,
    required this.onDismiss,
    this.icon,
    this.accent,
  });

  final String message;
  final Duration duration;
  final VoidCallback onDismiss;
  final IconData? icon;
  final Color? accent;

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.6),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    Future.delayed(widget.duration, () {
      if (!mounted) return;
      _ctrl.reverse();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final mq = MediaQuery.of(context);
    final accent = widget.accent ?? c.textPrimary;

    return Positioned(
      left: 16,
      right: 16,
      bottom: mq.padding.bottom + 24,
      child: SafeArea(
        top: false,
        child: IgnorePointer(
          ignoring: false,
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: Material(
                color: Colors.transparent,
                child: GestureDetector(
                  onTap: widget.onDismiss,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: c.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        if (widget.icon != null) ...[
                          Icon(widget.icon, color: accent, size: 22),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Text(
                            widget.message,
                            style: TextStyle(
                              color: c.textPrimary,
                              fontFamily: 'Rajdhani',
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
