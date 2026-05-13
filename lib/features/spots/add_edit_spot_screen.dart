import 'package:flutter/material.dart';
import '../../shared/widgets/app_toast.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import '../../core/format/app_formats.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/fishing_spot.dart';
import '../../shared/models/waterbody.dart';
import '../../shared/services/app_providers.dart';
import '../../shared/widgets/photo_picker_field.dart';
import '../../shared/widgets/apex_app_bar.dart';
import '../../shared/widgets/water_location_field.dart';
import '../waterbodies/waterbody_picker_sheet.dart';

class AddEditSpotScreen extends ConsumerStatefulWidget {
  const AddEditSpotScreen({
    super.key,
    this.existing,
    this.prefillLat,
    this.prefillLng,
    this.prefillName,
  });
  final FishingSpot? existing;

  /// Vorbefüllte Koordinaten (z. B. „Spot aus Fang anlegen").
  /// Wirken nur, wenn [existing] null ist.
  final double? prefillLat;
  final double? prefillLng;
  final String? prefillName;

  @override
  ConsumerState<AddEditSpotScreen> createState() => _AddEditSpotScreenState();
}

class _AddEditSpotScreenState extends ConsumerState<AddEditSpotScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _waterBodyCtrl = TextEditingController();
  final _depthCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String? _waterbodyId;
  double? _lat;
  double? _lng;
  List<StructureType> _structures = [];
  String? _photoPath;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = e.name;
      _waterBodyCtrl.text = e.waterBodyName ?? '';
      _waterbodyId = e.waterbodyId;
      _depthCtrl.text = AppNum.text(e.depthM);
      _notesCtrl.text = e.notes ?? '';
      _lat = e.lat;
      _lng = e.lng;
      _structures = List.from(e.structures);
      _photoPath = e.photoPath;
    } else {
      if (widget.prefillLat != null && widget.prefillLng != null) {
        _lat = widget.prefillLat;
        _lng = widget.prefillLng;
      }
      if (widget.prefillName != null && widget.prefillName!.isNotEmpty) {
        _nameCtrl.text = widget.prefillName!;
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _waterBodyCtrl.dispose();
    _depthCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // HARTER, synchroner Re-Entrancy-Guard: muss vor allem anderen stehen
    // (auch vor `unfocus()` / `validate()`), damit schnelle Mehrfach-Taps
    // auf langsamen Geräten nicht mehrere Spots anlegen. setState reicht
    // hier nicht — die UI rebuildet erst im nächsten Frame, taps zwischen
    // jetzt und dann würden noch durchrutschen.
    if (_loading) return;
    _loading = true;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      _loading = false;
      if (mounted) setState(() {});
      return;
    }
    if (_lat == null || _lng == null) {
      _loading = false;
      if (mounted) setState(() {});
      AppToast.error(context, 'Bitte einen Standort auf der Karte markieren');
      return;
    }
    if (mounted) setState(() {}); // jetzt Spinner anzeigen
    try {
      final spot = FishingSpot(
        id: widget.existing?.id ?? const Uuid().v4(),
        name: _nameCtrl.text.trim(),
        lat: _lat!,
        lng: _lng!,
        waterbodyId: _waterbodyId,
        waterBodyName: _waterBodyCtrl.text.isNotEmpty
            ? _waterBodyCtrl.text.trim()
            : null,
        depthM: _depthCtrl.text.isNotEmpty
            ? double.tryParse(_depthCtrl.text.replaceAll(',', '.'))
            : null,
        structures: _structures,
        notes: _notesCtrl.text.isNotEmpty ? _notesCtrl.text.trim() : null,
        photoPath: _photoPath,
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
      );

      if (widget.existing != null) {
        await ref.read(spotProvider.notifier).editSpot(spot);
      } else {
        await ref.read(spotProvider.notifier).addSpot(spot);
      }
      if (!mounted) return;
      AppToast.success(
        context,
        widget.existing != null ? 'Spot aktualisiert' : 'Spot gespeichert',
      );
      context.pop();
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Speichern fehlgeschlagen: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch fürs Ableiten der Map-Marker (andere Spots) und für die
    // Karten-Initialposition, wenn ein Gewässer mit Koordinaten gewählt ist.
    final allSpots = ref.watch(spotProvider).valueOrNull ?? const [];
    final waterbodies = ref.watch(waterbodyProvider).valueOrNull ?? const [];
    Waterbody? selectedWb;
    for (final w in waterbodies) {
      if (w.id == _waterbodyId) {
        selectedWb = w;
        break;
      }
    }
    // Andere Spots (zur Orientierung im Karten-Picker). Den aktuell
    // bearbeiteten Spot rausfiltern, sonst sieht man sich selbst doppelt.
    final otherSpotMarkers = <LatLng>[
      for (final s in allSpots)
        if (s.id != widget.existing?.id) LatLng(s.lat, s.lng),
    ];
    // Falls noch kein Standort gesetzt ist, aber ein Gewässer mit
    // Mittelpunkt gewählt wurde \u2192 Karte dort \u00f6ffnen.
    final LatLng? effectiveMapInitial = (_lat != null && _lng != null)
        ? LatLng(_lat!, _lng!)
        : (selectedWb?.centerLat != null && selectedWb?.centerLng != null
              ? LatLng(selectedWb!.centerLat!, selectedWb.centerLng!)
              : null);

    return Scaffold(
      appBar: ApexAppBar(
        extraActions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: ApexColors.primary,
                ),
              ),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text(
                'SPEICHERN',
                style: TextStyle(
                  color: ApexColors.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Name
            TextFormField(
              controller: _nameCtrl,
              style: TextStyle(color: ApexColors.of(context).textPrimary),
              decoration: const InputDecoration(labelText: 'Spot-Name *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Pflichtfeld' : null,
            ),
            const SizedBox(height: 16),
            _WaterbodyPickerTile(
              waterbodyId: _waterbodyId,
              fallbackName: _waterBodyCtrl.text,
              onPicked: (wb) => setState(() {
                if (wb == null) {
                  _waterbodyId = null;
                  // Freitext-Namen behalten (Map/Reverse-Geocode)
                } else {
                  _waterbodyId = wb.id;
                  _waterBodyCtrl.text = wb.name;
                }
              }),
            ),
            const SizedBox(height: 20),

            // Karten-/Such-Picker
            const _Label('STANDORT'),
            const SizedBox(height: 8),
            WaterLocationField(
              label: (_lat != null && _lng != null)
                  ? (_waterBodyCtrl.text.trim().isNotEmpty
                        ? _waterBodyCtrl.text.trim()
                        : 'Standort gewählt')
                  : 'Karte oder Suche',
              subLabel: (_lat != null && _lng != null)
                  ? '${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}'
                  : null,
              hasLocation: _lat != null && _lng != null,
              mapInitial: effectiveMapInitial,
              existingSpots: otherSpotMarkers,
              onPicked: (p) => setState(() {
                _lat = p.lat;
                _lng = p.lng;
                // Map-/Reverse-Geocode-Namen nur übernehmen, wenn KEIN
                // Gewässer explizit ausgewählt ist (sonst nicht
                // überschreiben).
                if (_waterbodyId == null &&
                    p.fullName != null &&
                    p.fullName!.isNotEmpty) {
                  _waterBodyCtrl.text = p.fullName!;
                  _waterBodyCtrl.selection = TextSelection.collapsed(
                    offset: _waterBodyCtrl.text.length,
                  );
                }
              }),
            ),
            const SizedBox(height: 20),

            // Tiefe
            const _Label('GEWÄSSER-DETAILS'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _depthCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              style: TextStyle(color: ApexColors.of(context).textPrimary),
              decoration: const InputDecoration(
                labelText: 'Tiefe (m)',
                hintText: 'z.B. 5,5',
              ),
            ),
            const SizedBox(height: 20),

            // Struktur-Picker
            const _Label('GEWÄSSERSTRUKTUR'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: StructureType.values.map((s) {
                final selected = _structures.contains(s);
                return GestureDetector(
                  onTap: () => setState(() {
                    if (selected) {
                      _structures.remove(s);
                    } else {
                      _structures.add(s);
                    }
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? ApexColors.of(context).primaryGlow
                          : ApexColors.of(context).surfaceVariant,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected
                            ? ApexColors.primary
                            : ApexColors.of(context).border,
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      s.displayName,
                      style: TextStyle(
                        fontSize: 12,
                        color: selected
                            ? ApexColors.primary
                            : ApexColors.of(context).textSecondary,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Foto
            const _Label('FOTO'),
            const SizedBox(height: 8),
            PhotoPickerField(
              path: _photoPath,
              onChanged: (p) => setState(() => _photoPath = p),
              label: 'Spot-Foto',
            ),
            const SizedBox(height: 20),

            // Notizen
            const _Label('NOTIZEN'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _notesCtrl,
              maxLines: 3,
              style: TextStyle(color: ApexColors.of(context).textPrimary),
              decoration: const InputDecoration(
                labelText: 'Notizen (optional)',
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
        color: ApexColors.of(context).textMuted,
      ),
    );
  }
}

/// Tap-Tile zum Auswählen / Löschen eines Waterbody. Zeigt den aktuellen
/// Status und öffnet das Bottom-Sheet. Bei „Kein Gewässer" → null.
class _WaterbodyPickerTile extends ConsumerWidget {
  const _WaterbodyPickerTile({
    required this.waterbodyId,
    required this.fallbackName,
    required this.onPicked,
  });
  final String? waterbodyId;
  final String fallbackName;
  final ValueChanged<Waterbody?> onPicked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ApexColors.of(context);
    final wbList = ref.watch(waterbodyProvider).valueOrNull ?? const [];
    final wb = waterbodyId == null
        ? null
        : wbList.where((w) => w.id == waterbodyId).cast<Waterbody?>().firstOrNull;

    final hasWb = wb != null;
    final title = hasWb
        ? wb.name
        : (fallbackName.trim().isNotEmpty
              ? fallbackName.trim()
              : 'Gewässer wählen (optional)');
    final subtitle = hasWb
        ? wb.subtitle
        : (fallbackName.trim().isNotEmpty
              ? 'Nicht verknüpft – tippen, um Gewässer zuzuordnen'
              : 'Tippen zum Auswählen oder Anlegen');

    return InkWell(
      onTap: () async {
        final picked = await WaterbodyPickerSheet.show(
          context,
          initialId: waterbodyId,
        );
        // Sheet liefert null sowohl bei „Kein Gewässer" als auch bei
        // Sheet-Dismiss. Wir können hier nicht zwischen beiden unterscheiden;
        // ein Tap auf „Kein Gewässer" ruft `pop(null)` ebenfalls. Akzeptiert.
        onPicked(picked);
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: c.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasWb ? ApexColors.primary.withAlpha(120) : c.border,
            width: hasWb ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: ApexColors.primary.withAlpha(40),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                hasWb ? Icons.water_rounded : Icons.water_drop_outlined,
                color: ApexColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'GEWÄSSER',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w700,
                      color: c.textMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: c.textMuted),
          ],
        ),
      ),
    );
  }
}
