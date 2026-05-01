import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Cached App-Pfade. iOS- & macOS-Sandbox-Pfade ändern sich bei jedem Build/
/// Reinstall, daher dürfen NUR relative Dateinamen persistiert werden.
class AppPaths {
  AppPaths._();

  static String? _docsPath;
  static String? _photosPath;

  /// Muss einmal in `main()` vor `runApp` aufgerufen werden.
  static Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _docsPath = dir.path;
    final photoDir = Directory(p.join(dir.path, 'photos'));
    if (!await photoDir.exists()) {
      await photoDir.create(recursive: true);
    }
    _photosPath = photoDir.path;
  }

  /// Aktueller Documents-Ordner. Nicht persistieren!
  static String get docs => _docsPath!;

  /// Aktueller Photos-Ordner unter `<docs>/photos`.
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
