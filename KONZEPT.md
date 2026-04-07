# Haken Dran – App-Konzept
### Prüfungsvorbereitung für die Angelprüfung in Deutschland

---

## 1. Vision & Positionierung

**„Haken Dran"** ist eine mobile Lern-App, die angehende Angler in Deutschland spielerisch und effektiv auf die Angelprüfung vorbereitet. Der Name ist bewusst doppeldeutig: *Haken* steht für den Angelhaken, *Haken Dran* für das Abhaken von Lernzielen und erfolgreich bestandenen Aufgaben.

**Zielgruppe:**
- Erstbewerber für den Fischereischein (Jugendliche & Erwachsene)
- Wiederholungsbewerber
- Neueinsteiger, die mit dem Angeln beginnen möchten

**Plattformen:** iOS (iPhone/iPad) & Android – **beide Plattformen sind Pflicht**, kein iOS-only oder Android-only
**Technologie:** Flutter (empfohlen) für eine einzige Codebasis, die nativ auf beiden Plattformen läuft

---

## 2. Regulatorische Grundlage

### 2.1 Bundeslandspezifische Prüfungen

In Deutschland ist das Fischereirecht Ländersache. Die Angelprüfung (offiziell: Fischerprüfung) unterscheidet sich je nach Bundesland erheblich – sowohl in Fragenkatalog, Themengewichtung als auch in den Zulassungsvoraussetzungen.

| Bundesland | Prüfungsumfang | Gerätekunde | Praktischer Anteil |
|---|---|---|---|
| **Brandenburg** ⭐ MVP | Schriftlich, kompakter Katalog (LFV Brandenburg), Angeln unter 14 ohne Schein erlaubt | ✗ | ✗ |
| **Mecklenburg-Vorpommern** ⭐ MVP | Schriftlich, einer der kürzesten Kataloge bundesweit | ✗ | ✗ |
| **Sachsen-Anhalt** ⭐ MVP | Schriftlich, überschaubarer Katalog (LAVF), klar strukturiert | ✗ | ✗ |
| Thüringen | Schriftlich, ähnlich Brandenburg | ✗ | ✗ |
| Niedersachsen | Schriftlich, mittlerer Umfang | ✗ | ✗ |
| Nordrhein-Westfalen | Nur schriftlich, 60 Fragen aus offiziellem Katalog | Teilweise | ✗ |
| Bayern | Schriftlich + praktisch, umfangreichster Katalog (LFV Bayern) | ✓ | ✓ |
| Baden-Württemberg | Schriftlich + praktisch, LFVBW-Katalog | ✓ | ✓ |
| Sachsen | Eigener Katalog, Junganglerschein ab 10 Jahren | Teilweise | ✗ |
| Hamburg/Berlin | Stadtstaaten mit eigenen Regelungen und Verbänden | ✗ | ✗ |
| ... | (alle 16 Bundesländer werden abgedeckt) | | |

### 2.2 Gemeinsame Themenbereiche (bundeslandübergreifend)

Auch wenn Fragenkataloge variieren, sind diese Kernthemen nahezu überall prüfungsrelevant:

1. **Fischkunde** – Arten, Anatomie, Laichzeiten, Schonmaße, Schonzeiten *(alle Bundesländer)*
2. **Gewässerkunde & Ökologie** – Gewässertypen, Wasserqualität, Nahrungsketten *(alle Bundesländer)*
3. **Tierschutz & Waidgerechtigkeit** – Betäuben, Töten, Catch & Release-Regelungen *(alle Bundesländer)*
4. **Fischereirecht** – Lizenzen, Erlaubnisscheine, Verbote, Strafvorschriften *(alle Bundesländer)*
5. **Naturschutz** – Schutzgebiete, Artenschutz, invasive Arten *(alle Bundesländer)*
6. **Gerätekunde** – Ruten, Rollen, Schnüre, Haken, Köder *(nur Bayern, BW, NRW und weitere – **nicht** in MVP-Bundesländern)*

### 2.3 Datenpflege & Aktualität

- Regulatorische Änderungen (z. B. neue Schonmaße, geänderte Prüfungsordnungen) werden redaktionell betreut.
- Ein **Content-Update-System** ermöglicht das Einspielen neuer Fragenkataloge ohne App-Update (Over-the-Air-Content via Backend-API).
- Quellen: Offizielle Landesfischereiverbände, Landesgesetze, Bundesjagdgesetz analoge Fischereigesetze.

---

## 3. Kernfunktionen

### 3.1 Bundesland-Auswahl & Personalisierung

- Beim Onboarding wählt der Nutzer sein **Bundesland**.
- Der Fragenpool wird entsprechend gefiltert: bundeslandspezifische Pflichtfragen + bundesweiter Kernkatalog.
- Profilwechsel möglich (z. B. für Umzug oder Prüfung in anderem Bundesland).

### 3.2 Lernmodi

#### Karteikarten-Modus
- Klassisches Frage-Antwort-Prinzip mit Aufdecken der Antwort.
- Nutzer bewertet selbst: „Gewusst" / „Nicht gewusst" (Leitner-System).

#### Prüfungssimulation
- Originalgetreue Nachbildung der Prüfungssituation je Bundesland.
- Zeitlimit entsprechend der realen Prüfungszeit.
- Auswertung mit Bestanden/Nicht bestanden, Prozentsatz, Fehlerübersicht.

#### Schwächentraining
- KI-gestützte Analyse der häufigsten Fehler.
- Automatische Zusammenstellung eines personalisierten Übungssets aus Schwachstellen.

#### Blitzrunde
- Kurze 5-Minuten-Sessions für unterwegs.
- 10 Zufallsfragen, schnell und spielerisch.

### 3.3 Fischlexikon

- Illustriertes Nachschlagewerk aller prüfungsrelevanten Fischarten.
- Erkennungsmerkmale, Schonmaße, Schonzeiten – bundeslandspezifisch angezeigt.
- Offline verfügbar.

### 3.4 Regelwerk-Bibliothek

- Komprimierte, verständlich formulierte Zusammenfassungen der wichtigsten Fischereigesetze je Bundesland.
- Kein juristisches Kauderwelsch – klare Sprache für Einsteiger.

---

## 4. Gamification-System

### 4.1 Erfahrungspunkte (EP) & Level

Jede Aktion bringt EP:

| Aktion | EP |
|---|---|
| Frage richtig beantwortet | +10 EP |
| Prüfungssimulation bestanden | +150 EP |
| Tagesziel erreicht | +50 EP |
| Makel-freie Runde (10/10) | +75 EP Bonus |
| Erste Anmeldung des Tages | +20 EP (Streak) |

Level-System mit angelthematischen Titeln:
- Lvl 1–5: **Wurmwerfer**
- Lvl 6–10: **Spinner**
- Lvl 11–20: **Petri-Jünger**
- Lvl 21–35: **Kescher-König**
- Lvl 36–50: **Meisterangler**
- Lvl 50+: **Legende am Wasser**

### 4.2 Streak-System

- Tägliches Lernen wird durch eine **Angelserie** (Streak) belohnt.
- Visualisierung: stilisierte Angelschnur, die sich durch den Kalender zieht.
- **Streak-Schutz**: Einmal pro Monat kann ein versäumter Tag nachgeholt werden.
- Meilensteine: 7 Tage, 30 Tage, 100 Tage mit Sonder-Badges.

### 4.3 Achievements & Abzeichen

Kategorien:

**Wissensabzeichen**
- „Fischflüsterer" – Alle Fischarten im Lexikon geöffnet
- „Gesetzeshüter" – Alle Kapitel im Regelwerk gelesen
- „Spezialist [Bundesland]" – 100% Trefferquote im BL-spezifischen Set

**Ausdauer-Abzeichen**
- „Frühaufsteher" – 7x vor 8 Uhr gelernt
- „Nachteule" – 7x nach 22 Uhr gelernt
- „Marathonangler" – 500 Fragen in einer Woche beantwortet

**Skill-Abzeichen**
- „Makellos" – Prüfungssimulation mit 100% abgeschlossen
- „Blitzangler" – 10 Blitzrunden in Folge ohne Fehler
- „Comeback-Kid" – Nach 3 Fehlversuchen bestanden

### 4.4 Ranglisten (Leaderboards)

- **Regionale Rangliste**: Vergleich mit Nutzern aus demselben Bundesland.
- **Globale Rangliste**: Deutschlandweiter Vergleich.
- **Freundes-Rangliste**: Duell-Modus mit Freunden (via App-Link oder QR-Code).
- Wöchentlicher Reset der Wochen-Rangliste; Allzeit-Liste bleibt bestehen.

### 4.5 Duell-Modus

- Zwei Spieler treten gegeneinander an: gleiche 10 Fragen, wer schneller & richtiger ist, gewinnt.
- Einladung per Link, Code oder Bluetooth (lokales Duell).
- Sieger erhält Bonus-EP, Verlierer bekommt „Aufholpaket" (personalisierte Wiederholungsfragen).

### 4.6 Saisonale Events & Herausforderungen

- **Wochenchallenge**: z. B. „Diese Woche 200 Fragen zur Fischkunde beantworten".
- **Saisonale Events**: z. B. Forellen-Saison-Event (März/April) mit thematischen Fragen und Sonder-Badges.
- Limitierte Abzeichen für Event-Teilnahme.

### 4.7 Virtuelle Trophäen & Angelpokale

- Virtuelle Pokalvitrine im Nutzerprofil.
- Pokale für besondere Leistungen: Erste bestandene Prüfungssimulation, erster Platz in der Rangliste etc.
- Teilbare Trophäen-Karten für Social Media (PNG-Export).

---

## 5. Onboarding

1. **Begrüßungsscreen** mit App-Maskottchen (z. B. animierter Hecht „Hektor")
2. **Bundesland-Auswahl** mit Kartenvisualisierung Deutschlands
3. **Lernziel-Festlegung**: Wann soll die Prüfung stattfinden? (Datum eingeben)
4. **Tägliches Lernziel**: 5 / 10 / 20 Minuten täglich – frei wählbar
5. **Kurzdiagnose-Quiz**: 5 Fragen → App ermittelt Ausgangsniveau
6. **Erster EP-Boost** für abgeschlossenes Onboarding (Motivation)

---

## 6. UX/UI-Design-Prinzipien

- **Farbpalette**: Naturnahe Töne – tiefes Waldgrün, Wasserblau, warmes Braun, helles Sandbeige.
- **Typographie**: Klare, gut lesbare Schrift; Überschriften mit leichtem Outdoor-Charakter.
- **Icons & Illustrationen**: Handgezeichneter Stil, Fisch- und Natursymbole.
- **Dark Mode**: Vollständig unterstützt (wichtig für Abendlerner).
- **Barrierefreiheit**: Mindestschriftgröße, ausreichende Kontraste, VoiceOver/TalkBack-Unterstützung.
- **Micro-Animations**: Fisch springt bei richtig beantworteter Frage, Wellen-Animation bei Fortschritt.

---

## 7. Technische Architektur (Übersicht)

### Cross-Platform-Anforderung

> **Non-verhandelbar:** Die App muss nativ auf **iOS (iPhone & iPad, ab iOS 16)** und **Android (ab Android 10 / API 29)** laufen – mit identischem Funktionsumfang auf beiden Plattformen.

**Gewählte Technologie: Flutter (Dart)**
- Eine einzige Codebasis, zwei native Apps
- Native Performance durch eigene Rendering-Engine (Skia/Impeller)
- Starkes Ökosystem für Offline-Fähigkeit, Animationen und Store-Publishing
- Kein WebView – echte native UI-Komponenten
- App Store (Apple) und Google Play Store: gleichzeitiger Launch beider Plattformen

```
┌─────────────────────────────────────────────────┐
│                  Mobile App                      │
│       Flutter (iOS & Android – eine Codebasis)   │
│  ┌──────────┐  ┌──────────┐  ┌────────────────┐ │
│  │  Lernmodul│  │Gamification│  │ Offline-Cache │ │
│  └──────────┘  └──────────┘  └────────────────┘ │
└───────────────────┬─────────────────────────────┘
                    │ Firebase SDK (FlutterFire)
┌───────────────────▼─────────────────────────────┐
│              Google Firebase                     │
│         (Region: europe-west3, Frankfurt)        │
│  ┌──────────┐  ┌──────────┐  ┌────────────────┐ │
│  │  Auth    │  │Firestore │  │Cloud Functions │ │
│  └──────────┘  └──────────┘  └────────────────┘ │
│  ┌──────────┐  ┌──────────┐  ┌────────────────┐ │
│  │  Storage │  │   FCM    │  │ Remote Config  │ │
│  └──────────┘  └──────────┘  └────────────────┘ │
└─────────────────────────────────────────────────┘
```

**Firebase-Dienste im Überblick:**

| Dienst | Verwendung |
|---|---|
| **Firebase Authentication** | E-Mail/Passwort, Google Sign-In, Apple Sign-In, anonymer Gastzugang |
| **Cloud Firestore** | Nutzerdaten, Lernfortschritt, Achievements, Ranglisten, Duell-Sessions |
| **Firebase Realtime Database** | Echtzeit-Duell-Ergebnisse (niedrige Latenz) |
| **Cloud Storage** | Bilder für Fischlexikon, Badges, Avatare, Fragenkatalog-JSON |
| **Cloud Functions** | XP-Vergabe, Achievement-Trigger, Leaderboard-Reset, Receipt Validation |
| **Remote Config** | Feature-Flags, Freemium-Gates, Katalog-Versioning (OTA) |
| **FCM** | Push-Benachrichtigungen (Streak, Achievements, Updates) |
| **Firebase Analytics** | Nutzerverhalten, Funnel-Analyse, Retention |
| **Firebase App Check** | Schutz vor API-Missbrauch |

### Content-Management
- Fragenkataloge werden als JSON in **Cloud Storage** versioniert abgelegt.
- **Remote Config** steuert, welche Katalogversion aktiv ist → OTA-Update ohne App-Store-Release.
- Redaktionelle Pflege über Firebase Console + eigenes Admin-Skript.

### Offline-Fähigkeit
- Vollständiger Fragenkatalog & Lexikon lokal gecacht.
- Lernfortschritt wird offline gespeichert und beim nächsten Online-Gang synchronisiert.

---

## 8. Datenschutz & Compliance

- **DSGVO-konform**: Datenminimierung, explizite Einwilligung, Auskunfts- und Löschrecht.
- Kein Pflicht-Account für den Basisbetrieb (Gastzugang möglich, kein Cloud-Sync).
- Account für Gamification-Features (Ranglisten, Duell) erforderlich – mit klarer Kommunikation warum.
- Daten werden ausschließlich auf Servern in der EU gehostet (Firebase Region: `europe-west3` Frankfurt).
- Kinder unter 16: KOPA-konformes Flow, keine personalisierten Daten ohne elterliche Einwilligung.

---

## 9. Monetarisierung

### Freemium-Modell

| Feature | Kostenlos | Premium (Haken Dran+) |
|---|---|---|
| Fragenkatalog (begrenzt) | 100 Fragen/Monat | Unbegrenzt |
| Prüfungssimulation | 1x pro Woche | Unbegrenzt |
| Schwächentraining | ✗ | ✓ |
| Alle Bundesländer | ✗ | ✓ |
| Duell-Modus | 3x pro Woche | Unbegrenzt |
| Offline-Modus | ✗ | ✓ |
| Werbefrei | ✗ | ✓ |

**Preismodell Premium:**
- Monatlich: 4,99 €
- Jährlich: 34,99 € (≈ 2,92 €/Monat)
- Einmalkauf (Lifetime): 59,99 €

### Weitere Einnahmen
- **Angelshop-Kooperationen**: Nicht-invasive, thematisch passende Partnerwerbung (z. B. Gutscheine).
- **Verband-Lizenzen**: Fischereiverbände können die App für Kursmitglieder lizenzieren (B2B).

---

## 10. Roadmap

### Phase 1 – MVP (Monat 1–3)
- [ ] 3 Piloten-Bundesländer: **Brandenburg, Mecklenburg-Vorpommern, Sachsen-Anhalt** (einfachste Prüfungen, kein Gerätekunde-Themenblock)
- [ ] Karteikarten- & Prüfungssimulations-Modus
- [ ] Grundlegendes Gamification: EP, Level, Streak
- [ ] Fischlexikon (offline)
- [ ] iOS & Android Launch

### Phase 2 – Ausbau (Monat 4–6)
- [ ] Alle 16 Bundesländer
- [ ] Duell-Modus
- [ ] Achievements & Ranglisten
- [ ] CMS für Content-Redaktion

### Phase 3 – Community & Erweiterung (Monat 7–12)
- [ ] Saisonale Events
- [ ] Freundes-Rangliste
- [ ] Vereins-/Verbands-Accounts (B2B)
- [ ] Erweiterung: Bootsführerschein-Modul (optional)

---

## 11. Erfolgsmessung (KPIs)

| KPI | Ziel (12 Monate) |
|---|---|
| Downloads | 50.000 |
| DAU (Daily Active Users) | 8.000 |
| Conversion Free → Premium | 12 % |
| Durchschnittliche Session-Dauer | > 8 Minuten |
| 7-Tage-Retention | > 45 % |
| App Store Rating | ≥ 4,5 Sterne |
| Bestandene Prüfungssimulationen | > 70 % der aktiven Nutzer |

---

## 12. Alleinstellungsmerkmale (USPs)

1. **Bundesland-Spezifität** – Keine andere App bietet diesen Detailgrad an regionaler Anpassung.
2. **Gamification mit Angler-Identität** – Kein generisches Quiz-Design, sondern eine Welt, in der man sich als Angler zuhause fühlt.
3. **Offline-First** – Lernen am See, im Wald, überall – auch ohne Internet.
4. **Aktuelle Inhalte** – Content-Updates unabhängig von App-Store-Releases.
5. **Community-Aspekt** – Duell-Modus und Ranglisten schaffen soziale Motivation.

---

*Konzeptstand: April 2026 | Version 1.0*
