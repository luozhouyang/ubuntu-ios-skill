# ubuntu-ios-skill

An [Agent Skill](https://agentskills.io) that sets up, verifies, and operates a
complete iOS toolchain on Ubuntu 24.04 x86_64 — build, sign, and ship
Swift/SwiftUI apps without a Mac or the Xcode GUI.

The skill wraps Swift, `xtool`, `rcodesign`, `pymobiledevice3`, a private
libimobiledevice stack, and an iOS SDK extracted from your own Xcode `.xip`.

## Requirements

- Ubuntu 24.04 LTS, x86_64
- 25–40 GB free disk; 8 GB+ RAM (16 GB+ preferred)
- `sudo` access
- A legally obtained `Xcode*.xip` from Apple (Swift 6.3.x ↔ Xcode 26;
  Swift 6.4.x ↔ Xcode 27)
- A physical iPhone or TestFlight for runtime testing — there is no iOS
  Simulator on Linux

## Install

### Agent ecosystem (recommended)

```bash
npx skills add luozhouyang/ubuntu-ios-skill
```

Add `-g` to install for all projects, or `-a claude-code` to target one agent.

### npm

```bash
npm install -D ubuntu-ios-skill
npx skills experimental_sync -a claude-code -y
```

> `npm install` alone only downloads the files. The skill is not visible to
> your agent until `skills experimental_sync` (or
> [`skills-npm`](https://github.com/antfu/skills-npm)) links it into
> `.agents/skills/` and your agent's skills directory.

## Use

Ask your agent:

> Set up the ubuntu-ios toolchain on this machine using
> ~/Downloads/Xcode_26.6_Universal.xip.

Or run the setup script from the installed skill directory:

```bash
# project install
.agents/skills/ubuntu-ios/scripts/setup.sh \
  --xcode-xip "$HOME/Downloads/Xcode_26.6_Universal.xip"

# global install
~/.claude/skills/ubuntu-ios/scripts/setup.sh \
  --xcode-xip "$HOME/Downloads/Xcode_26.6_Universal.xip"
```

Then verify:

```bash
ubuntu-ios doctor
.agents/skills/ubuntu-ios/scripts/verify.sh --smoke
```

The full operating guide — proxy handling, SwiftPM cache repair, TestFlight
uploads, and device pairing — lives in
[`skills/ubuntu-ios/SKILL.md`](skills/ubuntu-ios/SKILL.md).

## Safety

- Apple SDKs, certificates, and provisioning profiles are never redistributed.
  Every user supplies their own `.xip`.
- Never commit `.p8` keys, certificates, provisioning profiles, or `ASC_*`
  credentials.
- This skill targets Ubuntu 24.04 x86_64. Other distributions and architectures
  are untested.

## Development

```bash
npm test                 # version/name sync + shell syntax + npm pack --dry-run
npx skills add . --list  # verify skill discovery
```

Releases are published from `v*` tags through GitHub Actions with npm
provenance.

## Publishing

The first release creates the package name:

```bash
npm login
npm publish --access public
```

`publishConfig.registry` pins the target to `https://registry.npmjs.org`, so a
local npm mirror does not redirect the publish. If npm refuses to generate
provenance outside CI, add `--no-provenance` to the first manual publish.

After the first publish, configure npmjs.com → the package's Settings →
Trusted Publisher for this repository and `.github/workflows/release.yml`.
Subsequent releases come from tags:

```bash
npm version minor
git push --follow-tags
```

## License

MIT
