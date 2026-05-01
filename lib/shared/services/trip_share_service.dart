import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format/app_formats.dart';
import '../models/trip.dart';

/// Baut einen teilbaren Text für einen [Trip] und ruft das native
/// Share-Sheet auf.
class TripShareService {
  const TripShareService();

  /// Erzeugt den formatierten Text (ohne zu teilen). Öffentlich, damit
  /// der Text auch für Preview/Copy verwendet werden kann.
  String buildShareText(Trip trip) {
    final df = AppDateFormats.weekdayDateMonthName;
    final buf = StringBuffer();
    buf.writeln('🪝 ${trip.name}');
    buf.writeln(df.format(trip.date));
    if (trip.waterBodyName != null && trip.waterBodyName!.isNotEmpty) {
      buf.writeln('📍 ${trip.waterBodyName}');
    }
    buf.writeln();
    buf.writeln(
      'Treffpunkt: '
      'https://maps.google.com/?q=${trip.centerLat.toStringAsFixed(5)},'
      '${trip.centerLng.toStringAsFixed(5)}',
    );

    if (trip.stops.isNotEmpty) {
      buf.writeln();
      buf.writeln('SPOTS (${trip.stops.length}):');
      for (var i = 0; i < trip.stops.length; i++) {
        final s = trip.stops[i];
        buf.writeln(
          '${i + 1}. ${s.name} — '
          'https://maps.google.com/?q=${s.lat.toStringAsFixed(5)},'
          '${s.lng.toStringAsFixed(5)}',
        );
        if (s.notes != null && s.notes!.trim().isNotEmpty) {
          buf.writeln('   ${s.notes!.trim()}');
        }
      }
    }

    if (trip.checklist.isNotEmpty) {
      buf.writeln();
      buf.writeln('PACKLISTE:');
      for (final item in trip.checklist) {
        buf.writeln('• $item');
      }
    }

    if (trip.notes != null && trip.notes!.trim().isNotEmpty) {
      buf.writeln();
      buf.writeln('NOTIZEN:');
      buf.writeln(trip.notes!.trim());
    }

    buf.writeln();
    buf.writeln('— geteilt aus Hooked');
    return buf.toString();
  }

  /// Öffnet das native Share-Sheet.
  Future<void> shareTrip(BuildContext context, Trip trip) async {
    final text = buildShareText(trip);
    final subject = 'Trip: ${trip.name}';
    final box = context.findRenderObject() as RenderBox?;
    await Share.share(
      text,
      subject: subject,
      sharePositionOrigin: box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : null,
    );
  }
}
