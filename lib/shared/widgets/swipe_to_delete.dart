import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';

/// Wickelt einen Listeneintrag in einen Swipe-to-Delete (von rechts nach links).
///
/// Während des Wischens werden die rechten Ecken des Kindes "gerade gezogen",
/// damit der enthüllte rote Hintergrund nahtlos an die Kachel anschließt
/// (keine Lücken oben/unten durch die Kartenrundung).
class SwipeToDelete extends StatefulWidget {
  const SwipeToDelete({
    super.key,
    required this.dismissKey,
    required this.onDelete,
    required this.child,
    this.confirmTitle = 'Löschen?',
    this.confirmMessage = 'Dieser Eintrag wird unwiderruflich gelöscht.',
    this.borderRadius = 16,
  });

  final Key dismissKey;
  final Future<void> Function() onDelete;
  final Widget child;
  final String confirmTitle;
  final String confirmMessage;
  final double borderRadius;

  @override
  State<SwipeToDelete> createState() => _SwipeToDeleteState();
}

class _SwipeToDeleteState extends State<SwipeToDelete> {
  bool _swiping = false;

  @override
  Widget build(BuildContext context) {
    final r = Radius.circular(widget.borderRadius);
    // Während des Wischens: rechte Ecken auf 0 → bündiger Übergang zum Rot.
    // Im Ruhezustand: rundherum gerundet (Original-Look der Kachel bleibt).
    final clipShape = _swiping
        ? BorderRadius.only(topLeft: r, bottomLeft: r)
        : BorderRadius.all(r);

    return Dismissible(
      key: widget.dismissKey,
      direction: DismissDirection.endToStart,
      dismissThresholds: const {DismissDirection.endToStart: 0.45},
      onUpdate: (d) {
        final swiping = d.progress > 0.001;
        if (swiping != _swiping) {
          setState(() => _swiping = swiping);
        }
      },
      background: Container(
        decoration: BoxDecoration(
          color: ApexColors.strike.withAlpha(40),
          // Rechts gerundet wie die Kachel; links eckig (wird von Kachel verdeckt).
          borderRadius: BorderRadius.only(topRight: r, bottomRight: r),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, color: ApexColors.strike, size: 26),
            SizedBox(width: 10),
            Text(
              'LÖSCHEN',
              style: TextStyle(
                fontFamily: 'Rajdhani',
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: ApexColors.strike,
              ),
            ),
          ],
        ),
      ),
      confirmDismiss: (_) async {
        HapticFeedback.mediumImpact();
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(widget.confirmTitle),
            content: Text(widget.confirmMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Abbrechen'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: ApexColors.strike),
                child: const Text('Löschen'),
              ),
            ],
          ),
        );
        return confirmed ?? false;
      },
      onDismissed: (_) async {
        await widget.onDelete();
      },
      child: ClipRRect(borderRadius: clipShape, child: widget.child),
    );
  }
}
