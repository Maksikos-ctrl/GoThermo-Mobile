#!/usr/bin/env bash
# One-time setup after cloning: creates the android/ and ios/ projects Flutter
# needs (they are not stored in this repo until you commit them), patches them
# and fetches the packages.
#
#   ./tool/setup.sh
#   flutter run            # with a simulator or a phone connected
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter is not installed. See https://docs.flutter.dev/get-started/install" >&2
  exit 1
fi

# `flutter create` never overwrites files that exist, so lib/ and test/ stay as they are.
flutter create . --org com.gothermo --project-name gothermo_mobile --platforms android,ios
python3 tool/patch_platforms.py
flutter pub get
echo
echo "Done. Next: flutter test && flutter run"
