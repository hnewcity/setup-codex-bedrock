# Contributing / 贡献指南

Thanks for your interest in improving `setup-codex-bedrock`! / 感谢你愿意改进本项目!

## How to contribute / 如何贡献

1. Fork the repo and create a branch from `main`. / Fork 仓库并从 `main` 切出分支。
2. Make your change. Keep the bilingual (中文 / English) prompts in sync. / 修改代码,保持中英文提示同步。
3. Run the checks below. / 运行下面的检查。
4. Open a pull request with a clear description. / 提交一个描述清晰的 PR。

## Local checks / 本地检查

The script is plain `bash`. Before opening a PR, please run:

本脚本是纯 `bash`。提 PR 前请运行:

```bash
# Syntax check / 语法检查
bash -n setup-codex-bedrock.sh

# Lint with shellcheck (https://www.shellcheck.net/) / 用 shellcheck 静态检查
shellcheck setup-codex-bedrock.sh
```

CI runs the same checks on every push and pull request.

CI 会在每次 push 和 PR 上运行同样的检查。

## Guidelines / 约定

- **Keep it dependency-free.** The script should run with only `bash`, `awk`, `sed`, and `grep`. / **保持零依赖。** 脚本只应依赖 `bash`、`awk`、`sed`、`grep`。
- **Idempotency matters.** Re-running the script must update in place, not duplicate. / **幂等很重要。** 重复运行必须就地更新,不能重复堆积。
- **Never echo secrets.** Secret input stays hidden; don't print keys to stdout/logs. / **永不回显密钥。** 密钥输入须隐藏,不要打印到 stdout/日志。
- **Bilingual parity.** Every user-facing string should have both 中文 and English via the `L` helper. / **双语对等。** 每条面向用户的文案都要通过 `L` 辅助函数提供中英文。

## Reporting issues / 报告问题

Please include your OS, shell, and the exact step where things went wrong.

请附上你的操作系统、shell,以及出问题的具体步骤。
