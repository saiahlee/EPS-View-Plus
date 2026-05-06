#!/usr/bin/env bash
# Build Ghostscript as a static x86_64 binary.

set -euo pipefail

cd "$(dirname "$0")"
bash fetch-source.sh

PREFIX="$PWD/install-x86_64"
rm -rf "$PREFIX"

cd src

# See build-arm64.sh for the rationale on -std=gnu17 and the dropped
# --enable-static / --disable-shared options.
export CFLAGS="-arch x86_64 -O2 -mmacosx-version-min=14.0 -std=gnu17"
export LDFLAGS="-arch x86_64 -mmacosx-version-min=14.0"

make distclean >/dev/null 2>&1 || true

./configure \
    --host=x86_64-apple-darwin \
    --prefix="$PREFIX" \
    --disable-cups \
    --disable-dbus \
    --disable-gtk \
    --disable-fontconfig \
    --without-x \
    --without-libidn \
    --without-libpaper \
    --without-pdftoraster \
    --without-tesseract \
    --with-drivers="png16m,pdfwrite,bbox,jpeg"

make -j"$(sysctl -n hw.ncpu)"
make install

echo "✓ x86_64 build complete: $PREFIX/bin/gs"
file "$PREFIX/bin/gs"
