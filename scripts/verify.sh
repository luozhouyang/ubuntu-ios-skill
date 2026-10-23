#!/usr/bin/env bash
# Verify an Ubuntu iOS toolchain installation. Exit 1 if a core check fails.
set -euo pipefail

SWIFT_VERSION="${SWIFT_VERSION:-6.3.3}"
PREFIX="${PREFIX:-$HOME/.local/ubuntu-ios-toolchain}"
SWIFT_PREFIX="${SWIFT_PREFIX:-$HOME/.local/swift-$SWIFT_VERSION}"
UBUNTU_IOS="${UBUNTU_IOS_BIN:-$HOME/.local/bin/ubuntu-ios}"
SDK_BUNDLE="$HOME/.swiftpm/swift-sdks/darwin.artifactbundle"
SMOKE=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [--smoke]

Checks Swift, xtool, rcodesign, the Darwin SDK, OpenAppleMacros, Darwin build
tools, pymobiledevice3, and usbmuxd visibility. With --smoke, also builds a
temporary SwiftUI app end to end.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --smoke) SMOKE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

export PATH="$SWIFT_PREFIX/usr/bin:$HOME/.local/bin:$PATH"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/lib/x86_64-linux-gnu/pkgconfig:${PKG_CONFIG_PATH:-}"
export LD_LIBRARY_PATH="$PREFIX/lib:$PREFIX/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"

FAIL=0
pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*" >&2; FAIL=1; }
info() { printf 'INFO  %s\n' "$*"; }

check_cmd() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    pass "$name: $(command -v "$name")"
  else
    fail "$name not found on PATH"
  fi
}

echo "== Toolchain =="
[[ -x "$UBUNTU_IOS" ]] && pass "launcher: $UBUNTU_IOS" || fail "launcher missing: $UBUNTU_IOS"
check_cmd swift
check_cmd xtool
check_cmd rcodesign

if command -v swift >/dev/null 2>&1; then
  info "$(swift --version 2>&1 | head -n1)"
  if swift sdk list 2>/dev/null | grep -qw darwin; then
    pass "Darwin SDK registered"
  else
    fail "Darwin SDK missing from 'swift sdk list'"
  fi
fi

if [[ -x "$SDK_BUNDLE/OpenAppleMacrosServer" ]]; then
  pass "OpenAppleMacrosServer present"
else
  fail "OpenAppleMacrosServer missing at $SDK_BUNDLE/OpenAppleMacrosServer"
fi

DARWIN_BIN="$SDK_BUNDLE/Developer/Platforms/iPhoneOS.platform/Developer/usr/bin"
for tool in actool xcstringstool momc ibtool; do
  if [[ -x "$DARWIN_BIN/$tool" ]]; then
    pass "Darwin tool: $tool"
  else
    fail "Darwin tool missing: $DARWIN_BIN/$tool"
  fi
done

if [[ -x "$HOME/pymobile3-venv/bin/python" ]] &&
   "$HOME/pymobile3-venv/bin/python" -c 'import pymobiledevice3' >/dev/null 2>&1; then
  pass "pymobiledevice3 venv"
else
  fail "pymobiledevice3 venv missing or broken at $HOME/pymobile3-venv"
fi

echo
echo "== USB / device =="
if command -v idevice_id >/dev/null 2>&1; then
  if output="$(idevice_id -l 2>&1)"; then
    if [[ -z "${output//[[:space:]]/}" ]]; then
      info "no USB iPhone detected (expected when unplugged)"
    else
      info "USB devices: ${output//$'\n'/, }"
    fi
  else
    fail "idevice_id error: ${output//$'\n'/ } (is usbmuxd running?)"
  fi
else
  fail "idevice_id not found (install libimobiledevice-utils)"
fi

echo
echo "== doctor =="
if "$UBUNTU_IOS" doctor; then
  pass "ubuntu-ios doctor"
else
  fail "ubuntu-ios doctor"
fi

if (( SMOKE )); then
  echo
  echo "== Smoke build =="
  smoke_dir="$(mktemp -d "${TMPDIR:-/tmp}/ubuntu-ios-verify.XXXXXX")"
  smoke_log="${TMPDIR:-/tmp}/ubuntu-ios-verify.log"
  if (
    cd "$smoke_dir"
    xtool new VerifyApp --skip-setup
    cd VerifyApp
    "$UBUNTU_IOS" build
  ) >"$smoke_log" 2>&1; then
    app="$(find "$smoke_dir" -maxdepth 4 -name 'VerifyApp.app' -type d | head -n1)"
    if [[ -n "$app" ]]; then
      pass "smoke build: $app"
      binary="$(find "$app" -maxdepth 1 -type f -perm -u+x | head -n1)"
      if [[ -n "$binary" ]] && file "$binary" | grep -q 'Mach-O 64-bit arm64'; then
        pass "smoke binary is Mach-O arm64"
      else
        fail "smoke binary is not Mach-O arm64"
      fi
    else
      fail "smoke build produced no .app bundle"
    fi
  else
    tail -n 40 "$smoke_log" >&2
    fail "smoke build failed (log: $smoke_log)"
  fi
  rm -rf "$smoke_dir"
fi

echo
if (( FAIL )); then
  echo "Verification failed. See references/troubleshooting.md." >&2
  exit 1
fi
echo "All checks passed."
