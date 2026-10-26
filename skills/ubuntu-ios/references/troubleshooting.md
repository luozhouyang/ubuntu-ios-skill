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

### A converted project re-clones packages into `.build/repositories`

`ubuntu-ios convert` writes a SwiftPM adapter under `.build/linux-ios`. That package resolves dependencies into its **own** repository cache:

```text
.build/linux-ios/.build/repositories/<name>-<hash>
```

If the global cache (`$HOME/.cache/org.swift.swiftpm/repositories`) is already warm but the new project directory is not, the first `xtool dev build` re-clones everything and appears to hang on the same packages you just prefetched. Reuse the warm cache instead of downloading twice:

```bash
mkdir -p /path/to/project/.build/linux-ios/.build/repositories
for repo in "$HOME"/.cache/org.swift.swiftpm/repositories/*; do
  ln -sfn "$repo" "/path/to/project/.build/linux-ios/.build/repositories/$(basename "$repo")"
done
```

SwiftPM accepts these symlinks. The cache keys must match exactly; if a package still clones, read the failing `git clone ... --mirror` line and use that path.

The same applies to the toolchain source build: `xtool`'s own checkout needs its `Package.resolved` pins, and deleting `Package.resolved` to "fix" a resolution error forces a full re-resolution over the network.

### SwiftPM through a proxy silently ignores `XTL_HTTP_PROXY`

`XTL_HTTP_PROXY` is xtool-only. SwiftPM and its `git` children read `http_proxy`/`https_proxy`; without them the first build stalls on `github.com`. Export both families:

```bash
export http_proxy=http://127.0.0.1:7897
export https_proxy=http://127.0.0.1:7897
export XTL_HTTP_PROXY=127.0.0.1:7897
```

One command can need both: `xtool dev run` talks to Apple (XTL_HTTP_PROXY) and clones packages (http_proxy) in the same invocation.

## xtool toolset/OAM downloads

The SDK builder fetches two GitHub release assets:

| xtool | toolset | OpenAppleMacros |
| --- | --- | --- |
| cache checkout (older) | `darwin-tools-linux-llvm/releases/download/v1.1.0/toolset-x86_64.tar.gz` | `OpenAppleMacros/releases/download/v1.3.0/OpenAppleMacrosServer-x86_64` |
| v1.24.0 (current) | `.../v1.1.0/toolset-x86_64.tar.gz` | `OpenAppleMacros/releases/download/v1.4.1/OpenAppleMacrosServer-x86_64.tar.gz` |

Read `Sources/XToolSupport/SDKBuilder.swift` in the xtool version you actually run; the pinned versions live there. Do not download the asset version for the wrong xtool release.

**Both downloads stream straight into `tar xzf -`.** There is no cache and no HTTP range resume: a dropped connection or a slow proxy restarts the transfer from zero. At ~70 KB/s through a congested proxy the SDK step can stall for 40+ minutes and look hung.

### Use local assets instead of patching xtool

xtool ≥ 1.24.0 accepts pre-downloaded assets through environment variables, so do **not** patch `SDKBuilder.swift`:

```bash
mkdir -p "$HOME/.cache/xtool/sdk-assets"
aria2c --all-proxy=http://127.0.0.1:7897 -x 8 -s 8 -k 1M \
  -d "$HOME/.cache/xtool/sdk-assets" -o toolset-x86_64.tar.gz \
  https://github.com/xtool-org/darwin-tools-linux-llvm/releases/download/v1.1.0/toolset-x86_64.tar.gz
aria2c --all-proxy=http://127.0.0.1:7897 -x 8 -s 8 -k 1M \
  -d "$HOME/.cache/xtool/sdk-assets" -o OpenAppleMacrosServer-x86_64.tar.gz \
  https://github.com/xtool-org/OpenAppleMacros/releases/download/v1.4.1/OpenAppleMacrosServer-x86_64.tar.gz
```

Then point the SDK build at them (absolute paths to a file **or** a directory):

```bash
export XTL_TOOLSET_TARBALL="$HOME/.cache/xtool/sdk-assets/toolset-x86_64.tar.gz"
export XTL_OAM_TARBALL="$HOME/.cache/xtool/sdk-assets/OpenAppleMacrosServer-x86_64.tar.gz"
xtool sdk install --slim "$HOME/Downloads/Xcode_26.6_Universal.xip"
```

Verify the archive before trusting it:

```bash
tar tzf "$HOME/.cache/xtool/sdk-assets/toolset-x86_64.tar.gz" | head
```

A truncated file fails with `gzip: unexpected end of file` partway through extraction, after the previous SDK has already been removed (see the `swiftc` failure below).

On xtool versions older than 1.24.0 the env overrides do not exist. Prefer upgrading xtool rather than patching a fork; if you must patch, key it to the exact commit, expect `xtool --version` to show `(dirty)`, and drop the patch once you upgrade.

After the installer finishes, `install_oam` builds the pinned OpenAppleMacros fork from source and overwrites the downloaded binary, so the final OAM server does not depend on the release asset.

### Download progress does not print until extraction starts

`xtool sdk install` buffers the download; a silent terminal for many minutes is normal. Check progress from another shell instead of interrupting:

```bash
ls -lh "$HOME/.cache/xtool/sdk-assets" 2>/dev/null
ps -o pid,etime,cmd -C xtool
```

Piping through `tr '\r' '\n' | tail -40` hides the progress bars; use `grep -vE '^\[(Downloading|Extracting|Installing)'` when you only want warnings, or write the full log to a file.

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

### `Darwin SDK is out of date, and was installed in 'slim' mode`

A full error from `xtool dev run` / `ubuntu-ios build`:

```text
Error: Darwin SDK is out of date, and was installed in 'slim' mode.

Slim SDKs take less disk space, but can't be auto-updated.
Please install a new SDK with
    xtool sdk install [--slim]
```

The SDK bundle records the xtool format it was built with, and a newer xtool rejects older bundles instead of migrating them:

```bash
cat "$HOME/.swiftpm/swift-sdks/darwin.artifactbundle/darwin-sdk-version.txt"
# epoch=2,darwinTools=1.1.0,oam=1.3.0   ← too old for xtool 1.24.0
# epoch=4,darwinTools=1.1.0,oam=1.4.1   ← expected
```

Rebuild it with the xtool you are actually running (do not restore an old bundle). The mismatch is purely local; no login or device state is lost:

```bash
export PATH="$HOME/.local/swift-6.3.3/usr/bin:$HOME/.local/ubuntu-ios-toolchain/bin:$HOME/.local/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/.local/ubuntu-ios-toolchain/lib:$HOME/.local/ubuntu-ios-toolchain/lib/x86_64-linux-gnu"
export XTL_TOOLSET_TARBALL="$HOME/.cache/xtool/sdk-assets/toolset-x86_64.tar.gz"
export XTL_OAM_TARBALL="$HOME/.cache/xtool/sdk-assets/OpenAppleMacrosServer-x86_64.tar.gz"
ulimit -n 65536
xtool sdk install --slim "$HOME/Downloads/Xcode_26.6_Universal.xip"
```

Then confirm `swift sdk list` prints `darwin`.

### `Could not find executable 'swiftc' in PATH` during `xtool sdk install`

The SDK build shells out to the Swift compiler. If the Swift toolchain is installed but not on `PATH`, the install fails **at the very end** — after extraction — and has already deleted the previous bundle:

```text
Error: Could not find executable 'swiftc' in PATH
```

The machine is left with no Darwin SDK at all, and the next build reports the SDK as missing rather than out of date. Always invoke `xtool sdk install` with the toolchain on `PATH`:

```bash
export PATH="$HOME/.local/swift-6.3.3/usr/bin:$PATH"
command -v swiftc   # must print an absolute path before starting
```

Diagnose the aftermath before retrying:

```bash
ls "$HOME/.swiftpm/swift-sdks/"                 # leftover darwin.artifactbundle.tmp?
cat "$HOME/.swiftpm/swift-sdks/darwin.artifactbundle/darwin-sdk-version.txt" 2>/dev/null
ls "$HOME/.cache/xtool/" | grep -E '^(darwin-|pid-)'
```

Clean up stale state and retry:

```bash
rm -rf "$HOME/.swiftpm/swift-sdks/darwin.artifactbundle.tmp"
rm -f "$HOME"/.cache/xtool/pid-*.lock
```

`xtool` refuses to start a second SDK install while a lock file exists, even if the process is long gone, so a killed run can block every later attempt with no useful message.

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

### Restarting `usbmuxd` without an interactive password prompt

Agents and scripts cannot answer `sudo`'s password prompt. Use an askpass helper so the password is entered in a GUI dialog and never appears in logs or shell history:

```bash
cat > /tmp/sudo-askpass-usbmuxd.sh <<'EOF'
#!/bin/sh
zenity --password --title="usbmuxd restart"
EOF
chmod 700 /tmp/sudo-askpass-usbmuxd.sh

SUDO_ASKPASS=/tmp/sudo-askpass-usbmuxd.sh sudo -A systemctl restart usbmuxd
idevice_id -l
```

Alternative: ask the user to run `sudo -v` in the terminal first, then reuse the cached credential within its timeout. Never put the password in a command line, an environment variable, or a file.

### Installing and launching on the device

`xtool dev run --usb` performs build → package → provision → sign → install → launch in one shot:

```bash
cd /path/to/project/.build/linux-ios
export PATH="$HOME/.local/swift-6.3.3/usr/bin:$HOME/.local/ubuntu-ios-toolchain/bin:$HOME/.local/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/.local/ubuntu-ios-toolchain/lib:$HOME/.local/ubuntu-ios-toolchain/lib/x86_64-linux-gnu"
export XTL_HTTP_PROXY=127.0.0.1:7897
ulimit -n 65536
xtool dev run --usb
```

Successful output ends with `Build complete!` followed by `[Installing] 100%` and `[Verifying] 100%`. It can stop after `[Verifying]` without printing a launch line and still have installed the app; verify independently:

```bash
~/pymobile3-venv/bin/pymobiledevice3 apps list --udid <UDID> | grep -i <app>
~/pymobile3-venv/bin/pymobiledevice3 developer dvt launch --udid <UDID> <bundle-id>
```

Notes on the free-account flow:

- xtool prefixes the bundle ID with the team: `com.example.app` → `XTL-<TEAMID>.com.example.app`. Device tools must use the prefixed ID; `xtool.yml` keeps the unprefixed one.
- The provisioning profile expires in 7 days. Re-run `xtool dev run --usb` after expiry; the app then reinstalls over the old one and keeps its data container.
- If iOS reports the developer as untrusted, accept it in **Settings → General → VPN & Device Management**.
- `xtool dev run --usb` requires Developer Mode. `idevicedevmodectl reveal` only exposes the menu item; `idevicedevmodectl enable` fails with `Device has a passcode set`, so the toggle has to be flipped by hand on the device, and it reboots.

### `xtool auth` / device deploy fails

Run `xtool auth` once and sign in with the Apple ID. For free accounts, expect short-lived provisioning; a paid membership is required for normal device/TestFlight work. Login itself has its own failure modes; see the next section.

## Apple ID login (GrandSlam)

`xtool auth login` authenticates against Apple's GrandSlam (GSA) service, not against a local account store. Failures here look like network or TLS problems but are usually identity problems.

### `This action cannot be completed at this time. (-80045)`

```text
Apple ID: you@example.com
Password:
Logging in...
Error: This action cannot be completed at this time. (-80045)
```

-80045 is Apple rejecting the *client identity*, not the credentials. Apple cross-checks several headers on `performSRP` / `GsService2`:

- `X-MMe-Client-Info` — must be a plausible Mac model, e.g. `<MacBookPro11,5> <Mac OS X;10.14.6;18G103> <com.apple.AuthKit/1 (com.apple.akd/1.0)>`
- the `User-Agent` — must look like a real AuthKit/Xcode client, **not** `xtool/...`
- the anisette headers (`X-Apple-I-MD*`) — must come from a working ADI provider

If any of these disagree with each other, Apple answers -80045 before it ever checks the password. A wrong password produces a different code (typically -20101), so -80045 means "fix the client, not the account".

**Fix: run xtool ≥ 1.24.0.** Older builds (including many forks in `$HOME/.cache/omarchy-apple-dev`) send an older client-info/UA pair that Apple stopped accepting for free Apple IDs. Upstream addressed this in PR #244 (modern User-Agent) and PR #348 (consistent client identity from the anisette provider). Do not attempt to hand-patch a cached fork: the headers and the anisette provider's `client_info` endpoint must agree, and a partial patch turns -80045 into an opaque 503.

```bash
xtool --version                    # expect v1.24.0 or newer
~/.local/bin/xtool auth login
```

### `HTTP 503` from `gsa.apple.com/grandslam/GsService2`

A 503 on the login POST, or on `GsService2/lookup`, is Apple's edge refusing the request. It is almost always the same identity mismatch as -80045: the device-info dictionary, client-info string, and User-Agent were inconsistent, so the request never reached the SRP verifier. Retrying the same build does not help.

Confirm it is not TLS before changing anything:

```bash
openssl s_client -connect gsa.apple.com:443 -servername gsa.apple.com </dev/null 2>/dev/null \
  | grep -E 'Verify return code|issuer='
# Verify return code: 0 (ok) — TLS is fine; the rejection is application-level
```

xtool (≥ 1.24.0) bundles the Apple Root CA, G2 and G3 roots, so `gsa.apple.com` and `gsd.apple.com` verify without system trust changes. Do not disable verification to "fix" a 503; `XTL_DISABLE_TLS_VALIDATION=1` only masks a real certificate problem and never resolves an identity rejection.

If TLS verifies cleanly and you are already on 1.24.0, check the anisette provider before anything else.

### Anisette/ADI provider is down or mismatched

Login needs machine-identity headers from an ADI provisioning service. xtool 1.24.0's default is the remote provider:

```text
https://mac-ani.jkcoxson.com
```

That host is community-run and can be slow, rate-limited, or offline; a dead provider surfaces as a timeout, a 502, or a failed WebSocket during `v3/provisioning_session`. Do not confuse this with a GSA error. Check reachability:

```bash
curl -sS -m 10 https://mac-ani.jkcoxson.com/v3/client_info
```

If it is unavailable, either wait/retry or run a local XADI/omnisette-compatible server and point xtool at it (requires a build that exposes the provider URL; the default binary does not). The same provider must be used for `login` and every later `run`/`ship`, because the saved token is bound to it.

### Login succeeds, then a build says "not logged in"

xtool stores the token at:

```text
$HOME/.config/xtool/data/XTLAuthToken
```

The token records which anisette provider issued it. `xtool auth status` (and any command that loads the token) **deletes the token if the current binary's provider ID differs**. In practice: if you ran `xtool auth login` with the official v1.24.0 binary and later invoke an older fork or a different build, the token is silently wiped.

Symptoms: `xtool auth status` prints a logged-in user with an expiry a year out; then the next command, run with a different binary, reports `Not logged in`. Nothing is corrupt — you simply have to log in again with the binary you intend to use.

Rules that avoid a second interactive login:

```bash
# One binary, used everywhere
readlink -f ~/.local/bin/xtool        # confirm which build the symlink points at
xtool auth status                     # only from that same build
```

- Keep a single `~/.local/bin/xtool` symlink and do not interleave forks.
- Never run an old fork's `auth status` "just to check".
- `xtool dev run` and `xtool ship` with a different build invalidate the token the same way.

### `auth login` cannot prompt / "Operation unsupported"

`xtool auth login` is interactive: it reads the Apple ID and password from a terminal and prompts for the 2FA code. It fails in non-TTY contexts, including commands executed through an agent harness's `!` shell:

```text
Error: Operation unsupported
```

Run it in a real terminal window. Everything non-interactive (`xtool dev run`, `xtool sdk install`) can proceed from a script afterwards, because the token is on disk.

If the account has 2FA, the code is requested at the prompt; there is no separate flag. Password-mode login works for free Apple IDs; app-specific passwords are not required.

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
