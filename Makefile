.PHONY: help get clean analyze test run run-ios run-android build-ios build-android fonts

# Standardziel
help:
	@echo ""
	@echo "  APEX Hunter — Flutter Makefile"
	@echo "  ─────────────────────────────────────────"
	@echo "  make get          → flutter pub get"
	@echo "  make clean        → flutter clean + pub get"
	@echo "  make analyze      → flutter analyze"
	@echo "  make test         → flutter test"
	@echo "  make run          → flutter run (zuerst verbundenes Gerät)"
	@echo "  make run-ios      → flutter run auf iOS Simulator"
	@echo "  make run-android  → flutter run auf Android Emulator"
	@echo "  make build-ios    → iOS Release-Build (ipa)"
	@echo "  make build-android→ Android Release-Build (apk)"
	@echo "  make fonts        → Rajdhani-Fonts von Google herunterladen"
	@echo ""

# ───────────────────────────────────────────────────
# Abhängigkeiten
# ───────────────────────────────────────────────────

get:
	flutter pub get

clean:
	flutter clean
	flutter pub get

# ───────────────────────────────────────────────────
# Code-Qualität
# ───────────────────────────────────────────────────

analyze:
	flutter analyze

test:
	flutter test

# ───────────────────────────────────────────────────
# App starten (Debug)
# ───────────────────────────────────────────────────

run:
	flutter run

run-ios:
	flutter run -d iPhone

run-android:
	flutter run -d android

# ───────────────────────────────────────────────────
# Release-Builds
# ───────────────────────────────────────────────────

build-ios:
	flutter build ipa --release

build-android:
	flutter build apk --release

# ───────────────────────────────────────────────────
# Assets
# ───────────────────────────────────────────────────

fonts:
	@echo "→ Rajdhani-Fonts werden heruntergeladen …"
	@mkdir -p assets/fonts
	@curl -sL "https://fonts.gstatic.com/s/rajdhani/v17/LDIxapCSOBg7S-QT7q4A.ttf" \
	  -o assets/fonts/Rajdhani-Regular.ttf
	@curl -sL "https://fonts.gstatic.com/s/rajdhani/v17/LDI2apCSOBg7S-QT7pbYF8Os.ttf" \
	  -o assets/fonts/Rajdhani-SemiBold.ttf
	@curl -sL "https://fonts.gstatic.com/s/rajdhani/v17/LDI2apCSOBg7S-QT7pa8FsOs.ttf" \
	  -o assets/fonts/Rajdhani-Bold.ttf
	@echo "✓ Fonts bereit: assets/fonts/"
