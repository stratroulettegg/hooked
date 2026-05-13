import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Cached App-Pfade. iOS- & macOS-Sandbox-Pfade ändern sich bei jedem Build/
/// Reinstall, daher dürfen NUR relative Dateinamen persistiert werden.
class AppPaths {
  AppPaths._();

  static String? _docsPath;
  static String? _photosPath;
  static String? _activeUid;

  /// Muss einmal in `main()` vor `runApp` aufgerufen werden.
  ///
  /// Setzt nur den Documents-Pfad und stellt sicher, dass der gemeinsame
  /// `<docs>/photos`-Ordner existiert (Legacy-Container für die UID-
  /// Unterordner). Der eigentliche User-Photos-Pfad wird in
  /// [activateForUid] aktiviert, sobald die Firebase-UID feststeht.
  static Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _docsPath = dir.path;
    final photoDir = Directory(p.join(dir.path, 'photos'));
    if (!await photoDir.exists()) {
      await photoDir.create(recursive: true);
    }
    // Fallback bis [activateForUid] gerufen wurde — verhindert NPE in
    // Code-Pfaden, die zu früh auf [photos] zugreifen.
    _photosPath = photoDir.path;
  }

  /// Schaltet den Photos-Ordner auf einen UID-spezifischen Unterordner
  /// `<docs>/photos/<uid>` um. Idempotent.
  ///
  /// Migration: Wenn beim ersten Aktivieren noch lose Dateien direkt unter
  /// `<docs>/photos/` liegen (Legacy aus der Pre-Multi-User-Zeit), werden
  /// sie einmalig in den UID-Ordner verschoben.
  static Future<void> activateForUid(String uid) async {
    if (_docsPath == null) {
      throw StateError('AppPaths.init() must run before activateForUid().');
    }
    if (_activeUid == uid && _photosPath != null) return;
    final base = Directory(p.join(_docsPath!, 'photos'));
    if (!await base.exists()) {
      await base.create(recursive: true);
    }
    final userDir = Directory(p.join(base.path, uid));
    if (!await userDir.exists()) {
      await userDir.create(recursive: true);
    }
    // Legacy-Dateien direkt unter <docs>/photos/ in den UID-Ordner ziehen.
    // Nur einmalig: sobald keine losen Dateien mehr da sind, NoOp.
    try {
      await for (final ent in base.list(followLinks: false)) {
        if (ent is File) {
          final dest = File(p.join(userDir.path, p.basename(ent.path)));
          if (!await dest.exists()) {
            try {
              await ent.rename(dest.path);
            } catch (_) {
              // Cross-device / Permission → kopieren statt verschieben.
              await ent.copy(dest.path);
              try {
                await ent.delete();
              } catch (_) {}
            }
          }
        }
      }
    } catch (_) {
      // Verzeichnislisting darf den Bootstrap nicht killen.
    }
    _photosPath = userDir.path;
    _activeUid = uid;
  }

  /// Aktiver Foto-User (Debug/Telemetry).
  static String? get activeUid => _activeUid;

  /// Aktueller Documents-Ordner. Nicht persistieren!
  static String get docs => _docsPath!;

  /// Aktueller Photos-Ordner unter `<docs>/photos/<uid>`.
  static String get photos => _photosPath!;

  /// Wandelt einen gespeicherten Foto-Bezeichner in einen aktuell gültigen
  /// absoluten Pfad. Akzeptiert sowohl reine Dateinamen (neu) als auch
  /// alte absolute Pfade (Legacy) und matcht dort den Basename gegen
  /// den aktuellen Photos-Ordner.
  static String? resolvePhoto(String? stored) {
    if (stored == null || stored.isEmpty) return null;
    if (_photosPath == null) return null;
    // Bereits relativ → joinen
    if (!p.isAbsolute(stored)) return p.join(_photosPath!, stored);
    // Absoluter Pfad: existiert er noch?
    if (File(stored).existsSync()) return stored;
    // Versuch: gleichen Dateinamen im aktuellen Photos-Ordner finden
    return p.join(_photosPath!, p.basename(stored));
  }

  /// Datei für gespeicherten Foto-Bezeichner, oder null wenn nicht vorhanden.
  static File? photoFile(String? stored) {
    final path = resolvePhoto(stored);
    if (path == null) return null;
    final f = File(path);
    return f.existsSync() ? f : null;
  }
}
