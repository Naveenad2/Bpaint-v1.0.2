#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# PaintPro Billing — one-time project setup (macOS / Linux)
#
# Generates the platform runner folders for your installed Flutter version,
# then fetches packages. Your source in lib/ and test/ is never touched.
# ---------------------------------------------------------------------------
set -euo pipefail

cd "$(dirname "$0")"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter was not found on PATH."
  echo "Install it from https://docs.flutter.dev/get-started/install and try again."
  exit 1
fi

echo "==> Flutter version"
flutter --version

echo "==> Enabling desktop support"
flutter config --enable-macos-desktop --enable-windows-desktop >/dev/null

STASH="$(mktemp -d)"
echo "==> Protecting sources in $STASH"
cp -R lib "$STASH/lib"
cp -R test "$STASH/test" 2>/dev/null || true
cp -R docs "$STASH/docs" 2>/dev/null || true
cp pubspec.yaml "$STASH/pubspec.yaml"
cp analysis_options.yaml "$STASH/analysis_options.yaml"
cp README.md "$STASH/README.md" 2>/dev/null || true

echo "==> Generating platform runners (windows, macos, linux)"
flutter create \
  --project-name paint_billing \
  --org com.paintpro \
  --platforms=windows,macos,linux \
  --overwrite . >/dev/null

echo "==> Restoring sources"
rm -rf lib && cp -R "$STASH/lib" lib
[ -d "$STASH/test" ] && { rm -rf test; cp -R "$STASH/test" test; }
[ -d "$STASH/docs" ] && { rm -rf docs; cp -R "$STASH/docs" docs; }
cp "$STASH/pubspec.yaml" pubspec.yaml
cp "$STASH/analysis_options.yaml" analysis_options.yaml
[ -f "$STASH/README.md" ] && cp "$STASH/README.md" README.md
rm -rf "$STASH"

echo "==> Fetching packages"
flutter pub get

echo "==> Analysing"
flutter analyze || true

echo "==> Running tests"
flutter test || true

cat <<'DONE'

Setup complete.

  Run in debug      :  flutter run -d macos      (or -d windows / -d linux)
  Build a release   :  flutter build macos --release
                       flutter build windows --release
                       flutter build linux --release

  First sign-in     :  admin / admin123   (change it in Settings > Users)

DONE
