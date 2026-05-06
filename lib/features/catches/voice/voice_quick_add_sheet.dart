import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:uuid/uuid.dart';

import '../../../core/format/app_formats.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/catch_entry.dart';
import '../../../shared/services/app_providers.dart';
import 'voice_catch_parser.dart';

/// Voice-Quick-Add für Fänge — Look-and-feel einer Sprachnachricht.
class VoiceQuickAddSheet extends ConsumerStatefulWidget {
  const VoiceQuickAddSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: true,
      builder: (_) => const Padding(
        padding: EdgeInsets.only(bottom: 0),
        child: VoiceQuickAddSheet(),
      ),
    );
  }

  @override
  ConsumerState<VoiceQuickAddSheet> createState() =>
      _VoiceQuickAddSheetState();
}

enum _Stage { ready, listening, parsed, error, denied }

class _VoiceQuickAddSheetState extends ConsumerState<VoiceQuickAddSheet> {
  late final stt.SpeechToText _speech;
  _Stage _stage = _Stage.ready;
  String _transcript = '';
  ParsedVoiceCatch? _parsed;
  String? _errorMessage;
  double _level = 0; // 0..1
  Timer? _autoStopTimer;
  Timer? _hintTimer;
  bool _showHint = false;

  // Silent GPS-Hintergrund-Erfassung während des Sprechens. Kein Permission-
  // Prompt — nur nutzen, wenn die App bereits autorisiert ist.
  Future<Position?>? _locationFuture;
  Position? _capturedPosition;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
  }

  @override
  void dispose() {
    _autoStopTimer?.cancel();
    _hintTimer?.cancel();
    if (_speech.isListening) {
      _speech.stop();
    }
    super.dispose();
  }

  Future<void> _startListening() async {
    setState(() {
      _transcript = '';
      _parsed = null;
      _errorMessage = null;
      _capturedPosition = null;
      _showHint = false;
    });
    _hintTimer?.cancel();
    _hintTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      // Nur einblenden, wenn nach 8 s noch nichts Sinnvolles erkannt wurde.
      if (_stage == _Stage.listening && _transcript.trim().length < 4) {
        setState(() => _showHint = true);
      }
    });

    // Stille GPS-Erfassung parallel zum Mic starten — ohne Permission-Prompt.
    _locationFuture = _captureLocationSilently()
      ..then((pos) {
        if (mounted) _capturedPosition = pos;
      }).catchError((_) {});

    final available = await _speech.initialize(
      onStatus: (status) {
        // status: 'listening', 'notListening', 'done'
        if (status == 'done' || status == 'notListening') {
          if (_stage == _Stage.listening && mounted) {
            _onListeningEnded();
          }
        }
      },
      onError: (err) {
        if (!mounted) return;
        setState(() {
          _stage = _Stage.error;
          _errorMessage = err.errorMsg;
        });
      },
    );

    if (!available) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.denied;
        _errorMessage =
            'Mikrofon- oder Spracherkennung wurde nicht freigegeben.';
      });
      return;
    }

    setState(() => _stage = _Stage.listening);

    await _speech.listen(
      localeId: 'de_DE',
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.dictation,
      ),
      onResult: (SpeechRecognitionResult r) {
        if (!mounted) return;
        setState(() => _transcript = r.recognizedWords);
      },
      onSoundLevelChange: (l) {
        if (!mounted) return;
        // Werte sind grob -2..10 (dB-artig). Auf 0..1 normieren.
        final norm = ((l + 2) / 12).clamp(0.0, 1.0);
        setState(() => _level = norm);
      },
    );

    // Sicherheits-Auto-Stop nach 30 s.
    _autoStopTimer?.cancel();
    _autoStopTimer = Timer(const Duration(seconds: 30), () {
      if (_speech.isListening) _stopListening();
    });
  }

  Future<void> _stopListening() async {
    _autoStopTimer?.cancel();
    await _speech.stop();
    _onListeningEnded();
  }

  Future<void> _cancelListening() async {
    _autoStopTimer?.cancel();
    await _speech.cancel();
    if (!mounted) return;
    setState(() {
      _stage = _Stage.ready;
      _transcript = '';
      _parsed = null;
    });
  }

  void _onListeningEnded() {
    if (!mounted) return;
    _hintTimer?.cancel();
    if (_transcript.trim().isEmpty) {
      setState(() => _stage = _Stage.ready);
      return;
    }
    final parsed = VoiceCatchParser.parse(_transcript);
    // Erfolgs-Haptik, wenn wir mindestens eine Spezies oder eine Zahl
    // erkannt haben — sonst dezenter Selection-Click.
    final hasUseful = parsed.species != null ||
        parsed.lengthCm != null ||
        parsed.weightG != null;
    HapticFeedback.mediumImpact();
    if (!hasUseful) {
      // Zusätzlich kurzer Selection-Click signalisiert „aber unklar".
      HapticFeedback.selectionClick();
    }
    setState(() {
      _parsed = parsed;
      _stage = _Stage.parsed;
      _showHint = false;
    });
  }

  /// GPS still im Hintergrund holen — nur wenn Permission bereits da ist,
  /// sonst null. Wirft nicht, blockiert nichts.
  Future<Position?> _captureLocationSilently() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null; // BEWUSST kein requestPermission — keinen Prompt mitten im Mic.
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

  CatchEntry _buildPrefillEntry(ParsedVoiceCatch p) {
    final pos = _capturedPosition;
    return CatchEntry(
      id: const Uuid().v4(),
      species: p.species ?? FishSpecies.hecht,
      weightG: p.weightG,
      lengthCm: p.lengthCm,
      caughtAt: DateTime.now(),
      retrieveStyles: const [],
      lat: pos?.latitude,
      lng: pos?.longitude,
      notes: p.transcript.isNotEmpty
          ? 'Per Sprache erfasst: "${p.transcript}"'
          : null,
    );
  }

  Future<void> _onAddPhotoAndDetails() async {
    final p = _parsed;
    if (p == null) return;
    // Auf bereits laufendes GPS warten — max. ein paar Hundert ms.
    await _awaitLocationBriefly();
    if (!mounted) return;
    final entry = _buildPrefillEntry(p);
    Navigator.pop(context);
    // Kleiner Delay, damit der Sheet-Pop sauber durchläuft.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    context.push('/catches/add', extra: entry);
  }

  Future<void> _onSaveDirect() async {
    final p = _parsed;
    if (p == null) return;
    await _awaitLocationBriefly();
    final entry = _buildPrefillEntry(p);
    await ref.read(catchProvider.notifier).addCatch(entry);
    if (!mounted) return;
    Navigator.pop(context);
  }

  /// Wartet kurz auf die laufende GPS-Anfrage — aber nie mehr als 600 ms,
  /// um den Confirm-Tap nicht spürbar zu verzögern.
  Future<void> _awaitLocationBriefly() async {
    final f = _locationFuture;
    if (f == null || _capturedPosition != null) return;
    try {
      _capturedPosition = await f.timeout(const Duration(milliseconds: 600));
    } catch (_) {
      // Timeout oder Fehler: einfach ohne Position weiter.
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ApexColors.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
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
                  'SPRACH-SCHNELLFANG',
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
                  _hintForStage(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: c.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                _buildStageContent(c),
                const SizedBox(height: 14),
                _buildActions(c),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _hintForStage() {
    switch (_stage) {
      case _Stage.ready:
        return 'Tippe das Mikrofon und sage z. B.\n„Hecht, 93 Zentimeter, 1350 Gramm".';
      case _Stage.listening:
        return 'Ich höre zu …';
      case _Stage.parsed:
        return 'Erkannt — passt das?';
      case _Stage.error:
        return _errorMessage ?? 'Da ist etwas schiefgelaufen.';
      case _Stage.denied:
        return _errorMessage ??
            'Mikrofon-Berechtigung fehlt. Bitte in den Einstellungen erlauben.';
    }
  }

  Widget _buildStageContent(ApexColors c) {
    switch (_stage) {
      case _Stage.ready:
        return _MicButton(
          listening: false,
          onTap: _startListening,
        );
      case _Stage.listening:
        return Column(
          children: [
            _Waveform(
              level: _level,
              listening: true,
              transcriptLength: _transcript.length,
            ),
            const SizedBox(height: 12),
            _LiveTranscript(text: _transcript, color: c.textPrimary),
            if (_showHint) ...[
              const SizedBox(height: 14),
              _SpeakingHint(color: c),
            ],
          ],
        );
      case _Stage.parsed:
        return _ParsedSummary(
          parsed: _parsed!,
          color: c,
          hasLocation: _capturedPosition != null,
        );
      case _Stage.error:
      case _Stage.denied:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Icon(
            Icons.mic_off,
            size: 48,
            color: c.textMuted,
          ),
        );
    }
  }

  Widget _buildActions(ApexColors c) {
    switch (_stage) {
      case _Stage.ready:
        return TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        );
      case _Stage.listening:
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton.icon(
              onPressed: _cancelListening,
              icon: const Icon(Icons.close),
              label: const Text('Abbrechen'),
            ),
            FilledButton.icon(
              onPressed: _stopListening,
              style: FilledButton.styleFrom(
                backgroundColor: ApexColors.primary,
                foregroundColor: Colors.black,
              ),
              icon: const Icon(Icons.stop),
              label: const Text('Fertig'),
            ),
          ],
        );
      case _Stage.parsed:
        final p = _parsed!;
        final canSave = p.hasAnyField;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: canSave ? _onAddPhotoAndDetails : null,
              style: FilledButton.styleFrom(
                backgroundColor: ApexColors.primary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text(
                'FOTO & DETAILS ERGÄNZEN',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: canSave ? _onSaveDirect : null,
              icon: const Icon(Icons.bolt),
              label: const Text('DIREKT SPEICHERN'),
              style: OutlinedButton.styleFrom(
                foregroundColor: c.textPrimary,
                side: BorderSide(color: c.border),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () {
                setState(() {
                  _stage = _Stage.ready;
                  _transcript = '';
                  _parsed = null;
                });
              },
              child: const Text('Nochmal aufnehmen'),
            ),
          ],
        );
      case _Stage.error:
      case _Stage.denied:
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Schließen'),
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  _stage = _Stage.ready;
                  _errorMessage = null;
                });
              },
              child: const Text('Erneut versuchen'),
            ),
          ],
        );
    }
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({required this.listening, required this.onTap});
  final bool listening;
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
                  ApexColors.primary,
                  ApexColors.primary.withAlpha(180),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: ApexColors.primary.withAlpha(140),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(Icons.mic, color: Colors.black, size: 44),
          ),
        ),
      ),
    );
  }
}

class _Waveform extends StatefulWidget {
  const _Waveform({
    required this.level,
    required this.listening,
    required this.transcriptLength,
  });

  /// Aktueller Pegel 0..1 (von speech_to_text geliefert).
  final double level;

  /// Ob aktiv aufgenommen wird — steuert den synthetischen Heartbeat,
  /// damit die Balken auch ohne brauchbaren Pegel sichtbar leben.
  final bool listening;

  /// Länge des bisher erkannten Transcripts — Änderung erzeugt einen Spike.
  final int transcriptLength;

  @override
  State<_Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<_Waveform>
    with SingleTickerProviderStateMixin {
  static const int _barCount = 40;

  // Rolling-Buffer mit den letzten Pegelwerten — neueste rechts.
  final List<double> _bars = List<double>.filled(_barCount, 0);

  // Geglätteter Live-Pegel, damit die Balken nicht ruckeln.
  double _smoothed = 0;

  // Aktivität basierend auf Zeit seit letzter Transcript-Änderung.
  // Klingt sanft ab, sodass Pausen sichtbar werden.
  double _activity = 0;
  int _lastTranscriptLength = 0;
  double _lastTranscriptChangeMs = 0;

  late final Ticker _ticker;
  Duration _lastShift = Duration.zero;

  // Pseudo-Zufalls-Jitter pro Index, damit unbenutzte Balken nicht alle gleich
  // hoch sind, wenn der Pegel kurz konstant ist.
  final List<double> _jitter = List<double>.generate(
    _barCount,
    (i) => 0.7 + math.Random(i * 31 + 7).nextDouble() * 0.3,
  );

  final math.Random _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(covariant _Waveform old) {
    super.didUpdateWidget(old);
    // Jede neue Silbe → Aktivität hochziehen, Zeitstempel aktualisieren.
    if (widget.transcriptLength != _lastTranscriptLength) {
      final delta = (widget.transcriptLength - _lastTranscriptLength).abs();
      _activity = math.min(1.0, _activity + 0.4 + delta * 0.03);
      _lastTranscriptChangeMs =
          DateTime.now().millisecondsSinceEpoch.toDouble();
      _lastTranscriptLength = widget.transcriptLength;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final tSec = elapsed.inMicroseconds / 1e6;
    final nowMs = DateTime.now().millisecondsSinceEpoch.toDouble();

    // 1) Aktivität klingt ab, sobald keine neuen Transcript-Zeichen kommen.
    //    Nach ~1.5 s Pause sind wir wieder bei ~0.
    final msSinceChange = nowMs - _lastTranscriptChangeMs;
    if (msSinceChange > 1500) {
      _activity *= 0.88;
    } else {
      _activity *= 0.96;
    }
    if (_activity < 0.01) _activity = 0;

    // 2) Idle-Atmer (sehr leise!) nur wenn Listening und absolute Stille —
    //    damit der Balken nicht tot wirkt.
    final idle = widget.listening && _activity < 0.05
        ? 0.04 + 0.04 * (0.5 + 0.5 * math.sin(tSec * 4.2))
        : 0.0;

    // 3) Echten Mic-Pegel sanft ziehen (auf iOS oft 0).
    final target = widget.level.clamp(0.0, 1.0);
    final isRising = target > _smoothed;
    final factor = isRising ? 0.45 : 0.18;
    _smoothed = _smoothed + (target - _smoothed) * factor;

    // Gesamt-Energie: maximaler von echtem Pegel, Aktivität und Idle-Atmer.
    final energy = math.max(_smoothed, math.max(_activity, idle));

    // 4) Alle ~50 ms einen neuen Balken nach rechts schieben.
    if (elapsed - _lastShift >= const Duration(milliseconds: 50)) {
      _lastShift = elapsed;
      // Mikro-Variation gewichtet mit Energie — hohe Energie → starke
      // Variation, niedrige Energie → ruhig.
      final micro = 0.5 + _rng.nextDouble() * (0.5 + energy * 1.0);
      final value = (energy * micro).clamp(0.0, 1.0);
      for (int i = 0; i < _barCount - 1; i++) {
        _bars[i] = _bars[i + 1];
      }
      _bars[_barCount - 1] = value;
    }

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: CustomPaint(
        size: const Size(double.infinity, 64),
        painter: _WaveformPainter(bars: _bars, jitter: _jitter),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({required this.bars, required this.jitter});
  final List<double> bars;
  final List<double> jitter;

  @override
  void paint(Canvas canvas, Size size) {
    final barCount = bars.length;
    const gap = 4.0;
    final barWidth = (size.width - gap * (barCount - 1)) / barCount;
    final cy = size.height / 2;
    final maxH = size.height * 0.92;

    final paintActive = Paint()..color = ApexColors.primary;
    final paintIdle = Paint()
      ..color = ApexColors.primary.withAlpha(70);

    for (int i = 0; i < barCount; i++) {
      final v = bars[i];
      // Sockel-Höhe + Jitter, damit auch in Ruhe leichte Wellen sichtbar sind.
      final h = math.max(barWidth, maxH * (0.06 + 0.94 * v) * jitter[i]);
      final x = i * (barWidth + gap);
      final rect = Rect.fromLTWH(x, cy - h / 2, barWidth, h);
      // Balken mit Pegel > Schwelle in voller Farbe, sonst gedimmt.
      final paint = v > 0.05 ? paintActive : paintIdle;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(barWidth / 2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) => true;
}

class _LiveTranscript extends StatelessWidget {
  const _LiveTranscript({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        text.isEmpty ? '…' : text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 16,
          color: color,
          height: 1.3,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _ParsedSummary extends StatelessWidget {
  const _ParsedSummary({
    required this.parsed,
    required this.color,
    required this.hasLocation,
  });
  final ParsedVoiceCatch parsed;
  final ApexColors color;
  final bool hasLocation;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    if (parsed.species != null) {
      chips.add(_chip(
        '${parsed.species!.emoji}  ${parsed.species!.displayName}',
        bg: ApexColors.primary,
        fg: Colors.black,
      ));
    }
    if (parsed.lengthCm != null) {
      chips.add(_chip(
        AppNum.cm(parsed.lengthCm!),
        bg: color.surface,
        fg: color.textPrimary,
        border: color.border,
      ));
    }
    if (parsed.weightG != null) {
      final w = parsed.weightG!;
      chips.add(_chip(
        AppNum.kg(w),
        bg: color.surface,
        fg: color.textPrimary,
        border: color.border,
      ));
    }
    if (hasLocation) {
      chips.add(_chip(
        '📍 Standort',
        bg: color.surface,
        fg: color.textPrimary,
        border: color.border,
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (chips.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Keine Werte erkannt — du kannst die Aufnahme wiederholen oder '
              'manuell weitermachen.',
              textAlign: TextAlign.center,
              style: TextStyle(color: color.textMuted, fontSize: 13),
            ),
          )
        else
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: chips,
          ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.border),
          ),
          child: Text(
            '„${parsed.transcript}"',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontStyle: FontStyle.italic,
              fontSize: 13,
              color: color.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(String text,
      {required Color bg, required Color fg, Color? border}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: border != null ? Border.all(color: border) : null,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Rajdhani',
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: fg,
        ),
      ),
    );
  }
}

/// Hilfe-Hint, eingeblendet wenn nach 8 s noch nichts verstanden wurde.
class _SpeakingHint extends StatelessWidget {
  const _SpeakingHint({required this.color});
  final ApexColors color;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: 1,
      duration: const Duration(milliseconds: 250),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: ApexColors.primary.withAlpha(30),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ApexColors.primary.withAlpha(80)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lightbulb_outline,
                color: ApexColors.primary, size: 18),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'Versuch z. B.: „Hecht, 90, ein Komma drei Kilo"',
                style: TextStyle(
                  color: color.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
