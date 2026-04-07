# Haken Dran – Entwicklungs-Checkliste

> Arbeitsliste für die Programmierung. Punkte werden beim Abarbeiten abgehakt.
> Reihenfolge entspricht der empfohlenen Bearbeitungsreihenfolge.

---

## 0. Projektsetup

- [ ] Flutter-Projekt initialisieren (`flutter create haken_dran`)
- [ ] Ordnerstruktur anlegen (features/, core/, data/, shared/)
- [ ] Git-Repository einrichten, `.gitignore` für Flutter konfigurieren
- [ ] Linting & Formatting einrichten (`flutter_lints`, `dart format`)
- [ ] CI/CD-Pipeline aufsetzen (GitHub Actions: Build-Check iOS & Android)
- [ ] Flavor-Konfiguration: `dev`, `staging`, `production`
- [ ] Abhängigkeiten (pubspec.yaml) definieren und installieren:
  - [ ] `riverpod` / `bloc` (State Management)
  - [ ] `go_router` (Navigation)
  - [ ] `hive` / `isar` (lokale Offline-Datenbank)
  - [ ] `flutter_localizations` (i18n, DE)
  - [ ] `shared_preferences` (User-Einstellungen)
  - [ ] `firebase_core`
  - [ ] `firebase_auth`
  - [ ] `cloud_firestore`
  - [ ] `firebase_storage`
  - [ ] `cloud_functions`
  - [ ] `firebase_messaging`
  - [ ] `firebase_remote_config`
  - [ ] `firebase_analytics`
  - [ ] `firebase_app_check`

---

## 1. Firebase-Setup & Datenmodell

- [ ] Firebase-Projekt in der Konsole anlegen, Region `europe-west3` (Frankfurt) wählen
- [ ] FlutterFire CLI einrichten (`flutterfire configure`)
- [ ] `google-services.json` (Android) & `GoogleService-Info.plist` (iOS) einbinden
- [ ] Firebase-Dienste aktivieren:
  - [ ] Authentication (E-Mail/Passwort, Google, Apple, Anonym)
  - [ ] Cloud Firestore (Produktionsmodus, Region EU)
  - [ ] Firebase Realtime Database (für Duell-Echtzeit)
  - [ ] Cloud Storage
  - [ ] Cloud Functions (Node.js 20 Runtime)
  - [ ] Remote Config
  - [ ] Firebase Cloud Messaging (FCM)
  - [ ] Firebase Analytics
  - [ ] Firebase App Check (DeviceCheck iOS / Play Integrity Android)
- [ ] Firestore-Datenstruktur (Collections) entwerfen:
  - [ ] `questions/{id}` (text, options, correct_answer, category, bundesland, difficulty)
  - [ ] `users/{uid}` (email, bundesland, xp, level, streak, last_active)
  - [ ] `user_progress/{uid}/answers/{question_id}` (correct_count, wrong_count, last_seen)
  - [ ] `achievements/{id}` (title, description, condition, badge_icon)
  - [ ] `user_achievements/{uid}/{achievement_id}` (unlocked_at)
  - [ ] `events/{id}` (title, start_date, end_date, question_ids)
  - [ ] `duels/{id}` (player1_uid, player2_uid, questions, answers, status)
- [ ] Firestore Security Rules definieren (nur auth. Nutzer, kein Fremdzugriff)
- [ ] Firestore Indexes anlegen (bundesland-Filter, Leaderboard-Sortierung nach XP)
- [ ] Cloud Functions implementieren:
  - [ ] `onAnswerSubmit` – XP vergeben, Achievement-Trigger prüfen
  - [ ] `onDuelComplete` – Sieger ermitteln, XP verteilen
  - [ ] `weeklyLeaderboardReset` – Scheduled Function (jeden Montag 00:00 CET)
  - [ ] `validateReceipt` – In-App-Purchase Verifizierung (Apple + Google)
  - [ ] `onUserCreate` – Initialdaten anlegen (XP=0, Level=1, Streak=0)
- [ ] Remote Config parametrisieren: `catalog_version`, `feature_duel_enabled`, `premium_enabled`
- [ ] Fragenkatalog als JSON in Cloud Storage hochladen (versioniert)
- [ ] Firebase Emulator Suite lokal einrichten (Auth, Firestore, Functions, Storage)

---

## 2. Fragenkatalog & Content

- [ ] Fragenkatalog Brandenburg beschaffen und strukturieren (LFV Brandenburg, JSON/CSV)
- [ ] Fragenkatalog Mecklenburg-Vorpommern beschaffen und strukturieren
- [ ] Fragenkatalog Sachsen-Anhalt beschaffen und strukturieren (LAVF)
- [ ] Fragenkataloge restliche 13 Bundesländer beschaffen (Phase 2, inkl. Bayern, NRW, BW mit Gerätekunde)
- [ ] Fragen in Datenbank importieren (Seed-Skript)
- [ ] Fragen nach Kategorien taggen (Fischkunde, Recht, Ökologie, …)
- [ ] Bundesland-Zuordnung je Frage pflegen (BL-spezifisch oder allgemein)
- [ ] Schonmaße & Schonzeiten je Bundesland als separaten Datensatz anlegen
- [ ] Fischlexikon-Einträge erstellen (Artname, Merkmale, Bild, Schonmaß, Schonzeit)

---

## 3. Onboarding

- [ ] Splash Screen (App-Logo, Ladeanimation)
- [ ] Begrüßungsscreen mit Maskottchen „Hektor"
- [ ] Bundesland-Auswahl (Karte Deutschlands, tippbar)
- [ ] Prüfungsdatum-Eingabe (optional, für Countdown)
- [ ] Tägliches Lernziel auswählen (5 / 10 / 20 Min.)
- [ ] Kurzdiagnose-Quiz (5 Startfragen → Ausgangsniveau ermitteln)
- [ ] Erster XP-Boost nach abgeschlossenem Onboarding
- [ ] Onboarding-Status persistent speichern (kein erneutes Anzeigen)

---

## 4. Lernmodi

### 4.1 Karteikarten-Modus
- [ ] Frage-Karte mit Aufdecken-Animation
- [ ] Bewertungsbuttons „Gewusst" / „Nicht gewusst"
- [ ] Leitner-System-Logik (Kartei-Fächer 1–5, Wiederholungsintervalle)
- [ ] Fortschrittsanzeige (x von y Karten)
- [ ] Session-Abschluss-Screen mit Zusammenfassung

### 4.2 Prüfungssimulation
- [ ] Fragenanzahl & Zeitlimit je Bundesland konfigurierbar hinterlegen
- [ ] Timer-Anzeige (Countdown)
- [ ] Multiple-Choice-Fragen (4 Antwortoptionen)
- [ ] Keine sofortige Rückmeldung während der Simulation
- [ ] Auswertungsscreen: Punkte, Bestanden/Nicht bestanden, Fehlerübersicht
- [ ] Falsche Antworten zum Schwächentraining vormerken

### 4.3 Schwächentraining
- [ ] Automatische Analyse der häufigsten Fehler aus `user_progress`
- [ ] Personalisiertes Übungsset generieren (Top-10-Schwachstellen)
- [ ] Nach jeder richtigen Antwort: Frage aus Schwächenpool entfernen
- [ ] Fortschrittsanzeige „Schwächen überwunden"

### 4.4 Blitzrunde
- [ ] 10 Zufallsfragen
- [ ] Maximale Session-Dauer: 5 Minuten (Timer)
- [ ] Sofortiges Feedback nach jeder Antwort (richtig/falsch + Erklärung)
- [ ] Schneller Neustart-Button nach Abschluss

---

## 5. Fischlexikon

- [ ] Listenansicht aller Fischarten (alphabetisch + nach Kategorie filterbar)
- [ ] Detailseite je Fischart (Bild, Merkmale, Schonmaß, Schonzeit)
- [ ] Bundesland-Filter für Schonmaße & Schonzeiten
- [ ] Volltext-Suche im Lexikon
- [ ] Offline-Verfügbarkeit sicherstellen (alle Bilder & Daten lokal)
- [ ] „Gesehen"-Markierung je Art (für Achievement „Fischflüsterer")

---

## 6. Regelwerk-Bibliothek

- [ ] Kapitelstruktur je Bundesland aufbauen
- [ ] Inhalte: Schonzeiten, Mindestmaße, Erlaubnisscheinpflicht, Verbote
- [ ] Lesestatus je Kapitel tracken (für Achievement)
- [ ] Offline-Verfügbarkeit
- [ ] Suche innerhalb der Bibliothek

---

## 7. Gamification

### 7.1 XP & Level
- [ ] XP-Vergabe-Logik in Cloud Function `onAnswerSubmit` implementieren
- [ ] Level-Berechnung aus XP-Gesamt (Schwellenwerte definieren)
- [ ] Level-Up-Animation & Benachrichtigung
- [ ] Profil-Screen: aktuelles Level, XP-Fortschrittsbalken, Titel anzeigen

### 7.2 Streak
- [ ] Tägliche Aktivität tracken (Datum der letzten Session)
- [ ] Streak-Zähler erhöhen / zurücksetzen
- [ ] Streak-Visualisierung (Angelschnur im Kalender)
- [ ] Streak-Schutz-Mechanismus (1x/Monat Nachholmöglichkeit)
- [ ] Push-Benachrichtigung: „Dein Streak ist in Gefahr!" (abends, falls nicht gelernt)

### 7.3 Achievements
- [ ] Achievement-Datenstruktur und Bedingungen definieren
- [ ] Trigger-Logik je Achievement implementieren (Event-basiert)
- [ ] Achievement-Unlock-Animation & Toast-Notification
- [ ] Achievement-Übersichtsseite im Profil

### 7.4 Ranglisten
- [ ] Globale Rangliste (Top 100, eigene Position)
- [ ] Bundesland-Rangliste
- [ ] Freundes-Rangliste (Freunde via Code/Link hinzufügen)
- [ ] Wöchentlicher Leaderboard-Reset (Firebase Scheduled Function)
- [ ] Allzeit-Rangliste

### 7.5 Duell-Modus
- [ ] Duell erstellen (10 gleiche Fragen für beide Spieler)
- [ ] Einladungslink / QR-Code generieren
- [ ] Echtzeit-Ergebnis nach beiden Abschlüssen (WebSocket oder Polling)
- [ ] Sieger/Verlierer-Screen mit XP-Vergabe
- [ ] „Aufholpaket" für Verlierer (Wiederholungsfragen)

### 7.6 Saisonale Events
- [ ] Event-Datenstruktur in Firestore Collection `events` anlegen
- [ ] Event-Banner auf Homescreen
- [ ] Event-spezifische Fragensets
- [ ] Limitierte Event-Badges vergeben
- [ ] Event-Countdown-Anzeige

---

## 8. Benutzerkonto & Profil

- [ ] Registrierung via Firebase Auth (E-Mail/Passwort, Google Sign-In, Apple Sign-In)
- [ ] Login / Logout
- [ ] Passwort zurücksetzen (E-Mail-Flow)
- [ ] Gastzugang (kein Account, kein Cloud-Sync, nur lokal)
- [ ] Profil-Screen: Avatar, Name, Bundesland, Level, XP, Streak, Achievements, Trophäen
- [ ] Kontoeinstellungen: Bundesland ändern, Lernziel ändern, Benachrichtigungen
- [ ] Account löschen (DSGVO-Pflicht)
- [ ] Datenexport auf Anfrage (DSGVO-Pflicht)

---

## 9. Offline-Fähigkeit & Sync

- [ ] Lokale Datenbank (Hive/Isar) für Fragenkatalog, Lexikon, Regelwerk
- [ ] Lernfortschritt lokal speichern
- [ ] Firestore Offline-Persistence aktivieren (`settings.persistenceEnabled = true`)
- [ ] Konfliktauflösung: Firestore-eigene Merge-Strategie nutzen, bei XP Cloud Function als Single Source of Truth
- [ ] OTA-Katalog-Update: Versionscheck beim App-Start, Download im Hintergrund
- [ ] Nutzer-Benachrichtigung bei verfügbarem Katalog-Update

---

## 10. Monetarisierung

- [ ] Freemium-Logik implementieren (Feature-Gates per User-Attribut)
- [ ] In-App-Purchase einbinden (Apple StoreKit 2 + Google Billing Library)
- [ ] Monatliches Abo (4,99 €)
- [ ] Jährliches Abo (34,99 €)
- [ ] Lifetime-Kauf (59,99 €)
- [ ] Abo-Status über Cloud Function `validateReceipt` validieren (Apple + Google)
- [ ] Paywall-Screen mit klarer Nutzenübersicht
- [ ] Restore Purchases-Funktion
- [ ] Nicht-invasive Werbebanner (nur Free-Tier, kein Interstitial während Quiz)

---

## 11. UI/UX & Design

- [ ] Design-System aufbauen (Farben, Typographie, Abstände, Komponenten)
- [ ] Dark Mode implementieren (ThemeData hell & dunkel)
- [ ] App-Icon (iOS & Android) erstellen und einbinden
- [ ] Splash Screen für beide Plattformen
- [ ] Micro-Animationen: Fisch-Sprung bei richtiger Antwort, Wellen-Fortlauf
- [ ] Barrierefreiheit: Mindestschriftgröße, Kontrastverhältnis ≥ 4.5:1
- [ ] VoiceOver (iOS) & TalkBack (Android) – Semantik-Labels an allen Elementen
- [ ] Responsive Layout: Smartphone + Tablet (iPad)
- [ ] Ladeanimationen / Skeleton-Screens (kein leerer Bildschirm beim Datenladen)

---

## 12. Benachrichtigungen

- [ ] Push-Benachrichtigungen einrichten (Firebase Cloud Messaging)
- [ ] Tägliche Lern-Erinnerung (zur vom Nutzer gewählten Uhrzeit)
- [ ] Streak-Gefahr-Benachrichtigung
- [ ] Achievement-Unlock-Benachrichtigung
- [ ] Katalog-Update-Benachrichtigung
- [ ] Opt-out-Möglichkeit pro Benachrichtigungstyp (DSGVO)

---

## 13. Datenschutz & Sicherheit

- [ ] Datenschutzerklärung (DSGVO) in App einbinden
- [ ] Nutzungsbedingungen (AGB) einbinden
- [ ] Einwilligungsbanner beim ersten Start (Tracking / Analytics)
- [ ] KOPA-konformer Flow für Nutzer unter 16 Jahren
- [ ] TLS: Firebase SDK kommuniziert nativ verschlüsselt (kein Zusatzaufwand)
- [ ] Passwörter: ausschließlich Firebase Auth verwaltet (kein eigenes Hashing)
- [ ] Token-Management: Firebase ID-Token + automatisches Refresh via FlutterFire SDK
- [ ] Firestore Security Rules als Eingabevalidierung (serverseitig, kein direkter DB-Write ohne Regel)
- [ ] Firebase App Check aktivieren (verhindert Zugriff von Bots/nicht-autorisierten Clients)
- [ ] EU-Hosting sicherstellen: alle Dienste auf Region `europe-west3` (Frankfurt)
- [ ] Penetrationstest (grundlegend) vor Go-Live

---

## 14. Testing

- [ ] Unit-Tests: Leitner-Logik, XP-Berechnung, Level-Berechnung
- [ ] Unit-Tests: Achievement-Trigger-Logik
- [ ] Widget-Tests: Karteikarte, Prüfungsscreen, Onboarding-Schritte
- [ ] Integration-Tests: Kompletter Lernflow (Start → Antwort → XP → Level-Up)
- [ ] Integration-Tests: Prüfungssimulation (Start → Auswertung)
- [ ] Cloud Functions Unit-Tests (Jest + Firebase Emulator Suite)
- [ ] Manuelle Tests: iOS (iPhone 14/15, iPad) & Android (Pixel, Samsung)
- [ ] Accessibility-Test mit VoiceOver & TalkBack
- [ ] Performance-Test: Ladezeit Fragenkatalog, Offline-Start < 2 Sekunden

---

## 15. Store-Veröffentlichung

- [ ] Apple Developer Account einrichten / verifizieren
- [ ] Google Play Console einrichten
- [ ] App Store Connect: App-Metadaten, Screenshots, Beschreibung (DE)
- [ ] Google Play: Store-Eintrag, Screenshots, Beschreibung (DE)
- [ ] Altersfreigabe konfigurieren (USK / App Store Ratings)
- [ ] TestFlight (iOS) & Internal Testing (Android) – Beta-Tester einladen
- [ ] App Review Guidelines prüfen (In-App-Purchase, Datenschutz)
- [ ] Datenschutz-Fragebogen Apple App Store ausfüllen
- [ ] Release-Notes für Launch formulieren
- [ ] App Store Optimierung (ASO): Keywords, Kategorie (Bildung)
- [ ] Produktionsrelease iOS & Android

---

*Stand: April 2026 | Wird laufend aktualisiert*
