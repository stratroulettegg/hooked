# Firebase Setup – APEX Hunter

Dieses Projekt nutzt Firebase für Auth und (in Phase B) für das Teilen von Trips.
Ohne Firebase-Konfiguration läuft die App weiter offline; die Cloud-Features
sind dann automatisch deaktiviert.

## Einmalige Schritte

### 1. Firebase-Projekt anlegen
1. <https://console.firebase.google.com> öffnen.
2. **Projekt hinzufügen** → Name z. B. `apex-hunter`.
3. Google Analytics optional (kann später aktiviert werden).

### 2. Region für Firestore auf EU stellen (**wichtig für DSGVO**)
1. Im Firebase-Console-Projekt: **Build → Firestore Database → Datenbank erstellen**.
2. **Region: `eur3 (europe-west)`** wählen (Frankfurt / Belgien).
   → einmal gesetzt, nicht änderbar.
3. Testmodus ist okay für den Anfang, wir setzen gleich Security Rules.

### 3. Auftragsverarbeitungsvertrag (DPA) akzeptieren
1. Firebase-Konsole → **Zahnrad ⚙ → Projekt-Einstellungen → Datenschutz- und Sicherheitscenter**
   (oder in der Google-Cloud-Konsole unter `cloud.google.com/terms/data-processing-addendum`).
2. DPA einsehen + PDF für die eigenen Unterlagen speichern.

### 4. Auth-Provider aktivieren
Firebase-Konsole → **Authentication → Sign-in method**:
- **E-Mail/Passwort** aktivieren
- **Google** aktivieren (Projekt-Support-E-Mail angeben)
- **Apple** aktivieren (nur falls iOS-Build)

### 5. FlutterFire CLI installieren & projektieren
```bash
dart pub global activate flutterfire_cli
cd /Users/ba34344/Private/haken_dran
flutterfire configure
```
Interaktiv auswählen:
- Projekt: `apex-hunter`
- Plattformen: `android`, `ios`, ggf. `macos`
Das Tool
- legt `lib/firebase_options.dart` an (optional, wir rufen aktuell `Firebase.initializeApp()` ohne Optionen auf),
- platziert `ios/Runner/GoogleService-Info.plist`,
- platziert `android/app/google-services.json`,
- passt Gradle-Dateien an.

> Hinweis: Unser Bootstrap nutzt `Firebase.initializeApp()` ohne Argumente und
> liest deshalb die nativen Config-Dateien. Das genügt für Android/iOS.
> `firebase_options.dart` wird nur gebraucht, wenn auch Web unterstützt
> werden soll.

### 6. iOS-spezifische Einrichtung

#### 6a. URL-Scheme für Google Sign-In
In `ios/Runner/Info.plist` muss der `REVERSED_CLIENT_ID` aus
`GoogleService-Info.plist` als URL-Scheme eingetragen sein. FlutterFire
macht das nicht automatisch. Ergänzen unter `<key>CFBundleURLTypes</key>`:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <!-- REVERSED_CLIENT_ID aus GoogleService-Info.plist -->
      <string>com.googleusercontent.apps.XXXXXXXXX-YYYYYY</string>
    </array>
  </dict>
</array>
```

#### 6b. Sign-in with Apple Capability
In Xcode: **Runner-Target → Signing & Capabilities → + Capability → „Sign in with Apple"**.

Im Apple Developer Portal:
1. App-ID → Capability „Sign in with Apple" aktivieren.
2. Service-ID anlegen (falls Web-Login geplant).

### 7. Android-spezifische Einrichtung

#### 7a. SHA-1 / SHA-256 Keys hinterlegen (für Google Sign-In)
```bash
cd android
./gradlew signingReport
```
In der Firebase-Konsole → **Projekt-Einstellungen → Deine Apps → Android-App → SHA-Fingerabdrücke** einfügen.
Danach `flutterfire configure` erneut laufen lassen (oder `google-services.json` manuell neu herunterladen).

#### 7b. Min SDK
`android/app/build.gradle.kts` muss `minSdk = 23` oder höher haben
(Firebase Auth & Google Sign-In Anforderung).

### 8. Erstes Smoke-Test
```bash
flutter run
```
- Menü oben rechts → **Anmelden**.
- Mit E-Mail registrieren → der User sollte in
  Firebase-Konsole → Authentication → Users auftauchen.
- Abmelden + erneut anmelden testen.

## Nächste Schritte (Phase B)

Sobald Auth läuft:
- `Trip` optional in Firestore unter `users/{uid}/sharedTrips/{tripId}` speichern,
  wenn der User einen Trip **teilen** möchte.
- Einladungs-Token unter `invites/{token}` ablegen.
- Security Rules: nur Mitglieder eines Trips dürfen ihn lesen/schreiben.

Die Rules kommen in Phase B in `firestore.rules` in der Projekt-Root.

## Trip-Einladungen (implementiert)

### Schema
- `/sharedTrips/{tripId}` — Vollständige Trip-Daten inkl. Stops, plus
  `ownerUid` und `createdAt`. Wird angelegt, sobald Owner eine Einladung
  erstellt.
- `/invites/{token}` — 8-stelliger Code (Alphabet `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`)
  mit `{tripId, ownerUid, createdAt, expiresAt}`. TTL standardmäßig 30 Tage.

### Flow
1. **Owner** öffnet Trip → Menü "Einladung erstellen"
   → `TripCloudShareService.createInvite()` schreibt Trip + Token,
   Share-Sheet öffnet sich mit Code und Link.
2. **Gast** öffnet Trip-Liste → "Einladung einlösen" (QR-Icon oben rechts)
   → gibt Code ein (wird aus Clipboard vorbefüllt, falls passend)
   → `redeemInvite()` lädt Trip, erzeugt neue lokale IDs und speichert
   den Trip in der lokalen Datenbank (`tripProvider.addTrip`).

### Security Rules
Siehe `firestore.rules` im Projekt-Root. Ausrollen mit:
```bash
firebase deploy --only firestore:rules
```
Die Rules erlauben:
- `read`: jeder authentifizierte User (Token ist clientseitig nicht zu raten).
- `create`: nur mit `ownerUid == auth.uid`.
- `update`/`delete`: nur der Owner.

### Bekannte Limitierungen
- Kein Echtzeit-Sync: Ein bereits importierter Trip aktualisiert sich nicht,
  wenn der Owner später etwas ändert. Gast müsste neu einladen/einlösen.
- Kein Deep-Link-Handler: Einladungen laufen ausschließlich über den
  8-stelligen Code, der kopiert/gesendet wird.
- Kein Invite-Widerruf-UI (Owner müsste manuell in Firestore löschen).
