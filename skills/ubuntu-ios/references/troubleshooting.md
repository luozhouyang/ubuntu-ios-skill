# Troubleshooting

Start with the cheap checks:

```bash
ubuntu-ios doctor
swift sdk list
xtool --version
rcodesign --version
```

Keep the installer log. Most failures below leave a precise command or path in it; searching the log for `error:` is faster than guessing.

## Network and proxy

### apt cannot connect, but curl works

`sudo` resets the environment by default, so `http_proxy`/`https_proxy` reach curl but not apt. Either pass the variables explicitly:

```bash
sudo env http_proxy=http://127.0.0.1:7897 https_proxy=http://127.0.0.1:7897 apt-get update
```

or write a temporary apt config and remove it when done:

```bash
sudo tee /etc/apt/apt.conf.d/99ubuntu-ios-proxy >/dev/null <<'EOF'
Acquire::http::Proxy "http://127.0.0.1:7897";
Acquire::https::Proxy "http://127.0.0.1:7897";
EOF
sudo apt-get update
sudo rm -f /etc/apt/apt.conf.d/99ubuntu-ios-proxy
```

`scripts/setup.sh` does this automatically when `--proxy` or `UBUNTU_IOS_PROXY` is set.

### xtool SDK build ends with `HTTPClientError.connectTimeout`

xtool's AsyncHTTPClient does not read `http_proxy`/`https_proxy`. It has its own variable, without a scheme:

```bash
export XTL_HTTP_PROXY=127.0.0.1:7897
```

Then re-run `ubuntu-ios sdk /path/to/Xcode.xip` or the installer. This is the fix for timeouts while downloading `toolset-x86_64.tar.gz` or `OpenAppleMacrosServer-x86_64`.

### Git clones fail with `RPC failed; curl 92 ... CANCEL` or `early EOF`

HTTP/2 through a flaky proxy is the usual cause. Use HTTP/1.1 and disable the low-speed cutoff for the setup process:

```bash
export GIT_CONFIG_COUNT=2
export GIT_CONFIG_KEY_0=http.version GIT_CONFIG_VALUE_0=HTTP/1.1
export GIT_CONFIG_KEY_1=http.lowSpeedLimit GIT_CONFIG_VALUE_1=0
```

`scripts/setup.sh` sets these only for its child processes; it does not edit global git config.

### PyPI downloads are very slow

A regional mirror helps:

```bash
export PIP_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/
```

`uv` parallelizes downloads and is usually much faster than pip. If the venv already exists:

```bash
uv pip install --python "$HOME/pymobile3-venv/bin/python" pymobiledevice3
```

## Large or stalled SwiftPM clones

SwiftPM keeps bare mirrors under:

```text
$HOME/.cache/org.swift.swiftpm/repositories/<name>-<hash>
```

When a clone stalls, stop the installer and SwiftPM first. Then copy the exact destination from the failing line, for example:

```bash
scripts/prefetch-swiftpm-repo.sh \
  https://github.com/swiftlang/swift-syntax.git \
  "$HOME/.cache/org.swift.swiftpm/repositories/swift-syntax-e1f983d3"
```

Known paths seen with the pinned toolchain:

| Package | Cache path |
| --- | --- |
| swift-syntax | `$HOME/.cache/org.swift.swiftpm/repositories/swift-syntax-e1f983d3` |
| swift-png | `$HOME/.cache/org.swift.swiftpm/repositories/swift-png-fab7dc4e` |

The hash suffix is internal to SwiftPM. If your log prints a different suffix, use that one. A correct mirror is a **bare** repository; `git -C <path> rev-parse --is-bare-repository` must print `true`.

SwiftPM may discard the directory and start over if an earlier clone process was still running. Kill the old process before prefetching, and do not run two installers concurrently.

## xtool toolset/OAM downloads

The SDK builder fetches two GitHub release assets:

```text
https://github.com/xtool-org/darwin-tools-linux-llvm/releases/download/v1.1.0/toolset-x86_64.tar.gz
https://github.com/xtool-org/OpenAppleMacros/releases/download/v1.3.0/OpenAppleMacrosServer-x86_64
```

A multi-connection downloader is dramatically faster on slow proxies:

```bash
aria2c --all-proxy=http://127.0.0.1:7897 -x 8 -s 8 -k 1M \
  -d /tmp -o toolset-x86_64.tar.gz \
  https://github.com/xtool-org/darwin-tools-linux-llvm/releases/download/v1.1.0/toolset-x86_64.tar.gz

aria2c --all-proxy=http://127.0.0.1:7897 -x 8 -s 8 -k 1M \
  -d /tmp -o OpenAppleMacrosServer-x86_64 \
  https://github.com/xtool-org/OpenAppleMacros/releases/download/v1.3.0/OpenAppleMacrosServer-x86_64
```

Upstream xtool always downloads these; it has no documented local-file option. Making it consume pre-downloaded files requires patching `SDKBuilder.swift` in the cached xtool checkout (add an env-checked branch in `installToolset`/`installMacros`, rebuild, reinstall). That patch is keyed to the pinned xtool commit, marks `xtool --version` as `(dirty)`, and must be re-applied if the commit changes. Prefer `XTL_HTTP_PROXY` plus a faster proxy; use the patch only when downloads are otherwise unusable.

After the installer finishes, `install_oam` builds the pinned OpenAppleMacros fork from source and overwrites the downloaded binary, so the final OAM server does not depend on the release asset.

## Toolchain and SDK

### `lzma.h file not found` while building xtool

`unxip` needs the liblzma headers; the upstream installer does not install them:

```bash
sudo apt-get install -y liblzma-dev zlib1g-dev
```

Then re-run the installer. The xtool build resumes incrementally.

### `xtool: error while loading shared libraries: libplist-2.0.so.12`

The private libimobiledevice prefix is not on the loader path. Use the launcher:

```bash
~/.local/bin/ubuntu-ios doctor
```

or export:

```bash
export LD_LIBRARY_PATH="$HOME/.local/ubuntu-ios-toolchain/lib:$HOME/.local/ubuntu-ios-toolchain/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
```

Do not replace Ubuntu's system libraries. The private prefix exists so system packages keep their own ABI.

### `swift sdk list` does not show `darwin`

```bash
ubuntu-ios sdk /path/to/Xcode.xip
swift sdk list
```

If a cached bundle exists, re-register it without the `.xip`:

```bash
xtool sdk install "$HOME/.cache/xtool/darwin-iPhoneOS26.5.xtoolsdk"
```

The Swift and Xcode generations must match: Swift 6.3.x ↔ Xcode 26, Swift 6.4.x ↔ Xcode 27. A mismatch usually fails later with missing modules or link errors, not at import time.

### Re-register after a Swift toolchain swap

Pairing and Apple ID state live in user-global paths and survive swaps. Re-register the SDK into the new toolchain:

```bash
export PATH="/path/to/new/swift/usr/bin:$PATH"
~/src/ubuntu-ios-toolchain/install-toolchain-upstream.sh --repair
```

`--repair` uses the cached `darwin-*.xtoolsdk` when available.

### `Too many open files`

```bash
ulimit -n 65536
ubuntu-ios build
```

`ubuntu-ios build` and `ship` already attempt this.

### Disk fills during SDK extraction

Xcode extraction can transiently need tens of GB. Keep 25–40 GB free. Old cached SDK bundles live in `$HOME/.cache/xtool`; remove unused `darwin-*` directories only when no build needs them.

### actool / xcstringstool / momc missing

The installer places Linux stand-ins under:

```text
$HOME/.swiftpm/swift-sdks/darwin.artifactbundle/Developer/Platforms/iPhoneOS.platform/Developer/usr/bin
```

Re-run the installer or `install-toolchain-upstream.sh --repair` to restore them.

## Device and USB

### `Device detection: ERROR: Unable to retrieve device list!`

Start `usbmuxd`:

```bash
sudo systemctl start usbmuxd
```

The Ubuntu service is udev-triggered; without a phone it may be inactive. `scripts/setup.sh` starts it on a best-effort basis. If the service is running but the device still disappears, try the official/data cable first; see the iOS 26 stall section below.

### iOS 26: `RX transfer stalled` or `lockdownd error -8`

**Check the cable first.** A charge-only or poor-quality third-party cable can enumerate the iPhone (serial number visible, configuration 4) and then stall the bulk endpoint on the first RX transfer. In a confirmed case, replacing a third-party charging cable with the official Apple cable fixed pairing immediately, with no change to `usbmuxd`, libimobiledevice, or kernel drivers. Use a known data-capable cable connected directly to the mainboard before changing the software stack.

If the cable is known-good, Ubuntu 24.04 ships `usbmuxd 1.1.1` from 2020. It can enumerate an iOS 26 iPhone, set configuration 4, then fail during the bulk transfer:

```text
Connected to v2.0 device ... 
RX transfer stalled for device ...
Removed device ...
```

or:

```text
ERROR: Could not connect to lockdownd, error code -8
```

Two kernel drivers can make this worse: `ipheth` (USB tethering) and `apple_mfi_fastcharge`. Keep the phone unlocked, then try:

```bash
sudo systemctl stop usbmuxd
sudo modprobe -r ipheth apple_mfi_fastcharge
printf 'blacklist ipheth\nblacklist apple_mfi_fastcharge\n' | \
  sudo tee /etc/modprobe.d/blacklist-iphone-usb.conf
sudo systemctl start usbmuxd
```

Blacklisting `ipheth` disables USB tethering; remove that line if you need it. Replug the iPhone and pair with the newer private tools:

```bash
export PATH="$HOME/.local/ubuntu-ios-toolchain/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/.local/ubuntu-ios-toolchain/lib:$HOME/.local/ubuntu-ios-toolchain/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
idevicepair pair
idevicepair validate
```

If the stall persists, build usbmuxd from git HEAD (the project has many fixes since the 2020 release) and run that binary instead of `/usr/sbin/usbmuxd`:

```bash
git clone https://github.com/libimobiledevice/usbmuxd.git
cd usbmuxd
./autogen.sh --prefix="$HOME/.local/ubuntu-ios-toolchain"
make -j"$(nproc)"
sudo systemctl stop usbmuxd
sudo ./usbmuxd --user usbmux -f -v
```

For persistence, point a systemd drop-in's `ExecStart` at the built binary. Keep the phone unlocked during pairing; `idevicedevmodectl enable` can enable Developer Mode later but reboots the device.

### Visible UDID but pairing fails

USB visibility and lockdown trust are separate:

```bash
idevice_id -l          # does usbmuxd see the device?
idevicepair validate   # is this host trusted?
```

Unlock the iPhone and tap **Trust**. Common states reported by `ubuntu-ios doctor`:

- not paired with this host
- waiting for the Trust dialog
- trust denied on the device
- device locked; unlock it first

If USB visibility itself fails, check the cable first (a charge-only cable can show a UDID and then stall), then the USB port, udev rules, and `usbmuxd` logs.

### `xtool auth` / device deploy fails

Run `xtool auth` once and sign in with the Apple ID. For free accounts, expect short-lived provisioning; a paid membership is required for normal device/TestFlight work.

## Signing and TestFlight

### Apple rejects the uploaded build

Read the complete `ubuntu-ios ship --upload` output. The local validator catches packaging and signing problems, but App Store Connect validation is authoritative. Common causes: missing app record, bundle ID mismatch, wrong provisioning profile, unsupported entitlement, or an icon/asset problem.

### Upload fails before validation

Check:

```bash
echo "$ASC_KEY_PATH"; echo "$ASC_ISSUER_ID"; echo "$ASC_KEY_ID"
```

The `.p8` must exist outside the repository, the key ID and issuer ID must come from the same App Store Connect API key, and the key needs a role that can upload builds (App Manager is typical). The API cannot create the app record; create it in App Store Connect first.

### Entitlements are dropped

`APP_ENTITLEMENTS` must point to an absolute path, and the provisioning profile must grant the same capabilities. A requested capability that the profile does not authorize is not preserved.

## Security

Never commit or paste:

- `.p8` App Store Connect keys
- signing private keys and certificates
- provisioning profiles
- `ASC_*` values, passwords, or generated secret material

Keep them under a private directory such as `$HOME/.appstoreconnect/private_keys/`. The repository `.gitignore` blocks common patterns but does not replace reviewing staged files.

## Ubuntu-specific rules

- Run the upstream installer with `--user-only`. Without it, the script uses `pacman`/`yay` and is meant for Arch/Omarchy.
- Keep the libplist/libimobiledevice stack in `$HOME/.local/ubuntu-ios-toolchain`. Do not install it over system copies.
- `ubuntu-ios` is the supported entry point because it sets `PATH`, `PKG_CONFIG_PATH`, and `LD_LIBRARY_PATH` consistently.
