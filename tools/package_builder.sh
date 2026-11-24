#!/usr/bin/env bash
# The FF7Recomp Builder release zip: build the Mac app with the kit (tools/make_builder_kit.sh,
# run first), strip it, sign it ad hoc and pack it. Refuses if anything in it still holds a
# path of this Mac (the release is shared) or the kit holds lifted game code.
#
#   bash tools/make_builder_kit.sh
#   bash tools/package_builder.sh 0.1.0      # -> build-builder/release/FF7Recomp-Builder-0.1.0.zip
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
VERSION="${1:?usage: package_builder.sh VERSION}"
KIT="$ROOT/build-builder/kit"
DD="$ROOT/build-builder/dd"
OUT="$ROOT/build-builder/release"
APP="$DD/Build/Products/Release/FF7Recomp Builder.app"

[[ -f "$KIT/VERSION" ]] || { echo "no kit: run tools/make_builder_kit.sh first" >&2; exit 1; }
if ar t "$KIT/lib/libff7_engine.a" | grep -q '^recomp_'; then
  echo "the kit's engine holds lifted game code: refusing" >&2; exit 1
fi

(cd "$ROOT/mac/builder" && xcodegen generate >/dev/null)
xcodebuild -project "$ROOT/mac/builder/FF7RecompBuilder.xcodeproj" -scheme FF7RecompBuilder \
  -configuration Release -derivedDataPath "$DD" MARKETING_VERSION="$VERSION" -quiet clean build

# the builder's own executable: no debug map (it names this Mac's build folders), then sign again
strip -S "$APP/Contents/MacOS/FF7Recomp Builder"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1
codesign --verify --deep --strict "$APP"

LEAKS="$(grep -rlaF "$HOME" "$APP" || true)"
if [[ -n "$LEAKS" ]]; then
  echo "the app still holds paths under $HOME:" >&2; echo "$LEAKS" >&2; exit 1
fi
if find "$APP" \( -iname 'ff7_en*' -o -iname '*.lgp' -o -iname '*.exe' \) | grep -q .; then
  echo "the app holds game files: refusing" >&2; exit 1
fi

mkdir -p "$OUT"
ZIP="$OUT/FF7Recomp-Builder-$VERSION.zip"
rm -f "$ZIP"
xattr -cr "$APP"
ditto -c -k --norsrc --noextattr --noqtn --keepParent "$APP" "$ZIP"
echo "$ZIP ($(du -h "$ZIP" | cut -f1)), kit $(cat "$KIT/VERSION")"
shasum -a 256 "$ZIP"
