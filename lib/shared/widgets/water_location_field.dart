import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_theme.dart';
import '../../features/spots/location_picker_screen.dart';
import '../services/nominatim_service.dart';

/// Ergebnis einer Gewässer-/Standort-Auswahl über [WaterLocationField].
///
/// Liefert immer Koordinaten und – sofern aus Suche oder Map-Picker bekannt –
/// den Namen des Gewässers/der Position.
class WaterLocationPick {
  const WaterLocationPick({
    required this.lat,
    required this.lng,
    required this.label,
    this.fullName,
  });

  final double lat;
  final double lng;

  /// Kurzer Anzeigename (z. B. „Chiemsee") oder Fallback auf Koordinaten.
  final String label;

  /// Vollständiger Name (z. B. aus Nominatim) – für Datenfelder.
  final String? fullName;
}

/// Einheitliches UI-Element für Gewässer-/Standort-Auswahl.
///
/// Look & Feel ist identisch in Forecast, Trips, Spots und Catches.
/// Zwei Aktions-Buttons: Suche (Bottom-Sheet) und Karte ([LocationPickerScreen]).
class WaterLocationField extends StatelessWidget {
  const WaterLocationField({
    super.key,
    required this.label,
    required this.hasLocation,
    required this.onPicked,
    this.sectionLabel,
    this.subLabel,
    this.mapInitial,
    this.mapTitle = 'Gewässer wählen',
    this.searchHint = 'See, Fluss, Kanal …',
    this.searchTitle = 'Gewässer suchen',
    this.onClear,
    this.icon,
    this.placeholderIcon,
  });

  /// Anzeigetext – z. B. „Chiemsee" oder „Aktueller Standort".
  final String label;

  /// Sub-Label unter dem Haupt-Label (z. B. Koordinaten).
  final String? subLabel;

  /// Mini-Header über der Card (z. B. „GEWÄSSER"). Optional.
  final String? sectionLabel;

  /// True → primärer Border + gefülltes Icon.
  final bool hasLocation;

  /// Wird mit dem Pick-Ergebnis aufgerufen (Suche oder Karte).
  final ValueChanged<WaterLocationPick> onPicked;

  /// Startposition für den Karten-Picker.
  final LatLng? mapInitial;

  /// Titel des Karten-Pickers.
  final String mapTitle;

  /// Platzhaltertext im Sucheingabefeld.
  final String searchHint;

  /// Titel im Such-Bottom-Sheet.
  final String searchTitle;

  /// Wenn gesetzt: Reset-Icon links neben den Aktions-Buttons.
  final VoidCallback? onClear;

  /// Icon links wenn `hasLocation == true`.
  final IconData? icon;

  /// Icon links wenn `hasLocation == false`.
  final IconData? placeholderIcon;

  Future<void> _openSearch(BuildContext context) async {
    final picked = await showWaterSearchSheet(
      context,
      title: searchTitle,
      hint: searchHint,
    );
    if (picked == null) return;
    onPicked(
      WaterLocationPick(
        lat: picked.location.latitude,
        lng: picked.location.longitude,
        label: picked.shortName,
        fullName: picked.shortName,
      ),
    );
  }

  Future<void> _openMap(BuildContext context) async {
    final res = await Navigator.push<PickedLocation>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            LocationPickerScreen(initialPosition: mapInitial, title: mapTitle),
      ),
    );
    if (res == null) return;
    onPicked(
      WaterLocationPick(
        lat: res.position.latitude,
        lng: res.position.longitude,
        label:
            res.waterBodyName ??
            'Karten-Position '
                '(${res.position.latitude.toStringAsFixed(3)}, '
                '${res.position.longitude.toStringAsFixed(3)})',
        fullName: res.waterBodyName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final iconData = hasLocation
        ? (icon ?? Icons.water_drop)
        : (placeholderIcon ?? Icons.add_location_alt_outlined);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasLocation ? ApexColors.primary.withAlpha(120) : c.border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            iconData,
            color: hasLocation ? ApexColors.primary : c.textMuted,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (sectionLabel != null)
                  Text(
                    sectionLabel!,
                    style: TextStyle(
                      fontFamily: 'Rajdhani',
                      fontSize: 10,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w700,
                      color: c.textMuted,
                    ),
                  ),
                if (sectionLabel != null) const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: hasLocation ? c.textPrimary : c.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (subLabel != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subLabel!,
                    style: TextStyle(
                      fontFamily: 'Rajdhani',
                      fontSize: 11,
                      color: c.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onClear != null && hasLocation)
            IconButton(
              icon: Icon(Icons.gps_fixed, color: c.textMuted, size: 20),
              tooltip: 'Zurücksetzen',
              onPressed: onClear,
            ),
          IconButton(
            icon: const Icon(Icons.search, color: ApexColors.primary),
            tooltip: 'Gewässer suchen',
            onPressed: () => _openSearch(context),
          ),
          IconButton(
            icon: const Icon(Icons.map_outlined, color: ApexColors.primary),
            tooltip: 'Auf Karte wählen',
            onPressed: () => _openMap(context),
          ),
        ],
      ),
    );
  }
}

/// Öffnet das einheitliche „Gewässer suchen"-Bottom-Sheet (Nominatim).
///
/// Liefert das ausgewählte [NominatimResult] oder `null`, wenn abgebrochen.
Future<NominatimResult?> showWaterSearchSheet(
  BuildContext context, {
  String title = 'Gewässer suchen',
  String hint = 'See, Fluss, Kanal …',
}) {
  return showModalBottomSheet<NominatimResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: ApexColors.of(context).surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => WaterSearchSheet(title: title, hint: hint),
  );
}

/// Bottom-Sheet zur Gewässer-Suche (Nominatim).
///
/// Drag-Handle, fixer Header (außerhalb der Scroll-Liste), SafeArea und
/// 3-Zeichen-Mindestlänge – identisch in allen Flows.
class WaterSearchSheet extends StatefulWidget {
  const WaterSearchSheet({
    super.key,
    this.title = 'Gewässer suchen',
    this.hint = 'See, Fluss, Kanal …',
  });

  final String title;
  final String hint;

  @override
  State<WaterSearchSheet> createState() => _WaterSearchSheetState();
}

class _WaterSearchSheetState extends State<WaterSearchSheet> {
  final _ctrl = TextEditingController();
  final _service = NominatimService();
  List<NominatimResult> _results = const [];
  bool _loading = false;
  String _lastQuery = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    _lastQuery = q;
    if (q.trim().length < 3) {
      setState(() {
        _results = const [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    final r = await _service.searchWater(q);
    if (!mounted || _lastQuery != q) return;
    setState(() {
      _results = r;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final mq = MediaQuery.of(context);
    return SafeArea(
      top: true,
      child: Padding(
        padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
        child: SizedBox(
          height: mq.size.height * 0.75,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    const Icon(Icons.water_drop, color: ApexColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: TextStyle(
                          fontFamily: 'Rajdhani',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Schließen',
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: _search,
                  onSubmitted: _search,
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: c.surfaceVariant,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: ApexColors.primary,
                        ),
                      )
                    : _results.isEmpty
                    ? Center(
                        child: Text(
                          _ctrl.text.trim().length < 3
                              ? 'Tippe mindestens 3 Zeichen.'
                              : 'Keine Gewässer gefunden.',
                          style: TextStyle(color: c.textMuted),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: _results.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: c.border),
                        itemBuilder: (_, i) {
                          final r = _results[i];
                          return ListTile(
                            leading: const Icon(
                              Icons.water_drop,
                              color: ApexColors.primary,
                            ),
                            title: Text(r.shortName),
                            subtitle: Text(
                              r.displayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: c.textMuted,
                              ),
                            ),
                            onTap: () => Navigator.of(context).pop(r),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
