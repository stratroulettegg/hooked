import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/models/catch_entry.dart';
import '../../../shared/services/app_paths.dart';
import '../../../shared/services/firebase/fish_suggestion_service.dart';

/// KI-gestützter Schnellfang — Flow: Foto → Analyse → Formular.
///
/// Sieht aus wie [VoiceQuickAddSheet]: gleiches Layout, gleiche Buttons.
class AiQuickAddSheet extends StatefulWidget {
  const AiQuickAddSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: true,
      builder: (_) => const Padding(
        padding: EdgeInsets.only(bottom: 0),
        child: AiQuickAddSheet(),
      ),
    );
  }

  @override
  State<AiQuickAddSheet> createState() => _AiQuickAddSheetState();
}

enum _Stage { ready, analysing, done, error }

class _AiQuickAddSheetState extends State<AiQuickAddSheet> {
  _Stage _stage = _Stage.ready;
  String? _savedPhotoPath; // relativer Dateiname im App-Photos-Ordner
  FishSuggestion? _suggestion;
  String? _errorMessage;

  final _service = FishSuggestionService();
  final _picker = ImagePicker();

  Future<Position?>? _locationFuture;
  Position? _capturedPosition;

  Future<void> _pickAndAnalyse(ImageSource source) async {
    try {
      final img = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
      if (img == null) return;

      // Foto dauerhaft speichern (gleiche Logik wie PhotoPickerField).
      final ext = p.extension(img.path).isNotEmpty ? p.extension(img.path) : '.jpg';
      final fileName = '${const Uuid().v4()}$ext';
      final dest = p.join(AppPaths.photos, fileName);
      await File(img.path).copy(dest);

      if (!mounted) return;
      HapticFeedback.lightImpact();
      setState(() {
        _savedPhotoPath = fileName;
        _stage = _Stage.analysing;
        _suggestion = null;
        _errorMessage = null;
      });

      // GPS still im Hintergrund.
      _locationFuture = _captureLocationSilently()
        ..then((pos) {
          if (mounted) _capturedPosition = pos;
        }).catchError((_) {});

      final file = File(dest);
      final result = await _service.suggestFromFile(file);

      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _suggestion = result;
        _stage = _Stage.done;
      });
    } catch (e) {
      if (!mounted) return;
      String msg;
      if (e is FirebaseFunctionsException) {
        msg = switch (e.code) {
          'unauthenticated' => 'Bitte zuerst einloggen.',
          'invalid-argument' => 'Bild konnte nicht verarbeitet werden.',
          'not-found' => 'KI-Funktion nicht erreichbar.',
          'resource-exhausted' => 'Tages-Limit erreicht. Morgen wieder!',
          _ => e.message ?? e.toString(),
        };
      } else {
        msg = e.toString();
      }
      setState(() {
        _stage = _Stage.error;
        _errorMessage = msg;
      });
    }
  }

  Future<Position?> _captureLocationSilently() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _awaitLocationBriefly() async {
    final f = _locationFuture;
    if (f == null || _capturedPosition != null) return;
    try {
      _capturedPosition =
          await f.timeout(const Duration(milliseconds: 600));
    } catch (_) {}
  }

  CatchEntry _buildPrefillEntry() {
    final pos = _capturedPosition;
    final s = _suggestion?.species;
    return CatchEntry(
      id: const Uuid().v4(),
      species: s ?? FishSpecies.hecht,
      caughtAt: DateTime.now(),
      retrieveStyles: const [],
      photoPath: _savedPhotoPath,
      lat: pos?.latitude,
      lng: pos?.longitude,
    );
  }

  Future<void> _onOpenForm() async {
    await _awaitLocationBriefly();
    if (!mounted) return;
    final entry = _buildPrefillEntry();
    Navigator.pop(context);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    context.push('/catches/add', extra: entry);
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: c.border, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Handle
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
                const SizedBox(height: 14),
                Text(
                  'KI-SCHNELLFANG',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Rajdhani',
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: c.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _subtitle(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: c.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                _buildContent(c),
                const SizedBox(height: 14),
                _buildActions(c),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _subtitle() {
    switch (_stage) {
      case _Stage.ready:
        return 'Mach ein Foto vom Fisch – die KI\nerkennt die Art automatisch.';
      case _Stage.analysing:
        return 'Analyse läuft …';
      case _Stage.done:
        final s = _suggestion?.species;
        if (s == null || s == FishSpecies.andere) {
          return 'Kein Fisch eindeutig erkannt –\ndu kannst die Art manuell wählen.';
        }
        return 'Erkannt – passt das?';
      case _Stage.error:
        return _errorMessage ?? 'Da ist etwas schiefgelaufen.';
    }
  }

  Widget _buildContent(ApexColors c) {
    switch (_stage) {
      case _Stage.ready:
        return _CameraButton(onTap: () => _pickAndAnalyse(ImageSource.camera));
      case _Stage.analysing:
        return const _PulsingAiIcon();
      case _Stage.done:
        return _ResultCard(
          photoPath: _savedPhotoPath,
          suggestion: _suggestion,
          colors: c,
        );
      case _Stage.error:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Icon(Icons.broken_image_outlined, size: 48, color: c.textMuted),
        );
    }
  }

  Widget _buildActions(ApexColors c) {
    switch (_stage) {
      case _Stage.ready:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: () => _pickAndAnalyse(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('AUS GALERIE WÄHLEN'),
              style: OutlinedButton.styleFrom(
                foregroundColor: c.textPrimary,
                side: BorderSide(color: c.border),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen'),
            ),
          ],
        );
      case _Stage.analysing:
        return TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        );
      case _Stage.done:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: _onOpenForm,
              style: FilledButton.styleFrom(
                backgroundColor: ApexColors.strike,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.edit_outlined),
              label: const Text(
                'DETAILS ERGÄNZEN & SPEICHERN',
                style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.0),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                setState(() {
                  _stage = _Stage.ready;
                  _savedPhotoPath = null;
                  _suggestion = null;
                  _capturedPosition = null;
                  _locationFuture = null;
                });
              },
              child: const Text('Nochmal fotografieren'),
            ),
          ],
        );
      case _Stage.error:
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Schließen'),
            ),
            FilledButton(
              onPressed: () => setState(() {
                _stage = _Stage.ready;
                _errorMessage = null;
              }),
              child: const Text('Erneut versuchen'),
            ),
          ],
        );
    }
  }
}

// ── Sub-Widgets ─────────────────────────────────────────────────────────────

class _CameraButton extends StatelessWidget {
  const _CameraButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  ApexColors.strike,
                  ApexColors.strike.withAlpha(180),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: ApexColors.strike.withAlpha(120),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(Icons.photo_camera, color: Colors.white, size: 44),
          ),
        ),
      ),
    );
  }
}

/// Pulsierende KI-Animation während der Analyse.
class _PulsingAiIcon extends StatefulWidget {
  const _PulsingAiIcon();

  @override
  State<_PulsingAiIcon> createState() => _PulsingAiIconState();
}

class _PulsingAiIconState extends State<_PulsingAiIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    _glow = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Äußerer Glow-Ring
              for (int i = 0; i < 3; i++)
                Transform.scale(
                  scale: 1.0 + i * 0.25 + _ctrl.value * 0.15,
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: ApexColors.strike.withAlpha(
                          ((1.0 - i * 0.3) * _glow.value * 80).toInt(),
                        ),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              // Icon
              Transform.scale(
                scale: _scale.value,
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ApexColors.strike,
                    boxShadow: [
                      BoxShadow(
                        color: ApexColors.strike
                            .withAlpha((_glow.value * 160).toInt()),
                        blurRadius: 28,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: Colors.white,
                    size: 44,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Ergebniskarte mit Vorschau-Foto + erkannter Art.
class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.photoPath,
    required this.suggestion,
    required this.colors,
  });

  final String? photoPath;
  final FishSuggestion? suggestion;
  final ApexColors colors;

  @override
  Widget build(BuildContext context) {
    final file = AppPaths.photoFile(photoPath);
    final species = suggestion?.species;

    return Column(
      children: [
        // Foto-Vorschau
        if (file != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(
              file,
              height: 160,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
        const SizedBox(height: 16),
        // Ergebnis-Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: species != null && species != FishSpecies.andere
                ? ApexColors.strike.withAlpha(25)
                : colors.surfaceVariant,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: species != null && species != FishSpecies.andere
                  ? ApexColors.strike.withAlpha(80)
                  : colors.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                species?.emoji ?? '🎣',
                style: const TextStyle(fontSize: 28),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    species != null
                        ? species.displayName
                        : 'Unbekannt',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: colors.textPrimary,
                    ),
                  ),
                  if (species != null && species != FishSpecies.andere) ...[
                    const SizedBox(height: 2),
                    Text(
                      'KI-Vorschlag · editierbar',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Winkel-Hilfe — unused jetzt, trotzdem als Referenz:
// extension _Angles on double { double get toRad => this * pi / 180; }
