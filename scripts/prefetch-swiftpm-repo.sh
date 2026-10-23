#!/usr/bin/env bash
# Mirror-clone a repository into SwiftPM's bare cache at the exact path SwiftPM
# prints in its failing `git clone` line. Use this when a large package clone
# (swift-syntax, swift-png) stalls or is repeatedly discarded.
set -euo pipefail

FORCE=0
ARGS=()

usage() {
  cat <<'EOF'
Usage: prefetch-swiftpm-repo.sh [--force] REPO_URL CACHE_PATH

  REPO_URL    e.g. https://github.com/swiftlang/swift-syntax.git
  CACHE_PATH  the destination from SwiftPM's log, e.g.
              ~/.cache/org.swift.swiftpm/repositories/swift-syntax-e1f983d3

The path suffix is SwiftPM's cache key. Copy it exactly; guessing it does not
work. Stop the installer/SwiftPM process first, otherwise it may delete the
directory and clone again. Respects http_proxy/https_proxy.

Options:
  --force     Re-clone even when CACHE_PATH already looks valid
  -h, --help  Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

[[ ${#ARGS[@]} -eq 2 ]] || { usage >&2; exit 2; }
REPO_URL="${ARGS[0]}"
CACHE_PATH="${ARGS[1]}"

[[ "$REPO_URL" =~ ^https?:// ]] || { echo "error: REPO_URL must be http(s)" >&2; exit 2; }
case "$CACHE_PATH" in
  "~/"*) CACHE_PATH="$HOME/${CACHE_PATH#\~/}" ;;
esac

if [[ -e "$CACHE_PATH" ]]; then
  if git -C "$CACHE_PATH" rev-parse --is-bare-repository 2>/dev/null | grep -qx true; then
    if (( FORCE )); then
      echo "==> Removing existing mirror (--force): $CACHE_PATH"
      rm -rf "$CACHE_PATH"
    else
      echo "Already a bare repository: $CACHE_PATH"
      git -C "$CACHE_PATH" rev-parse --short HEAD 2>/dev/null || true
      echo "Use --force to replace it."
      exit 0
    fi
  else
    echo "==> Removing incomplete cache directory: $CACHE_PATH"
    rm -rf "$CACHE_PATH"
  fi
fi

mkdir -p "$(dirname "$CACHE_PATH")"
echo "==> Mirror-cloning $REPO_URL"
echo "    -> $CACHE_PATH"
git \
  -c http.version=HTTP/1.1 \
  -c http.lowSpeedLimit=0 \
  -c http.lowSpeedTime=999999 \
  -c core.symlinks=true \
  -c core.fsmonitor=false \
  -c core.longpaths=true \
  clone --mirror --progress "$REPO_URL" "$CACHE_PATH"

echo "==> Verifying"
bare="$(git -C "$CACHE_PATH" rev-parse --is-bare-repository)"
refs="$(git -C "$CACHE_PATH" show-ref | wc -l | tr -d ' ')"
echo "bare=$bare refs=$refs size=$(du -sh "$CACHE_PATH" | cut -f1)"
[[ "$bare" == true && "$refs" -gt 0 ]] || {
  echo "error: mirror looks invalid" >&2
  exit 1
}
echo "Done. Restart the installer; SwiftPM should now fetch from this cache."
