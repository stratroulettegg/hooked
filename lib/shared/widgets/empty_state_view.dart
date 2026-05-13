import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Einheitlicher Empty-State für alle Tabs (Fänge, Spots, Trips, Feed).
///
/// Layout: zentriertes Icon (64px, textMuted), Headline (Rajdhani 20/700),
/// Beschreibung (13/secondary), primärer FilledButton.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.ctaLabel,
    required this.ctaIcon,
    required this.onCta,
  });

  final IconData icon;
  final String title;
  final String description;
  final String ctaLabel;
  final IconData ctaIcon;
  final VoidCallback onCta;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: c.textMuted),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Rajdhani',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: c.textSecondary),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onCta,
              icon: Icon(ctaIcon),
              label: Text(ctaLabel),
            ),
          ],
        ),
      ),
    );
  }
}
