import '../../../shared/models/catch_entry.dart';

/// Ergebnis eines Sprach-Parses für einen Schnell-Fang.
class ParsedVoiceCatch {
  const ParsedVoiceCatch({
    required this.transcript,
    this.species,
    this.lengthCm,
    this.weightG,
    this.notes,
  });

  final String transcript;
  final FishSpecies? species;
  final double? lengthCm;
  final int? weightG;

  /// Optionaler Resttext, der nicht erkannt werden konnte (kann später als
  /// Notiz gespeichert werden).
  final String? notes;

  bool get hasAnyField =>
      species != null || lengthCm != null || weightG != null;
}

/// Pure-Dart Parser für deutsche Sprach-Eingaben wie
/// „Hecht, 93 Zentimeter, 1350 Gramm".
///
/// Erkennt:
/// - Art (inkl. einiger Synonyme)
/// - Länge in cm/m
/// - Gewicht in g/kg/Pfund
class VoiceCatchParser {
  static const Map<String, FishSpecies> _speciesAliases = {
    'hecht': FishSpecies.hecht,
    'hechte': FishSpecies.hecht,
    'esox': FishSpecies.hecht,
    'zander': FishSpecies.zander,
    'sander': FishSpecies.zander,
    'schill': FishSpecies.zander,
    'fogosch': FishSpecies.zander,
    'barsch': FishSpecies.barsch,
    'barsche': FishSpecies.barsch,
    'flussbarsch': FishSpecies.barsch,
    'kretzer': FishSpecies.barsch,
    'wels': FishSpecies.wels,
    'waller': FishSpecies.wels,
    'schaiden': FishSpecies.wels,
    'forelle': FishSpecies.forelle,
    'forellen': FishSpecies.forelle,
    'bachforelle': FishSpecies.forelle,
    'regenbogenforelle': FishSpecies.forelle,
    'huchen': FishSpecies.huchen,
    'donaulachs': FishSpecies.huchen,
    'aal': FishSpecies.aal,
    'aale': FishSpecies.aal,
  };

  /// Parst rohen Sprach-Transcript-Text.
  static ParsedVoiceCatch parse(String raw) {
    final transcript = raw.trim();
    if (transcript.isEmpty) {
      return ParsedVoiceCatch(transcript: transcript);
    }
    // Wir suchen Art im Original-Lowertext, Zahlen aber im normalisierten,
    // damit „drei Kilo" → „3 Kilo" wird.
    final lower = transcript.toLowerCase();
    final normalized = _normalizeNumbers(lower);

    final species = _findSpecies(lower);
    final lengthCm =
        _findLengthCm(normalized) ?? _findImplicitLengthCm(normalized);
    final weightG = _findWeightG(normalized);

    return ParsedVoiceCatch(
      transcript: transcript,
      species: species,
      lengthCm: lengthCm,
      weightG: weightG,
    );
  }

  // ─── Deutsche Zahlwörter → Ziffern ─────────────────────────────────────────

  static const Map<String, String> _numberWords = {
    'null': '0',
    'ein': '1',
    'eins': '1',
    'eine': '1',
    'einen': '1',
    'einem': '1',
    'einer': '1',
    'zwei': '2',
    'zwo': '2',
    'drei': '3',
    'vier': '4',
    'fünf': '5',
    'fuenf': '5',
    'sechs': '6',
    'sieben': '7',
    'acht': '8',
    'neun': '9',
    'zehn': '10',
    'elf': '11',
    'zwölf': '12',
    'zwoelf': '12',
    'dreizehn': '13',
    'vierzehn': '14',
    'fünfzehn': '15',
    'fuenfzehn': '15',
    'sechzehn': '16',
    'siebzehn': '17',
    'achtzehn': '18',
    'neunzehn': '19',
    'zwanzig': '20',
    'dreißig': '30',
    'dreissig': '30',
    'vierzig': '40',
    'fünfzig': '50',
    'fuenfzig': '50',
    'sechzig': '60',
    'siebzig': '70',
    'achtzig': '80',
    'neunzig': '90',
    'hundert': '100',
    'einhundert': '100',
    'zweihundert': '200',
    // Angler-Slang: „zwanziger / dreißiger / … / hunderter" → reine Zahl.
    // „neunziger Hecht" = 90 cm Hecht.
    'zwanziger': '20',
    'dreißiger': '30',
    'dreissiger': '30',
    'vierziger': '40',
    'fünfziger': '50',
    'fuenfziger': '50',
    'sechziger': '60',
    'siebziger': '70',
    'achtziger': '80',
    'neunziger': '90',
    'hunderter': '100',
    'einhunderter': '100',
    'hundertzehner': '110',
    'hundertzwanziger': '120',
    'hundertdreißiger': '130',
    'hundertdreissiger': '130',
    'hundertvierziger': '140',
    'hundertfünfziger': '150',
    'hundertfuenfziger': '150',
    // Halb-Begriffe für Kilo: 1,5 / 2,5 / 0,5
    'anderthalb': '1.5',
    'eineinhalb': '1.5',
    'zweieinhalb': '2.5',
    'dreieinhalb': '3.5',
    'viereinhalb': '4.5',
    'fünfeinhalb': '5.5',
    'fuenfeinhalb': '5.5',
    'ein halbes': '0.5',
    'ein halber': '0.5',
    'ein halb': '0.5',
  };

  /// Ersetzt deutsche Zahlwörter durch Ziffern, damit „drei Kilo" und
  /// „ein Kilo" matchbar werden.
  static String _normalizeNumbers(String text) {
    var t = text;

    // 1) Mehrwort-Patterns zuerst (z. B. „ein halbes").
    final multiWord = _numberWords.keys.where((k) => k.contains(' ')).toList();
    for (final phrase in multiWord) {
      t = t.replaceAll(
        RegExp('\\b${RegExp.escape(phrase)}\\b'),
        _numberWords[phrase]!,
      );
    }

    // 2) Einzelne Wort-Tokens — als Inline-Replacement, damit Whitespaces
    //    und Satzzeichen exakt erhalten bleiben (Dart's String.split mit
    //    Capture-Group behält die Separatoren NICHT, das hatten wir vorher).
    t = t.replaceAllMapped(RegExp(r'[a-zäöüß]+', caseSensitive: false), (m) {
      final word = m.group(0)!.toLowerCase();
      final repl = _numberWords[word];
      return repl ?? m.group(0)!;
    });

    return t;
  }

  static FishSpecies? _findSpecies(String text) {
    // Wort-für-Wort suchen, damit „barschartig" nicht auf „barsch" matcht.
    final words = text
        .replaceAll(RegExp(r'[^a-zäöüß0-9 ]+', caseSensitive: false), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty);
    for (final w in words) {
      final hit = _speciesAliases[w];
      if (hit != null) return hit;
    }
    return null;
  }

  /// Sucht eine Längenangabe in cm. Akzeptiert „93 cm", „93 Zentimeter",
  /// „1,2 m", „1.2 Meter" → in cm umgerechnet.
  static double? _findLengthCm(String text) {
    // Eventuelle Ordinal-/Plural-Suffixe nach Zahl entfernen:
    // „90er Zentimeter" → „90 Zentimeter".
    final cleaned = text.replaceAllMapped(
      RegExp(r'(\d)\s*er(n|s)?\b'),
      (m) => m.group(1)!,
    );

    final reCm = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*(?:cm|centimeter|zentimeter|sentimeter|santimeter)\b',
      caseSensitive: false,
    );
    final reMeter = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*(?:m|meter)\b',
      caseSensitive: false,
    );

    final cmMatch = reCm.firstMatch(cleaned);
    if (cmMatch != null) {
      final v = _toDouble(cmMatch.group(1));
      if (v != null) return v;
    }
    final mMatch = reMeter.firstMatch(cleaned);
    if (mMatch != null) {
      final v = _toDouble(mMatch.group(1));
      if (v != null) return v * 100.0;
    }
    return null;
  }

  /// Sucht eine Gewichtsangabe in Gramm. Akzeptiert „1350 g", „1350 Gramm",
  /// „1,35 kg", „1.35 Kilo[gramm]", „3 Pfund" (1 Pfund = 500 g).
  static int? _findWeightG(String text) {
    final cleaned = text.replaceAllMapped(
      RegExp(r'(\d)\s*er(n|s)?\b'),
      (m) => m.group(1)!,
    );

    final reKg = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*(?:kg|kilo(?:gramm)?s?)\b',
      caseSensitive: false,
    );
    final rePfund = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*pfund\b',
      caseSensitive: false,
    );
    final reG = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*(?:g|gramm)\b',
      caseSensitive: false,
    );

    final kgMatch = reKg.firstMatch(cleaned);
    if (kgMatch != null) {
      final v = _toDouble(kgMatch.group(1));
      if (v != null) return (v * 1000).round();
    }
    final pfundMatch = rePfund.firstMatch(cleaned);
    if (pfundMatch != null) {
      final v = _toDouble(pfundMatch.group(1));
      if (v != null) return (v * 500).round();
    }
    final gMatch = reG.firstMatch(cleaned);
    if (gMatch != null) {
      final v = _toDouble(gMatch.group(1));
      if (v != null) return v.round();
    }
    return null;
  }

  static double? _toDouble(String? s) {
    if (s == null) return null;
    return double.tryParse(s.replaceAll(',', '.'));
  }

  /// Fallback: findet eine „freie" Zahl im plausiblen cm-Bereich (20–250),
  /// die nicht direkt vor einer Gewichtseinheit (kg/g/pfund) steht. Damit
  /// werden Sprechweisen wie „Neunziger Hecht" → 90, „Hecht 110, 1,3 Kilo"
  /// → 110 cm korrekt erfasst.
  static double? _findImplicitLengthCm(String normalized) {
    // „Xer"-Suffix nach Zahl entfernen: „90er" → „90", „110er" → „110".
    final cleaned = normalized.replaceAllMapped(
      RegExp(r'(\d)\s*er(n|s)?\b'),
      (m) => m.group(1)!,
    );
    final reNumber = RegExp(r'(\d+(?:[.,]\d+)?)([^\d]*)');
    for (final m in reNumber.allMatches(cleaned)) {
      final v = _toDouble(m.group(1));
      if (v == null) continue;
      // Was kommt direkt nach der Zahl? Erste paar Nicht-Ziffern-Zeichen.
      final tail = (m.group(2) ?? '').toLowerCase();
      // Wenn direkt eine Gewichts- oder explizite Längen-Einheit folgt,
      // überlassen wir das den expliziten Parsern.
      if (RegExp(
        r'^\s*(?:kg|kilo|gramm|\bg\b|pfund|cm|centimeter|zentimeter|sentimeter|santimeter|m\b|meter)',
      ).hasMatch(tail)) {
        continue;
      }
      // Plausibler Längenbereich für Süßwasserfische in cm.
      if (v >= 20 && v <= 250 && v.truncateToDouble() == v) {
        return v;
      }
    }
    return null;
  }
}
