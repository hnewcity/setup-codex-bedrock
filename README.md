# setup-codex-bedrock

> 一个交互式、双语、幂等的 shell 脚本,帮你把 [Codex](https://developers.openai.com/codex) 配置到 [Amazon Bedrock](https://aws.amazon.com/bedrock/) 上(OpenAI 兼容的 Responses API / Mantle 路径)。
>
> An interactive, bilingual, idempotent shell script that configures [Codex](https://developers.openai.com/codex) to run against [Amazon Bedrock](https://aws.amazon.com/bedrock/) (the OpenAI-compatible Responses API / Mantle path).

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/shell-bash-4EAA25.svg?logo=gnubash&logoColor=white)](setup-codex-bedrock.sh)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE.svg?logo=powershell&logoColor=white)](setup-codex-bedrock.ps1)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](#贡献--contributing)

---

## 中文

### 这是什么

`setup-codex-bedrock.sh` 是一个零依赖的交互式向导,把繁琐的 Codex → Amazon Bedrock 配置过程一步步引导完成。它会更新 `~/.codex/config.toml`、写入 shell 环境变量或 `~/.codex/.env`,并在需要时调用 `aws` CLI 帮你处理凭证。

### 特性

- **交互式 + 双语**:全程中文 / English 提示,首屏选择语言。
- **幂等**:用 marker 块管理写入内容,重复运行只更新不堆积。
- **安全**:密钥输入可见,便于核对;`~/.codex/.env` 自动 `chmod 600`;任何改动前自动备份原文件。
- **多种认证方式**:
  - Bedrock API key(最简单,设置 `AWS_BEARER_TOKEN_BEDROCK`)
  - AWS SDK 凭证链:命名 Profile / AWS SSO / 长期 AK·SK / 临时凭证 / 联合身份(credential_process)
- **多目标**:写入 CLI(shell rc)、桌面 App·IDE(`~/.codex/.env`),或两者都写。
- **跨平台**:macOS / Linux 用 `setup-codex-bedrock.sh`,Windows 用 `setup-codex-bedrock.ps1`。

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

### Windows

在 PowerShell(Windows PowerShell 5.1 或 PowerShell 7)中运行:

```powershell
# 克隆后运行(推荐,带 -ExecutionPolicy Bypass 绕过脚本限制)
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-codex-bedrock.ps1

# 或远程一行拉起:走纯 ASCII 的 install.ps1 引导(请先审阅脚本内容)
irm https://raw.githubusercontent.com/hnewcity/setup-codex-bedrock/main/install.ps1 | iex
```

> ⚠️ 远程请用 `install.ps1`,**不要**直接 `irm .../setup-codex-bedrock.ps1 | iex`:
> 主脚本带 UTF-8 BOM(让 `-File`/双击在中文系统上正确解析),而 PS 5.1 的
> `irm | iex` 会把 BOM 粘到首行 `<#` 前,导致注释块失效、整段中文被当代码解析报错。
> `install.ps1` 是纯 ASCII 引导,先正确下载主脚本再用 `-File` 跑,规避了这个问题。

> ⚠️ **跑不起来?** 若直接双击 `.ps1` 或用 `.\setup-codex-bedrock.ps1` 运行,报
> `无法加载 ... 因为在此系统上禁止运行脚本`,这是 Windows 默认的 ExecutionPolicy 限制。
> 用上面第一条带 `-ExecutionPolicy Bypass` 的命令即可,无需改系统策略。

与 bash 版的区别:

- **CLI 目标**写入的是**用户级环境变量**(`[Environment]::SetEnvironmentVariable(..., 'User')`),而不是 shell rc。需要**新开终端窗口**才生效。
- `%USERPROFILE%\.codex\.env` 用 `icacls` 设为仅当前用户可访问(相当于 `chmod 600`)。
- 改用 AWS SDK 凭证时,会同时删除用户级的旧 `AWS_BEARER_TOKEN_BEDROCK`,避免 Codex 仍优先使用旧 key。
- 桌面 App:完全退出(包括托盘图标)后重开。

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
- **Safe**: key input is visible so you can verify it; `~/.codex/.env` is `chmod 600`; every file is backed up before changes.
- **Multiple auth methods**:
  - Bedrock API key (simplest, sets `AWS_BEARER_TOKEN_BEDROCK`)
  - AWS SDK credential chain: named profile / AWS SSO / long-term AK·SK / temporary credentials / federated (credential_process)
- **Multiple targets**: write to the CLI (shell rc), the desktop app/IDE (`~/.codex/.env`), or both.
- **Cross-platform**: `setup-codex-bedrock.sh` for macOS / Linux, `setup-codex-bedrock.ps1` for Windows.

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

### Windows

Run in PowerShell (Windows PowerShell 5.1 or PowerShell 7):

```powershell
# After cloning (recommended; -ExecutionPolicy Bypass avoids the script-blocking policy)
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-codex-bedrock.ps1

# Or remotely in one line via the pure-ASCII install.ps1 bootstrap (review the script first)
irm https://raw.githubusercontent.com/hnewcity/setup-codex-bedrock/main/install.ps1 | iex
```

> ⚠️ Remotely, use `install.ps1` — do **not** pipe `setup-codex-bedrock.ps1` straight into iex.
> The main script carries a UTF-8 BOM (so `-File` / double-click parse Chinese text correctly),
> but PS 5.1's `irm | iex` prepends that BOM to the first line `<#`, breaking the comment block
> so the whole header is parsed as code. `install.ps1` is pure ASCII: it downloads the main
> script and runs it with `-File`, sidestepping the problem.

> ⚠️ **Can't run it?** If you double-click the `.ps1` or run `.\setup-codex-bedrock.ps1` and get
> `... cannot be loaded because running scripts is disabled on this system`, that's Windows' default
> ExecutionPolicy. Use the first command above with `-ExecutionPolicy Bypass` — no need to change the system policy.

Differences from the bash version:

- The **CLI target** writes **user-level environment variables** (`[Environment]::SetEnvironmentVariable(..., 'User')`) instead of a shell rc. Open a **new terminal window** for them to take effect.
- `%USERPROFILE%\.codex\.env` is locked to the current user via `icacls` (the equivalent of `chmod 600`).
- Switching to AWS SDK credentials also removes a stale user-level `AWS_BEARER_TOKEN_BEDROCK`, so Codex doesn't keep preferring the old key.
- Desktop app: fully quit (including the tray icon), then reopen.

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

- 密钥仅在输入时显示,脚本不会再把它打印到终端或日志;注意防窥屏。/ Keys are visible only while you type them; the script never prints them afterwards. Mind shoulder-surfing.
- 长期 AK/SK 写入 `~/.aws`(通过 `aws configure set`),而不是 shell 文件。/ Long-term AK/SK are written to `~/.aws` (via `aws configure set`), not to shell files.
- 临时凭证不会被写入任何文件。/ Temporary credentials are never written to any file.
- `~/.codex/.env` 会被设置为 `600` 权限(Windows 上为仅当前用户可访问)。/ `~/.codex/.env` is set to `600` permissions (current-user-only ACL on Windows).

> ⚠️ 切勿把含密钥的 `~/.codex/.env`、`~/.aws` 或 shell rc 文件提交到版本库。
> ⚠️ Never commit `~/.codex/.env`, `~/.aws`, or shell rc files that contain secrets.

## 贡献 / Contributing

欢迎 issue 和 PR。请参阅 [CONTRIBUTING.md](CONTRIBUTING.md)。
Issues and PRs welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## 许可 / License

[MIT](LICENSE)
