# Hooked – Monetarisierungsplan

Stand: 7. Mai 2026 · Status: **geplant, Umsetzung sobald Apple-Org-Account + Google-Play-Org-Account verifiziert sind**

> Ziel: Freemium mit klarem Pro-Mehrwert, fairer Free-Tier, RevenueCat als Abstraction-Layer über Apple StoreKit + Google Play Billing.

---

## 💶 Preise

| Tier | Preis | Hinweis |
|---|---|---|
| Hooked Pro Monthly | **2,99 €** | Niedrigschwellig, Impulskauf |
| Hooked Pro Yearly | **24,99 €** | ~10 Monate Monthly-Preis · 7-Tage Free Trial |
| Hooked Pro Lifetime | **49,99 €** | Einmalkauf, ~2× Yearly · für Power-User |

- Yearly mit 7-Tage Free Trial → erhöht Konversion deutlich
- Lifetime als Non-Consumable IAP (nicht Subscription)
- RevenueCat-Entitlement-Name: `hooked_pro`

---

## 🎯 Feature-Matrix

| Feature | Free | Pro |
|---|---|---|
| Catches lokal anlegen (Foto lokal) | ✅ | ✅ |
| Foto-Cloud-Backup | ❌ | ✅ |
| Spots, Karten-View | ✅ | ✅ |
| Community-Feed (lesen, posten, like, kommentieren) | ✅ | ✅ |
| Predator-Score **aktuell** (heute) | ✅ | ✅ |
| Predator-Score **Forecast** (7 Tage, Mondphase, Detail-Wetter) | ❌ | ✅ |
| Aktive Trips | **3** | unbegrenzt |
| Trip-Sharing (Cloud-Einladung + Teilnehmer) | ❌ | ✅ |
| Voice-Quick-Add | ✅ | ✅ |
| Revier-Wrapped (Jahresreview) | ✅ | ✅ |
| Werbefrei | (Werbung aktuell nicht aktiv, schafft aber Wertversprechen) | ✅ |

**Definition „aktiver Trip"**: alle Trips ohne `endDate` ODER mit `endDate > now`. Vergangene Trips zählen nicht ins Limit.

---

## 🔧 Tech-Stack

- **`purchases_flutter`** (RevenueCat SDK) — kostenlos bis 2,5k MTR, danach 1 % Revenue
- **Firebase Custom Claims** über RevenueCat-Webhook → Cloud Function → Firestore-User-Doc + Auth-Custom-Claims
- **Firestore Rules**: Cloud-Trip-Sharing + Foto-Upload nur wenn `pro == true` (Server-side enforcement gegen gehackte Clients)

---

## 📋 Umsetzung – 5 PRs

### PR 1: Pro-Status-Infrastruktur
- [ ] RevenueCat-Account anlegen (https://app.revenuecat.com/signup)
- [ ] `purchases_flutter` zu `pubspec.yaml`
- [ ] `RevenueCatBootstrap` analog zu `FirebaseBootstrap`
- [ ] `proStatusProvider` (Riverpod, `Stream<CustomerInfo>`)
- [ ] `isProProvider` als reaktive Source-of-Truth
- [ ] Restore-Purchase-Funktion (Apple-Pflicht!)

### PR 2: Paywall-Screen
- [ ] `lib/features/pro/paywall_screen.dart` im Apex-Style (Rajdhani, ApexColors.primary)
- [ ] 3 Pricing-Cards (Monthly · Yearly mit "Most Popular"-Badge · Lifetime)
- [ ] Free-Trial-Badge "7 Tage gratis testen" auf Yearly
- [ ] Trust-Elemente: Restore-Button, AGB-Link, Datenschutz-Link
- [ ] Settings-Eintrag „Hooked Pro verwalten" → öffnet Apple/Google Subscription Management

### PR 3: Feature-Gates
- [ ] `_GateOrPaywall` Widget-Helper (`if (!isPro) showPaywall(context, feature: 'cloud_backup')`)
- [ ] **Trip-Limit**: bei `addTrip()` aktive Trips zählen, ggf. Paywall
- [ ] **Trip-Sharing**: Cloud-Share-Button → Paywall für Free
- [ ] **Foto-Upload**: Free speichert nur lokal, Pro lädt zu Storage
- [ ] **Predator-Forecast**: Free = "Heute"-Tab only, Pro = 7-Tage-Tabs freigeschaltet

### PR 4: Backend-Synchronisierung
- [ ] Cloud Function `revenuecatWebhook` (HTTP-Endpoint mit Shared-Secret-Header)
- [ ] On Webhook: Firestore-User-Doc `proExpiresAt` schreiben + Auth-Custom-Claim `pro: true`
- [ ] Firestore Rules: `request.auth.token.pro == true` für `sharedTrips/*`, `tripPhotos/*`, `catchPhotos/*` mit Cloud-Pfad
- [ ] Storage Rules: Foto-Upload nur mit Pro-Claim (außer Profilbild — bleibt für alle frei)

### PR 5: UX-Polish + Marketing
- [ ] „Jetzt 7 Tage gratis testen"-Banner an Stellen wo Free-User Pro-Features sehen (z.B. Trip-Liste mit Sperr-Hinweis)
- [ ] Onboarding-Slot Nr. 6: Pro-Vorstellung (skippable)
- [ ] „Pro Active"-Badge im Profil-Screen + Ablaufdatum
- [ ] Datenschutz-Update: Apple/Google verarbeiten Zahlungsdaten als eigenständige Verantwortliche
- [ ] App Store Privacy Details ergänzen: „Käufe" als Datenkategorie

---

## 🛠️ Store-Setup (sobald Org-Accounts da)

### Apple App Store Connect
- **Subscription Group**: „Hooked Pro" (1 Group)
- **Products**:
  - Product ID: `hooked_pro_monthly` · Type: Auto-Renewable Subscription · Duration: 1 Month · Price: 2,99 €
  - Product ID: `hooked_pro_yearly` · Type: Auto-Renewable Subscription · Duration: 1 Year · Price: 24,99 € · Free Trial: 7 Days
  - Product ID: `hooked_pro_lifetime` · Type: Non-Consumable IAP · Price: 49,99 €
- Lokalisierte Beschreibungen DE
- Subscription Display Name: „Hooked Pro"

### Google Play Console
- **Subscriptions**:
  - Product ID: `hooked_pro_monthly` · Base Plan: Monthly auto-renewing · 2,99 €
  - Product ID: `hooked_pro_yearly` · Base Plan: Yearly auto-renewing · Trial Offer: 7 Tage · 24,99 €
- **Managed Product** (Einmalkauf):
  - Product ID: `hooked_pro_lifetime` · 49,99 €
- Beschreibungen DE

### RevenueCat-Konfiguration
- Project: „Hooked"
- Apps: iOS + Android verknüpfen mit Bundle-/Package-ID `de.apex.hooked`
- **Entitlement**: `hooked_pro`
- **Offerings**: `default` mit allen drei Packages
- Webhook-URL → Cloud Function (Auth via Shared Secret)

---

## 🧠 Strategische Notizen

- **Conversion-Hypothese**: 2-5 % der aktiven User werden Pro (Branchen-Standard für Hobby-Apps mit klarem Mehrwert)
- **Yearly vs. Monthly**: Erwartung 60/35/5 Split (Yearly/Monthly/Lifetime) wegen Free-Trial-Anreiz
- **Lifetime-Risiko**: Bei nachhaltigem Wachstum kann Lifetime nach Launch-Phase auf 79,99 € erhöht oder ganz entfernt werden („Lifetime nur für Early Adopters")
- **Werbung bleibt vorerst aus** — kann später als Native-Ad im Free-Tier-Feed nachgezogen werden, falls Conversion stagniert

---

## �️ Phase 2: Tiefenkarten (separates Pricing)

> **Wichtig**: Tiefenkarten gehören **nicht** in `hooked_pro`. Sie verursachen laufende Drittkosten (Lizenz pro Region oder API-Calls) und würden die Marge eines Flatrate-Abos auffressen.

### Modell A — Regionspaket als Einmalkauf (Empfehlung)
- Pro See/Revier oder Bundle (z.B. „Bayern", „Mecklenburg-Vorpommern")
- **Non-Consumable IAP**, Preis 4,99 € – 9,99 € pro Region, lebenslang offline nutzbar
- Product-IDs: `hooked_map_<region>` (z.B. `hooked_map_bayern`)
- RevenueCat-Entitlements: `map_bayern`, `map_mv`, …
- Vorteil: deckt Lizenzkosten 1:1, kein Abo-Druck für Gelegenheits-Angler

### Modell B — „Pro+" Abo-Stufe (nur bei Flatrate-Lizenz)
- On-top-Abo zu `hooked_pro`: **6,99 €/Monat** oder **59,99 €/Jahr**
- Enthält alle Tiefenkarten + neue Regionen automatisch
- Nur sinnvoll, wenn Karten-Anbieter Flatrate-Lizenz gibt
- Entitlement: `hooked_pro_plus`

### Modell C — Karten-Credits (Fallback bei API-Pay-per-Call)
- Z.B. Navionics-artige Anbieter, die pro Tile/Call abrechnen
- User kauft Credits (10 Credits = 4,99 €), 1 Credit = 1 Region für 30 Tage
- UX-Komplexität hoch → nur wenn Lizenzmodell zwingt

### Pro-User-Goodie
- 10–20 % Rabatt auf Karten-Bundles für `hooked_pro`-Subscriber (Loyalty)
- Technisch: zweite Offering in RevenueCat (`maps_pro_discount`) abhängig vom `hooked_pro`-Entitlement

### Entscheidungs-Trigger (vor Verhandlung mit Karten-Anbieter)
1. Lizenzkosten klären: Pauschal/Region vs. pro API-Call
2. Datenrechte: Dürfen Karten offline gecached werden?
3. Update-Frequenz: Wie oft müssen Karten neu lizenziert werden?
4. Erst danach Modell A/B/C festlegen.

---

## �📅 Timeline

1. **Jetzt**: README finalisieren ✅
2. **Nach Apple/Google-Org-Verifikation** (~1-2 Wochen): Store-Produkte anlegen
3. **Parallel**: PR 1 (Infrastruktur) im Code, mit Mock-`isProProvider` testbar
4. **Sobald Stores live + RevenueCat verbunden**: PR 2-5 zügig durch
5. **Vor Submission**: Sandbox-Tests mit Apple-Tester-Accounts und Play-Test-Tracks
