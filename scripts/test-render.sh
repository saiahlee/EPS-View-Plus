#!/usr/bin/env bash
# Smoke test for the bundled converter.
#
# Renders one EPS from ../test_eps/ and ../../test_eps/ to PDF and PNG using
# the same gs invocations the app issues at runtime. Useful for verifying
# that ghostscript/build-universal.sh produced a working binary without
# launching the full Xcode build.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONVERTER="${CONVERTER:-$REPO_ROOT/ghostscript/universal/converter}"

if [ ! -x "$CONVERTER" ]; then
  echo "error: converter not found at $CONVERTER"
  echo "       Run: cd ghostscript && bash build-universal.sh"
  exit 2
fi

# Pick a test EPS from common locations
TEST_EPS=""
for d in "$REPO_ROOT/../test_eps" "$REPO_ROOT/test_eps" "$1"; do
  if [ -d "$d" ]; then
    candidate="$(find "$d" -maxdepth 2 -name "*.eps" -type f 2>/dev/null | head -n 1 || true)"
    if [ -n "$candidate" ]; then
      TEST_EPS="$candidate"
      break
    fi
  fi
done

if [ -z "$TEST_EPS" ]; then
  echo "error: no .eps file found. Pass a path as the first argument or place files in test_eps/"
  exit 2
fi

echo "Converter: $CONVERTER"
echo "Source:    $TEST_EPS"

OUT_DIR="$(mktemp -d)"
PDF_OUT="$OUT_DIR/out.pdf"
PNG_OUT="$OUT_DIR/out.png"

echo
echo "── EPS → PDF ──"
time "$CONVERTER" \
  -dNOPAUSE -dBATCH -dQUIET -dSAFER \
  -dEPSCrop \
  -sDEVICE=pdfwrite \
  -dCompatibilityLevel=1.4 \
  "-sOutputFile=$PDF_OUT" \
  "$TEST_EPS"
[ -f "$PDF_OUT" ] && echo "  ✓ $PDF_OUT ($(du -h "$PDF_OUT" | cut -f1))"

echo
echo "── EPS → PNG (300 DPI) ──"
time "$CONVERTER" \
  -dNOPAUSE -dBATCH -dQUIET -dSAFER \
  -dEPSCrop \
  -dTextAlphaBits=4 -dGraphicsAlphaBits=4 \
  -sDEVICE=png16m \
  -r300 \
  "-sOutputFile=$PNG_OUT" \
  "$TEST_EPS"
[ -f "$PNG_OUT" ] && echo "  ✓ $PNG_OUT ($(du -h "$PNG_OUT" | cut -f1))"

echo
echo "Outputs left at: $OUT_DIR"
echo "✓ Smoke test passed."
