import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';

enum MapProvider { apple, google }

/// Öffnet Apple- oder Google-Maps für einen Standort.
class ExternalMapLauncher {
  ExternalMapLauncher._();

  /// Zeigt ein Bottom-Sheet mit Auswahl Apple/Google und öffnet die gewählte App.
  /// Auf Android gibt es keine Auswahl — dort wird direkt Google Maps geöffnet.
  static Future<void> choose(
    BuildContext context, {
    required double lat,
    required double lng,
    String? label,
  }) async {
    if (Platform.isAndroid) {
      final ok = await openGoogleMaps(lat: lat, lng: lng, label: label);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Karten-App konnte nicht geöffnet werden.')),
        );
      }
      return;
    }

    final provider = await showModalBottomSheet<MapProvider>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _MapChooserSheet(),
    );
    if (provider == null) return;

    final ok = switch (provider) {
      MapProvider.apple => await openAppleMaps(lat: lat, lng: lng, label: label),
      MapProvider.google => await openGoogleMaps(lat: lat, lng: lng, label: label),
    };
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Karten-App konnte nicht geöffnet werden.')),
      );
    }
  }

  /// Öffnet Apple Maps (iOS) bzw. fällt auf Google Web zurück.
  static Future<bool> openAppleMaps({
    required double lat,
    required double lng,
    String? label,
  }) async {
    final q = label == null ? '' : '&q=${Uri.encodeComponent(label)}';
    return _tryUrls([
      Uri.parse('https://maps.apple.com/?ll=$lat,$lng$q'),
      Uri.parse('maps://?ll=$lat,$lng$q'),
    ]);
  }

  /// Öffnet Google Maps:
  /// 1. native App via `comgooglemaps://` (iOS) bzw. `geo:` (Android)
  /// 2. Universal-Link `https://www.google.com/maps/search/?api=1&query=...`
  static Future<bool> openGoogleMaps({
    required double lat,
    required double lng,
    String? label,
  }) async {
    final labelEnc = label == null ? null : Uri.encodeComponent(label);
    final urls = <Uri>[
      if (Platform.isIOS)
        Uri.parse('comgooglemaps://?q=$lat,$lng&center=$lat,$lng&zoom=14'),
      if (Platform.isAndroid)
        Uri.parse(
          'geo:$lat,$lng?q=$lat,$lng'
          '${labelEnc != null ? '($labelEnc)' : ''}',
        ),
      // Universal-Link: öffnet auf iOS/Android die Google-Maps-App direkt,
      // sofern installiert, sonst Browser.
      Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'),
    ];
    return _tryUrls(urls);
  }

  static Future<bool> _tryUrls(List<Uri> urls) async {
    for (final url in urls) {
      try {
        final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
        if (kDebugMode) {
          debugPrint('[ExternalMapLauncher] $url → launched=$ok');
        }
        if (ok) return true;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[ExternalMapLauncher] $url failed: $e');
        }
      }
    }
    return false;
  }
}

class _MapChooserSheet extends StatelessWidget {
  const _MapChooserSheet();

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'IN KARTEN-APP ÖFFNEN',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: c.textMuted,
                ),
              ),
            ),
            _ChooserTile(
              icon: Icons.map_outlined,
              title: 'Apple Karten',
              onTap: () => Navigator.pop(context, MapProvider.apple),
            ),
            const SizedBox(height: 8),
            _ChooserTile(
              icon: Icons.public,
              title: 'Google Maps',
              onTap: () => Navigator.pop(context, MapProvider.google),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChooserTile extends StatelessWidget {
  const _ChooserTile({required this.icon, required this.title, required this.onTap});
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Material(
      color: c.surfaceVariant,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: ApexColors.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: c.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
