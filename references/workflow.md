# Build, sign, and ship workflow

This assumes `ubuntu-ios doctor` passes and `swift sdk list` contains `darwin`.

## 1. Convert an Xcode project

```bash
ubuntu-ios convert MyApp.xcodeproj \
  --target MyApp \
  --out .build/linux-ios \
  --bundle-id com.example.myapp
```

The converter writes an xtool/SwiftPM adapter next to the output directory. Read every `warning:` line: storyboards/XIBs, unusual build phases, proprietary tools, and macOS-only dependencies often need project-specific changes. Linux has no Interface Builder compiler; the bundled `ibtool` handles a small xib subset only.

Projects already prepared for xtool can skip conversion.

## 2. Build

```bash
cd .build/linux-ios
ubuntu-ios build
```

`ubuntu-ios build` raises the open-file limit and runs `xtool dev build`. For large projects, also check:

- `ulimit -n 65536`
- free disk under `$HOME`
- that no stale module cache from a previous SDK/toolchain is present; delete the project's `.build` directory if an old failure persists

The result is an `.app` bundle under `xtool/` in the project.

## 3. Sign and package

From the generated adapter or any xtool-ready project:

```bash
ubuntu-ios ship
```

The pipeline performs a release build, processes resources, wraps dynamic SwiftPM products where required, signs the app and embedded code, creates an `.ipa`, and runs local validation. Any `FAIL` stops the pipeline.

Signing may create an Apple Distribution certificate and an App Store provisioning profile on the first run. This requires an Apple ID and a paid membership for normal distribution.

## 4. Upload to TestFlight

One-time App Store Connect setup:

1. Users and Access → Integrations → create a team API key with a role that can upload builds (App Manager is typical).
2. Download the `.p8` once and keep it outside the repository, for example `$HOME/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8`.
3. Note the Key ID and Issuer ID.
4. Create the app record in App Store Connect (Apps → + → New App). The API cannot create apps.

Then:

```bash
export ASC_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8"
export ASC_ISSUER_ID="00000000-0000-0000-0000-000000000000"
export ASC_KEY_ID="XXXXXXXXXX"

ubuntu-ios ship --upload
```

`--upload` uploads a build; it does not submit the app for review. When Apple reports `COMPLETE`, the build appears in TestFlight after processing.

## 5. Capabilities and entitlements

```bash
export APP_ENTITLEMENTS=/absolute/path/to/MyApp.entitlements
ubuntu-ios ship --upload
```

The signing changes preserve requested capabilities only when the provisioning profile also grants them. Typical cases: push notifications (APNs), associated domains, app groups, keychain sharing.

## 6. Physical iPhone

There is no iOS Simulator on Ubuntu. Use a physical device or TestFlight.

1. Connect a USB data cable, unlock the iPhone, tap **Trust**.
2. Check visibility and trust separately:

   ```bash
   idevice_id -l
   idevicepair validate
   ubuntu-ios doctor --device
   ```

3. Sign in once for device deploys:

   ```bash
   xtool auth
   ```

4. From the project directory:

   ```bash
   ./device-run.sh
   ```

   `device-run.sh` installs and launches the app. LLDB/device debugging is more involved; consult the toolchain repository's `FINDINGS.md` and `device-run.sh` options.

## 7. Optional: Mac app

The upstream repository also ships `ship-mac.sh` for a SwiftPM package with one executable product. It builds a `.app`, signs it with a Developer ID Application certificate, and optionally notarizes it. This is separate from the iOS path and is not needed for TestFlight.

## Operational notes

- Keep the project checkout and the toolchain checkout separate. The toolchain repository is not a dependency of the app; generated projects reference xtool and the SDK.
- Keep `.p8` keys, certificates, profiles, and `ASC_*` values out of git and out of logs.
- Pin known-good Swift/Xcode versions for production. Apple changes SDK layouts and validation rules.
- Re-run `ubuntu-ios doctor` after any Swift, Xcode, or xtool upgrade.
