---
name: ubuntu-ios
description: Set up, verify, and operate the Ubuntu iOS toolchain (Swift + xtool + rcodesign + pymobiledevice3) to build, sign, and ship Swift/SwiftUI iOS apps from Ubuntu Linux without Xcode or a Mac. Use this skill whenever the user mentions building iOS apps on Ubuntu or Linux, installing Swift 6.x with an Xcode .xip SDK, xtool, rcodesign, pymobiledevice3, iPhone USB pairing on Linux, TestFlight uploads from Linux, or errors such as libplist-2.0.so.12, HTTPClientError.connectTimeout, swift-syntax/swift-png clone stalls, or a missing darwin SDK — even if the user does not say "ubuntu-ios" explicitly.
metadata:
  author: luozhouyang
  version: "1.0.0"
---

# Ubuntu iOS Toolchain

Build and ship iOS apps on Ubuntu 24.04 x86_64 without macOS or the Xcode GUI. This skill wraps the community chain: official Swift, a private libimobiledevice stack, `xtool`, `rcodesign`, `pymobiledevice3`, Linux replacements for Apple build tools, and an iOS SDK extracted from a user-supplied Xcode `.xip`.

This is not Xcode on Linux. There is no iOS Simulator; runtime testing needs a physical iPhone or TestFlight. Apple SDKs, certificates, provisioning profiles, and credentials are never redistributed.

All script paths below are relative to the directory containing this SKILL.md.

## Before starting

Collect these facts before changing the machine:

- Ubuntu 24.04 LTS, x86_64. Other distros/arches are untested; stop and ask if the host differs.
- `sudo` access, 25–40 GB free disk (Xcode extraction is large), and 8 GB+ RAM (16 GB+ preferred).
- A legally obtained `Xcode*.xip` from Apple Developer Downloads. Match generations: Swift 6.3.x ↔ Xcode 26, Swift 6.4.x ↔ Xcode 27.
- A free Apple ID (to download Xcode). A paid Apple Developer membership is required for normal TestFlight/App Store distribution.
- Network access. If the host uses a proxy, read "Proxy and slow downloads" before running the installer; this is the most common failure point.

Agents run in a non-interactive shell. Before a script that calls `sudo`, either the user runs `sudo -v` in that terminal, or `SUDO_ASKPASS` is configured. The bundled scripts fail fast with guidance instead of hanging.

## Quick start

The setup script is idempotent and handles apt dependencies, the missing `liblzma-dev`, proxy propagation, repository cloning, SDK import, `usbmuxd`, `doctor`, and a smoke build:

```bash
scripts/setup.sh --xcode-xip "$HOME/Downloads/Xcode_26.6_Universal.xip"
```

Useful variants:

```bash
scripts/setup.sh --xcode-xip /path/to/Xcode.xip --proxy 127.0.0.1:7897
scripts/setup.sh --verify-only
scripts/setup.sh --xcode-xip /path/to/Xcode.xip --skip-smoke
```

`--dir` changes the toolchain checkout (default `$HOME/src/ubuntu-ios-toolchain`), and `--repo` changes the clone URL. If `--xcode-xip` is omitted, the script looks for exactly one `.xip` in `$HOME/Downloads`; if several exist it lists them instead of guessing.

## What the setup script does

1. Validates Ubuntu 24.04 x86_64, disk, RAM, and `sudo` availability.
2. Installs apt dependencies, including `liblzma-dev` and `zlib1g-dev` which the upstream installer currently omits. `unxip` in the xtool dependency graph fails with `lzma.h not found` without them.
3. If a proxy is supplied, writes a temporary apt proxy config. `sudo` strips `http_proxy`/`https_proxy`, so apt otherwise connects directly and fails behind a proxy. The temp config is removed on exit.
4. Clones `VeloxityNL/ubuntu-ios-toolchain` if needed and runs `install-ubuntu.sh` with `XCODE_XIP` set.
5. Exports `XTL_HTTP_PROXY` for xtool. xtool's AsyncHTTPClient ignores standard proxy variables and uses its own `host:port` variable; without it, `xtool sdk build` ends in `HTTPClientError.connectTimeout`.
6. Creates `~/.local/bin/ubuntu-ios` if the installer did not reach that step, starts `usbmuxd`, runs `ubuntu-ios doctor`, and optionally builds a fresh SwiftUI project.

## Manual path

Use this when the script cannot run (unsupported host, existing custom checkout, or the user wants each step visible):

```bash
git clone https://github.com/VeloxityNL/ubuntu-ios-toolchain.git
cd ubuntu-ios-toolchain
./install-ubuntu.sh
./ubuntu-ios sdk "$HOME/Downloads/Xcode_26.6_Universal.xip"
./ubuntu-ios doctor
```

The installer intentionally stops at the SDK step when `XCODE_XIP` is not set; that is not a failure. Re-run with `XCODE_XIP=/path/to/Xcode.xip ./install-ubuntu.sh`, or run `./ubuntu-ios sdk /path/to/Xcode.xip`.

Never run `install-toolchain-upstream.sh` without `--user-only` on Ubuntu. The non-user mode uses `pacman`/`yay` and is for Arch/Omarchy.

## Proxy and slow downloads

Set the conventional variables first; git, curl, pip, and SwiftPM respect them:

```bash
export http_proxy=http://127.0.0.1:7897
export https_proxy=http://127.0.0.1:7897
export all_proxy=socks5://127.0.0.1:7897
export XTL_HTTP_PROXY=127.0.0.1:7897   # xtool only; no scheme, no trailing slash
```

`scripts/setup.sh` uses `--proxy`/`UBUNTU_IOS_PROXY` or the first non-empty `https_proxy`, `http_proxy`, `HTTPS_PROXY`, `HTTP_PROXY`.

Rules that prevent most stalls:

- `sudo` drops proxy variables. For apt, write `/etc/apt/apt.conf.d/99ubuntu-ios-proxy` with `Acquire::http::Proxy` and `Acquire::https::Proxy`, or run apt with explicit `sudo VAR=value` assignments. Remove the temp config afterwards.
- Prefer `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_n`/`GIT_CONFIG_VALUE_n` over editing the user's global git config. Set `http.version=HTTP/1.1` and `http.lowSpeedLimit=0`; HTTP/2 through a flaky proxy causes `RPC failed ... CANCEL` and `early EOF`.
- `PIP_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/` (or another regional mirror) is useful when PyPI is slow. `uv` parallelizes downloads better than pip; `scripts/setup.sh` leaves this choice to the environment.
- If SwiftPM repeatedly re-clones a large package (`swift-syntax`, `swift-png`), stop the installer and mirror-clone manually into the exact cache path printed in the failing `git clone` line:

  ```bash
  scripts/prefetch-swiftpm-repo.sh \
    https://github.com/swiftlang/swift-syntax.git \
    "$HOME/.cache/org.swift.swiftpm/repositories/swift-syntax-e1f983d3"
  ```

  The `-e1f983d3` suffix is SwiftPM's cache key and must match the log exactly. Replacing it with a guessed path does nothing.

If the xtool SDK step still downloads slowly, the assets are:

```text
https://github.com/xtool-org/darwin-tools-linux-llvm/releases/download/v1.1.0/toolset-x86_64.tar.gz
https://github.com/xtool-org/OpenAppleMacros/releases/download/v1.3.0/OpenAppleMacrosServer-x86_64
```

`aria2c --all-proxy=http://127.0.0.1:7897 -x 8 -s 8` downloads them much faster. Making xtool consume local copies requires a source patch keyed to the pinned xtool commit; treat that as an advanced workaround, not the default. See `references/troubleshooting.md`.

## Verification

Always verify before claiming success:

```bash
ubuntu-ios doctor
swift sdk list          # must print darwin
scripts/verify.sh       # checks binaries, SDK, OAM, Darwin tools
scripts/verify.sh --smoke
```

Expected `doctor` state on a healthy machine without a phone:

- Swift, xtool, rcodesign, and Darwin SDK all present.
- `usbmuxd state: running`.
- `Device detection: no USB iPhone detected` and `Pairing state: not checked (no device)`.
- Exit code 0. With `--device`, no phone is a failure by design.

`scripts/verify.sh --smoke` creates a temporary `xtool new` project and runs `ubuntu-ios build`. Success ends with `Build complete!` and an `.app` containing a Mach-O arm64 executable. This is the quickest end-to-end proof that the SDK, linker, and asset tools work together.

## Daily workflow

Convert an existing Xcode project:

```bash
ubuntu-ios convert MyApp.xcodeproj \
  --target MyApp \
  --out .build/linux-ios \
  --bundle-id com.example.myapp
cd .build/linux-ios
ubuntu-ios build
```

Build, sign, and package from an xtool-ready project:

```bash
ubuntu-ios ship
```

Upload to TestFlight (create the App Store Connect API key first; keep the `.p8` outside the repository):

```bash
export ASC_KEY_PATH="$HOME/keys/AuthKey_XXXXXXXXXX.p8"
export ASC_ISSUER_ID="00000000-0000-0000-0000-000000000000"
export ASC_KEY_ID="XXXXXXXXXX"
ubuntu-ios ship --upload
```

Capabilities such as push notifications and associated domains come from an entitlements file plus a matching provisioning profile:

```bash
export APP_ENTITLEMENTS=/absolute/path/to/MyApp.entitlements
ubuntu-ios ship --upload
```

Physical iPhone:

1. Connect USB with a data-capable cable (charge-only cables can enumerate then drop), unlock, tap **Trust**.
2. `ubuntu-ios doctor --device` must report a paired device.
3. Run `xtool auth` once for device deploys.
4. Run `device-run.sh` from the project directory.

`idevice_id -l` answers USB visibility; `idevicepair validate` answers trust/pairing. They fail for different reasons, so diagnose them separately.

## Important paths

| Path | Purpose |
| --- | --- |
| `$HOME/src/ubuntu-ios-toolchain` | Default checkout used by `scripts/setup.sh` |
| `$HOME/.local/swift-6.3.3` | Swift toolchain |
| `$HOME/.local/ubuntu-ios-toolchain` | Private libplist/libimobiledevice prefix; its `bin/` has newer `idevicepair`/`idevicedevmodectl` |
| `$HOME/.local/bin/ubuntu-ios` | Launcher that exports the private library paths |
| `$HOME/.local/bin/xtool`, `rcodesign`, `ipsw` | Build/sign/device tools |
| `$HOME/.swiftpm/swift-sdks/darwin.artifactbundle` | Registered Darwin SDK, OAM server, Darwin tools |
| `$HOME/pymobile3-venv` | `pymobiledevice3` virtualenv |
| `$HOME/.cache/xtool` | Cached `darwin-*.xtoolsdk` bundles |
| `$HOME/.cache/org.swift.swiftpm/repositories` | SwiftPM bare repository cache |
| `$HOME/.cache/omarchy-apple-dev` | Pinned xtool/OAM sources and builds |

Run `xtool`, `swift`, and `rcodesign` through `~/.local/bin/ubuntu-ios` or with the launcher's `LD_LIBRARY_PATH`. Calling `xtool` directly without the private prefix produces `libplist-2.0.so.12: cannot open shared object file`.

On iOS 26 devices, first swap to a known data-capable cable: a charge-only third-party cable can enumerate the phone and then fail with `RX transfer stalled`. If the cable is good, Ubuntu's packaged `usbmuxd 1.1.1` (2020) can still connect and then fail with the same `RX transfer stalled` or `lockdownd error -8`. The launcher puts the private prefix's `idevicepair`/`idevicedevmodectl` 1.4.0 first. If the stall persists, unload `ipheth` and `apple_mfi_fastcharge`, and if needed build usbmuxd from git HEAD. See `references/troubleshooting.md`.

## Guardrails

- Never commit or paste `.p8` keys, certificates, provisioning profiles, passwords, or `ASC_*` values. The repository `.gitignore` helps but is not a guarantee; review staged files.
- Do not redistribute Xcode or Apple SDK contents. Each user must obtain their own `.xip`.
- Do not replace Ubuntu's system libraries with the private prefix. The launcher uses `LD_LIBRARY_PATH` for a reason; system-wide replacement breaks other packages.
- Keep generated signing material outside the repository, for example `$HOME/.appstoreconnect/private_keys/`.
- Prefer pinned, known-good Swift/Xcode pairs for production. Apple changes SDK formats and signing rules.

## Troubleshooting

Read `references/troubleshooting.md` for symptom → cause → fix details. The highest-frequency failures:

| Symptom | First fix |
| --- | --- |
| `lzma.h file not found` during xtool build | `sudo apt-get install -y liblzma-dev zlib1g-dev` |
| apt `Unable to connect` behind a proxy | apt proxy config; sudo strips proxy env |
| `HTTPClientError.connectTimeout` in `xtool sdk build` | `export XTL_HTTP_PROXY=host:port` |
| `libplist-2.0.so.12` missing | use `~/.local/bin/ubuntu-ios` |
| SwiftPM clone stalls / re-clones | `scripts/prefetch-swiftpm-repo.sh` with the exact cache path |
| `swift sdk list` lacks `darwin` | `ubuntu-ios sdk /path/to/Xcode.xip` |
| `Too many open files` | `ulimit -n 65536` |
| No device detected | data-capable cable; start `usbmuxd`; unlock and trust the iPhone |
| `RX transfer stalled` / phone drops after connect | swap in an official/data cable; then check `usbmuxd` and `ipheth` |

## References

- `references/troubleshooting.md` — network, SwiftPM, SDK, signing, and device failures.
- `references/workflow.md` — conversion, shipping, TestFlight, entitlements, and device runs.
- `references/architecture.md` — how the components fit together and why the private prefix exists.
- `assets/env.example` — proxy, pip mirror, App Store Connect, and entitlements template.
- `evals/evals.json` — realistic prompts for testing this skill.
