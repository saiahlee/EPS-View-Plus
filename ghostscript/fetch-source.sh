#!/usr/bin/env bash
# Downloads and extracts the pinned Ghostscript source.
# Idempotent: skips if src/ already populated.

set -euo pipefail

cd "$(dirname "$0")"

GS_VERSION="${GS_VERSION:-10.04.0}"
GS_TAG="${GS_VERSION//./}"
GS_TARBALL="ghostscript-${GS_VERSION}.tar.gz"
GS_URL="https://github.com/ArtifexSoftware/ghostpdl-downloads/releases/download/gs${GS_TAG}/${GS_TARBALL}"

if [ -d "src" ] && [ -f "src/configure" ]; then
  echo "✓ Source already present at src/"
  exit 0
fi

if [ ! -f "${GS_TARBALL}" ]; then
  echo "Downloading Ghostscript ${GS_VERSION} from Artifex..."
  curl -fL --progress-bar -o "${GS_TARBALL}" "${GS_URL}"
fi

# Optional checksum verification (uncomment after pinning a verified hash)
# EXPECTED_SHA256="<paste-published-sha256-here>"
# echo "${EXPECTED_SHA256}  ${GS_TARBALL}" | shasum -a 256 -c

echo "Extracting..."
rm -rf src
tar xf "${GS_TARBALL}"
mv "ghostscript-${GS_VERSION}" src

echo "✓ Source extracted to src/"
