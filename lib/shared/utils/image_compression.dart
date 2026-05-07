import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Komprimiert ein Bild für Cloud-Uploads:
/// - skaliert auf maximal [maxEdge] Pixel (längere Kante)
/// - encodiert als JPEG mit [quality] (1-100)
///
/// Läuft in einem Isolate (compute), damit der UI-Thread nicht blockiert.
/// Liefert die komprimierten JPEG-Bytes oder die Originaldatei-Bytes,
/// falls das Decoden fehlschlägt (z. B. exotische Container) — der Upload
/// soll nie an der Komprimierung scheitern.
Future<Uint8List> compressForUpload(
  File source, {
  int maxEdge = 1920,
  int quality = 82,
}) async {
  final bytes = await source.readAsBytes();
  return compute(_compressInIsolate, _CompressArgs(bytes, maxEdge, quality));
}

class _CompressArgs {
  final Uint8List bytes;
  final int maxEdge;
  final int quality;
  const _CompressArgs(this.bytes, this.maxEdge, this.quality);
}

Uint8List _compressInIsolate(_CompressArgs args) {
  final decoded = img.decodeImage(args.bytes);
  if (decoded == null) return args.bytes;

  // EXIF-Orientation auflösen, sonst rotiert das Bild im Backend falsch.
  final oriented = img.bakeOrientation(decoded);

  final longer = oriented.width >= oriented.height
      ? oriented.width
      : oriented.height;
  final resized = longer > args.maxEdge
      ? img.copyResize(
          oriented,
          width: oriented.width >= oriented.height ? args.maxEdge : null,
          height: oriented.height > oriented.width ? args.maxEdge : null,
          interpolation: img.Interpolation.linear,
        )
      : oriented;

  return Uint8List.fromList(img.encodeJpg(resized, quality: args.quality));
}
