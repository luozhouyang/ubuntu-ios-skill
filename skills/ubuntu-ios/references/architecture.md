# Architecture and paths

The toolchain reproduces the iOS build/sign/package pipeline on Linux. It does not run Xcode, and it does not include Apple binaries.

```text
Ubuntu 24.04 x86_64
├── official Swift 6.3.x                 ($HOME/.local/swift-6.3.3)
├── private libplist/libimobiledevice    ($HOME/.local/ubuntu-ios-toolchain)
├── xtool                                ($HOME/.local/bin/xtool)
├── Darwin SDK from user's Xcode.xip     ($HOME/.swiftpm/swift-sdks/darwin.artifactbundle)
│   ├── iPhoneOS / iPhoneSimulator / MacOSX SDKs
│   ├── OpenAppleMacrosServer
│   └── Linux darwin-tools (actool, ibtool, momc, xcstringstool)
├── rcodesign                            ($HOME/.local/bin/rcodesign)
├── ipsw                                 ($HOME/.local/bin/ipsw)
├── pymobiledevice3                      ($HOME/pymobile3-venv)
└── ubuntu-ios launcher                  ($HOME/.local/bin/ubuntu-ios)
```

## Why a private libimobiledevice prefix

Ubuntu 24.04's packaged libplist/libimobiledevice are older than the ABI expected by the pinned iOS stack. Replacing system copies would break other packages that depend on them. The installer builds newer versions into `$HOME/.local/ubuntu-ios-toolchain` and the launcher points `LD_LIBRARY_PATH` and `PKG_CONFIG_PATH` at that prefix for toolchain processes only.

Versions used by the pinned installer:

- libplist 2.8.0
- libimobiledevice-glue 1.3.0
- libtatsu 1.0.5
- libimobiledevice 1.4.0

If you run `xtool` directly and see `libplist-2.0.so.12: cannot open shared object file`, the launcher environment was bypassed.

## Why the launcher matters

`~/.local/bin/ubuntu-ios` is a small wrapper that exports:

- `PATH` for the official Swift toolchain and user tools
- `PKG_CONFIG_PATH` for the private prefix
- `LD_LIBRARY_PATH` for the private prefix

It then executes the toolchain repository's `ubuntu-ios` dispatcher. `doctor`, `sdk`, `convert`, `build`, and `ship` all rely on that environment. Running `xtool` or `swift` from a random shell can work for some commands and fail for others, which makes launcher usage the reliable default.

## SDK extraction flow

1. The user supplies `Xcode.xip`.
2. `xtool sdk build` verifies the archive, extracts the needed platform SDKs and toolchain pieces, downloads the Linux toolset and OpenAppleMacros release assets, and writes a portable `darwin.xtoolsdk` bundle.
3. `xtool sdk install` registers the bundle with SwiftPM as `darwin`.
4. The installer places Linux replacements for `actool`, `ibtool`, `momc`, and `xcstringstool` inside the bundle's platform `Developer/usr/bin`.
5. The installer builds the pinned OpenAppleMacros fork and writes zero-byte plugin stubs that outrank the toolchain's own macro plugins.

The cached bundle (`$HOME/.cache/xtool/darwin-*.xtoolsdk`) is toolchain-independent. After a Swift toolchain swap, re-register it with `install-toolchain-upstream.sh --repair` instead of re-extracting Xcode.

## Build and signing flow

`ubuntu-ios build` delegates to `xtool dev build`:

```text
Swift sources + resources
  → SwiftPM / SwiftBuild
  → clang / ld64.lld against the iPhoneOS SDK
  → actool / xcstringstool / momc for resources
  → .app bundle
```

`ubuntu-ios ship` adds the distribution steps:

```text
release build → resource processing → dynamic-product wrapping
  → rcodesign signing (app + embedded code)
  → .ipa creation → local validation → optional App Store Connect upload
```

Apple's server-side validation remains authoritative.

## What is intentionally absent

- Xcode application and Apple SDK binaries
- iOS Simulator
- Apple certificates, provisioning profiles, App Store Connect keys
- A macOS compatibility layer

Complex Xcode build phases, proprietary build tools, unusual binary dependencies, and packages that assume macOS may need project-specific changes.
