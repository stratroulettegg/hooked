import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/catch_entry.dart';
import '../../shared/models/waterbody.dart';
import '../../shared/services/app_providers.dart';
import '../../shared/widgets/apex_app_bar.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/photo_picker_field.dart';
import '../../shared/widgets/water_location_field.dart';

class AddEditWaterbodyScreen extends ConsumerStatefulWidget {
  const AddEditWaterbodyScreen({super.key, this.existing});
  final Waterbody? existing;

  @override
  ConsumerState<AddEditWaterbodyScreen> createState() =>
      _AddEditWaterbodyScreenState();
}

class _AddEditWaterbodyScreenState
    extends ConsumerState<AddEditWaterbodyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _regionCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _regulationsCtrl = TextEditingController();

  WaterbodyType _type = WaterbodyType.see;
  List<FishSpecies> _species = [];
  List<ClosedSeason> _closedSeasons = [];
  List<SpinFishingBan> _spinBans = [];
  String? _photoPath;
  double? _centerLat;
  double? _centerLng;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = e.name;
      _regionCtrl.text = e.region ?? '';
      _notesCtrl.text = e.notes ?? '';
      _regulationsCtrl.text = e.regulationsUrl ?? '';
      _type = e.type;
      _species = List.from(e.allowedSpecies);
      _closedSeasons = List.from(e.closedSeasons);
      _spinBans = List.from(e.spinBans);
      _photoPath = e.photoPath;
      _centerLat = e.centerLat;
      _centerLng = e.centerLng;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _regionCtrl.dispose();
    _notesCtrl.dispose();
    _regulationsCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_loading) return;
    _loading = true;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      _loading = false;
      if (mounted) setState(() {});
      return;
    }
    if (mounted) setState(() {});
    try {
      final id = widget.existing?.id ?? const Uuid().v4();
      // closedSeasons immer mit aktueller waterbody_id ausstatten.
      final cs = _closedSeasons
          .map((c) => c.copyWith(waterbodyId: id))
          .toList();
      final sb = _spinBans
          .map((b) => b.copyWith(waterbodyId: id))
          .toList();
      final wb = Waterbody(
        id: id,
        name: _nameCtrl.text.trim(),
        type: _type,
        region: _regionCtrl.text.trim().isEmpty
            ? null
            : _regionCtrl.text.trim(),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        regulationsUrl: _regulationsCtrl.text.trim().isEmpty
            ? null
            : _regulationsCtrl.text.trim(),
        photoPath: _photoPath,
        allowedSpecies: _species,
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
        closedSeasons: cs,
        spinBans: sb,
        centerLat: _centerLat,
        centerLng: _centerLng,
      );
      if (widget.existing != null) {
        await ref.read(waterbodyProvider.notifier).editWaterbody(wb);
      } else {
        await ref.read(waterbodyProvider.notifier).addWaterbody(wb);
      }
      if (!mounted) return;
      AppToast.success(
        context,
        widget.existing != null
            ? 'Gewässer aktualisiert'
            : 'Gewässer angelegt',
      );
      Navigator.of(context).pop(wb);
    } catch (e) {
      if (mounted) AppToast.error(context, 'Speichern fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    final id = widget.existing?.id;
    final allSpots = ref.watch(spotProvider).valueOrNull ?? const [];
    final assignedSpotMarkers = <LatLng>[
      for (final s in allSpots)
        if (id != null && s.waterbodyId == id) LatLng(s.lat, s.lng),
    ];
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
            TextFormField(
              controller: _nameCtrl,
              style: TextStyle(color: c.textPrimary),
              decoration: const InputDecoration(labelText: 'Name *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Pflichtfeld' : null,
            ),
            const SizedBox(height: 16),
            _Label('TYP'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: WaterbodyType.values.map((t) {
                final sel = _type == t;
                return GestureDetector(
                  onTap: () => setState(() => _type = t),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: sel ? c.primaryGlow : c.surfaceVariant,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: sel ? ApexColors.primary : c.border,
                        width: sel ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      t.displayName,
                      style: TextStyle(
                        fontSize: 12,
                        color: sel ? ApexColors.primary : c.textSecondary,
                        fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _regionCtrl,
              style: TextStyle(color: c.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Region / Bundesland (optional)',
                hintText: 'z. B. Bayern',
              ),
            ),
            const SizedBox(height: 20),

            _Label('STANDORT'),
            const SizedBox(height: 8),
            WaterLocationField(
              label: _centerLat != null && _centerLng != null
                  ? (_nameCtrl.text.trim().isEmpty
                        ? 'Markierte Position'
                        : _nameCtrl.text.trim())
                  : 'Position wählen',
              subLabel: _centerLat != null && _centerLng != null
                  ? '${_centerLat!.toStringAsFixed(4)}, '
                        '${_centerLng!.toStringAsFixed(4)}'
                  : 'Optional — Suche oder Karte',
              hasLocation: _centerLat != null && _centerLng != null,
              mapInitial: _centerLat != null && _centerLng != null
                  ? LatLng(_centerLat!, _centerLng!)
                  : null,
              mapTitle: 'Gewässer-Mittelpunkt',
              searchTitle: 'Gewässer suchen',
              existingSpots: assignedSpotMarkers,
              onPicked: (p) => setState(() {
                _centerLat = p.lat;
                _centerLng = p.lng;
                if (_nameCtrl.text.trim().isEmpty &&
                    (p.fullName?.isNotEmpty ?? false)) {
                  _nameCtrl.text = p.fullName!;
                }
              }),
              onClear: (_centerLat != null && _centerLng != null)
                  ? () => setState(() {
                      _centerLat = null;
                      _centerLng = null;
                    })
                  : null,
            ),
            const SizedBox(height: 20),

            _Label('FOTO'),
            const SizedBox(height: 8),
            PhotoPickerField(
              path: _photoPath,
              onChanged: (p) => setState(() => _photoPath = p),
              label: 'Gewässer-Foto',
            ),
            const SizedBox(height: 20),

            _Label('VORKOMMENDE FISCHARTEN'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: FishSpecies.values
                  .where((s) => s != FishSpecies.andere)
                  .map((s) {
                    final sel = _species.contains(s);
                    return GestureDetector(
                      onTap: () => setState(() {
                        if (sel) {
                          _species.remove(s);
                        } else {
                          _species.add(s);
                        }
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: sel ? c.primaryGlow : c.surfaceVariant,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: sel ? ApexColors.primary : c.border,
                            width: sel ? 1.5 : 1,
                          ),
                        ),
                        child: Text(
                          s.displayName,
                          style: TextStyle(
                            fontSize: 12,
                            color: sel ? ApexColors.primary : c.textSecondary,
                            fontWeight: sel
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  })
                  .toList(),
            ),
            const SizedBox(height: 20),

            _Label('SCHONZEITEN & MINDESTMASSE'),
            const SizedBox(height: 8),
            ..._closedSeasons.asMap().entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ClosedSeasonRow(
                  cs: e.value,
                  onEdit: (updated) => setState(() {
                    _closedSeasons[e.key] = updated;
                  }),
                  onRemove: () => setState(() {
                    _closedSeasons.removeAt(e.key);
                  }),
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _addClosedSeason,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Schonzeit hinzufügen'),
              style: OutlinedButton.styleFrom(
                foregroundColor: ApexColors.primary,
                side: const BorderSide(color: ApexColors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),

            _Label('SPINNFISCHVERBOTE'),
            const SizedBox(height: 8),
            ..._spinBans.asMap().entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SpinBanRow(
                  ban: e.value,
                  onEdit: (updated) => setState(() {
                    _spinBans[e.key] = updated;
                  }),
                  onRemove: () => setState(() {
                    _spinBans.removeAt(e.key);
                  }),
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _addSpinBan,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Spinnfischverbot hinzufügen'),
              style: OutlinedButton.styleFrom(
                foregroundColor: ApexColors.primary,
                side: const BorderSide(color: ApexColors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),

            _Label('REGELN / KARTE'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _regulationsCtrl,
              style: TextStyle(color: c.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Link zur Gewässerordnung (optional)',
                hintText: 'https://…',
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 20),

            _Label('NOTIZEN'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _notesCtrl,
              maxLines: 4,
              style: TextStyle(color: c.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Notizen (optional)',
                hintText:
                    'Pegel, Befahrung, Nachtangeln, Gastkarten, …',
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Future<void> _addClosedSeason() async {
    final res = await _ClosedSeasonEditor.show(context);
    if (res != null) {
      setState(() {
        _closedSeasons.add(
          res.copyWith(
            id: const Uuid().v4(),
            waterbodyId: widget.existing?.id ?? '',
          ),
        );
      });
    }
  }

  Future<void> _addSpinBan() async {
    final res = await _SpinBanEditor.show(context);
    if (res != null) {
      setState(() {
        _spinBans.add(
          res.copyWith(
            id: const Uuid().v4(),
            waterbodyId: widget.existing?.id ?? '',
          ),
        );
      });
    }
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

class _ClosedSeasonRow extends StatelessWidget {
  const _ClosedSeasonRow({
    required this.cs,
    required this.onEdit,
    required this.onRemove,
  });
  final ClosedSeason cs;
  final ValueChanged<ClosedSeason> onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return InkWell(
      onTap: () async {
        final res = await _ClosedSeasonEditor.show(context, initial: cs);
        if (res != null) onEdit(res.copyWith(id: cs.id, waterbodyId: cs.waterbodyId));
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: c.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.gavel_rounded, size: 16, color: ApexColors.scoreMid),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cs.species.displayName,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    cs.minLengthCm != null
                        ? '${cs.rangeLabel}  ·  Mindestmaß ${cs.minLengthCm!.toStringAsFixed(0)} cm'
                        : cs.rangeLabel,
                    style: TextStyle(color: c.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, size: 18, color: c.textMuted),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

class _ClosedSeasonEditor extends StatefulWidget {
  const _ClosedSeasonEditor({this.initial});
  final ClosedSeason? initial;

  static Future<ClosedSeason?> show(
    BuildContext context, {
    ClosedSeason? initial,
  }) {
    return showDialog<ClosedSeason?>(
      context: context,
      builder: (_) => _ClosedSeasonEditor(initial: initial),
    );
  }

  @override
  State<_ClosedSeasonEditor> createState() => _ClosedSeasonEditorState();
}

class _ClosedSeasonEditorState extends State<_ClosedSeasonEditor> {
  late FishSpecies _species;
  late int _fromMonth;
  late int _fromDay;
  late int _toMonth;
  late int _toDay;
  final _minLenCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _species = i?.species ?? FishSpecies.hecht;
    _fromMonth = i?.fromMonth ?? 2;
    _fromDay = i?.fromDay ?? 1;
    _toMonth = i?.toMonth ?? 4;
    _toDay = i?.toDay ?? 30;
    _minLenCtrl.text = i?.minLengthCm?.toStringAsFixed(0) ?? '';
  }

  @override
  void dispose() {
    _minLenCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return AlertDialog(
      title: const Text('Schonzeit'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<FishSpecies>(
              initialValue: _species,
              decoration: const InputDecoration(labelText: 'Art'),
              items: FishSpecies.values
                  .where((s) => s != FishSpecies.andere)
                  .map(
                    (s) => DropdownMenuItem(value: s, child: Text(s.displayName)),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _species = v ?? _species),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: 'Von',
                    month: _fromMonth,
                    day: _fromDay,
                    onPick: (m, d) => setState(() {
                      _fromMonth = m;
                      _fromDay = d;
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DateField(
                    label: 'Bis',
                    month: _toMonth,
                    day: _toDay,
                    onPick: (m, d) => setState(() {
                      _toMonth = m;
                      _toDay = d;
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _minLenCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Mindestmaß (cm, optional)',
              ),
              style: TextStyle(color: c.textPrimary),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () {
            final ml = double.tryParse(_minLenCtrl.text.replaceAll(',', '.'));
            Navigator.of(context).pop(
              ClosedSeason(
                id: widget.initial?.id ?? '',
                waterbodyId: widget.initial?.waterbodyId ?? '',
                species: _species,
                fromMonth: _fromMonth,
                fromDay: _fromDay,
                toMonth: _toMonth,
                toDay: _toDay,
                minLengthCm: ml,
              ),
            );
          },
          child: const Text('Übernehmen'),
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.month,
    required this.day,
    required this.onPick,
  });
  final String label;
  final int month;
  final int day;
  final void Function(int month, int day) onPick;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime(DateTime.now().year, month, day),
          firstDate: DateTime(DateTime.now().year, 1, 1),
          lastDate: DateTime(DateTime.now().year, 12, 31),
          helpText: 'Datum (Jahr egal)',
        );
        if (picked != null) onPick(picked.month, picked.day);
      },
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(
          '${day.toString().padLeft(2, '0')}.${month.toString().padLeft(2, '0')}',
          style: TextStyle(color: c.textPrimary, fontSize: 14),
        ),
      ),
    );
  }
}

class _SpinBanRow extends StatelessWidget {
  const _SpinBanRow({
    required this.ban,
    required this.onEdit,
    required this.onRemove,
  });
  final SpinFishingBan ban;
  final ValueChanged<SpinFishingBan> onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return InkWell(
      onTap: () async {
        final res = await _SpinBanEditor.show(context, initial: ban);
        if (res != null) {
          onEdit(res.copyWith(id: ban.id, waterbodyId: ban.waterbodyId));
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: c.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.do_not_disturb_on_outlined,
              size: 16,
              color: ApexColors.scoreLow,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ban.rangeLabel,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  if ((ban.notes ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      ban.notes!.trim(),
                      style: TextStyle(color: c.textMuted, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, size: 18, color: c.textMuted),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

class _SpinBanEditor extends StatefulWidget {
  const _SpinBanEditor({this.initial});
  final SpinFishingBan? initial;

  static Future<SpinFishingBan?> show(
    BuildContext context, {
    SpinFishingBan? initial,
  }) {
    return showDialog<SpinFishingBan?>(
      context: context,
      builder: (_) => _SpinBanEditor(initial: initial),
    );
  }

  @override
  State<_SpinBanEditor> createState() => _SpinBanEditorState();
}

class _SpinBanEditorState extends State<_SpinBanEditor> {
  late int _fromMonth;
  late int _fromDay;
  late int _toMonth;
  late int _toDay;
  late bool _yearRound;
  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _fromMonth = i?.fromMonth ?? 10;
    _fromDay = i?.fromDay ?? 1;
    _toMonth = i?.toMonth ?? 4;
    _toDay = i?.toDay ?? 30;
    _yearRound = i?.isYearRound ?? false;
    _notesCtrl.text = i?.notes ?? '';
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return AlertDialog(
      title: const Text('Spinnfischverbot'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Ganzjährig'),
              value: _yearRound,
              activeThumbColor: ApexColors.primary,
              onChanged: (v) => setState(() {
                _yearRound = v;
                if (v) {
                  _fromMonth = 1;
                  _fromDay = 1;
                  _toMonth = 12;
                  _toDay = 31;
                }
              }),
            ),
            if (!_yearRound) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: _DateField(
                      label: 'Von',
                      month: _fromMonth,
                      day: _fromDay,
                      onPick: (m, d) => setState(() {
                        _fromMonth = m;
                        _fromDay = d;
                      }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DateField(
                      label: 'Bis',
                      month: _toMonth,
                      day: _toDay,
                      onPick: (m, d) => setState(() {
                        _toMonth = m;
                        _toDay = d;
                      }),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Hinweis (optional)',
                hintText: 'z. B. Salmoniden-Schutz, Schonbezirk',
              ),
              style: TextStyle(color: c.textPrimary),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () {
            final notes = _notesCtrl.text.trim();
            Navigator.of(context).pop(
              SpinFishingBan(
                id: widget.initial?.id ?? '',
                waterbodyId: widget.initial?.waterbodyId ?? '',
                fromMonth: _fromMonth,
                fromDay: _fromDay,
                toMonth: _toMonth,
                toDay: _toDay,
                notes: notes.isEmpty ? null : notes,
              ),
            );
          },
          child: const Text('Übernehmen'),
        ),
      ],
    );
  }
}
