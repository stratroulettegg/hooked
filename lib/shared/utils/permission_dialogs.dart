import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/app_theme.dart';

/// Hilfsfunktionen für freundliches Permission-Error-Handling.
///
/// Wenn z.B. der ImagePicker eine `PlatformException` mit Code wie
/// `camera_access_denied` oder `photo_access_denied` wirft, zeigen wir
/// einen Dialog mit Erklärtext und einem Button, der direkt in die
/// System-Einstellungen führt.
class PermissionDialogs {
  const PermissionDialogs._();

  /// Öffnet die System-Einstellungen der App.
  static Future<bool> openSettings() => openAppSettings();

  /// Prüft ob ein PlatformException-Fehler ein Permission-Denied-Fehler ist.
  static bool isPermissionDenied(Object error) {
    if (error is! PlatformException) return false;
    final code = error.code.toLowerCase();
    return code.contains('denied') ||
        code.contains('permission') ||
        code.contains('access');
  }

  /// Mappt PlatformException-Code auf ein passendes Permission-Detail.
  static _PermDetail _detail(Object error) {
    if (error is PlatformException) {
      final code = error.code.toLowerCase();
      if (code.contains('camera')) {
        return const _PermDetail(
          title: 'Kamera-Zugriff erforderlich',
          message:
              'Hooked braucht Zugriff auf die Kamera, um Fotos von '
              'deinen Fängen zu machen. Du kannst den Zugriff in den '
              'Einstellungen aktivieren.',
          icon: Icons.photo_camera_outlined,
        );
      }
      if (code.contains('photo') ||
          code.contains('library') ||
          code.contains('gallery')) {
        return const _PermDetail(
          title: 'Foto-Zugriff erforderlich',
          message:
              'Hooked braucht Zugriff auf deine Mediathek, um Fotos '
              'auswählen zu können. Du kannst den Zugriff in den '
              'Einstellungen aktivieren.',
          icon: Icons.photo_library_outlined,
        );
      }
    }
    return const _PermDetail(
      title: 'Zugriff erforderlich',
      message:
          'Diese Aktion benötigt eine Berechtigung, die du nicht '
          'erteilt hast. Du kannst sie in den Einstellungen aktivieren.',
      icon: Icons.lock_outline,
    );
  }

  /// Zeigt einen freundlichen Dialog für einen Permission-Denied-Fehler.
  /// Der Benutzer kann direkt zu den App-Einstellungen springen.
  static Future<void> showPermissionDeniedDialog(
    BuildContext context,
    Object error,
  ) async {
    final detail = _detail(error);
    final c = ApexColors.of(context);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          icon: Icon(detail.icon, size: 48, color: ApexColors.primary),
          title: Text(
            detail.title,
            style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          content: Text(
            detail.message,
            style: TextStyle(color: c.textSecondary, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Abbrechen', style: TextStyle(color: c.textMuted)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: ApexColors.primary,
                foregroundColor: Colors.black,
              ),
              onPressed: () async {
                Navigator.of(ctx).pop();
                await openAppSettings();
              },
              child: const Text('Einstellungen öffnen'),
            ),
          ],
        );
      },
    );
  }
}

class _PermDetail {
  const _PermDetail({
    required this.title,
    required this.message,
    required this.icon,
  });
  final String title;
  final String message;
  final IconData icon;
}
