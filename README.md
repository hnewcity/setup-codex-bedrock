# setup-codex-bedrock

> 一个交互式、双语、幂等的 shell 脚本,帮你把 [Codex](https://developers.openai.com/codex) 配置到 [Amazon Bedrock](https://aws.amazon.com/bedrock/) 上(OpenAI 兼容的 Responses API / Mantle 路径)。
>
> An interactive, bilingual, idempotent shell script that configures [Codex](https://developers.openai.com/codex) to run against [Amazon Bedrock](https://aws.amazon.com/bedrock/) (the OpenAI-compatible Responses API / Mantle path).

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/shell-bash-4EAA25.svg?logo=gnubash&logoColor=white)](setup-codex-bedrock.sh)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](#贡献--contributing)

---

## 中文

### 这是什么

`setup-codex-bedrock.sh` 是一个零依赖的交互式向导,把繁琐的 Codex → Amazon Bedrock 配置过程一步步引导完成。它会更新 `~/.codex/config.toml`、写入 shell 环境变量或 `~/.codex/.env`,并在需要时调用 `aws` CLI 帮你处理凭证。

### 特性

- **交互式 + 双语**:全程中文 / English 提示,首屏选择语言。
- **幂等**:用 marker 块管理写入内容,重复运行只更新不堆积。
- **安全**:密钥隐藏输入、不回显;`~/.codex/.env` 自动 `chmod 600`;任何改动前自动备份原文件。
- **多种认证方式**:
  - Bedrock API key(最简单,设置 `AWS_BEARER_TOKEN_BEDROCK`)
  - AWS SDK 凭证链:命名 Profile / AWS SSO / 长期 AK·SK / 临时凭证 / 联合身份(credential_process)
- **多目标**:写入 CLI(shell rc)、桌面 App·IDE(`~/.codex/.env`),或两者都写。

### 前置条件

- `bash` 与基础工具(`awk`、`sed`、`grep`)——macOS / Linux 自带。
- [Codex](https://developers.openai.com/codex) 已安装。
- 一个能访问 Bedrock 上 OpenAI 模型的 **AWS 账号**(模型当前仅在美区可用)。
- 若使用 AWS SDK 凭证链,需安装 [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)。

### 快速开始

```bash
# 克隆仓库
git clone https://github.com/hnewcity/setup-codex-bedrock.git
cd setup-codex-bedrock

# 运行向导
bash setup-codex-bedrock.sh
```

或者一行直接拉起(请先审阅脚本内容再这样运行):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/hnewcity/setup-codex-bedrock/main/setup-codex-bedrock.sh)
```

### 让配置生效

- **终端 (CLI)**:`source ~/.zshrc`(或你的 rc 文件),然后运行 `codex`,用 `/status` 确认 provider 是 `amazon-bedrock`。
- **桌面 App**:`Cmd+Q` 完全退出后重开(它读 `~/.codex/.env`,不读 shell rc)。

### 排错清单

- model ID 必须精确匹配(`openai.gpt-5.5` / `openai.gpt-5.4`)。
- region 必须是模型可用的美区。
- API key / 临时凭证未过期("token expired" 即过期,需重新生成)。
- 短期 API key 最长约 12 小时过期;常用建议生成 long-term key。
- 重新运行本脚本可随时轮换凭证,managed 块会被就地替换。

---

## English

### What is this

`setup-codex-bedrock.sh` is a zero-dependency interactive wizard that walks you through the fiddly process of pointing Codex at Amazon Bedrock. It updates `~/.codex/config.toml`, writes shell environment variables or `~/.codex/.env`, and invokes the `aws` CLI to handle credentials when needed.

### Features

- **Interactive + bilingual**: prompts in Chinese / English, language picked on the first screen.
- **Idempotent**: writes are wrapped in marker blocks, so re-running updates in place instead of piling up.
- **Safe**: secret input is hidden and never echoed; `~/.codex/.env` is `chmod 600`; every file is backed up before changes.
- **Multiple auth methods**:
  - Bedrock API key (simplest, sets `AWS_BEARER_TOKEN_BEDROCK`)
  - AWS SDK credential chain: named profile / AWS SSO / long-term AK·SK / temporary credentials / federated (credential_process)
- **Multiple targets**: write to the CLI (shell rc), the desktop app/IDE (`~/.codex/.env`), or both.

### Prerequisites

- `bash` and standard tools (`awk`, `sed`, `grep`) — bundled on macOS / Linux.
- [Codex](https://developers.openai.com/codex) installed.
- An **AWS account** with access to OpenAI models on Bedrock (currently US regions only).
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) if you use the AWS SDK credential chain.

### Quick start

```bash
# Clone the repo
git clone https://github.com/hnewcity/setup-codex-bedrock.git
cd setup-codex-bedrock

# Run the wizard
bash setup-codex-bedrock.sh
```

Or run it in one line (review the script first before doing this):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/hnewcity/setup-codex-bedrock/main/setup-codex-bedrock.sh)
```

### Make it take effect

- **Terminal (CLI)**: `source ~/.zshrc` (or your rc file), then run `codex` and use `/status` to confirm the provider is `amazon-bedrock`.
- **Desktop app**: `Cmd+Q` to fully quit, then reopen (it reads `~/.codex/.env`, not your shell rc).

### Troubleshooting

- The model ID must match exactly (`openai.gpt-5.5` / `openai.gpt-5.4`).
- The region must be a US region where the model is available.
- The API key / temp credentials must not be expired ("token expired" => regenerate).
- Short-term API keys expire in ~12h; for regular use generate a long-term key.
- Re-run this script anytime to rotate credentials; the managed block is replaced in place.

---

## 安全说明 / Security notes

- 脚本永远不会把你的密钥回显到终端或日志。/ The script never echoes your secrets to the terminal or logs.
- 长期 AK/SK 写入 `~/.aws`(通过 `aws configure set`),而不是 shell 文件。/ Long-term AK/SK are written to `~/.aws` (via `aws configure set`), not to shell files.
- 临时凭证不会被写入任何文件。/ Temporary credentials are never written to any file.
- `~/.codex/.env` 会被设置为 `600` 权限。/ `~/.codex/.env` is set to `600` permissions.

> ⚠️ 切勿把含密钥的 `~/.codex/.env`、`~/.aws` 或 shell rc 文件提交到版本库。
> ⚠️ Never commit `~/.codex/.env`, `~/.aws`, or shell rc files that contain secrets.

## 贡献 / Contributing

欢迎 issue 和 PR。请参阅 [CONTRIBUTING.md](CONTRIBUTING.md)。
Issues and PRs welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## 许可 / License

[MIT](LICENSE)
