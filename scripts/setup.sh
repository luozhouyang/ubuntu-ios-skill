#!/usr/bin/env bash
# Install the Ubuntu iOS toolchain with the fixes learned from clean-machine runs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SWIFT_VERSION="${SWIFT_VERSION:-6.3.3}"
WORKDIR="${UBUNTU_IOS_TOOLCHAIN_DIR:-$HOME/src/ubuntu-ios-toolchain}"
REPO_URL="${UBUNTU_IOS_TOOLCHAIN_REPO:-https://github.com/VeloxityNL/ubuntu-ios-toolchain.git}"
PREFIX="${PREFIX:-$HOME/.local/ubuntu-ios-toolchain}"
SWIFT_PREFIX="${SWIFT_PREFIX:-$HOME/.local/swift-$SWIFT_VERSION}"
XCODE_XIP="${XCODE_XIP:-}"
PROXY="${UBUNTU_IOS_PROXY:-${https_proxy:-${http_proxy:-${HTTPS_PROXY:-${HTTP_PROXY:-}}}}}"
SKIP_SMOKE=0
VERIFY_ONLY=0

say() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") --xcode-xip PATH [options]

Installs the Ubuntu iOS toolchain (Swift, xtool, rcodesign, Darwin SDK) on
Ubuntu 24.04 x86_64 and verifies it.

Options:
  --xcode-xip PATH     Xcode .xip from Apple (Xcode 26 for Swift 6.3.x)
  --dir PATH           Toolchain checkout (default: $WORKDIR)
  --repo URL           Toolchain git URL (default: $REPO_URL)
  --proxy HOST:PORT    HTTP proxy for apt, git, curl, pip, and xtool
  --skip-smoke         Skip the end-to-end SwiftUI build
  --verify-only        Do not install; run scripts/verify.sh
  -h, --help           Show this help

Environment:
  SWIFT_VERSION, PREFIX, SWIFT_PREFIX, XCODE_XIP, UBUNTU_IOS_PROXY,
  UBUNTU_IOS_TOOLCHAIN_DIR, UBUNTU_IOS_TOOLCHAIN_REPO

Non-interactive sudo: run 'sudo -v' in this terminal first, or set
SUDO_ASKPASS to a graphical/CLI askpass helper.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --xcode-xip) XCODE_XIP="${2:-}"; shift 2 ;;
    --dir) WORKDIR="${2:-}"; shift 2 ;;
    --repo) REPO_URL="${2:-}"; shift 2 ;;
    --proxy) PROXY="${2:-}"; shift 2 ;;
    --skip-smoke) SKIP_SMOKE=1; shift ;;
    --verify-only) VERIFY_ONLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (use --help)" ;;
  esac
done

normalize_hostport() {
  local value="$1"
  value="${value#*://}"
  value="${value%/}"
  printf '%s\n' "$value"
}

if [[ -n "$PROXY" ]]; then
  if [[ "$PROXY" == socks* ]]; then
    warn "SOCKS proxy detected; apt and xtool expect an HTTP CONNECT proxy. Prefer the HTTP proxy endpoint."
  fi
  PROXY_HOSTPORT="$(normalize_hostport "$PROXY")"
  [[ "$PROXY_HOSTPORT" == *:* ]] || die "proxy must be HOST:PORT or a URL containing it"
  export http_proxy="http://$PROXY_HOSTPORT"
  export https_proxy="http://$PROXY_HOSTPORT"
  export XTL_HTTP_PROXY="$PROXY_HOSTPORT"
  say "Using proxy $PROXY_HOSTPORT"
else
  PROXY_HOSTPORT=""
fi

if (( VERIFY_ONLY )); then
  exec "$SCRIPT_DIR/verify.sh"
fi

# ---- sudo -----------------------------------------------------------------
SUDO=()
if [[ "$(id -u)" -eq 0 ]]; then
  SUDO=()
elif [[ -n "${SUDO_ASKPASS:-}" ]]; then
  SUDO=(sudo -A)
elif sudo -n true 2>/dev/null; then
  SUDO=(sudo -n)
elif [[ -t 0 ]]; then
  SUDO=(sudo)
else
  die "sudo needs a password. Run 'sudo -v' in this terminal or set SUDO_ASKPASS."
fi

sudo_run() {
  if [[ ${#SUDO[@]} -eq 0 ]]; then
    "$@"
  else
    "${SUDO[@]}" "$@"
  fi
}

# ---- host checks ----------------------------------------------------------
[[ "$(uname -s)" == Linux ]] || die "Linux required"
[[ "$(uname -m)" == x86_64 ]] || die "Ubuntu x86_64 required (found $(uname -m))"
# shellcheck disable=SC1091
. /etc/os-release
if [[ "${ID:-}" != ubuntu ]]; then
  warn "designed for Ubuntu 24.04; found ${PRETTY_NAME:-unknown Linux}"
elif [[ "${VERSION_ID:-}" != 24.04* ]]; then
  warn "tested on Ubuntu 24.04; found ${PRETTY_NAME:-unknown Ubuntu}"
fi

avail_kb="$(df -Pk "$HOME" | awk 'NR==2 {print $4}')"
if [[ "${avail_kb:-0}" -lt 20971520 ]]; then
  die "at least 20 GB free is required under $HOME (found $((avail_kb / 1024 / 1024)) GB)"
elif [[ "${avail_kb:-0}" -lt 31457280 ]]; then
  warn "25-40 GB free recommended; Xcode extraction is large"
fi

mem_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
if [[ "${mem_kb:-0}" -lt 7340032 ]]; then
  warn "8 GB RAM minimum; 16 GB+ recommended for larger apps"
fi

if [[ -z "$XCODE_XIP" ]]; then
  mapfile -t xips < <(find "$HOME/Downloads" -maxdepth 1 -type f -name '*.xip' 2>/dev/null | sort)
  case "${#xips[@]}" in
    0) die "no .xip found. Download one from https://developer.apple.com/download/all/?q=Xcode and pass --xcode-xip PATH" ;;
    1) XCODE_XIP="${xips[0]}" ;;
    *) printf 'Found multiple .xip files; pass --xcode-xip explicitly:\n' >&2
       printf '  %s\n' "${xips[@]}" >&2
       exit 1 ;;
  esac
fi
[[ -f "$XCODE_XIP" ]] || die "Xcode .xip not found: $XCODE_XIP"
[[ -r "$XCODE_XIP" ]] || die "Xcode .xip is not readable: $XCODE_XIP"
xip_bytes="$(stat -c '%s' "$XCODE_XIP")"
if [[ "$xip_bytes" -lt 1073741824 ]]; then
  warn "the .xip is smaller than 1 GB; verify the download is complete"
fi
XCODE_XIP="$(readlink -f "$XCODE_XIP")"
say "Xcode archive: $XCODE_XIP"

# ---- apt proxy + dependencies ---------------------------------------------
APT_CONF="/etc/apt/apt.conf.d/99ubuntu-ios-skill-proxy"
APT_CONF_CREATED=0
TMPBIN=""

cleanup() {
  if (( APT_CONF_CREATED )); then
    sudo_run rm -f "$APT_CONF" >/dev/null 2>&1 || true
  fi
  if [[ -n "$TMPBIN" ]]; then
    rm -rf "$TMPBIN"
  fi
}
trap cleanup EXIT

if [[ -n "$PROXY_HOSTPORT" && ! -e "$APT_CONF" ]]; then
  say "Configuring a temporary apt proxy"
  printf 'Acquire::http::Proxy "http://%s";\nAcquire::https::Proxy "http://%s";\n' \
    "$PROXY_HOSTPORT" "$PROXY_HOSTPORT" | sudo_run tee "$APT_CONF" >/dev/null
  APT_CONF_CREATED=1
fi

say "Installing build dependencies"
sudo_run apt-get update
sudo_run env DEBIAN_FRONTEND=noninteractive apt-get install -y \
  build-essential git curl ca-certificates pkg-config autoconf automake libtool cmake ninja-build \
  python3 python3-venv python3-pip unzip zip xz-utils zstd rsync jq liblzma-dev zlib1g-dev \
  libssl-dev libcurl4-openssl-dev libxml2-dev libsqlite3-dev libedit-dev libncurses-dev \
  libusb-1.0-0-dev usbmuxd libusbmuxd-dev libimobiledevice-dev libimobiledevice-utils libplist-dev \
  poppler-utils libheif-examples

# The upstream installer calls plain `sudo`. When authentication comes from an
# askpass helper, put a tiny wrapper first on PATH so every child uses it.
if [[ ${#SUDO[@]} -gt 0 && "${SUDO[0]}" == sudo && "${SUDO[1]:-}" == "-A" ]]; then
  TMPBIN="$(mktemp -d "${TMPDIR:-/tmp}/ubuntu-ios-sudo.XXXXXX")"
  printf '#!/bin/sh\nexec /usr/bin/sudo -A "$@"\n' > "$TMPBIN/sudo"
  chmod +x "$TMPBIN/sudo"
  export PATH="$TMPBIN:$PATH"
fi

# Keep flaky proxies from corrupting large clones. These are process-local.
export GIT_CONFIG_COUNT=3
export GIT_CONFIG_KEY_0="http.version" GIT_CONFIG_VALUE_0="HTTP/1.1"
export GIT_CONFIG_KEY_1="http.lowSpeedLimit" GIT_CONFIG_VALUE_1="0"
export GIT_CONFIG_KEY_2="http.lowSpeedTime" GIT_CONFIG_VALUE_2="999999"

# ---- checkout + launcher --------------------------------------------------
if [[ ! -d "$WORKDIR/.git" ]]; then
  say "Cloning $REPO_URL"
  mkdir -p "$(dirname "$WORKDIR")"
  git clone --depth 1 "$REPO_URL" "$WORKDIR"
else
  say "Using existing checkout: $WORKDIR"
fi

create_launcher() {
  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/ubuntu-ios" <<EOF
#!/usr/bin/env bash
export PATH="$SWIFT_PREFIX/usr/bin:$PREFIX/bin:\$HOME/.local/bin:\$PATH"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/lib/x86_64-linux-gnu/pkgconfig:\${PKG_CONFIG_PATH:-}"
export LD_LIBRARY_PATH="$PREFIX/lib:$PREFIX/lib/x86_64-linux-gnu:\${LD_LIBRARY_PATH:-}"
exec "$WORKDIR/ubuntu-ios" "\$@"
EOF
  chmod +x "$HOME/.local/bin/ubuntu-ios"
}

if [[ ! -x "$HOME/.local/bin/ubuntu-ios" ]]; then
  create_launcher
  say "Created $HOME/.local/bin/ubuntu-ios"
fi

# ---- install --------------------------------------------------------------
say "Running the toolchain installer (Swift + xtool + SDK; this takes a while)"
(
  cd "$WORKDIR"
  XCODE_XIP="$XCODE_XIP" ./install-ubuntu.sh
)

if [[ ! -x "$HOME/.local/bin/ubuntu-ios" ]]; then
  create_launcher
fi

export PATH="$SWIFT_PREFIX/usr/bin:$HOME/.local/bin:$PATH"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/lib/x86_64-linux-gnu/pkgconfig:${PKG_CONFIG_PATH:-}"
export LD_LIBRARY_PATH="$PREFIX/lib:$PREFIX/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"

if ! swift sdk list 2>/dev/null | grep -qw darwin; then
  say "Registering the Darwin SDK"
  "$HOME/.local/bin/ubuntu-ios" sdk "$XCODE_XIP"
fi

if command -v systemctl >/dev/null 2>&1 && ! pgrep -x usbmuxd >/dev/null 2>&1; then
  sudo_run systemctl start usbmuxd >/dev/null 2>&1 || warn "could not start usbmuxd (plug in the iPhone or start it manually)"
fi

# ---- verify ---------------------------------------------------------------
if [[ -x "$SCRIPT_DIR/verify.sh" ]]; then
  "$SCRIPT_DIR/verify.sh" || die "verification failed; see references/troubleshooting.md"
fi

if (( ! SKIP_SMOKE )); then
  say "Building a temporary SwiftUI app (end-to-end smoke test)"
  smoke_dir="$(mktemp -d "${TMPDIR:-/tmp}/ubuntu-ios-smoke.XXXXXX")"
  smoke_log="${TMPDIR:-/tmp}/ubuntu-ios-smoke.log"
  if ! (
    cd "$smoke_dir"
    xtool new SmokeApp --skip-setup
    cd SmokeApp
    "$HOME/.local/bin/ubuntu-ios" build
  ) >"$smoke_log" 2>&1; then
    tail -n 40 "$smoke_log" >&2
    die "smoke build failed; full log: $smoke_log"
  fi
  rm -rf "$smoke_dir"
  say "Smoke build passed"
fi

say "Done"
cat <<EOF

Next steps:
  ubuntu-ios doctor
  ubuntu-ios doctor --device      # after connecting and trusting an iPhone
  xtool auth                     # once, before device deploys

Project workflow:
  ubuntu-ios convert MyApp.xcodeproj --target MyApp --out .build/linux-ios --bundle-id com.example.myapp
  cd .build/linux-ios && ubuntu-ios build
  ubuntu-ios ship --upload       # after setting ASC_KEY_PATH, ASC_ISSUER_ID, ASC_KEY_ID

Never commit .p8 keys, certificates, provisioning profiles, or credentials.
EOF
