/**
 * Wortfilter für Display-Names, Handles und Steckbriefe.
 *
 * Defense-in-Depth:
 * - Client zeigt Hinweis vorab (siehe `lib/shared/services/moderation/community_words.dart`).
 * - Cloud Function `claimHandle` prüft beim Reservieren.
 * - Trigger `onUserProfileWritten` bereinigt nachträglich (z. B. Display-Name).
 *
 * Die Liste deckt absichtlich nur grob die schlimmsten DACH/EN-Begriffe ab
 * (Nazi-/Holocaust-Bezug, Slurs, Gewaltaufrufe, Sexualstraftaten). Sie ist
 * nicht vollständig und ersetzt keine menschliche Moderation, sondern hebt
 * nur die offensichtlichsten Fälle.
 *
 * Strategie:
 * - Tokens werden gegen normalisierten Text matched (lower, ohne Sonder-
 *   zeichen, Leetspeak-Mapping wie 1→i, 3→e, 0→o, 4→a, $→s, @→a).
 * - "Whole-Word"-Tokens (Standard) werden nur an Wortgrenzen erkannt, damit
 *   "scunthorpe" nicht fälschlich blockiert wird.
 * - Codes wie `1488`, `88`, `wp` matchen nur als ganzes Wort (separate
 *   Liste `STANDALONE_CODES`).
 */

// Wortstämme (Substring-Match nach Normalisierung). Beim Bauen achten:
// LOWER-CASE, keine Umlaute (oe/ae/ue), keine Sonderzeichen.
const ROOT_WORDS: readonly string[] = [
  // Nationalsozialismus / Holocaust
  "hitler",
  "naziland",
  "nazideutschland",
  "heilhitler",
  "siegheil",
  "judenhass",
  "judenhasser",
  "judenfeind",
  "judenmord",
  "judenmoerder",
  "judensau",
  "antisemit",
  "holocaust",
  "shoah",
  "auschwitz",
  "kzwaerter",
  "gaskammer",
  "endloesung",
  "rassenschande",
  "untermensch",
  "blutundboden",
  "drittesreich",
  "fuehrer",
  "reichsbuerger",
  "weisserstolz",
  "whitepower",
  "whitepride",
  "kkk",
  "klanmember",

  // Gewalt-/Mord-Aufrufe
  "killjews",
  "killmuslims",
  "killtrans",
  "killgays",
  "killallm",
  "killallw",
  "tothomos",
  "totaffen",
  "gasdiejuden",
  "gasthejews",

  // Slurs (DE/EN, Auswahl)
  "neger",
  "negerin",
  "kanake",
  "kanacke",
  "zigeuner",
  "schwuchtel",
  "schwuchteln",
  "schwanzlutscher",
  "transensau",
  "tranny",
  "faggot",
  "nigger",
  "niggers",
  "niglet",
  "chink",
  "spic",
  "kike",
  "kikes",
  "wetback",
  "towelhead",
  "sandnigger",
  "retard",
  "retardo",
  "mongo",
  "mongoloid",
  "spasti",
  "spasto",

  // Sexualstraftaten / Kinderschänder
  "kinderficker",
  "kinderschaender",
  "paedophil",
  "pedo",
  "pedos",
  "pedophile",
  "lolicon",
  "shotacon",
  "vergewaltiger",
  "rapist",

  // Terrororganisationen / Symbole
  "isis",
  "alqaida",
  "alqaeda",
  "taliban",
  "hamas",
  "swastika",
  "hakenkreuz",
  "sigrune",
  "ssrune",
  "totenkopf",
] as const;

// Codes, die nur als ganzes Token blockiert werden sollen (sonst zu viele
// false positives).
const STANDALONE_CODES: readonly string[] = [
  "1488",
  "88", // "Heil Hitler"
  "14",
  "hh", // "Heil Hitler"
  "ns", // "Nationalsozialismus"
  "wp", // "White Power"
  "hj", // "Hitlerjugend"
  "kz", // Konzentrationslager
  "rgs", // "Rasse, Glaube, Sippe"
  "afd1488",
] as const;

const LEET_MAP: Record<string, string> = {
  "0": "o",
  "1": "i",
  "3": "e",
  "4": "a",
  "5": "s",
  "7": "t",
  "8": "b",
  "9": "g",
  "@": "a",
  "$": "s",
  "!": "i",
  "|": "i",
};

function normalize(input: string): string {
  let s = input.toLowerCase().trim();
  // Umlaute / scharfes S
  s = s
    .replace(/ä/g, "ae")
    .replace(/ö/g, "oe")
    .replace(/ü/g, "ue")
    .replace(/ß/g, "ss");
  // Leetspeak
  s = s
    .split("")
    .map((ch) => LEET_MAP[ch] ?? ch)
    .join("");
  // Alles außer a-z, 0-9 wegwerfen → bleibt nur Konsonanten/Buchstaben.
  // Damit fallen auch . _ - / Leerzeichen weg, sodass "h_i_t_l_e_r"
  // erkannt wird.
  s = s.replace(/[^a-z0-9]+/g, "");
  return s;
}

function tokenize(input: string): string[] {
  return input
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter((t) => t.length > 0);
}

/**
 * Liefert das verbotene Wort, das im Input gefunden wurde – oder null,
 * wenn der Input sauber ist.
 */
export function findBannedWord(input: string): string | null {
  if (!input) return null;

  // Substring-Check auf normalisiertem Text.
  const norm = normalize(input);
  for (const word of ROOT_WORDS) {
    if (norm.includes(word)) return word;
  }

  // Standalone-Codes: nur als ganzes Token (z. B. " 88 " aber nicht "1988").
  // Hier Leet ebenfalls mappen, aber ohne das Token zu mergen.
  const tokens = tokenize(input);
  const leetTokens = tokens.map((t) =>
    t
      .split("")
      .map((ch) => LEET_MAP[ch] ?? ch)
      .join(""),
  );
  for (const code of STANDALONE_CODES) {
    if (tokens.includes(code) || leetTokens.includes(code)) return code;
  }

  return null;
}

export function isClean(input: string): boolean {
  return findBannedWord(input) === null;
}
