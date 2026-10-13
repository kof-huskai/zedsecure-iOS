#!/usr/bin/env bash
# Builds the proxy core as an .xcframework for iOS. Must run on macOS (use the CI runner).
#
# UNVERIFIED SCAFFOLD: the upstream build commands change between versions.
# Check the README / Makefile of each repo at the pinned tag before relying on this.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/.cores"
OUT="$ROOT/Frameworks"
SING_BOX_REF="${SING_BOX_REF:-main}"   # TODO: pin to a release tag

mkdir -p "$WORK" "$OUT"

# Go toolchain: on GitHub Actions use actions/setup-go before this script.
go version

# --- sing-box (libbox) ------------------------------------------------------
# Milestone 2 uses sing-box alone: libbox ships its own tun handling for iOS and
# covers VLESS/Reality, VMess, Trojan, Shadowsocks, Hysteria2, TUIC, WireGuard.
if [ ! -d "$WORK/sing-box" ]; then
  git clone https://github.com/SagerNet/sing-box.git "$WORK/sing-box"
fi
(
  cd "$WORK/sing-box"
  git fetch --tags
  git checkout "$SING_BOX_REF"
  go install -v github.com/sagernet/gomobile/cmd/gomobile@latest
  go install -v github.com/sagernet/gomobile/cmd/gobind@latest
  # Upstream Makefile target at time of writing: `make lib_ios`
  # (runs: go run ./cmd/internal/build_libbox -target apple -platform ios)
  make lib_ios
)
rm -rf "$OUT/Libbox.xcframework"
cp -R "$WORK/sing-box/Libbox.xcframework" "$OUT/"

# --- Xray (later) -----------------------------------------------------------
# XTLS/libXray provides an Apple build; add it only once sing-box works end to end.

echo "Done: $OUT"
