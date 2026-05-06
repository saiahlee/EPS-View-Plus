#!/usr/bin/env bash
# Build Ghostscript as a static arm64 binary.

set -euo pipefail

cd "$(dirname "$0")"
bash fetch-source.sh

PREFIX="$PWD/install-arm64"
rm -rf "$PREFIX"

cd src

# -std=gnu17 pins the language version below C23. Recent macOS Command
# Line Tools (clang 21+) default to C23, where Ghostscript 10.04.0's
# bundled zlib (K&R-style declarations + fdopen macro shadowing) fails
# to compile. gnu17 keeps everything legal and reproducible.
export CFLAGS="-arch arm64 -O2 -mmacosx-version-min=14.0 -std=gnu17"
export LDFLAGS="-arch arm64 -mmacosx-version-min=14.0"

make distclean >/dev/null 2>&1 || true

# Note: ghostscript's configure does not understand --enable-static or
# --disable-shared. We omit them and rely on the default behaviour, which
# produces a standalone executable that does not link against any
# Homebrew-installed libgs.
./configure \
    --host=aarch64-apple-darwin \
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

echo "✓ arm64 build complete: $PREFIX/bin/gs"
file "$PREFIX/bin/gs"
