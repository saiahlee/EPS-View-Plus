#!/usr/bin/env bash
# Bundle Homebrew's Ghostscript into ghostscript/universal/ as a
# self-contained binary set ready for the app's Contents/Tools/ folder.
#
# Output:
#   universal/converter           the gs executable, renamed
#   universal/lib/<dylibs>        every transitive dylib it depends on,
#                                 with install_name_tool rewrites so the
#                                 executable looks for them via @rpath.
#
# Compatible with macOS's stock bash 3.2.

set -euo pipefail

cd "$(dirname "$0")"

OUT="$PWD/universal"
mkdir -p "$OUT/lib"

BREW_PREFIX="$(brew --prefix 2>/dev/null || echo /opt/homebrew)"

# 1) Locate brew's gs
if ! command -v brew >/dev/null 2>&1; then
    echo "error: Homebrew is not installed. See https://brew.sh"
    echo "       Or set EPS_GS_BUILD_FROM_SOURCE=1 and re-run build-universal.sh"
    exit 1
fi

if ! brew list ghostscript >/dev/null 2>&1; then
    echo "→ Installing Ghostscript via Homebrew..."
    brew install ghostscript
fi

GS_BIN="$(brew --prefix ghostscript)/bin/gs"
if [ ! -x "$GS_BIN" ]; then
    echo "error: brew installed gs but it isn't at $GS_BIN"
    exit 1
fi

echo "✓ Found Homebrew Ghostscript: $GS_BIN"
"$GS_BIN" --version

# 2) Copy the binary
cp -f "$GS_BIN" "$OUT/converter"
chmod +x "$OUT/converter"
chmod u+w "$OUT/converter"

# ────────────────────────────────────────────────────────────────────
# 3) Resolve dylib dependencies — fixed-point loop.
#
# Some Homebrew dylibs reference siblings via @rpath rather than absolute
# paths (e.g. libwebpmux refers to @rpath/libsharpyuv.0.dylib). We handle
# both cases:
#   • Absolute non-system path          → copy file directly
#   • @rpath/<basename> reference       → search Homebrew prefix
#                                         (lib/ and Cellar/) for that
#                                         basename, copy first hit
# Repeat until a full pass adds nothing.
# ────────────────────────────────────────────────────────────────────
echo
echo "── Resolving dylib dependencies ──"

# List every dependency line (raw paths or @rpath forms) referenced
# by a binary. Excludes /usr/lib, /System, @executable_path,
# @loader_path, and self-referential @rpath/<self>.
list_deps_raw() {
    otool -L "$1" 2>/dev/null | tail -n +2 | \
        sed -E 's/^[[:space:]]+//; s/ \(compatibility.*$//' | \
        awk '
            $0 == ""                  { next }
            $0 ~ /^\/usr\/lib\//      { next }
            $0 ~ /^\/System\//        { next }
            $0 ~ /^@executable_path\//{ next }
            $0 ~ /^@loader_path\//    { next }
            $0 ~ /^@/                 { print; next }
            $0 ~ /^\//                { print }
        '
}

# Locate a dylib by basename in Homebrew's filesystem.
# Looks first in $BREW_PREFIX/lib, then walks Cellar.
locate_brew_dylib() {
    local base="$1"
    if [ -f "$BREW_PREFIX/lib/$base" ]; then
        echo "$BREW_PREFIX/lib/$base"
        return 0
    fi
    # Search Cellar — pick the most recently modified hit.
    find "$BREW_PREFIX/Cellar" -maxdepth 6 -type f -name "$base" 2>/dev/null | head -n 1
}

iteration=0
while : ; do
    iteration=$((iteration + 1))
    added_marker="$(mktemp)"

    # Build the list of binaries to scan in this pass: converter + lib/
    SCAN_LIST="$OUT/converter"
    for f in "$OUT/lib"/*.dylib; do
        [ -f "$f" ] || continue
        SCAN_LIST="$SCAN_LIST
$f"
    done

    printf '%s\n' "$SCAN_LIST" | while IFS= read -r bin; do
        [ -n "$bin" ] || continue
        list_deps_raw "$bin" | while IFS= read -r dep; do
            [ -n "$dep" ] || continue

            case "$dep" in
                @rpath/*)
                    base="${dep#@rpath/}"
                    target="$OUT/lib/$base"
                    [ -f "$target" ] && continue
                    src="$(locate_brew_dylib "$base")"
                    if [ -n "$src" ] && [ -f "$src" ]; then
                        cp -f "$src" "$target"
                        chmod u+w "$target"
                        echo "  copied (rpath) $base"
                        echo "1" >> "$added_marker"
                    else
                        echo "  warn: could not locate @rpath/$base in Homebrew"
                    fi
                    ;;
                /*)
                    base="$(basename "$dep")"
                    target="$OUT/lib/$base"
                    [ -f "$target" ] && continue
                    if [ -f "$dep" ]; then
                        cp -f "$dep" "$target"
                        chmod u+w "$target"
                        echo "  copied $base"
                        echo "1" >> "$added_marker"
                    fi
                    ;;
            esac
        done
    done

    if [ -s "$added_marker" ]; then
        rm -f "$added_marker"
        continue
    fi
    rm -f "$added_marker"
    break
done

echo "  ($(ls -1 "$OUT/lib" 2>/dev/null | wc -l | tr -d ' ') dylibs in lib/, $iteration scan pass(es))"

# ────────────────────────────────────────────────────────────────────
# 4) Rewrite install_names so everything looks for siblings via @rpath
# ────────────────────────────────────────────────────────────────────
echo
echo "── Rewriting install_names ──"

install_name_tool -add_rpath "@executable_path/lib" "$OUT/converter" 2>/dev/null || true

rewrite_one() {
    local file="$1"
    local is_dylib=0
    if file "$file" | grep -q 'dynamically linked shared library'; then
        is_dylib=1
    fi

    list_deps_raw "$file" | while IFS= read -r dep; do
        [ -n "$dep" ] || continue
        case "$dep" in
            @rpath/*)
                # Already in the right form
                continue
                ;;
            /*)
                base="$(basename "$dep")"
                install_name_tool -change "$dep" "@rpath/$base" "$file" 2>/dev/null || true
                ;;
        esac
    done

    if [ "$is_dylib" = "1" ]; then
        install_name_tool -id "@rpath/$(basename "$file")" "$file" 2>/dev/null || true
    fi
}

rewrite_one "$OUT/converter"
for lib in "$OUT/lib"/*.dylib; do
    [ -f "$lib" ] || continue
    rewrite_one "$lib"
done

# ────────────────────────────────────────────────────────────────────
# 5) Re-codesign ad-hoc
# ────────────────────────────────────────────────────────────────────
echo
echo "── Re-signing (ad-hoc) ──"
for lib in "$OUT/lib"/*.dylib; do
    [ -f "$lib" ] || continue
    codesign --force --sign - "$lib" 2>/dev/null || true
done
codesign --force --sign - "$OUT/converter" 2>/dev/null || true

# ────────────────────────────────────────────────────────────────────
# 6) Verification
# ────────────────────────────────────────────────────────────────────
echo
echo "── Verification ──"
file "$OUT/converter"
echo
echo "Linkage:"
otool -L "$OUT/converter" | sed 's/^/  /'
echo
echo "lib/ (count: $(ls -1 "$OUT/lib" | wc -l | tr -d ' ')):"
ls -lh "$OUT/lib" | sed 's/^/  /'
echo
echo "Smoke test:"
"$OUT/converter" --version

echo
echo "✓ Bundle ready at $OUT/"
echo "  Total size: $(du -sh "$OUT" | cut -f1)"
