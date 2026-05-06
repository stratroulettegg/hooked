import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import '../../core/format/app_formats.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/catch_entry.dart';
import '../../shared/models/fishing_spot.dart';
import '../../shared/services/app_providers.dart';
import '../../shared/data/lure_catalog.dart';
import '../../shared/widgets/photo_picker_field.dart';
import '../../shared/widgets/apex_app_bar.dart';
import '../../shared/widgets/water_location_field.dart';

class AddEditCatchScreen extends ConsumerStatefulWidget {
  const AddEditCatchScreen({super.key, this.existing, this.prefill});
  final CatchEntry? existing;

  /// Vorbefüllung für neue Einträge (z. B. aus Voice-Quick-Add).
  /// Wirkt nur, wenn [existing] null ist.
  final CatchEntry? prefill;

  @override
  ConsumerState<AddEditCatchScreen> createState() => _AddEditCatchScreenState();
}

class _AddEditCatchScreenState extends ConsumerState<AddEditCatchScreen> {
  final _formKey = GlobalKey<FormState>();
  late FishSpecies _species;
  late DateTime _caughtAt;
  final _weightCtrl = TextEditingController();
  final _lengthCtrl = TextEditingController();
  final _lureCtrl = TextEditingController();
  final _lureColorCtrl = TextEditingController();
  final _depthCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final Set<RetrieveStyle> _retrieveStyles = {};
  String? _photoPath;

  // Vorbefüllte GPS-Koordinaten (z. B. aus Voice-Quick-Add). Werden beim
  // Speichern als Fallback genutzt, falls kein Spot verknüpft wird.
  double? _prefillLat;
  double? _prefillLng;

  // Spot-Verknüpfung
  String? _spotId; // existierender Spot
  bool _createNewSpot = false; // neuen Spot inline anlegen
  final _newSpotNameCtrl = TextEditingController();
  final _newSpotWaterBodyCtrl = TextEditingController();
  final _newSpotDepthCtrl = TextEditingController();
  final _newSpotNotesCtrl = TextEditingController();
  double? _newSpotLat;
  double? _newSpotLng;
  String? _newSpotPhotoPath;
  List<StructureType> _newSpotStructures = [];

  // Privacy: wenn deaktiviert, werden Lat/Lng beim Speichern auf null gesetzt
  // (Fang taucht dann nicht mit GPS-Koordinaten auf, etwaige Spot-Linkings
  // bleiben aber bestehen).
  bool _saveLocation = true;

  // Community-Feed: opt-in.
  bool _isShared = false;
  bool _shareWater = false;

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing ?? widget.prefill;
    _species = e?.species ?? FishSpecies.hecht;
    _caughtAt = e?.caughtAt ?? DateTime.now();
    if (e != null) {
      _weightCtrl.text = e.weightG?.toString() ?? '';
      _lengthCtrl.text = AppNum.text(e.lengthCm);
      _lureCtrl.text = e.lure ?? '';
      _lureColorCtrl.text = e.lureColor ?? '';
      _depthCtrl.text = AppNum.text(e.depthM);
      _notesCtrl.text = e.notes ?? '';
      _retrieveStyles
        ..clear()
        ..addAll(e.retrieveStyles);
      _photoPath = e.photoPath;
      _spotId = e.spotId;
      _isShared = e.isShared;
      _shareWater = e.shareWater;
      // Nur als Prefill-Fallback merken, wenn es ein neuer Eintrag ist.
      if (widget.existing == null) {
        _prefillLat = e.lat;
        _prefillLng = e.lng;
      } else {
        // Im Edit-Modus: wenn der Eintrag keine Koordinaten und keinen Spot
        // hat, nehmen wir an, dass der Standort bewusst verborgen wurde.
        if (e.lat == null && e.lng == null && e.spotId == null) {
          _saveLocation = false;
        }
      }
    }
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _lengthCtrl.dispose();
    _lureCtrl.dispose();
    _lureColorCtrl.dispose();
    _depthCtrl.dispose();
    _notesCtrl.dispose();
    _newSpotNameCtrl.dispose();
    _newSpotWaterBodyCtrl.dispose();
    _newSpotDepthCtrl.dispose();
    _newSpotNotesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;
    if (_createNewSpot) {
      if (_newSpotNameCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Bitte einen Spot-Namen eingeben oder “Kein Spot” wählen',
            ),
          ),
        );
        return;
      }
      if (_newSpotLat == null || _newSpotLng == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bitte Spot-Standort auf der Karte markieren'),
          ),
        );
        return;
      }
    }
    setState(() => _loading = true);
    try {
      String? linkedSpotId = _spotId;
      double? linkedLat;
      double? linkedLng;
      if (_createNewSpot) {
        final newSpot = FishingSpot(
          id: const Uuid().v4(),
          name: _newSpotNameCtrl.text.trim(),
          lat: _newSpotLat!,
          lng: _newSpotLng!,
          waterBodyName: _newSpotWaterBodyCtrl.text.trim().isNotEmpty
              ? _newSpotWaterBodyCtrl.text.trim()
              : null,
          depthM: _newSpotDepthCtrl.text.trim().isNotEmpty
              ? double.tryParse(_newSpotDepthCtrl.text.replaceAll(',', '.'))
              : null,
          structures: List.from(_newSpotStructures),
          notes: _newSpotNotesCtrl.text.trim().isNotEmpty
              ? _newSpotNotesCtrl.text.trim()
              : null,
          photoPath: _newSpotPhotoPath,
          createdAt: DateTime.now(),
        );
        final created = await ref.read(spotProvider.notifier).addSpot(newSpot);
        linkedSpotId = created.id;
        linkedLat = created.lat;
        linkedLng = created.lng;
      } else if (linkedSpotId != null) {
        final spots =
            ref.read(spotProvider).valueOrNull ?? const <FishingSpot>[];
        final s = spots.where((e) => e.id == linkedSpotId).firstOrNull;
        linkedLat = s?.lat;
        linkedLng = s?.lng;
      }

      // Auto-Spot-Zuordnung: Wenn (noch) kein Spot verknüpft ist, aber wir
      // eine Fang-Position kennen, suchen wir den nächstgelegenen eigenen
      // Spot im Umkreis von 75 m. So muss man bei Voice-Quick-Add nicht
      // manuell nachverlinken.
      // Achtung: Bei aktivem Privacy-Toggle (`_saveLocation == false`) wird
      // diese Auto-Zuordnung übersprungen, sonst wäre der Standort indirekt
      // über den verknüpften Spot rekonstruierbar.
      String? autoLinkedSpotName;
      if (_saveLocation && linkedSpotId == null && !_createNewSpot) {
        final probeLat = _prefillLat;
        final probeLng = _prefillLng;
        if (probeLat != null && probeLng != null) {
          final spots =
              ref.read(spotProvider).valueOrNull ?? const <FishingSpot>[];
          const distance = Distance();
          final probe = LatLng(probeLat, probeLng);
          FishingSpot? nearest;
          double nearestMeters = double.infinity;
          for (final s in spots) {
            final m = distance(probe, LatLng(s.lat, s.lng));
            if (m < nearestMeters) {
              nearestMeters = m;
              nearest = s;
            }
          }
          if (nearest != null && nearestMeters <= 75) {
            linkedSpotId = nearest.id;
            linkedLat = nearest.lat;
            linkedLng = nearest.lng;
            autoLinkedSpotName = nearest.name;
          }
        }
      }

      final entry = CatchEntry(
        id: widget.existing?.id ?? const Uuid().v4(),
        species: _species,
        weightG: _weightCtrl.text.isNotEmpty
            ? int.tryParse(_weightCtrl.text)
            : null,
        lengthCm: _lengthCtrl.text.isNotEmpty
            ? double.tryParse(_lengthCtrl.text.replaceAll(',', '.'))
            : null,
        lure: _lureCtrl.text.isNotEmpty ? _lureCtrl.text : null,
        lureColor: _lureColorCtrl.text.isNotEmpty ? _lureColorCtrl.text : null,
        depthM: _depthCtrl.text.isNotEmpty
            ? double.tryParse(_depthCtrl.text.replaceAll(',', '.'))
            : null,
        notes: _notesCtrl.text.isNotEmpty ? _notesCtrl.text : null,
        retrieveStyles: _retrieveStyles.toList(),
        photoPath: _photoPath,
        spotId: linkedSpotId,
        lat: _saveLocation ? (linkedLat ?? _prefillLat) : null,
        lng: _saveLocation ? (linkedLng ?? _prefillLng) : null,
        caughtAt: _caughtAt,
        // Defensive Sicherung: ein Community-Post ohne Foto ist nicht
        // erlaubt. Sollte der Schalter trotzdem aktiv sein (z.\u202fB. weil
        // ein bestehender Eintrag das Foto verloren hat), wird die
        // Freigabe hier hart deaktiviert.
        isShared: _isShared
            && _photoPath != null
            && _photoPath!.isNotEmpty,
        shareWater: _isShared
            && _shareWater
            && _photoPath != null
            && _photoPath!.isNotEmpty,
      );

      if (widget.existing != null) {
        await ref.read(catchProvider.notifier).editCatch(entry);
      } else {
        await ref.read(catchProvider.notifier).addCatch(entry);
      }
      if (mounted) {
        if (autoLinkedSpotName != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('📍 Automatisch mit Spot „$autoLinkedSpotName" verknüpft'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        context.pop();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
            // Zielfisch
            _SectionLabel('ZIELFISCH'),
            const SizedBox(height: 8),
            _SpeciesPicker(
              value: _species,
              onChanged: (v) => setState(() => _species = v),
            ),
            const SizedBox(height: 20),

            // Datum & Zeit
            _SectionLabel('ZEITPUNKT'),
            const SizedBox(height: 8),
            _DateTimePicker(
              value: _caughtAt,
              onChanged: (v) => setState(() => _caughtAt = v),
            ),
            const SizedBox(height: 20),

            // Maße
            _SectionLabel('MAßE'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _ApexTextField(
                    controller: _weightCtrl,
                    label: 'Gewicht (g)',
                    keyboardType: TextInputType.number,
                    hint: 'z.B. 2400',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ApexTextField(
                    controller: _lengthCtrl,
                    label: 'Länge (cm)',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: _decimalFormatters,
                    hint: 'z.B. 65',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Köder
            _SectionLabel('KÖDER'),
            const SizedBox(height: 8),
            _RecentLuresChips(
              currentValue: _lureCtrl.text,
              onPick: (lure) => setState(() {
                _lureCtrl.text = lure;
                _lureCtrl.selection = TextSelection.collapsed(
                  offset: _lureCtrl.text.length,
                );
              }),
            ),
            _LurePicker(
              value: _lureCtrl.text.isEmpty ? null : _lureCtrl.text,
              onChanged: (v) => setState(() => _lureCtrl.text = v ?? ''),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ApexTextField(
                    controller: _lureColorCtrl,
                    label: 'Farbe',
                    hint: 'z.B. Perch',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ApexTextField(
                    controller: _depthCtrl,
                    label: 'Tiefe (m)',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: _decimalFormatters,
                    hint: 'z.B. 4,5',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _RetrievePicker(
              selected: _retrieveStyles,
              onChanged: (set) => setState(() {
                _retrieveStyles
                  ..clear()
                  ..addAll(set);
              }),
            ),
            const SizedBox(height: 20),

            // Foto vom Fang
            _SectionLabel('FANG-FOTO'),
            const SizedBox(height: 8),
            PhotoPickerField(
              path: _photoPath,
              onChanged: (p) => setState(() {
                _photoPath = p;
                // Ohne Foto kein Community-Post — Schalter wird passend
                // synchron mit zur\u00fcckgesetzt, damit kein verwaister
                // Share-Status \u00fcberlebt.
                if (p == null || p.isEmpty) {
                  _isShared = false;
                  _shareWater = false;
                }
              }),
              label: 'Fang-Foto',
            ),
            const SizedBox(height: 14),

            // Notizen zum Fang (direkt unter dem Foto)
            _SectionLabel('NOTIZEN ZUM FANG'),
            const SizedBox(height: 8),
            _ApexTextField(
              controller: _notesCtrl,
              label: 'Drill, Bedingungen, Beobachtungen …',
              hint:
                  'z. B. Sonniger Vormittag, Drill ca. 3 Min, Biss kurz nach Stop & Go',
              maxLines: 4,
            ),
            const SizedBox(height: 20),

            // Spot-Verknüpfung
            _SectionLabel('SPOT'),
            const SizedBox(height: 8),
            _SpotSection(
              spotId: _spotId,
              createNew: _createNewSpot,
              newName: _newSpotNameCtrl,
              newWaterBody: _newSpotWaterBodyCtrl,
              newDepth: _newSpotDepthCtrl,
              newNotes: _newSpotNotesCtrl,
              newLat: _newSpotLat,
              newLng: _newSpotLng,
              newPhoto: _newSpotPhotoPath,
              newStructures: _newSpotStructures,
              catchLat: widget.existing?.lat ?? _prefillLat,
              catchLng: widget.existing?.lng ?? _prefillLng,
              defaultSpotName: 'Spot ${_species.displayName}',
              onModeChange: ({String? id, bool createNew = false}) {
                setState(() {
                  _spotId = id;
                  _createNewSpot = createNew;
                });
              },
              onLocation: (lat, lng) => setState(() {
                _newSpotLat = lat;
                _newSpotLng = lng;
              }),
              onPhotoChanged: (p) => setState(() => _newSpotPhotoPath = p),
              onStructuresChanged: (s) =>
                  setState(() => _newSpotStructures = s),
            ),
            const SizedBox(height: 20),
            _PrivacyToggle(
              value: _saveLocation,
              onChanged: (v) => setState(() => _saveLocation = v),
            ),
            const SizedBox(height: 24),
            const _SectionLabel('COMMUNITY'),
            const SizedBox(height: 8),
            _CommunityShareCard(
              isShared: _isShared,
              shareWater: _shareWater,
              hasPhoto:
                  _photoPath != null && _photoPath!.isNotEmpty,
              onSharedChanged: (v) => setState(() {
                _isShared = v;
                if (!v) _shareWater = false;
              }),
              onShareWaterChanged: (v) =>
                  setState(() => _shareWater = v),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
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

class _ApexTextField extends StatelessWidget {
  const _ApexTextField({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.hint,
    this.maxLines = 1,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final String? hint;
  final int maxLines;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      inputFormatters: inputFormatters,
      style: TextStyle(color: ApexColors.of(context).textPrimary),
      decoration: InputDecoration(labelText: label, hintText: hint),
    );
  }
}

/// Erlaubt Ziffern sowie Punkt und Komma als Dezimaltrenner.
final List<TextInputFormatter> _decimalFormatters = [
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
];

class _SpeciesPicker extends StatelessWidget {
  const _SpeciesPicker({required this.value, required this.onChanged});
  final FishSpecies value;
  final ValueChanged<FishSpecies> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: FishSpecies.values.map((s) {
        final selected = s == value;
        return GestureDetector(
          onTap: () => onChanged(s),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? ApexColors.of(context).primaryGlow
                  : ApexColors.of(context).surfaceVariant,
              borderRadius: BorderRadius.circular(10),
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
                fontSize: 13,
                color: selected
                    ? ApexColors.primary
                    : ApexColors.of(context).textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _RetrievePicker extends StatelessWidget {
  const _RetrievePicker({required this.selected, required this.onChanged});
  final Set<RetrieveStyle> selected;
  final ValueChanged<Set<RetrieveStyle>> onChanged;

  static const _groups = <String, List<RetrieveStyle>>{
    'Führungstechniken': [
      RetrieveStyle.cranking,
      RetrieveStyle.stopGo,
      RetrieveStyle.speedVariation,
      RetrieveStyle.faulenzen,
      RetrieveStyle.jig,
      RetrieveStyle.dragging,
      RetrieveStyle.tumbling,
      RetrieveStyle.twitch,
      RetrieveStyle.jerking,
      RetrieveStyle.walkTheDog,
      RetrieveStyle.ripping,
      RetrieveStyle.shaking,
      RetrieveStyle.deadSticking,
      RetrieveStyle.liftDrop,
      RetrieveStyle.vertical,
      RetrieveStyle.pelagic,
    ],
    'Finesse-Methoden & Rigs': [
      RetrieveStyle.dropShot,
      RetrieveStyle.texasRig,
      RetrieveStyle.carolinaRig,
      RetrieveStyle.nedRig,
      RetrieveStyle.cheburashkaRig,
      RetrieveStyle.freeRig,
      RetrieveStyle.wackyRig,
    ],
  };

  Future<void> _open(BuildContext context) async {
    final c = ApexColors.of(context);
    final working = Set<RetrieveStyle>.from(selected);
    final result = await showModalBottomSheet<Set<RetrieveStyle>>(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.7,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            builder: (_, scrollCtrl) {
              return ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
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
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        'Technik wählen',
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      if (working.isNotEmpty)
                        TextButton(
                          onPressed: () => setSheet(working.clear),
                          child: const Text(
                            'Leeren',
                            style: TextStyle(color: ApexColors.primary),
                          ),
                        ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(working),
                        child: const Text(
                          'Fertig',
                          style: TextStyle(
                            color: ApexColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Mehrfachauswahl möglich.',
                    style: TextStyle(color: c.textMuted, fontSize: 12),
                  ),
                  for (final entry in _groups.entries) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 16, 0, 8),
                      child: Text(
                        entry.key.toUpperCase(),
                        style: TextStyle(
                          color: c.textMuted,
                          fontSize: 11,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: entry.value.map((s) {
                        final isOn = working.contains(s);
                        return GestureDetector(
                          onTap: () => setSheet(() {
                            if (isOn) {
                              working.remove(s);
                            } else {
                              // In dieser Gruppe nur eine Auswahl erlauben.
                              working.removeAll(entry.value);
                              working.add(s);
                            }
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isOn
                                  ? ApexColors.primary
                                  : c.surfaceVariant,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isOn ? ApexColors.primary : c.border,
                                width: isOn ? 1.5 : 1,
                              ),
                            ),
                            child: Text(
                              s.displayName,
                              style: TextStyle(
                                fontSize: 13,
                                color: isOn ? Colors.white : c.textSecondary,
                                fontWeight: isOn
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              );
            },
          ),
        );
      },
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final label = selected.isEmpty
        ? 'Technik wählen …'
        : selected.map((e) => e.displayName).join(', ');
    return InkWell(
      onTap: () => _open(context),
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: const InputDecoration(labelText: 'Technik (optional)'),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selected.isEmpty ? c.textMuted : c.textPrimary,
                ),
              ),
            ),
            Icon(Icons.arrow_drop_down, color: c.textMuted),
          ],
        ),
      ),
    );
  }
}

class _StyleChip extends StatelessWidget {
  const _StyleChip({required this.label, required this.selected});
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: selected
            ? ApexColors.of(context).primaryGlow
            : ApexColors.of(context).surfaceVariant,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? ApexColors.primary : ApexColors.of(context).border,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: selected
              ? ApexColors.primary
              : ApexColors.of(context).textSecondary,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }
}

class _DateTimePicker extends StatelessWidget {
  const _DateTimePicker({required this.value, required this.onChanged});
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2010),
          lastDate: DateTime.now(),
          builder: (context, child) =>
              Theme(data: Theme.of(context), child: child!),
        );
        if (date == null || !context.mounted) return;
        final time = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(value),
          builder: (context, child) =>
              Theme(data: Theme.of(context), child: child!),
        );
        if (time == null) return;
        onChanged(
          DateTime(date.year, date.month, date.day, time.hour, time.minute),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: ApexColors.of(context).surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ApexColors.of(context).border),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, color: ApexColors.primary, size: 18),
            const SizedBox(width: 10),
            Text(
              AppDateFormats.dayMonthYearHourMinute.format(value),
              style: TextStyle(
                color: ApexColors.of(context).textPrimary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Spot-Verknüpfung im Fang-Formular.
///
/// Drei Modi: kein Spot, existierenden Spot wählen, neuen Spot inline anlegen.
class _SpotSection extends ConsumerWidget {
  const _SpotSection({
    required this.spotId,
    required this.createNew,
    required this.newName,
    required this.newWaterBody,
    required this.newDepth,
    required this.newNotes,
    required this.newLat,
    required this.newLng,
    required this.newPhoto,
    required this.newStructures,
    required this.catchLat,
    required this.catchLng,
    required this.defaultSpotName,
    required this.onModeChange,
    required this.onLocation,
    required this.onPhotoChanged,
    required this.onStructuresChanged,
  });

  final String? spotId;
  final bool createNew;
  final TextEditingController newName;
  final TextEditingController newWaterBody;
  final TextEditingController newDepth;
  final TextEditingController newNotes;
  final double? newLat;
  final double? newLng;
  final String? newPhoto;
  final List<StructureType> newStructures;
  final double? catchLat;
  final double? catchLng;
  final String defaultSpotName;
  final void Function({String? id, bool createNew}) onModeChange;
  final void Function(double lat, double lng) onLocation;
  final ValueChanged<String?> onPhotoChanged;
  final ValueChanged<List<StructureType>> onStructuresChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ApexColors.of(context);
    final spotsAsync = ref.watch(spotProvider);
    final spots = spotsAsync.valueOrNull ?? const <FishingSpot>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (spotId == null && !createNew && catchLat != null && catchLng != null) ...[
          _CreateSpotFromCatchHint(
            onTap: () {
              onLocation(catchLat!, catchLng!);
              if (newName.text.trim().isEmpty) {
                newName.text = defaultSpotName;
                newName.selection = TextSelection.collapsed(
                  offset: newName.text.length,
                );
              }
              onModeChange(id: null, createNew: true);
            },
          ),
          const SizedBox(height: 12),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _StyleChip(
              label: 'Kein Spot',
              selected: spotId == null && !createNew,
            ).asTap(() => onModeChange(id: null, createNew: false)),
            _StyleChip(
              label: 'Vorhandenen wählen',
              selected: spotId != null && !createNew,
            ).asTap(() async {
              final picked = await _pickSpot(context, spots, spotId);
              if (picked != null) onModeChange(id: picked, createNew: false);
            }),
            _StyleChip(
              label: '+ Neu anlegen',
              selected: createNew,
            ).asTap(() => onModeChange(id: null, createNew: true)),
          ],
        ),
        if (spotId != null && !createNew) ...[
          const SizedBox(height: 10),
          _SpotPreview(spot: spots.where((s) => s.id == spotId).firstOrNull),
        ],
        if (createNew) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: newName,
            style: TextStyle(color: c.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Spot-Name *',
              hintText: 'z.B. Kraut-Bucht Nord',
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: newWaterBody,
            style: TextStyle(color: c.textPrimary),
            decoration: const InputDecoration(labelText: 'Gewässer (optional)'),
          ),
          const SizedBox(height: 10),
          WaterLocationField(
            label: (newLat != null && newLng != null)
                ? (newWaterBody.text.trim().isNotEmpty
                      ? newWaterBody.text.trim()
                      : 'Standort gewählt')
                : 'Karte oder Suche',
            subLabel: (newLat != null && newLng != null)
                ? '${newLat!.toStringAsFixed(5)}, ${newLng!.toStringAsFixed(5)}'
                : null,
            hasLocation: newLat != null && newLng != null,
            mapInitial: (newLat != null && newLng != null)
                ? LatLng(newLat!, newLng!)
                : null,
            onPicked: (p) {
              onLocation(p.lat, p.lng);
              if (p.fullName != null &&
                  p.fullName!.isNotEmpty &&
                  newWaterBody.text.trim().isEmpty) {
                newWaterBody.text = p.fullName!;
                newWaterBody.selection = TextSelection.collapsed(
                  offset: newWaterBody.text.length,
                );
              }
            },
          ),
          const SizedBox(height: 14),
          _SectionLabel('GEWÄSSER-DETAILS'),
          const SizedBox(height: 8),
          TextFormField(
            controller: newDepth,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: _decimalFormatters,
            style: TextStyle(color: c.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Tiefe (m)',
              hintText: 'z.B. 5,5',
            ),
          ),
          const SizedBox(height: 14),
          _SectionLabel('GEWÄSSERSTRUKTUR'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: StructureType.values.map((s) {
              final selected = newStructures.contains(s);
              return GestureDetector(
                onTap: () {
                  final next = List<StructureType>.from(newStructures);
                  if (selected) {
                    next.remove(s);
                  } else {
                    next.add(s);
                  }
                  onStructuresChanged(next);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? c.primaryGlow : c.surfaceVariant,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected ? ApexColors.primary : c.border,
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    s.displayName,
                    style: TextStyle(
                      fontSize: 12,
                      color: selected ? ApexColors.primary : c.textSecondary,
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          _SectionLabel('FOTO'),
          const SizedBox(height: 8),
          PhotoPickerField(
            path: newPhoto,
            onChanged: onPhotoChanged,
            label: 'Spot-Foto',
            height: 140,
          ),
          const SizedBox(height: 14),
          _SectionLabel('NOTIZEN ZUM SPOT'),
          const SizedBox(height: 8),
          TextFormField(
            controller: newNotes,
            maxLines: 3,
            style: TextStyle(color: c.textPrimary),
            decoration: const InputDecoration(labelText: 'Notizen (optional)'),
          ),
        ],
      ],
    );
  }

  Future<String?> _pickSpot(
    BuildContext context,
    List<FishingSpot> spots,
    String? current,
  ) async {
    if (spots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Noch keine Spots angelegt – nutze „+ Neu anlegen“'),
        ),
      );
      return null;
    }
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: ApexColors.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final c = ApexColors.of(ctx);
        return SafeArea(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: spots.length,
            itemBuilder: (_, i) {
              final s = spots[i];
              final selected = s.id == current;
              return ListTile(
                leading: Icon(
                  Icons.place,
                  color: selected ? ApexColors.primary : c.textSecondary,
                ),
                title: Text(s.name, style: TextStyle(color: c.textPrimary)),
                subtitle: s.waterBodyName != null
                    ? Text(
                        s.waterBodyName!,
                        style: TextStyle(color: c.textMuted),
                      )
                    : null,
                trailing: selected
                    ? Icon(Icons.check, color: ApexColors.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, s.id),
              );
            },
          ),
        );
      },
    );
  }
}

class _SpotPreview extends StatelessWidget {
  const _SpotPreview({required this.spot});
  final FishingSpot? spot;

  @override
  Widget build(BuildContext context) {
    final s = spot;
    final c = ApexColors.of(context);
    if (s == null) {
      return Text('Spot nicht gefunden', style: TextStyle(color: c.textMuted));
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Icon(Icons.place, color: ApexColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.name,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (s.waterBodyName != null)
                  Text(
                    s.waterBodyName!,
                    style: TextStyle(color: c.textMuted, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension _ChipTap on _StyleChip {
  Widget asTap(VoidCallback onTap) =>
      GestureDetector(onTap: onTap, child: this);
}

// ---------------------------------------------------------------------------
// Köder-Picker mit fester, kategorisierter Auswahl
// ---------------------------------------------------------------------------

class _LurePicker extends StatelessWidget {
  const _LurePicker({required this.value, required this.onChanged});
  final String? value;
  final ValueChanged<String?> onChanged;

  Future<void> _open(BuildContext context) async {
    final c = ApexColors.of(context);
    final result = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (_, scrollCtrl) {
            return ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
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
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      'Köder wählen',
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    if (value != null)
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(''),
                        child: const Text(
                          'Löschen',
                          style: TextStyle(color: ApexColors.primary),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final entry in kLureCatalog.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 0, 8),
                    child: Text(
                      entry.key.toUpperCase(),
                      style: TextStyle(
                        color: c.textMuted,
                        fontSize: 11,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: entry.value.map((name) {
                      final selected = name == value;
                      return GestureDetector(
                        onTap: () => Navigator.of(ctx).pop(name),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? ApexColors.primary
                                : c.surfaceVariant,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected ? ApexColors.primary : c.border,
                              width: selected ? 1.5 : 1,
                            ),
                          ),
                          child: Text(
                            name,
                            style: TextStyle(
                              fontSize: 13,
                              color: selected ? Colors.white : c.textSecondary,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
    if (result != null) {
      onChanged(result.isEmpty ? null : result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return InkWell(
      onTap: () => _open(context),
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: const InputDecoration(labelText: 'Köder'),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value ?? 'Köder wählen …',
                style: TextStyle(
                  color: value == null ? c.textMuted : c.textPrimary,
                ),
              ),
            ),
            Icon(Icons.arrow_drop_down, color: c.textMuted),
          ],
        ),
      ),
    );
  }
}

class _CreateSpotFromCatchHint extends StatelessWidget {
  const _CreateSpotFromCatchHint({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Material(
      color: ApexColors.primary.withAlpha(28),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: ApexColors.primary.withAlpha(50),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.add_location_alt_outlined,
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
                      'Spot aus diesem Fang anlegen',
                      style: TextStyle(
                        color: c.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Übernimmt die Fang-Position als Standort',
                      style: TextStyle(color: c.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: ApexColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Zeigt eine Reihe von Chips mit den 3 zuletzt am häufigsten verwendeten
/// Ködern. Tap füllt das Köder-Feld direkt — spart Tippen bei Routine-Setups.
class _RecentLuresChips extends ConsumerWidget {
  const _RecentLuresChips({
    required this.currentValue,
    required this.onPick,
  });

  final String currentValue;
  final void Function(String lure) onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ApexColors.of(context);
    final catches = ref.watch(catchProvider).valueOrNull ?? const <CatchEntry>[];

    // Häufigkeit der letzten ~50 Einträge zählen, leere ignorieren.
    final recent = catches.take(50);
    final counts = <String, int>{};
    for (final e in recent) {
      final l = e.lure?.trim();
      if (l == null || l.isEmpty) continue;
      counts[l] = (counts[l] ?? 0) + 1;
    }
    if (counts.isEmpty) return const SizedBox.shrink();

    final top = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final chips = top.take(3).map((e) => e.key).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final lure in chips)
            _RecentLureChip(
              label: lure,
              selected: lure == currentValue,
              color: c,
              onTap: () => onPick(lure),
            ),
        ],
      ),
    );
  }
}

class _RecentLureChip extends StatelessWidget {
  const _RecentLureChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final ApexColors color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? ApexColors.primary.withAlpha(40)
          : color.surface,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected
              ? ApexColors.primary
              : color.border,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.history,
                size: 14,
                color: selected ? ApexColors.primary : color.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? ApexColors.primary : color.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Switch zum Verbergen des Standorts. Wenn aus, werden Lat/Lng beim
/// Speichern auf null gesetzt — der Fang ist dann nicht auf der Karte
/// sichtbar und wird ohne Koordinaten geteilt.
class _PrivacyToggle extends StatelessWidget {
  const _PrivacyToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Icon(
            value ? Icons.location_on : Icons.location_off,
            color: value ? ApexColors.primary : c.textMuted,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Standort speichern',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value
                      ? 'GPS-Koordinaten werden mit dem Fang gespeichert'
                      : 'Hotspot bleibt geheim — kein GPS am Fang',
                  style: TextStyle(fontSize: 12, color: c.textMuted),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: ApexColors.primary,
          ),
        ],
      ),
    );
  }
}

/// Kombinierte Karte für die Community-Sektion: hebt sich durch
/// Primary-Akzent klar von den lokalen "Spot"-Optionen darüber ab.
/// Enthält den Haupt-Toggle (in Feed teilen) und ein eingerücktes
/// Sub-Toggle (Gewässer mit teilen), das nur erscheint, wenn der
/// Beitrag tatsächlich geteilt wird.
class _CommunityShareCard extends StatelessWidget {
  const _CommunityShareCard({
    required this.isShared,
    required this.shareWater,
    required this.hasPhoto,
    required this.onSharedChanged,
    required this.onShareWaterChanged,
  });

  final bool isShared;
  final bool shareWater;
  final bool hasPhoto;
  final ValueChanged<bool> onSharedChanged;
  final ValueChanged<bool> onShareWaterChanged;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    // Ohne hochgeladenes Foto ist ein Community-Post nicht erlaubt.
    // Der Toggle bleibt sichtbar (damit Nutzer:innen verstehen, was
    // m\u00f6glich w\u00e4re), wird aber deaktiviert und visuell ged\u00e4mpft.
    final disabled = !hasPhoto;
    final activelyShared = isShared && hasPhoto;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: activelyShared
            ? ApexColors.primary.withAlpha(20)
            : c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: activelyShared
              ? ApexColors.primary.withAlpha(120)
              : c.border,
          width: activelyShared ? 1.2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: activelyShared
                        ? ApexColors.primary.withAlpha(40)
                        : c.surface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: activelyShared
                          ? ApexColors.primary.withAlpha(160)
                          : c.border,
                    ),
                  ),
                  child: Icon(
                    disabled
                        ? Icons.no_photography_outlined
                        : (activelyShared
                            ? Icons.public
                            : Icons.lock_outline),
                    size: 18,
                    color: activelyShared
                        ? ApexColors.primary
                        : c.textMuted,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mit der Community teilen',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: disabled
                              ? c.textMuted
                              : c.textPrimary,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        disabled
                            ? 'Lade ein Foto deines Fangs hoch, um ihn zu teilen'
                            : (activelyShared
                                ? 'Andere Angler:innen sehen Foto, Art & Maße'
                                : 'Bleibt nur in deinem privaten Fangbuch'),
                        style: TextStyle(
                          fontSize: 12,
                          color: c.textMuted,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: activelyShared,
                  onChanged: disabled ? null : onSharedChanged,
                  activeThumbColor: ApexColors.primary,
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: !activelyShared
                ? const SizedBox.shrink()
                : Column(
                    children: [
                      Container(
                        height: 1,
                        color: ApexColors.primary.withAlpha(60),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                            14, 10, 14, 12),
                        child: Row(
                          children: [
                            const SizedBox(width: 4),
                            Icon(
                              shareWater
                                  ? Icons.water
                                  : Icons.water_outlined,
                              size: 18,
                              color: shareWater
                                  ? ApexColors.primary
                                  : c.textMuted,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Gewässer-Name mit teilen',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: c.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    shareWater
                                        ? 'Gewässername ist im Feed sichtbar'
                                        : 'Hotspot bleibt geheim',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: c.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch.adaptive(
                              value: shareWater,
                              onChanged: onShareWaterChanged,
                              activeThumbColor: ApexColors.primary,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

