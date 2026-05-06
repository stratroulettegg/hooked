import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import '../../core/format/app_formats.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/fishing_spot.dart';
import '../../shared/models/trip.dart';
import '../../shared/services/app_providers.dart';
import '../../shared/widgets/apex_app_bar.dart';
import '../../shared/widgets/water_location_field.dart';
import '../spots/location_picker_screen.dart';

class AddEditTripScreen extends ConsumerStatefulWidget {
  const AddEditTripScreen({super.key, this.existing});
  final Trip? existing;

  @override
  ConsumerState<AddEditTripScreen> createState() => _AddEditTripScreenState();
}

class _AddEditTripScreenState extends ConsumerState<AddEditTripScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _waterBodyCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _checkCtrl = TextEditingController();

  DateTime? _date;
  double? _centerLat;
  double? _centerLng;
  List<_DraftStop> _stops = [];
  List<String> _checklist = [];
  bool _loading = false;

  static const _defaultChecklist = [
    'Angelschein',
    'Rute + Rolle',
    'Köder',
    'Kescher',
    'Maßband',
    'Taschenlampe',
    'Verpflegung',
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = e.name;
      _waterBodyCtrl.text = e.waterBodyName ?? '';
      _notesCtrl.text = e.notes ?? '';
      _date = e.date;
      _centerLat = e.centerLat;
      _centerLng = e.centerLng;
      _stops = e.stops
          .map(
            (s) => _DraftStop(
              id: s.id,
              name: s.name,
              lat: s.lat,
              lng: s.lng,
              spotId: s.spotId,
              notes: s.notes,
            ),
          )
          .toList();
      _checklist = List.of(e.checklist);
    } else {
      _checklist = List.of(_defaultChecklist);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _waterBodyCtrl.dispose();
    _notesCtrl.dispose();
    _checkCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _date ?? now.add(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day - 30),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _addStopFromMap() async {
    final initial = _centerLat != null && _centerLng != null
        ? LatLng(_centerLat!, _centerLng!)
        : null;
    final res = await Navigator.push<PickedLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          initialPosition: initial,
          title: 'Spot markieren',
        ),
      ),
    );
    if (res == null) return;
    final name = await _askStopName(suggested: 'Spot ${_stops.length + 1}');
    if (name == null) return;
    final position = res.position;
    setState(() {
      _stops.add(
        _DraftStop(
          id: '',
          name: name,
          lat: position.latitude,
          lng: position.longitude,
        ),
      );
      _centerLat ??= position.latitude;
      _centerLng ??= position.longitude;
    });
  }

  Future<void> _addStopFromExisting() async {
    final spots = ref.read(spotProvider).valueOrNull ?? [];
    if (spots.isEmpty) {
      _snack('Noch keine Spots angelegt');
      return;
    }
    final chosen = await showModalBottomSheet<FishingSpot>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'Aus meinen Spots',
                style: TextStyle(
                  fontFamily: 'Rajdhani',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: ApexColors.of(ctx).textPrimary,
                ),
              ),
            ),
            for (final s in spots)
              ListTile(
                leading: const Icon(
                  Icons.location_on,
                  color: ApexColors.primary,
                ),
                title: Text(s.name),
                subtitle: s.waterBodyName != null
                    ? Text(s.waterBodyName!)
                    : null,
                onTap: () => Navigator.pop(ctx, s),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) {
      setState(() {
        _stops.add(
          _DraftStop(
            id: '',
            name: chosen.name,
            lat: chosen.lat,
            lng: chosen.lng,
            spotId: chosen.id,
          ),
        );
        _centerLat ??= chosen.lat;
        _centerLng ??= chosen.lng;
      });
    }
  }

  Future<String?> _askStopName({required String suggested}) async {
    final ctrl = TextEditingController(text: suggested);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Spot-Name'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'z. B. Schilfgürtel Nord',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              FocusScope.of(ctx).unfocus();
              Navigator.pop(
                ctx,
                ctrl.text.trim().isEmpty ? suggested : ctrl.text.trim(),
              );
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;
    if (_date == null) {
      _snack('Bitte ein Datum wählen');
      return;
    }
    // Wenn kein Center gesetzt ist, Center vom ersten Stop übernehmen.
    double? lat = _centerLat;
    double? lng = _centerLng;
    if ((lat == null || lng == null) && _stops.isNotEmpty) {
      lat = _stops.first.lat;
      lng = _stops.first.lng;
    }
    if (lat == null || lng == null) {
      _snack('Bitte ein Gewässer oder mindestens einen Spot setzen');
      return;
    }
    setState(() => _loading = true);
    try {
      final existing = widget.existing;
      final trip = Trip(
        id: existing?.id ?? '',
        name: _nameCtrl.text.trim(),
        date: _date!,
        waterBodyName: _waterBodyCtrl.text.trim().isEmpty
            ? null
            : _waterBodyCtrl.text.trim(),
        centerLat: lat,
        centerLng: lng,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        checklist: _checklist,
        createdAt: existing?.createdAt ?? DateTime.now(),
        cloudTripId: existing?.cloudTripId,
        stops: [
          for (int i = 0; i < _stops.length; i++)
            TripStop(
              id: _stops[i].id.isEmpty ? const Uuid().v4() : _stops[i].id,
              tripId: existing?.id ?? '',
              name: _stops[i].name,
              lat: _stops[i].lat,
              lng: _stops[i].lng,
              spotId: _stops[i].spotId,
              orderIndex: i,
              notes: _stops[i].notes,
            ),
        ],
      );
      if (existing != null) {
        await ref.read(tripProvider.notifier).editTrip(trip);
      } else {
        await ref.read(tripProvider.notifier).addTrip(trip);
      }
      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return Scaffold(
      appBar: ApexAppBar(
        extraActions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(12),
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
                  letterSpacing: 1.2,
                ),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Trip-Name *',
                hintText: 'z. B. Frühjahrs-Hecht am Chiemsee',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Pflichtfeld' : null,
            ),
            const SizedBox(height: 14),
            // Datum
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Datum *',
                  prefixIcon: Icon(Icons.calendar_today),
                ),
                child: Text(
                  _date == null
                      ? 'Datum wählen'
                      : AppDateFormats.weekdayDateLong.format(_date!),
                  style: TextStyle(
                    color: _date == null ? c.textMuted : c.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            // Gewässer-Name (Freitext)
            TextFormField(
              controller: _waterBodyCtrl,
              decoration: const InputDecoration(
                labelText: 'Gewässer',
                hintText: 'z. B. Chiemsee',
              ),
            ),
            const SizedBox(height: 10),
            // Einheitlicher Gewässer-/Karten-Picker
            WaterLocationField(
              sectionLabel: 'POSITION',
              label: (_centerLat != null && _centerLng != null)
                  ? (_waterBodyCtrl.text.trim().isNotEmpty
                        ? _waterBodyCtrl.text.trim()
                        : 'Mittelpunkt gewählt')
                  : 'Karte oder Suche',
              subLabel: (_centerLat != null && _centerLng != null)
                  ? '${_centerLat!.toStringAsFixed(4)}, ${_centerLng!.toStringAsFixed(4)}'
                  : null,
              hasLocation: _centerLat != null && _centerLng != null,
              mapInitial: (_centerLat != null && _centerLng != null)
                  ? LatLng(_centerLat!, _centerLng!)
                  : null,
              onClear: (_centerLat != null && _centerLng != null)
                  ? () => setState(() {
                      _centerLat = null;
                      _centerLng = null;
                    })
                  : null,
              onPicked: (p) => setState(() {
                _centerLat = p.lat;
                _centerLng = p.lng;
                if (p.fullName != null && p.fullName!.isNotEmpty) {
                  _waterBodyCtrl.text = p.fullName!;
                  _waterBodyCtrl.selection = TextSelection.collapsed(
                    offset: _waterBodyCtrl.text.length,
                  );
                }
              }),
            ),
            const SizedBox(height: 20),
            // Stops
            Row(
              children: [
                Text(
                  'SPOTS (${_stops.length})',
                  style: TextStyle(
                    fontFamily: 'Rajdhani',
                    fontSize: 12,
                    letterSpacing: 1.8,
                    fontWeight: FontWeight.w700,
                    color: c.textMuted,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addStopFromExisting,
                  icon: const Icon(Icons.bookmark_border, size: 18),
                  label: const Text('Aus Spots'),
                ),
                TextButton.icon(
                  onPressed: _addStopFromMap,
                  icon: const Icon(Icons.add_location_alt, size: 18),
                  label: const Text('Neu'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (_stops.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.border),
                ),
                child: Text(
                  'Noch keine Spots – füge Punkte hinzu, die du auf dem Trip abfahren willst.',
                  style: TextStyle(color: c.textSecondary, fontSize: 13),
                ),
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: _stops.length,
                onReorder: (oldI, newI) {
                  setState(() {
                    if (newI > oldI) newI--;
                    final item = _stops.removeAt(oldI);
                    _stops.insert(newI, item);
                  });
                },
                itemBuilder: (_, i) {
                  final s = _stops[i];
                  return Container(
                    key: ValueKey('stop_$i${s.lat}_${s.lng}'),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.border),
                    ),
                    child: Row(
                      children: [
                        ReorderableDragStartListener(
                          index: i,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              Icons.drag_indicator,
                              color: c.textMuted,
                            ),
                          ),
                        ),
                        Container(
                          width: 26,
                          height: 26,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: ApexColors.primary.withAlpha(36),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: ApexColors.primary.withAlpha(80),
                            ),
                          ),
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                              fontFamily: 'Rajdhani',
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: ApexColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: c.textPrimary,
                                ),
                              ),
                              Text(
                                '${s.lat.toStringAsFixed(4)}, ${s.lng.toStringAsFixed(4)}${s.spotId != null ? ' · eigener Spot' : ''}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: c.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(() => _stops.removeAt(i)),
                          icon: Icon(
                            Icons.close,
                            color: c.textSecondary,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            const SizedBox(height: 20),
            // Checkliste
            Text(
              'PACKLISTE',
              style: TextStyle(
                fontFamily: 'Rajdhani',
                fontSize: 12,
                letterSpacing: 1.8,
                fontWeight: FontWeight.w700,
                color: c.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            ..._checklist.asMap().entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_box_outline_blank,
                      size: 18,
                      color: c.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e.value,
                        style: TextStyle(color: c.textPrimary),
                      ),
                    ),
                    IconButton(
                      onPressed: () =>
                          setState(() => _checklist.removeAt(e.key)),
                      icon: Icon(Icons.close, size: 18, color: c.textMuted),
                    ),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _checkCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Eintrag hinzufügen',
                      isDense: true,
                    ),
                    onSubmitted: (v) {
                      final txt = v.trim();
                      if (txt.isEmpty) return;
                      setState(() {
                        _checklist.add(txt);
                        _checkCtrl.clear();
                      });
                    },
                  ),
                ),
                IconButton(
                  onPressed: () {
                    final txt = _checkCtrl.text.trim();
                    if (txt.isEmpty) return;
                    setState(() {
                      _checklist.add(txt);
                      _checkCtrl.clear();
                    });
                  },
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notizen',
                hintText: 'Taktik, Köder-Plan, Treffpunkt …',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DraftStop {
  String id;
  String name;
  double lat;
  double lng;
  String? spotId;
  String? notes;
  _DraftStop({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    this.spotId,
    this.notes,
  });
}
