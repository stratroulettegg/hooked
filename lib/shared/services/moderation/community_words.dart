/// Wortfilter (Client-seitige Vorprüfung). Spiegelung der Server-Liste in
/// `functions/src/community_words.ts`. Die endgültige Prüfung passiert
/// immer auf dem Server – diese Liste hier ist nur für sofortiges
/// UI-Feedback (Edit-Profil, Username-Wahl).
library;

const _rootWords = <String>[
  // Nationalsozialismus / Holocaust
  'hitler', 'naziland', 'nazideutschland', 'heilhitler', 'siegheil',
  'judenhass', 'judenhasser', 'judenfeind', 'judenmord', 'judenmoerder',
  'judensau', 'antisemit', 'holocaust', 'shoah', 'auschwitz', 'kzwaerter',
  'gaskammer', 'endloesung', 'rassenschande', 'untermensch', 'blutundboden',
  'drittesreich', 'fuehrer', 'reichsbuerger', 'weisserstolz', 'whitepower',
  'whitepride', 'kkk', 'klanmember',

  // Gewalt-/Mord-Aufrufe
  'killjews', 'killmuslims', 'killtrans', 'killgays', 'killallm', 'killallw',
  'tothomos', 'totaffen', 'gasdiejuden', 'gasthejews',

  // Slurs
  'neger', 'negerin', 'kanake', 'kanacke', 'zigeuner', 'schwuchtel',
  'schwuchteln', 'schwanzlutscher', 'transensau', 'tranny', 'faggot',
  'nigger', 'niggers', 'niglet', 'chink', 'spic', 'kike', 'kikes', 'wetback',
  'towelhead', 'sandnigger', 'retard', 'retardo', 'mongo', 'mongoloid',
  'spasti', 'spasto',

  // Sexualstraftaten
  'kinderficker', 'kinderschaender', 'paedophil', 'pedo', 'pedos',
  'pedophile', 'lolicon', 'shotacon', 'vergewaltiger', 'rapist',

  // Terror / Symbole
  'isis', 'alqaida', 'alqaeda', 'taliban', 'hamas', 'swastika', 'hakenkreuz',
  'sigrune', 'ssrune', 'totenkopf',
];

const _standaloneCodes = <String>[
  '1488', '88', '14', 'hh', 'ns', 'wp', 'hj', 'kz', 'rgs', 'afd1488',
];

const _leetMap = <String, String>{
  '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '8': 'b',
  '9': 'g', '@': 'a', r'$': 's', '!': 'i', '|': 'i',
};

String _normalize(String input) {
  var s = input.toLowerCase().trim();
  s = s
      .replaceAll('ä', 'ae')
      .replaceAll('ö', 'oe')
      .replaceAll('ü', 'ue')
      .replaceAll('ß', 'ss');
  final buf = StringBuffer();
  for (final ch in s.split('')) {
    buf.write(_leetMap[ch] ?? ch);
  }
  s = buf.toString();
  s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '');
  return s;
}

List<String> _tokenize(String input) {
  return input
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((t) => t.isNotEmpty)
      .toList();
}

/// Liefert das gefundene verbotene Wort oder `null`, wenn der Input
/// sauber ist.
String? findBannedWord(String input) {
  if (input.isEmpty) return null;
  final norm = _normalize(input);
  for (final word in _rootWords) {
    if (norm.contains(word)) return word;
  }
  final tokens = _tokenize(input);
  final leetTokens = tokens.map((t) {
    final buf = StringBuffer();
    for (final ch in t.split('')) {
      buf.write(_leetMap[ch] ?? ch);
    }
    return buf.toString();
  }).toList();
  for (final code in _standaloneCodes) {
    if (tokens.contains(code) || leetTokens.contains(code)) return code;
  }
  return null;
}

bool isClean(String input) => findBannedWord(input) == null;
