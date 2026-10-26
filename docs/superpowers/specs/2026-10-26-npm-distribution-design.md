# ubuntu-ios-skill 的 npm 分发设计

- 日期：2026-10-26
- 状态：待审阅
- 仓库：https://github.com/luozhouyang/ubuntu-ios-skill

## 1. 目标

让同一个仓库同时支持两种安装方式，且不维护两份内容：

1. Agent 生态（主通道）：`npx skills add luozhouyang/ubuntu-ios-skill`
2. npm（版本化分发通道）：`npm i -D ubuntu-ios-skill` + `npx skills experimental_sync`

发布到 npm 后，包名、版本、README 和 provenance 都由 npm 提供；skill 内容仍以 `SKILL.md` 为准。

## 2. 非目标

- 不提供自定义安装 CLI（`npx ubuntu-ios-skill install`）。
- 不添加 `postinstall` 下载逻辑。
- 不改变 skill 的安装行为、脚本逻辑或工具链内容。
- 不发布 Apple SDK、证书或任何凭据。

## 3. 已确认决策

| 决策 | 结果 |
| --- | --- |
| 包内布局 | `skills/ubuntu-ios/` |
| 自定义 CLI | 不提供 |
| 许可证 | MIT |
| npm 包名 | `ubuntu-ios-skill`（未加 scope） |

## 4. 目标结构

```text
ubuntu-ios-skill/
├── package.json
├── README.md
├── LICENSE
├── .gitignore
├── .github/workflows/
│   ├── ci.yml
│   └── release.yml
├── tools/
│   └── check-version.mjs
├── docs/superpowers/specs/   # 不进入 npm tarball
└── skills/
    └── ubuntu-ios/
        ├── SKILL.md
        ├── references/
        ├── scripts/
        ├── assets/
        └── evals/
```

移动规则：`SKILL.md`、`references/`、`scripts/`、`assets/`、`evals/` 整体移入 `skills/ubuntu-ios/`。`SKILL.md` 内部所有路径都是相对自身目录的，移动后无需改文案；`scripts/setup.sh` 通过 `BASH_SOURCE` 定位 skill 目录，也无需改代码。

根目录的 `scripts/` 使用 `tools/`，避免与 `skills/ubuntu-ios/scripts/` 混淆。

`.gitignore` 必须包含：`node_modules/`、`*.tgz`、`.DS_Store`、`.agents/`、`.claude/skills/`。

## 5. package.json

```json
{
  "name": "ubuntu-ios-skill",
  "version": "1.0.0",
  "description": "Agent skill: set up, verify, and operate the Ubuntu iOS toolchain (Swift + xtool + rcodesign + pymobiledevice3) to build and ship iOS apps from Linux without a Mac.",
  "keywords": [
    "agent-skills", "skills", "claude-code", "codex", "cursor", "opencode",
    "ios", "swift", "swiftui", "ubuntu", "linux", "xtool", "rcodesign",
    "pymobiledevice3", "testflight"
  ],
  "license": "MIT",
  "author": "luozhouyang",
  "files": ["skills/"],
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

约束：

- 使用 `files` 白名单，不创建 `.npmignore`。npm 自动包含 `package.json`、`README.md`、`LICENSE`。
- 不设置 `main` / `exports` / `bin`；这是内容包，不是可执行包。
- 不设置 `engines`；CI 使用的 Node 版本由 workflow 固定。
- 版本号必须与 `skills/ubuntu-ios/SKILL.md` 的 `metadata.version` 一致。

## 6. 版本一致性检查

`tools/check-version.mjs`：

1. 读取根 `package.json` 的 `version`。
2. 读取 `skills/ubuntu-ios/SKILL.md` 的 frontmatter，提取 `metadata.version`。
3. 两者不相等时打印两个值并以非零码退出。
4. 同时校验 frontmatter `name` 等于目录名 `ubuntu-ios`，避免 `skills` CLI 发现时名称漂移。

该脚本不引入任何依赖，使用 Node 内置模块。

## 7. README

README 面向 npm 与 GitHub 首页，至少包含：

- 一句话说明：在 Ubuntu Linux 上构建、签名并发布 iOS 应用，不需要 Mac 或 Xcode GUI。
- 系统要求（Ubuntu 24.04 x86_64、Xcode `.xip`、磁盘/RAM、sudo）。
- 两种安装方式及其区别：
  - `npx skills add luozhouyang/ubuntu-ios-skill`（推荐，支持多 agent）
  - `npm i -D ubuntu-ios-skill && npx skills experimental_sync -a claude-code -y`
- 明确提示：**只执行 `npm install` 不会激活 skill**，必须运行 sync。
- 安装后如何触发：向 agent 说“用 ubuntu-ios 在这台机器上搭好 iOS 工具链”。
- 安全边界：不分发 Apple SDK；`.p8`、证书、profile 不得入库。
- 指向 `skills/ubuntu-ios/SKILL.md` 作为完整说明。

## 8. LICENSE

添加标准 MIT 文本，版权行为 `Copyright (c) 2026 luozhouyang`。

## 9. CI 与发布

### ci.yml

触发：`push` 与 `pull_request`。

步骤：

1. checkout。
2. `bash -n skills/ubuntu-ios/scripts/*.sh`。
3. `npm test`（版本一致性 + `npm pack --dry-run`）。
4. `npx --yes skills add . --list`：验证 `skills` CLI 能从本仓库发现 `ubuntu-ios`。

`shellcheck` 不在首版 CI 范围内；首版只用 `bash -n` 做语法检查。

### release.yml

触发：推送 `v*` tag。

- 权限：`contents: read`、`id-token: write`。
- 使用 `actions/setup-node` 固定 Node 22。
- `npm install -g npm@latest`，确保支持 trusted publishing。
- `npm publish --provenance --access public`。

首次发布需手动执行 `npm login && npm publish --access public` 创建包；之后在 npmjs.com 包设置中配置 Trusted Publisher（GitHub Actions，指向本仓库和 `release.yml`），后续不再使用长期 token。

## 10. 发布流程

1. 修改 `package.json` 与 `SKILL.md` 的版本号。
2. `npm test` 本地通过。
3. `npm version minor`（或 `patch` / `major`）。
4. `git push --follow-tags`。
5. CI 发布成功后在 npm 页面确认 provenance 标识与 tarball 内容。

## 11. 验收标准

- `npx skills add . --list` 输出包含 `ubuntu-ios`。
- `npm pack --dry-run` 的文件列表只包含 `package.json`、`README.md`、`LICENSE` 和 `skills/ubuntu-ios/` 下的内容；不包含 `docs/`、`.github/`、`node_modules/`。
- `npm test` 在版本不一致时失败、一致时通过。
- 解包 tarball 后，`skills/ubuntu-ios/scripts/*.sh` 保持可执行位。
- 从任意临时目录执行 `npx skills add /path/to/ubuntu-ios-skill -a claude-code -y` 后，目标 skill 目录包含 `SKILL.md`、`references/`、`scripts/`、`assets/`、`evals/`。

## 12. 风险与说明

- npm 包无法替代 `skills` CLI 的 agent 目录管理；README 必须写清“安装后需 sync”。
- `skills experimental_sync` 仍标记为实验性；`skills-npm` 是替代实现。包布局同时兼容两者，因此该风险不影响内容结构。
- 首次发布前无法配置 trusted publisher；首次手动发布是必要步骤。
- 仓库公开且包公开时 provenance 才有意义；如改为私有 registry 需重新评估。
