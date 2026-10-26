# ubuntu-ios-skill npm 分发改造 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 subagent-driven-development（推荐）或 executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 把现有 skill 仓库改造成同时可通过 `npx skills add` 和 npm 安装的包，并加入版本一致性检查、CI 与基于 tag 的发布流程。

**架构：** skill 内容整体移入 `skills/ubuntu-ios/`，仓库根目录只保留 npm 元数据、文档、CI 和检查脚本。`package.json` 用 `files: ["skills/"]` 白名单发布内容；`tools/check-version.mjs` 保证 `package.json` 与 `SKILL.md` 的版本和名称一致；GitHub Actions 负责 CI 与带 provenance 的 npm 发布。

**技术栈：** Node.js 22（CI）/ Node.js 24（本地）、npm 11、GitHub Actions、`skills` CLI、Bash。

**规格：** `docs/superpowers/specs/2026-10-26-npm-distribution-design.md`

---

## 全局约束

- npm 包名固定为 `ubuntu-ios-skill`，初始版本 `1.0.0`，许可证 MIT。
- skill 目录固定为 `skills/ubuntu-ios/`，frontmatter `name` 必须为 `ubuntu-ios`。
- `package.json` 只允许 `files: ["skills/"]` 白名单；不得添加 `bin`、`main`、`exports`、`engines`、`postinstall`。
- npm 自动包含 `package.json`、`README.md`、`LICENSE`；其余文件不得进入 tarball。
- CI 使用 Node 22；发布必须使用 `npm publish --provenance --access public`。
- 本计划只做本地改造与验证，**不执行 `npm publish`、不 push、不打 tag**。
- 不得在仓库中出现 `.p8`、证书、provisioning profile 或 `ASC_*` 凭据。
- 所有命令在 worktree `/home/luozhouyang/github/luozhouyang/ubuntu-ios-skill/.worktrees/npm-distribution` 中执行。

---

### 任务 1：把 skill 内容移入 `skills/ubuntu-ios/`

**文件：**
- 移动：`SKILL.md` → `skills/ubuntu-ios/SKILL.md`
- 移动：`references/` → `skills/ubuntu-ios/references/`
- 移动：`scripts/` → `skills/ubuntu-ios/scripts/`
- 移动：`assets/` → `skills/ubuntu-ios/assets/`
- 移动：`evals/` → `skills/ubuntu-ios/evals/`
- 创建：`.gitignore`

- [x] **步骤 1：写一个当前会失败的布局检查**

运行：

```bash
test -f skills/ubuntu-ios/SKILL.md \
  && test -d skills/ubuntu-ios/references \
  && test -d skills/ubuntu-ios/scripts \
  && test -d skills/ubuntu-ios/assets \
  && test -d skills/ubuntu-ios/evals
```

预期：退出码 1（新路径尚不存在）。

- [x] **步骤 2：移动文件**

运行：

```bash
mkdir -p skills/ubuntu-ios
git mv SKILL.md references scripts assets evals skills/ubuntu-ios/
```

预期：`git status` 显示 5 个重命名。

- [x] **步骤 3：验证布局与脚本语法**

运行：

```bash
test -f skills/ubuntu-ios/SKILL.md \
  && test -d skills/ubuntu-ios/references \
  && test -d skills/ubuntu-ios/scripts \
  && test -d skills/ubuntu-ios/assets \
  && test -d skills/ubuntu-ios/evals \
  && test ! -e SKILL.md \
  && test ! -e scripts
```

预期：退出码 0。

运行：

```bash
bash -n skills/ubuntu-ios/scripts/setup.sh \
  && bash -n skills/ubuntu-ios/scripts/verify.sh \
  && bash -n skills/ubuntu-ios/scripts/prefetch-swiftpm-repo.sh
```

预期：退出码 0，无输出。

- [x] **步骤 4：创建 `.gitignore`**

写入 `.gitignore`：

```gitignore
node_modules/
*.tgz
.DS_Store
.agents/
.claude/skills/
.worktrees/
```

- [x] **步骤 5：Commit**

```bash
git add .gitignore skills/
git commit -m "refactor: move skill content under skills/ubuntu-ios"
```

---

### 任务 2：添加 `package.json` 与版本一致性检查

**文件：**
- 创建：`tools/check-version.mjs`
- 创建：`package.json`

- [x] **步骤 1：编写版本检查脚本**

写入 `tools/check-version.mjs`：

```js
#!/usr/bin/env node
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = dirname(dirname(fileURLToPath(import.meta.url)))
const pkg = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'))
const skillMd = readFileSync(
  join(root, 'skills', 'ubuntu-ios', 'SKILL.md'),
  'utf8',
)

const frontmatter = skillMd.match(/^---\r?\n([\s\S]*?)\r?\n---/)
if (!frontmatter) {
  console.error('error: skills/ubuntu-ios/SKILL.md has no YAML frontmatter')
  process.exit(1)
}

const block = frontmatter[1]
const name = block.match(/^name:\s*"?([^"\r\n]+?)"?\s*$/m)?.[1]
const version = block.match(
  /^metadata:[ \t]*\r?\n(?:[ \t]+[^\r\n]*\r?\n)*?[ \t]+version:\s*"?([^"\r\n]+?)"?\s*$/m,
)?.[1]

const errors = []
if (name !== 'ubuntu-ios') {
  errors.push(
    `SKILL.md name is ${JSON.stringify(name)}, expected "ubuntu-ios"`,
  )
}
if (version !== pkg.version) {
  errors.push(
    `SKILL.md metadata.version is ${JSON.stringify(version)}, package.json version is ${JSON.stringify(pkg.version)}`,
  )
}
if (pkg.name !== 'ubuntu-ios-skill') {
  errors.push(
    `package.json name is ${JSON.stringify(pkg.name)}, expected "ubuntu-ios-skill"`,
  )
}

if (errors.length > 0) {
  for (const error of errors) console.error(`error: ${error}`)
  process.exit(1)
}

console.log(
  `ok: ${pkg.name}@${pkg.version} <-> skills/ubuntu-ios (${name}@${version})`,
)
```

- [x] **步骤 2：运行脚本确认失败**

运行：

```bash
node tools/check-version.mjs
```

预期：退出码 1，报错包含 `ENOENT` 和 `package.json`（文件尚不存在）。

- [x] **步骤 3：创建 `package.json`**

写入 `package.json`：

```json
{
  "name": "ubuntu-ios-skill",
  "version": "1.0.0",
  "description": "Agent skill: set up, verify, and operate the Ubuntu iOS toolchain (Swift + xtool + rcodesign + pymobiledevice3) to build and ship iOS apps from Linux without a Mac.",
  "keywords": [
    "agent-skills",
    "skills",
    "claude-code",
    "codex",
    "cursor",
    "opencode",
    "ios",
    "swift",
    "swiftui",
    "ubuntu",
    "linux",
    "xtool",
    "rcodesign",
    "pymobiledevice3",
    "testflight"
  ],
  "license": "MIT",
  "author": "luozhouyang",
  "files": [
    "skills/"
  ],
  "repository": {
    "type": "git",
    "url": "git+https://github.com/luozhouyang/ubuntu-ios-skill.git"
  },
  "homepage": "https://github.com/luozhouyang/ubuntu-ios-skill#readme",
  "bugs": {
    "url": "https://github.com/luozhouyang/ubuntu-ios-skill/issues"
  },
  "scripts": {
    "test": "node tools/check-version.mjs && bash -n skills/ubuntu-ios/scripts/*.sh && npm pack --dry-run"
  },
  "publishConfig": {
    "access": "public",
    "provenance": true
  }
}
```

- [x] **步骤 4：运行版本检查确认通过**

运行：

```bash
node tools/check-version.mjs
```

预期输出：

```text
ok: ubuntu-ios-skill@1.0.0 <-> skills/ubuntu-ios (ubuntu-ios@1.0.0)
```

- [x] **步骤 5：确认 tarball 只包含 skill 内容**

运行：

```bash
npm pack --dry-run
```

预期：文件列表包含 `package.json` 与 `skills/ubuntu-ios/` 下的文件；不包含 `tools/`、`docs/`、`.github/`、`.gitignore`。

- [x] **步骤 6：Commit**

```bash
git add package.json tools/check-version.mjs
git commit -m "feat: add npm package metadata and version check"
```

---

### 任务 3：添加 `README.md` 与 `LICENSE`

**文件：**
- 创建：`README.md`
- 创建：`LICENSE`

- [x] **步骤 1：写入 MIT 许可证**

写入 `LICENSE`：

```text
MIT License

Copyright (c) 2026 luozhouyang

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [x] **步骤 2：写入 README**

写入 `README.md`：

```markdown
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

## License

MIT
```

- [x] **步骤 3：验证 README 拼写与打包内容**

运行：

```bash
node tools/check-version.mjs
npm pack --dry-run
```

预期：版本检查输出 `ok: ...`；tarball 文件列表包含 `README.md` 和 `LICENSE`。

另外运行：

```bash
grep -n '^ubuntu-ios doctor$' README.md
```

预期：输出包含 `ubuntu-ios doctor` 这一行（确认命令拼写正确）。

- [x] **步骤 4：Commit**

```bash
git add README.md LICENSE
git commit -m "docs: add npm readme and MIT license"
```

---

### 任务 4：添加 CI 与发布 workflow

**文件：**
- 创建：`.github/workflows/ci.yml`
- 创建：`.github/workflows/release.yml`

- [x] **步骤 1：写入 CI workflow**

写入 `.github/workflows/ci.yml`：

```yaml
name: ci

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

jobs:
  check:
    runs-on: ubuntu-latest
    env:
      DISABLE_TELEMETRY: "1"
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: "22"
      - name: Version, shell, and package checks
        run: npm test
      - name: Verify skill discovery
        run: npx --yes skills@latest add . --list
```

- [x] **步骤 2：写入发布 workflow**

写入 `.github/workflows/release.yml`：

```yaml
name: release

on:
  push:
    tags: ["v*"]

permissions:
  contents: read
  id-token: write

jobs:
  publish:
    runs-on: ubuntu-latest
    env:
      DISABLE_TELEMETRY: "1"
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: "22"
          registry-url: "https://registry.npmjs.org"
      - name: Update npm for trusted publishing
        run: npm install -g npm@latest
      - name: Verify package
        run: npm test
      - name: Publish
        run: npm publish --provenance --access public
```

- [x] **步骤 3：校验 YAML 语法**

运行：

```bash
python3 -c "import yaml; [yaml.safe_load(open(p)) for p in ['.github/workflows/ci.yml', '.github/workflows/release.yml']]; print('yaml ok')"
```

预期输出：`yaml ok`。

- [x] **步骤 4：本地运行 CI 的检查**

运行：

```bash
npm test
```

预期：版本检查 `ok`，`bash -n` 无输出，`npm pack --dry-run` 成功。

运行：

```bash
npx --yes skills@latest add . --list
```

预期：输出包含 `ubuntu-ios`。若网络不可用导致失败，记录错误并在下一步继续；不要修改 skill 布局来绕过。

- [x] **步骤 5：Commit**

```bash
git add .github/workflows/ci.yml .github/workflows/release.yml
git commit -m "ci: add package checks and npm release workflow"
```

---

### 任务 5：最终验收

**文件：** 无新增；只验证。

- [x] **步骤 1：运行完整检查**

运行：

```bash
npm test
```

预期：退出码 0。

- [x] **步骤 2：检查 tarball 内容**

运行：

```bash
rm -rf /tmp/ubuntu-ios-skill-pack
mkdir -p /tmp/ubuntu-ios-skill-pack
npm pack --pack-destination /tmp/ubuntu-ios-skill-pack
tar -tzf /tmp/ubuntu-ios-skill-pack/ubuntu-ios-skill-1.0.0.tgz
```

预期输出只包含：

```text
package/LICENSE
package/README.md
package/package.json
package/skills/ubuntu-ios/SKILL.md
package/skills/ubuntu-ios/assets/env.example
package/skills/ubuntu-ios/evals/evals.json
package/skills/ubuntu-ios/references/architecture.md
package/skills/ubuntu-ios/references/troubleshooting.md
package/skills/ubuntu-ios/references/workflow.md
package/skills/ubuntu-ios/scripts/prefetch-swiftpm-repo.sh
package/skills/ubuntu-ios/scripts/setup.sh
package/skills/ubuntu-ios/scripts/verify.sh
```

- [x] **步骤 3：确认脚本可执行位保留**

运行：

```bash
tar -tvzf /tmp/ubuntu-ios-skill-pack/ubuntu-ios-skill-1.0.0.tgz \
  | grep 'skills/ubuntu-ios/scripts/'
```

预期：三行均以 `-rwxr-xr-x` 开头。

- [x] **步骤 4：确认 skill 可被发现**

运行：

```bash
npx --yes skills@latest add . --list
```

预期：输出包含 `ubuntu-ios`。

- [x] **步骤 5：确认工作区干净**

运行：

```bash
git status --short
```

预期：无输出。

- [x] **步骤 6：汇报结果**

汇报：

- 5 个任务的 commit。
- `npm test` 与 `npx skills add . --list` 的实际输出。
- tarball 文件清单和脚本权限。
- 明确说明尚未执行 `npm publish`、未 push、未打 tag；发布需要用户手动登录 npm 并配置 Trusted Publisher。
