#!/usr/bin/env bash
#
# setup-codex-bedrock.sh
# 渐进式配置 Codex 使用 Amazon Bedrock (OpenAI 兼容 Responses API / Mantle 路径)
# Progressive setup for Codex on Amazon Bedrock (OpenAI-compatible Responses API / Mantle path)
#
# 特性 / Features:
#   - 交互式 + 双语(中文 / English)
#   - 幂等:marker 块管理,重复运行只更新不堆积
#   - 安全:密钥隐藏输入、不回显;.env chmod 600;改动前自动备份
#   - 多认证:Bedrock API key / AWS SDK 凭证链(profile·SSO·长期AKSK·临时·联合身份)
#   - 多目标:CLI(shell rc) / 桌面App·IDE(~/.codex/.env) / 两者
#
# 用法 / Usage: bash setup-codex-bedrock.sh

set -u

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CONFIG_TOML="$CODEX_HOME/config.toml"
ENV_FILE="$CODEX_HOME/.env"
BLOCK_START="# >>> codex-bedrock (managed by setup script) >>>"
BLOCK_END="# <<< codex-bedrock (managed by setup script) <<<"

# ---------- 颜色 ----------
c_blue()  { printf '\033[1;34m%s\033[0m\n' "$*"; }
c_green() { printf '\033[1;32m%s\033[0m\n' "$*"; }
c_yellow(){ printf '\033[1;33m%s\033[0m\n' "$*"; }
c_dim()   { printf '\033[2m%s\033[0m\n' "$*"; }
die()     { printf '\033[1;31m%s\033[0m\n' "$*" >&2; exit 1; }

# ---------- 语言 ----------
LANGV="zh"
# L "中文" "English" -> 按当前语言输出
L() { if [ "$LANGV" = "en" ]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }

# ---------- 文件工具 ----------
backup() {
  local f="$1"
  [ -f "$f" ] || return 0
  local b
  b="$f.bak.$(date +%Y%m%d%H%M%S)"
  cp "$f" "$b" && c_dim "  $(L '已备份' 'backup'): $b"
}

# 替换或追加 marker 块(幂等)
upsert_block() {
  local file="$1"; shift
  local content="$1"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  if grep -qF "$BLOCK_START" "$file"; then
    awk -v s="$BLOCK_START" -v e="$BLOCK_END" '
      $0==s {skip=1}
      skip==0 {print}
      $0==e {skip=0}
    ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  fi
  printf '%s\n%s%s\n' "$BLOCK_START" "$content" "$BLOCK_END" >> "$file"
}

# 顶层 TOML key 就地更新或前置插入(顶层 key 必须在任何 [table] 之前)
upsert_toml() {
  local file="$1" key="$2" line="$3"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$file"; then
    awk -v k="$key" -v l="$line" '
      $0 ~ ("^[[:space:]]*" k "[[:space:]]*=") && !done {print l; done=1; next}
      {print}
    ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  else
    printf '%s\n' "$line" | cat - "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  fi
}

ask() { # ask "提示" "默认值"
  local prompt="$1" def="${2:-}" ans
  if [ -n "$def" ]; then
    read -r -p "$prompt [$def]: " ans
    printf '%s' "${ans:-$def}"
  else
    read -r -p "$prompt: " ans
    printf '%s' "$ans"
  fi
}

# ---------- 探测当前状态 ----------
preflight() {
  c_blue "$(L '==> 当前状态' '==> Current state')"
  if [ -f "$CONFIG_TOML" ]; then
    local prov; prov=$(grep -E '^[[:space:]]*model_provider[[:space:]]*=' "$CONFIG_TOML" | head -1 | sed 's/.*=//; s/[" ]//g')
    local mdl;  mdl=$(grep -E '^[[:space:]]*model[[:space:]]*=' "$CONFIG_TOML" | head -1 | sed 's/.*=//; s/[" ]//g')
    echo "  config.toml: $(L 存在 exists) | model_provider=${prov:-<unset>} model=${mdl:-<unset>}"
  else
    echo "  config.toml: $(L '不存在(将创建)' 'missing (will create)')"
  fi
  if [ -f "$ENV_FILE" ]; then
    echo "  ~/.codex/.env: $(L 存在 exists) ($(stat -f '%Lp' "$ENV_FILE" 2>/dev/null || stat -c '%a' "$ENV_FILE" 2>/dev/null))"
  else
    echo "  ~/.codex/.env: $(L 不存在 missing)"
  fi
  [ -n "${AWS_BEARER_TOKEN_BEDROCK:-}" ] && echo "  shell: AWS_BEARER_TOKEN_BEDROCK $(L 已设 set) (len=${#AWS_BEARER_TOKEN_BEDROCK})" || echo "  shell: AWS_BEARER_TOKEN_BEDROCK $(L 未设 unset)"
  [ -n "${AWS_REGION:-}" ] && echo "  shell: AWS_REGION=$AWS_REGION" || echo "  shell: AWS_REGION $(L 未设 unset)"
  echo
}

choose_region() {
  c_blue "$(L '==> 选择 AWS Region (Bedrock 上的 OpenAI 模型仅在美区)' '==> Choose AWS Region (OpenAI models on Bedrock are US-only)')" >&2
  if [ "$LANGV" = "en" ]; then
    cat >&2 <<'EOF'
  1) us-east-2   (doc default)
  2) us-east-1
  3) us-west-2
  4) custom
EOF
  else
    cat >&2 <<'EOF'
  1) us-east-2   (文档默认)
  2) us-east-1
  3) us-west-2
  4) 自定义
EOF
  fi
  local r; r=$(ask "  $(L 选择 Choose)" "1")
  case "$r" in
    1) printf 'us-east-2' ;;
    2) printf 'us-east-1' ;;
    3) printf 'us-west-2' ;;
    4) ask "  $(L '输入 region' 'enter region')" "us-east-2" ;;
    *) printf 'us-east-2' ;;
  esac
}

choose_model() {
  c_blue "$(L '==> 选择模型(可跳过,用默认)' '==> Choose model (optional, can skip)')" >&2
  if [ "$LANGV" = "en" ]; then
    cat >&2 <<'EOF'
  1) openai.gpt-5.5  (default)
  2) openai.gpt-5.4
  3) leave model unset
EOF
  else
    cat >&2 <<'EOF'
  1) openai.gpt-5.5  (默认)
  2) openai.gpt-5.4
  3) 不写 model,用默认
EOF
  fi
  local m; m=$(ask "  $(L 选择 Choose)" "1")
  case "$m" in
    1) printf 'openai.gpt-5.5' ;;
    2) printf 'openai.gpt-5.4' ;;
    3) printf '' ;;
    *) printf 'openai.gpt-5.5' ;;
  esac
}

choose_targets() {
  c_blue "$(L '==> 配置写到哪里?' '==> Where to write config?')" >&2
  if [ "$LANGV" = "en" ]; then
    cat >&2 <<'EOF'
  1) both        (recommended, default)
  2) CLI only    (shell rc, for running codex in terminal)
  3) Desktop/IDE only  (~/.codex/.env)
EOF
  else
    cat >&2 <<'EOF'
  1) 两者都写   (推荐,默认)
  2) 仅 CLI     (shell rc,终端跑 codex)
  3) 仅 桌面App/IDE  (~/.codex/.env)
EOF
  fi
  ask "  $(L 选择 Choose)" "1"
}

detect_rc() {
  case "${SHELL:-}" in
    *zsh)  printf '%s' "$HOME/.zshrc" ;;
    *bash) [ -f "$HOME/.bashrc" ] && printf '%s' "$HOME/.bashrc" || printf '%s' "$HOME/.bash_profile" ;;
    *)     printf '%s' "$HOME/.zshrc" ;;
  esac
}

# ================= 主流程 / MAIN =================
clear 2>/dev/null || true

# 0) 语言选择(最先,双语提示)
printf 'Language / 语言:  [1] 中文   [2] English  [1]: '
read -r _l
case "$_l" in 2|en|EN|e|E|english) LANGV="en" ;; *) LANGV="zh" ;; esac

c_green "$(L 'Codex + Amazon Bedrock 配置向导' 'Codex + Amazon Bedrock setup wizard')"
c_dim "$(L '随时 Ctrl-C 退出;改动前自动备份。' 'Ctrl-C to quit anytime; files are backed up before changes.')"
echo
preflight

# 1) 认证方式
c_blue "$(L '==> 认证方式 (Codex 按序检查: 先 API key, 后 AWS SDK 凭证链)' '==> Auth method (Codex checks in order: API key first, then AWS SDK chain)')"
if [ "$LANGV" = "en" ]; then
  cat <<'EOF'
  1) Bedrock API key   (simplest, sets AWS_BEARER_TOKEN_BEDROCK)
  2) AWS SDK creds     (profile / SSO / long-term AKSK / temp / federated)
EOF
else
  cat <<'EOF'
  1) Bedrock API key   (最简单, 设 AWS_BEARER_TOKEN_BEDROCK)
  2) AWS SDK 凭证链     (profile / SSO / 长期AKSK / 临时 / 联合身份)
EOF
fi
AUTH=$(ask "  $(L 选择 Choose)" "1")

# 收集变量
BLOCK_CONTENT=""
REGION=""
AWS_DO=""        # 延迟到 apply 执行的动作: ""|configure|set|sso
AWS_PROF=""
AK=""; SK=""

case "$AUTH" in
  1)
    echo
    c_yellow "$(L '  请粘贴 Bedrock API key (输入隐藏,不回显):' '  Paste Bedrock API key (hidden input):')"
    read -r -s -p "  AWS_BEARER_TOKEN_BEDROCK: " BEARER; echo
    [ -n "$BEARER" ] || die "$(L 未输入 key 'no key entered')"
    REGION=$(choose_region)
    BLOCK_CONTENT="export AWS_BEARER_TOKEN_BEDROCK='$BEARER'
export AWS_REGION='$REGION'
"
    ;;
  2)
    echo
    c_blue "$(L '==> AWS SDK 凭证来源 (文档 Option 2 的 5 种)' '==> AWS SDK credential source (5 from doc Option 2)')"
    if [ "$LANGV" = "en" ]; then
      cat <<'EOF'
  a) Named profile     (~/.aws already set, or run aws configure now)
  b) AWS SSO           (aws sso login --profile, browser login)
  c) Long-term AK/SK   (IAM user keys, no session token, persistable)
  d) Temp credentials  (AK/SK + session token, expires, this session only)
  e) Federated         (SSO/OIDC via profile credential_process)
EOF
    else
      cat <<'EOF'
  a) 命名 Profile      (~/.aws 已配好, 或现在 aws configure 配)
  b) AWS SSO           (aws sso login --profile, 浏览器登录)
  c) 长期 AK/SK        (IAM user 永久密钥, 无 session token, 可持久化)
  d) 临时凭证          (AK/SK + session token, 会过期, 仅本次会话)
  e) 联合身份          (SSO/OIDC, 走 profile 的 credential_process)
EOF
    fi
    SUB=$(ask "  $(L 选择 Choose)" "a")
    REGION=$(choose_region)
    case "$SUB" in
      a)
        AWS_PROF=$(ask "  $(L 'profile 名称' 'profile name')" "codex-bedrock")
        BLOCK_CONTENT="export AWS_PROFILE='$AWS_PROF'
export AWS_REGION='$REGION'
"
        echo
        RUN=$(ask "  $(L '现在用 aws configure 交互式配置该 profile? (y/N)' 'Run aws configure for this profile now? (y/N)')" "N")
        case "$RUN" in y|Y|yes) AWS_DO="configure";; esac
        [ -z "$AWS_DO" ] && c_dim "  $(L "跳过: 假定 ~/.aws 已配好 profile '$AWS_PROF'" "skip: assuming ~/.aws already has profile '$AWS_PROF'")"
        ;;
      b)
        AWS_PROF=$(ask "  $(L 'SSO profile 名称' 'SSO profile name')" "codex-bedrock")
        BLOCK_CONTENT="export AWS_PROFILE='$AWS_PROF'
export AWS_REGION='$REGION'
"
        echo
        RUN=$(ask "  $(L "现在执行 aws sso login --profile $AWS_PROF? (Y/n)" "Run aws sso login --profile $AWS_PROF now? (Y/n)")" "Y")
        case "$RUN" in n|N|no) c_dim "  $(L "跳过, 记得自行: aws sso login --profile $AWS_PROF" "skipped; run later: aws sso login --profile $AWS_PROF")";; *) AWS_DO="sso";; esac
        ;;
      c)
        echo
        c_blue "$(L '  长期 AK/SK 二选一:' '  Long-term AK/SK, pick one:')"
        if [ "$LANGV" = "en" ]; then
          echo "    1) paste keys, written to ~/.aws via 'aws configure set' (recommended, not in shell files)"
          echo "    2) I already configured ~/.aws, just set profile + region"
        else
          echo "    1) 粘贴密钥, 由脚本写入 ~/.aws (aws configure set, 推荐, 不进 shell 文件)"
          echo "    2) 我已配好 ~/.aws, 只设 profile + region"
        fi
        HOW=$(ask "  $(L 选择 Choose)" "1")
        if [ "$HOW" = "1" ]; then
          AWS_PROF=$(ask "  $(L '写入哪个 profile' 'write to which profile')" "codex-bedrock")
          read -r -s -p "  AWS_ACCESS_KEY_ID: " AK; echo
          read -r -s -p "  AWS_SECRET_ACCESS_KEY: " SK; echo
          [ -n "$AK" ] && [ -n "$SK" ] || die "$(L 'AK/SK 不能为空' 'AK/SK must not be empty')"
          AWS_DO="set"
          BLOCK_CONTENT="export AWS_PROFILE='$AWS_PROF'
export AWS_REGION='$REGION'
"
        else
          AWS_PROF=$(ask "  $(L 'profile 名称' 'profile name')" "codex-bedrock")
          BLOCK_CONTENT="export AWS_PROFILE='$AWS_PROF'
export AWS_REGION='$REGION'
"
        fi
        ;;
      d)
        echo
        c_yellow "$(L '  临时凭证会过期, 不写入文件; 仅把 region 写入配置。' '  Temp creds expire; not written to files. Only region is saved.')"
        c_blue "$(L '  把下面三件套粘到终端再跑 codex (值自行替换):' '  Paste these in your terminal, then run codex (replace values):')"
        cat <<EOF

  export AWS_ACCESS_KEY_ID=<your-access-key-id>
  export AWS_SECRET_ACCESS_KEY=<your-secret-access-key>
  export AWS_SESSION_TOKEN=<your-session-token>
  export AWS_REGION=$REGION

EOF
        BLOCK_CONTENT="export AWS_REGION='$REGION'
"
        ;;
      e)
        echo
        c_yellow "$(L '  联合身份: 在 ~/.aws/config 的 profile 里配 credential_process,' '  Federated: configure credential_process in your ~/.aws/config profile,')"
        c_yellow "$(L '  把浏览器登录/令牌交换/缓存/刷新交给该 helper,SDK 自动解析。' '  let that helper handle browser login / token exchange / cache / refresh.')"
        AWS_PROF=$(ask "  $(L '使用哪个 profile' 'which profile')" "codex-bedrock")
        BLOCK_CONTENT="export AWS_PROFILE='$AWS_PROF'
export AWS_REGION='$REGION'
"
        c_dim "  $(L '脚本仅设 AWS_PROFILE + AWS_REGION; credential_process 需你自行配置。' 'Script only sets AWS_PROFILE + AWS_REGION; configure credential_process yourself.')"
        ;;
      *) die "$(L 无效选择 'invalid choice')" ;;
    esac
    ;;
  *) die "$(L 无效选择 'invalid choice')" ;;
esac

# 2) 模型
echo
MODEL=$(choose_model)

# 3) 目标
echo
TARGETS=$(choose_targets)
RC_FILE=$(detect_rc)

# 4) 摘要确认
echo
c_blue "$(L '==> 即将应用:' '==> About to apply:')"
echo "  - config.toml: model_provider = \"amazon-bedrock\""
[ -n "$MODEL" ] && echo "  - config.toml: model = \"$MODEL\"" || echo "  - config.toml: $(L 'model 不变' 'model unchanged')"
echo "  - Region: $REGION"
[ -n "$AWS_PROF" ] && echo "  - AWS_PROFILE: $AWS_PROF"
case "$AWS_DO" in
  configure) echo "  - $(L '将运行' 'will run'): aws configure --profile $AWS_PROF" ;;
  set)       echo "  - $(L '将运行' 'will run'): aws configure set (AK/SK -> ~/.aws, profile $AWS_PROF)" ;;
  sso)       echo "  - $(L '将运行' 'will run'): aws sso login --profile $AWS_PROF" ;;
esac
case "$TARGETS" in
  2) echo "  - $(L '写入' write) CLI: $RC_FILE" ;;
  3) echo "  - $(L '写入' write) Desktop/IDE: $ENV_FILE (chmod 600)" ;;
  *) echo "  - $(L '写入' write) CLI: $RC_FILE"; echo "  - $(L '写入' write) Desktop/IDE: $ENV_FILE (chmod 600)" ;;
esac
echo
GO=$(ask "  $(L '确认应用? (y/N)' 'Apply? (y/N)')" "N")
case "$GO" in y|Y|yes) ;; *) c_yellow "$(L '已取消,未改动任何文件。' 'Cancelled, no files changed.')"; exit 0 ;; esac

# 5) 应用
echo
c_blue "$(L '==> 应用中...' '==> Applying...')"

backup "$CONFIG_TOML"
upsert_toml "$CONFIG_TOML" "model_provider" 'model_provider = "amazon-bedrock"'
[ -n "$MODEL" ] && upsert_toml "$CONFIG_TOML" "model" "model = \"$MODEL\""
c_green "  config.toml $(L 已更新 updated)"

# 执行延迟的 aws 命令
case "$AWS_DO" in
  configure)
    command -v aws >/dev/null 2>&1 || die "$(L '未找到 aws CLI' 'aws CLI not found')"
    aws configure --profile "$AWS_PROF"
    aws configure set region "$REGION" --profile "$AWS_PROF"
    c_green "  aws configure $(L 完成 'done') (profile $AWS_PROF)"
    ;;
  set)
    command -v aws >/dev/null 2>&1 || die "$(L '未找到 aws CLI' 'aws CLI not found')"
    aws configure set aws_access_key_id "$AK" --profile "$AWS_PROF"
    aws configure set aws_secret_access_key "$SK" --profile "$AWS_PROF"
    aws configure set region "$REGION" --profile "$AWS_PROF"
    AK=""; SK=""
    c_green "  AK/SK $(L '已写入 ~/.aws' 'written to ~/.aws') (profile $AWS_PROF)"
    ;;
  sso)
    command -v aws >/dev/null 2>&1 || die "$(L '未找到 aws CLI' 'aws CLI not found')"
    aws sso login --profile "$AWS_PROF" && c_green "  aws sso login $(L 完成 'done')"
    ;;
esac

case "$TARGETS" in
  2|1)
    backup "$RC_FILE"
    upsert_block "$RC_FILE" "$BLOCK_CONTENT"
    c_green "  $RC_FILE $(L '已更新 (managed 块)' 'updated (managed block)')"
    ;;
esac
case "$TARGETS" in
  3|1)
    backup "$ENV_FILE"
    upsert_block "$ENV_FILE" "$BLOCK_CONTENT"
    chmod 600 "$ENV_FILE"
    c_green "  $ENV_FILE $(L 已更新 updated) (chmod 600)"
    ;;
esac

# 6) 收尾
echo
c_green "$(L '==> 完成' '==> Done')"
if [ "$LANGV" = "en" ]; then
cat <<EOF

Next, make it take effect:
  - Terminal (CLI):  source $RC_FILE   then run codex; use /status to confirm provider is amazon-bedrock
  - Desktop app:     Cmd+Q to fully quit, then reopen (it reads ~/.codex/.env, not shell rc)

Troubleshooting:
  - model ID must match exactly (openai.gpt-5.5 / openai.gpt-5.4)
  - region must be a US region where the model is available
  - API key / temp creds must not be expired ("token expired" => regenerate)
  - re-run this script anytime to rotate; the managed block is replaced in place
EOF
else
cat <<EOF

下一步让配置生效:
  - 终端 (CLI):  source $RC_FILE   然后运行 codex,用 /status 确认 provider 是 amazon-bedrock
  - 桌面 App:    Cmd+Q 完全退出后重开 (它读 ~/.codex/.env,不读 shell rc)

排错清单:
  - model ID 必须精确匹配 (openai.gpt-5.5 / openai.gpt-5.4)
  - region 必须是模型可用的美区
  - API key / 临时凭证未过期 ("token expired" 即过期,需重新生成)
  - 重新运行本脚本可随时轮换,managed 块会被就地替换
EOF
fi
[ "$AUTH" = "1" ] && c_yellow "$(L '注意: short-term API key 最长 ~12h 过期; 常用建议生成 long-term key。' 'Note: short-term API keys expire in ~12h; for regular use generate a long-term key.')"
exit 0
