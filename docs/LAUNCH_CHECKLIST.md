# Hooked – Launch-Readiness-Checkliste

Stand: 7. Mai 2026 · Version `1.0.0+1` · Bundle-/AppId `de.apex.hooked` · Firebase-Projekt `hooked-fangtagebuch` (europe-west3)

> Ablauf: Punkte oben nach unten abarbeiten. Reihenfolge ist optimiert: erst Blocker, dann Compliance, dann Polish. Jeder Punkt hat einen klaren Akzeptanz-Test.

---

## 🛑 BLOCKER – ohne diese Punkte kein Store-Submit

### B1. Android Release-Signing einrichten
- [ ] Production-Keystore erzeugen (außerhalb Repo speichern, Backup!):
  ```bash
  keytool -genkey -v -keystore ~/keys/hooked-release.jks \
    -keyalg RSA -keysize 2048 -validity 10000 -alias hooked
  ```
- [ ] `android/key.properties` (in `.gitignore`!) anlegen:
  ```
  storePassword=…
  keyPassword=…
  keyAlias=hooked
  storeFile=/Users/ba34344/keys/hooked-release.jks
  ```
- [ ] `android/.gitignore` enthält `key.properties` (prüfen)
- [ ] [android/app/build.gradle.kts](android/app/build.gradle.kts) Zeile 32–36 ersetzen:
  - `signingConfigs { create("release") { … } }` mit Keystore aus `key.properties`
  - `buildTypes.release.signingConfig = signingConfigs.getByName("release")`
- [ ] `flutter build appbundle --release` baut ohne Fehler und nicht mehr mit Debug-Keys
- **Akzeptanz**: `jarsigner -verify` zeigt Production-Cert; `bundletool` lässt sich validieren

### B2. iOS Sign-in-with-Apple Capability final aktivieren
- [x] Apple Developer Portal → App ID `de.apex.hooked` → "Sign In with Apple" aktiv
- [x] Provisioning Profile (Distribution) neu erzeugen
- [x] Xcode → Runner → Signing & Capabilities → "Sign In with Apple" sichtbar (✅ Entitlements-File ist da)
- [x] `flutter build ipa --release` läuft fehlerfrei durch
- **Akzeptanz**: Release-IPA installiert sich auf TestFlight, Apple-Login funktioniert

### B3. Privacy Policy finalisieren
- [ ] [site/datenschutz.html](site/datenschutz.html) Zeile 9 "Vorläufige Fassung während der Entwicklungsphase" entfernen
- [ ] Verantwortliche Stelle (Name, Anschrift, E-Mail) eintragen
- [x] Domain final festlegen (`hooked-fangtagebuch.app`?) und alle Verweise konsistent halten
- [x] Kontakt-E-Mail `info@drill-und-angelpunkt.de` muss erreichbar sein
- **Akzeptanz**: Datenschutz öffnet im Browser ohne "Vorläufig"-Hinweis, alle Pflichtangaben da

### B4. Privacy Policy + Impressum **in der App** verlinken
- [ ] Settings-Screen (`lib/features/settings/`) zwei neue Einträge:
  - "Datenschutz" → `url_launcher` auf datenschutz-URL
  - "Impressum" → `url_launcher` auf impressum-URL
- [ ] Auch im Auth-Screen Hinweis "Mit Anmeldung akzeptiere ich [Datenschutz](…)"
- [ ] Beide URLs als Konstanten in `lib/core/constants/legal_urls.dart` (kein hardcoded Streuung)
- **Akzeptanz**: Tap → externer Browser öffnet das Dokument

### B5. Firebase Crashlytics einbauen
- [x] `pubspec.yaml`: `firebase_crashlytics: ^4.1.3`
- [x] `pubspec.yaml`: `firebase_crashlytics: ^4.1.3`
- [x] iOS: `pod install` ausgeführt — `firebase_crashlytics` (Firebase SDK 11.15.0) ist im Workspace registriert
- [ ] iOS: Run-Script-Phase für dSYM-Upload in Xcode hinzufügen *(User-Task: Xcode → Runner Target → Build Phases → New Run Script Phase: `"${PODS_ROOT}/FirebaseCrashlytics/run"`, Input Files: `${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Resources/DWARF/${TARGET_NAME}` und `$(SRCROOT)/$(BUILT_PRODUCTS_DIR)/$(INFOPLIST_PATH)`)*
- [x] Android: `com.google.firebase.crashlytics`-Plugin in `android/settings.gradle.kts` + `android/app/build.gradle.kts`
- [x] [lib/main.dart](lib/main.dart) globale Handler erweitert (`recordFlutterFatalError` + `recordError`, nur in Release aktiv); defensive `try/catch` um `setCrashlyticsCollectionEnabled` falls Native-Plugin nicht antwortet
- [ ] Test-Crash auslösen (Debug-Button) → in Firebase Console sichtbar *(post-Build-Test)*
- **Akzeptanz**: Crash in Release-Build erscheint binnen ~5 Min in Crashlytics-Dashboard

### B6. Account-Login-Texte/Typos fixen ✅
- [x] [lib/features/auth/auth_screen.dart](lib/features/auth/auth_screen.dart): `"Nur noetig"` → `"Nur nötig"`
- [x] [lib/features/auth/auth_screen.dart](lib/features/auth/auth_screen.dart): `"loeschen"` → `"löschen"`
- [x] Auch `Bestaetigung` → `Bestätigung` und `spaeter` → `später` in [auth_service.dart](lib/shared/services/firebase/auth_service.dart) gefixt
- **Akzeptanz**: Keine Umlaut-Workarounds in sichtbaren Strings

---

## ⚠️ STARK EMPFOHLEN VOR LAUNCH

### V1. DSGVO Datenexport (Art. 20)
- [ ] Cloud Function `exportUserData` in `functions/`: liefert ZIP/JSON aus
  - catches, spots, trips, sharedTrips (eigener Anteil), feed (eigene Posts), userMeta
  - signed Storage-URL für Foto-Bundle (24 h gültig)
- [ ] Settings-Screen Button "Meine Daten exportieren" → Funktion + E-Mail-Link
- [ ] Begrenzung: max 1× pro 24 h pro User (gegen Abuse)
- **Akzeptanz**: Export-Mail enthält vollständige Nutzerdaten in maschinenlesbarer Form

### V2. Stille `catch (_) {}` mit Logging versehen ✅
Datei-Stellen (mind. 17, hier die kritischen):
- [x] [lib/shared/widgets/app_quick_add_fab.dart](lib/shared/widgets/app_quick_add_fab.dart) Z. ~93
- [x] [lib/shared/services/app_providers.dart](lib/shared/services/app_providers.dart) (alle leeren `catch (_) {}` haben Fallback-Code, kein silent fail)
- [x] Alle weiteren via `grep -n "catch (_)" lib/` durchgegangen — leere Blöcke jetzt mit `debugPrint`
- [x] Pattern: `catch (e) { debugPrint('…: $e'); }`; Crashlytics-Hooks laufen automatisch via `PlatformDispatcher.instance.onError`
- **Akzeptanz**: kein silent-fail im Release-Build mehr, Telemetry sichtbar

### V3. `// ignore: discarded_futures` ersetzen ✅
- [x] [lib/main.dart](lib/main.dart) Z. ~72/82/91: `unawaited(() async { try { … } catch (e, st) { debugPrint(…); } }())`
- [x] Crashlytics greift global über `PlatformDispatcher.instance.onError`, daher reicht das lokale Logging
- **Akzeptanz**: Keine ungetrackten Futures mehr in Hot-Pfaden

### V4. App-Größe messen + reduzieren falls > 100 MB
- [ ] `flutter build appbundle --analyze-size`
- [ ] `flutter build ios --analyze-size`
- [ ] `assets/fische/` Bilder ggf. in WebP konvertieren
- [ ] Unbenutzte Assets prüfen (`grep` durch `lib/`)
- **Akzeptanz**: Release-Bundle < 80 MB (iOS), < 60 MB (Android-AAB)

### V5. Manuelle QA-Runde auf Release-Builds
- [ ] **Auth**: Google-Login, Apple-Login, Logout, Account-Delete (mit echtem Re-Login danach)
- [ ] **Onboarding**: skippable, vollständig durchgehbar
- [ ] **Permissions**: Kamera ablehnen → Dialog + "Einstellungen" funktioniert
- [ ] **Permissions**: Mikrofon ablehnen → Voice-Sheet zeigt "Einstellungen"-Button
- [ ] **Permissions**: Fotos ablehnen → Dialog
- [ ] **Permissions**: Standort ablehnen → fällt graceful zurück
- [ ] **Catches**: Anlegen mit Foto, Bearbeiten, Löschen, Voice-Quick-Add
- [ ] **Spots**: Anlegen, Karten-View
- [ ] **Trips**: Anlegen, Sharing per Link
- [ ] **Revier-Wrapped**: 3× hintereinander öffnen → Konfetti konsistent
- [ ] **Community-Feed**: Like, Kommentar, Report, Block
- [ ] **Notifications**: Trip-Reminder kommt zur richtigen Zeit
- [ ] **Offline**: App startet ohne Netzwerk, zeigt sinnvolle Zustände
- [ ] **Account-Delete**: Posts/Trips/Foto-Files in Cloud sind danach weg (Firestore Console prüfen)
- **Akzeptanz**: Alle Punkte ohne Crash, ohne unhandled Snackbar-Errors

### V6. Test-Mindestabdeckung
- [ ] Unit-Tests für `predator_score_engine.dart` (deterministisch, leicht testbar)
- [ ] Unit-Tests für `voice_catch_parser.dart` (Pure-Function-Logik)
- [ ] Unit-Tests für `auth_service.dart` mit FakeFirebaseAuth
- [ ] Widget-Test für Onboarding-Flow
- **Ziel**: ~20 % Coverage als Bug-Frühwarn-System
- **Akzeptanz**: `flutter test` grün im CI

---

## 📦 STORE-SUBMISSION ARTEFAKTE

### S1. App Store (iOS)
- [ ] App Store Connect App-Datensatz angelegt
- [ ] App-Icon 1024×1024 (PNG, no alpha)
- [ ] Screenshots: iPhone 6.7" und 6.1" je mind. 3 (besser 5–6)
- [ ] App-Beschreibung (DE + EN)
- [ ] Keywords-Liste
- [ ] Support-URL + Marketing-URL
- [ ] Privacy-Policy-URL
- [ ] Altersfreigabe: 12+ vermutlich (User-generated Content via Community)
- [ ] App Privacy Details: Standort, Fotos, ID, gesammelte Daten korrekt deklarieren
- [ ] Sign-in-with-Apple-Hinweis: erste Demo-Account-Credentials für Reviewer
- [ ] Review-Notes mit Test-Account, Hinweis auf Community-Moderation, Account-Delete-Pfad

### S2. Google Play Console (Android)
- [ ] Play Console App angelegt
- [ ] Feature-Graphic 1024×500
- [ ] App-Icon 512×512
- [ ] Screenshots: Phone (mind. 2), 7"-Tablet optional
- [ ] App-Beschreibung kurz + lang (DE + EN)
- [ ] Datenschutzerklärung-URL
- [ ] Data-Safety-Form vollständig
- [ ] Inhaltsbewertung-Fragebogen
- [ ] Zielgruppe + Inhalte (User-generated → Moderation erläutern)
- [ ] App-Signing by Google Play aktivieren (empfohlen)
- [ ] Internal-Testing-Track für Smoke-Test vor Production

### S3. Marketing-Assets
- [ ] Landing Page [site/index.html](site/index.html) aktuell?
- [ ] Sitemap [site/sitemap.xml](site/sitemap.xml) aktuell?
- [ ] App-Store-Badges + Play-Store-Badges einbinden
- [ ] OG-Tags für Social Sharing

---

## 🧪 OBSERVABILITY POST-LAUNCH

- [ ] Crashlytics-Alerts auf "neue Crashes ≥ 0,5 %"
- [ ] Firestore Usage-Alerts (kostenseitig)
- [ ] Cloud Functions Error-Rate-Alerts
- [ ] Email-Adresse für Reports/Beschwerden monitored

---

## 💡 NICE-TO-HAVE (post-Launch, NICHT blockend)

- Firebase Analytics aktivieren (Retention, Funnels)
- Firebase Cloud Messaging (Push) für Community-Notifications
- A/B-Testing-Setup
- Erweiterte Test-Coverage (60 %+)
- Web-PWA bauen
- Lokalisierung Englisch
- "Gewässer entdecken"-Feature (siehe separate Diskussion – pausiert)

---

## ✅ BEREITS ERLEDIGT (Stand 7. Mai 2026)

- ✅ Auth: Apple + Google + Nonce-Replay-Schutz
- ✅ Account-Delete via Cloud Function (Feed/Storage/SharedTrips/userMeta)
- ✅ Firestore + Storage Rules restriktiv (kein `allow if true`)
- ✅ iOS + Android Permission-Texte vollständig (deutsch)
- ✅ Permission-Helper [lib/shared/utils/permission_dialogs.dart](lib/shared/utils/permission_dialogs.dart) mit "Einstellungen öffnen"
- ✅ Foto-Permission-Handling in [photo_picker_field.dart](lib/shared/widgets/photo_picker_field.dart) + [edit_profile_screen.dart](lib/features/auth/edit_profile_screen.dart)
- ✅ Mikrofon-Permission-Handling in [voice_quick_add_sheet.dart](lib/features/catches/voice/voice_quick_add_sheet.dart)
- ✅ Globale Error-Handler in [main.dart](lib/main.dart) (FlutterError + PlatformDispatcher)
- ✅ Fire-and-forget Feed-Calls (toggleLike, deleteComment) abgesichert
- ✅ Onboarding 5 Screens + skippable
- ✅ Moderation: Report + Block + Blocked-Users-Screen
- ✅ Local Notifications inkl. Timezone + Quiet Hours
- ✅ App-Icons + Adaptive Icons konfiguriert
- ✅ flutter_launcher_icons in [pubspec.yaml](pubspec.yaml)
- ✅ Revier-Wrapped Konfetti-Bug (1./2./3. Öffnen) gefixt
- ✅ AppToast-Overlay-System (FAB-Verschiebe-Bug bei SnackBars behoben, 14 Dateien migriert)
- ✅ Privacy/Impressum-Links in App ([lib/core/constants/legal_urls.dart](lib/core/constants/legal_urls.dart) + Profile-Section + Auth-Consent)
- ✅ B6 Typos (noätig, löschen, Bestätigung, später)
- ✅ V2 Stille `catch (_) {}` mit `debugPrint`-Logging
- ✅ V3 `discarded_futures` durch `unawaited(() async { try … } catch … }())` ersetzt
- ✅ B5 Crashlytics: pubspec, Android-Gradle-Plugin, main.dart-Hooks (iOS dSYM-Upload offen)
- ✅ Profilbild-DSGVO-Cleanup in `deleteUserAccount` Cloud Function (deployed)
- ✅ Account-Delete-Race-Condition gefixt (`AuthResult.isSuccess` + `_userIsGone()`)
- ✅ flutter analyze: nur 4 Pre-existing Info-Level-Issues

---

## 📋 PRIORISIERTE ARBEITSREIHENFOLGE

**Tag 1** – Echte Blocker, parallelisierbar:
1. Du: Keystore + key.properties (B1) · Apple Capability + Provisioning (B2)
2. Ich: Privacy/Impressum-Links in App (B4) · Typos (B6) · Crashlytics-Setup (B5) · Privacy-Policy-Wording-Cleanup (B3)

**Tag 2** – Compliance + Robustheit:
3. DSGVO-Export (V1)
4. `catch (_)` und `discarded_futures` durchgehen (V2, V3)
5. App-Size-Check (V4)

**Tag 3** – QA + Submission:
6. Manuelle QA-Runde (V5)
7. Test-Suite-Grundstock (V6)
8. Store-Artefakte (S1, S2)

**Tag 4** – Internal Testing → Production
