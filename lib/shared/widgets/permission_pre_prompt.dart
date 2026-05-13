import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';

/// Welche Permission das Sheet erklärt.
enum PermissionKind { photos, camera, location, notifications, microphone }

class _PermissionCopy {
  const _PermissionCopy({
    required this.icon,
    required this.title,
    required this.body,
    required this.cta,
  });
  final IconData icon;
  final String title;
  final String body;
  final String cta;
}

const Map<PermissionKind, _PermissionCopy> _copy = {
  PermissionKind.photos: _PermissionCopy(
    icon: Icons.photo_library_outlined,
    title: 'Foto aus deiner Galerie',
    body:
        'Hooked öffnet gleich die Foto-Auswahl. Wir laden nur das Bild hoch, das du selbst aussuchst — keinen Zugriff auf den Rest deiner Galerie.',
    cta: 'Galerie öffnen',
  ),
  PermissionKind.camera: _PermissionCopy(
    icon: Icons.photo_camera_outlined,
    title: 'Foto aufnehmen',
    body:
        'Für Fotos direkt aus der App brauchen wir Kamera-Zugriff. Das Foto landet nur in deinem Fang — nirgendwo sonst.',
    cta: 'Kamera öffnen',
  ),
  PermissionKind.location: _PermissionCopy(
    icon: Icons.my_location_rounded,
    title: 'Aktueller Standort',
    body:
        'Damit wir deinen aktuellen Spot auf der Karte zeigen oder Wetter & Beißzeit für dich berechnen können, brauchen wir deinen Standort. Du kannst die Genauigkeit jederzeit in den iOS-Einstellungen anpassen.',
    cta: 'Standort freigeben',
  ),
  PermissionKind.notifications: _PermissionCopy(
    icon: Icons.notifications_active_outlined,
    title: 'Push-Benachrichtigungen',
    body:
        'Wir melden uns nur bei wirklich relevanten Dingen: neue Beiträge von Anglern, denen du folgst, sowie Antworten auf deine Fänge. Kein Spam, versprochen.',
    cta: 'Aktivieren',
  ),
  PermissionKind.microphone: _PermissionCopy(
    icon: Icons.mic_none_rounded,
    title: 'Sprachnotiz',
    body:
        'Für Voice-Quick-Add brauchen wir kurz Mikrofon-Zugriff. Audio wird lokal verarbeitet und nicht hochgeladen.',
    cta: 'Mikrofon nutzen',
  ),
};

/// Zeigt einmal pro Permission-Kind ein freundliches Erklär-Sheet,
/// bevor das native iOS/Android-Dialog erscheint. Gibt `true` zurück,
/// wenn der User „weiter" tippt (oder das Sheet bereits gesehen wurde),
/// `false` bei explizitem Abbruch.
class PermissionPrePrompt {
  PermissionPrePrompt._();

  static String _seenKey(PermissionKind k) => 'perm_preprompt_seen_${k.name}';

  /// Liefert true, wenn weitergemacht werden soll (User hat bestätigt
  /// oder das Sheet wurde schon einmal gesehen).
  static Future<bool> ensure(
    BuildContext context,
    PermissionKind kind, {
    bool force = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (!force && (prefs.getBool(_seenKey(kind)) ?? false)) {
      return true;
    }
    if (!context.mounted) return false;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PrePromptSheet(kind: kind),
    );
    if (ok == true) {
      await prefs.setBool(_seenKey(kind), true);
      return true;
    }
    return false;
  }
}

class _PrePromptSheet extends StatelessWidget {
  const _PrePromptSheet({required this.kind});
  final PermissionKind kind;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final copy = _copy[kind]!;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.border),
        ),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: c.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: ApexColors.primary.withAlpha(30),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: ApexColors.primary.withAlpha(80),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(copy.icon, color: ApexColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    copy.title,
                    style: TextStyle(
                      fontFamily: 'Rajdhani',
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              copy.body,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: c.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
              ),
              child: Text(copy.cta),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Nicht jetzt',
                style: TextStyle(color: c.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
