#!/usr/bin/env bash
# Builds sing-box's libbox as an iOS .xcframework and packs it into Libbox.xcframework.tgz
# in the repository root. Must run on macOS with Xcode (the CI "libbox" job does this).
#
# The version is pinned on purpose: PacketTunnel/PlatformInterface.swift is written against
# the libbox API of this exact release. Bump SING_BOX_REF only together with that file.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WORK_DIR:-$ROOT/.cores}"
SING_BOX_REF="${SING_BOX_REF:-v1.13.21}"
OUTPUT="$ROOT/Libbox.xcframework.tgz"

go version

mkdir -p "$WORK"
if [ ! -d "$WORK/sing-box/.git" ]; then
  git clone --depth 1 --branch "$SING_BOX_REF" https://github.com/SagerNet/sing-box.git "$WORK/sing-box"
fi

cd "$WORK/sing-box"
git describe --tags || true

# Same gomobile fork and version that sing-box's own Makefile (lib_install) uses.
go install -v github.com/sagernet/gomobile/cmd/gomobile@v0.1.12
go install -v github.com/sagernet/gomobile/cmd/gobind@v0.1.12
export PATH="$(go env GOPATH)/bin:$PATH"

# iOS device only (arm64) to keep CI time down. The upstream default also builds
# simulator, tvOS and macOS slices; use -platform ios,iossimulator for simulator builds.
go run ./cmd/internal/build_libbox -target apple -platform ios

test -d Libbox.xcframework

rm -f "$OUTPUT"
# tar keeps the framework layout intact (upload-artifact would flatten symlinks).
tar -czf "$OUTPUT" Libbox.xcframework
echo "Wrote $OUTPUT"
