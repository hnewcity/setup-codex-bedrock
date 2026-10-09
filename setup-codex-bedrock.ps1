<#
 setup-codex-bedrock.ps1
 渐进式配置 Codex 使用 Amazon Bedrock (Windows / PowerShell 版)
 Progressive setup for Codex on Amazon Bedrock (Windows / PowerShell edition)

 特性 / Features:
   - 交互式 + 双语(中文 / English)
   - 幂等: 用户级环境变量就地覆盖; .env 用 marker 块管理, 重复运行只更新不堆积
   - 安全: .env 仅当前用户可读写 (icacls); 改动前自动备份
   - 多认证: Bedrock API key / AWS SDK 凭证链(profile·SSO·长期AKSK·临时·联合身份)
   - 多目标: CLI(用户环境变量) / 桌面App·IDE(~/.codex/.env) / 两者

 用法 / Usage:
   powershell -ExecutionPolicy Bypass -File .\setup-codex-bedrock.ps1
   irm https://raw.githubusercontent.com/hnewcity/setup-codex-bedrock/main/setup-codex-bedrock.ps1 | iex
#>

# 全部逻辑包在函数里: 通过 irm | iex 运行时不污染调用方会话, 也不会因 exit 关掉窗口
function Invoke-CodexBedrockSetup {
  Set-StrictMode -Version 2.0
  $ErrorActionPreference = 'Stop'

  $CodexHome  = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
  $ConfigToml = Join-Path $CodexHome 'config.toml'
  $EnvFile    = Join-Path $CodexHome '.env'
  $BlockStart = '# >>> codex-bedrock (managed by setup script) >>>'
  $BlockEnd   = '# <<< codex-bedrock (managed by setup script) <<<'
  $OnWindows  = [System.Environment]::OSVersion.Platform -eq 'Win32NT'
  $Utf8NoBom  = New-Object System.Text.UTF8Encoding($false)
  $LangV      = 'zh'

  # ---------- 颜色 ----------
  function Write-Title([string]$m) { Write-Host $m -ForegroundColor Cyan }
  function Write-Ok([string]$m)    { Write-Host $m -ForegroundColor Green }
  function Write-Warn([string]$m)  { Write-Host $m -ForegroundColor Yellow }
  function Write-Dim([string]$m)   { Write-Host $m -ForegroundColor DarkGray }

  # ---------- 语言 ----------
  # L "中文" "English" -> 按当前语言输出
  function L([string]$Zh, [string]$En) { if ($LangV -eq 'en') { $En } else { $Zh } }

  # ---------- 文件工具 ----------
  function Read-FileLines([string]$Path) {
    $list = New-Object 'System.Collections.Generic.List[string]'
    if (Test-Path -LiteralPath $Path) { $list.AddRange([System.IO.File]::ReadAllLines($Path)) }
    , $list
  }

  # UTF-8 无 BOM 写入 (PowerShell 5.1 的 Set-Content -Encoding UTF8 会带 BOM, TOML 解析器不认)
  function Write-FileLines([string]$Path, $Lines) {
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $text = ($Lines -join [Environment]::NewLine) + [Environment]::NewLine
    [System.IO.File]::WriteAllText($Path, $text, $Utf8NoBom)
  }

  function Backup-File([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $b = "$Path.bak.$(Get-Date -Format yyyyMMddHHmmss)"
    Copy-Item -LiteralPath $Path -Destination $b
    Write-Dim "  $(L '已备份' 'backup'): $b"
  }

  # 替换或追加 marker 块(幂等)
  function Set-ManagedBlock([string]$Path, [string[]]$Content) {
    $out = New-Object 'System.Collections.Generic.List[string]'
    $skip = $false
    foreach ($l in (Read-FileLines $Path)) {
      if ($l -eq $BlockStart) { $skip = $true; continue }
      if ($skip) { if ($l -eq $BlockEnd) { $skip = $false }; continue }
      $out.Add($l)
    }
    $out.Add($BlockStart); $out.AddRange($Content); $out.Add($BlockEnd)
    Write-FileLines $Path $out
  }

  # 顶层 TOML key 就地更新或前置插入(顶层 key 必须在任何 [table] 之前)
  function Set-TomlKey([string]$Path, [string]$Key, [string]$Line) {
    $lines = Read-FileLines $Path
    $re = '^\s*' + [regex]::Escape($Key) + '\s*='
    $idx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
      if ($lines[$i] -match '^\s*\[') { break }
      if ($lines[$i] -match $re) { $idx = $i; break }
    }
    if ($idx -ge 0) { $lines[$idx] = $Line } else { $lines.Insert(0, $Line) }
    Write-FileLines $Path $lines
  }

  function Get-TomlValue([string]$Path, [string]$Key) {
    $re = '^\s*' + [regex]::Escape($Key) + '\s*=\s*"?([^"]*)"?'
    foreach ($l in (Read-FileLines $Path)) { if ($l -match $re) { return $Matches[1].Trim() } }
    ''
  }

  # 相当于 chmod 600: 去掉继承权限, 只给当前用户完全控制
  function Protect-File([string]$Path) {
    if ($OnWindows) {
      $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
      & icacls $Path /inheritance:r /grant:r "${me}:(F)" | Out-Null
      if ($LASTEXITCODE -ne 0) { Write-Warn "  $(L 'icacls 设置权限失败, 请手动检查' 'icacls failed; check file permissions manually'): $Path" }
    } else {
      & chmod 600 $Path
    }
  }

  function Get-UserEnv([string]$Name) { [Environment]::GetEnvironmentVariable($Name, 'User') }

  # 写用户级环境变量 (新开的终端/应用生效), 同时更新当前进程
  function Set-UserEnv([string]$Name, $Value) {
    [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
    if ($null -eq $Value) { Remove-Item -Path "Env:$Name" -ErrorAction SilentlyContinue }
    else { Set-Item -Path "Env:$Name" -Value $Value }
  }

  function Read-Answer([string]$Prompt, [string]$Default = '') {
    if ($Default) { $p = "$Prompt [$Default]" } else { $p = $Prompt }
    $a = Read-Host $p
    if ([string]::IsNullOrWhiteSpace($a)) { $Default } else { $a.Trim() }
  }

  function Assert-AwsCli {
    if (-not (Get-Command aws -ErrorAction SilentlyContinue)) { throw (L '未找到 aws CLI' 'aws CLI not found') }
  }

  # ---------- 探测当前状态 ----------
  function Show-Preflight {
    Write-Title (L '==> 当前状态' '==> Current state')
    if (Test-Path -LiteralPath $ConfigToml) {
      $prov = Get-TomlValue $ConfigToml 'model_provider'
      $mdl  = Get-TomlValue $ConfigToml 'model'
      if (-not $prov) { $prov = '<unset>' }
      if (-not $mdl)  { $mdl  = '<unset>' }
      Write-Host "  config.toml: $(L '存在' 'exists') | model_provider=$prov model=$mdl"
    } else {
      Write-Host "  config.toml: $(L '不存在(将创建)' 'missing (will create)')"
    }
    if (Test-Path -LiteralPath $EnvFile) { Write-Host "  $EnvFile`: $(L '存在' 'exists')" }
    else { Write-Host "  $EnvFile`: $(L '不存在' 'missing')" }
    $tok = Get-UserEnv 'AWS_BEARER_TOKEN_BEDROCK'
    if ($tok) { Write-Host "  user env: AWS_BEARER_TOKEN_BEDROCK $(L '已设' 'set') (len=$($tok.Length))" }
    else { Write-Host "  user env: AWS_BEARER_TOKEN_BEDROCK $(L '未设' 'unset')" }
    $reg = Get-UserEnv 'AWS_REGION'
    if ($reg) { Write-Host "  user env: AWS_REGION=$reg" } else { Write-Host "  user env: AWS_REGION $(L '未设' 'unset')" }
    Write-Host ''
  }

  function Select-Region {
    Write-Title (L '==> 选择 AWS Region (Bedrock 上的 OpenAI 模型仅在美区)' '==> Choose AWS Region (OpenAI models on Bedrock are US-only)')
    Write-Host "  1) us-west-2   ($(L '默认' 'default'))"
    Write-Host '  2) us-east-2'
    Write-Host '  3) us-east-1'
    Write-Host "  4) $(L '自定义' 'custom')"
    switch (Read-Answer "  $(L '选择' 'Choose')" '1') {
      '2' { 'us-east-2' }
      '3' { 'us-east-1' }
      '4' { Read-Answer "  $(L '输入 region' 'enter region')" 'us-west-2' }
      default { 'us-west-2' }
    }
  }

  function Select-Model {
    Write-Title (L '==> 选择模型(可跳过,用默认)' '==> Choose model (optional, can skip)')
    Write-Host "  1) $(L '不写 model' 'leave model unset')  ($(L '默认' 'default'))"
    Write-Host '  2) openai.gpt-5.5'
    Write-Host '  3) openai.gpt-5.4'
    switch (Read-Answer "  $(L '选择' 'Choose')" '1') {
      '2' { 'openai.gpt-5.5' }
      '3' { 'openai.gpt-5.4' }
      default { '' }
    }
  }

  function Select-Targets {
    Write-Title (L '==> 配置写到哪里?' '==> Where to write config?')
    Write-Host "  1) $(L '两者都写   (推荐,默认)' 'both        (recommended, default)')"
    Write-Host "  2) $(L '仅 CLI     (用户环境变量,终端跑 codex)' 'CLI only    (user environment variables, for running codex in terminal)')"
    Write-Host "  3) $(L '仅 桌面App/IDE' 'Desktop/IDE only')  ($EnvFile)"
    Read-Answer "  $(L '选择' 'Choose')" '1'
  }

  # ================= 主流程 / MAIN =================
  try { Clear-Host } catch { }

  # 0) 语言选择(最先,双语提示)
  $l = Read-Host 'Language / 语言:  [1] 中文   [2] English  [1]'
  if ($l -match '^(2|en|e|english)$') { $LangV = 'en' }

  Write-Ok (L 'Codex + Amazon Bedrock 配置向导 (Windows)' 'Codex + Amazon Bedrock setup wizard (Windows)')
  Write-Dim (L '随时 Ctrl-C 退出;改动前自动备份。' 'Ctrl-C to quit anytime; files are backed up before changes.')
  Write-Host ''
  Show-Preflight

  # 1) 认证方式
  Write-Title (L '==> 认证方式 (Codex 按序检查: 先 API key, 后 AWS SDK 凭证链)' '==> Auth method (Codex checks in order: API key first, then AWS SDK chain)')
  Write-Host "  1) Bedrock API key   ($(L '最简单, 设 AWS_BEARER_TOKEN_BEDROCK' 'simplest, sets AWS_BEARER_TOKEN_BEDROCK'))"
  Write-Host "  2) $(L 'AWS SDK 凭证链   ' 'AWS SDK creds    ')  (profile / SSO / $(L '长期AKSK / 临时 / 联合身份' 'long-term AKSK / temp / federated'))"
  $auth = Read-Answer "  $(L '选择' 'Choose')" '1'

  # 收集变量: $vars 是要写入的环境变量 (有序)
  $vars    = [ordered]@{}
  $region  = ''
  $awsDo   = ''   # 延迟到 apply 执行的动作: ''|configure|set|sso
  $awsProf = ''
  $ak = ''; $sk = ''

  switch ($auth) {
    '1' {
      Write-Host ''
      Write-Warn (L '  请粘贴 Bedrock API key:' '  Paste Bedrock API key:')
      $bearer = Read-Answer '  AWS_BEARER_TOKEN_BEDROCK'
      if (-not $bearer) { throw (L '未输入 key' 'no key entered') }
      $region = Select-Region
      $vars['AWS_BEARER_TOKEN_BEDROCK'] = $bearer
      $vars['AWS_REGION'] = $region
    }
    '2' {
      Write-Host ''
      Write-Title (L '==> AWS SDK 凭证来源 (文档 Option 2 的 5 种)' '==> AWS SDK credential source (5 from doc Option 2)')
      if ($LangV -eq 'en') {
        Write-Host '  a) Named profile     (~/.aws already set, or run aws configure now)'
        Write-Host '  b) AWS SSO           (aws sso login --profile, browser login)'
        Write-Host '  c) Long-term AK/SK   (IAM user keys, no session token, persistable)'
        Write-Host '  d) Temp credentials  (AK/SK + session token, expires, this session only)'
        Write-Host '  e) Federated         (SSO/OIDC via profile credential_process)'
      } else {
        Write-Host '  a) 命名 Profile      (~/.aws 已配好, 或现在 aws configure 配)'
        Write-Host '  b) AWS SSO           (aws sso login --profile, 浏览器登录)'
        Write-Host '  c) 长期 AK/SK        (IAM user 永久密钥, 无 session token, 可持久化)'
        Write-Host '  d) 临时凭证          (AK/SK + session token, 会过期, 仅本次会话)'
        Write-Host '  e) 联合身份          (SSO/OIDC, 走 profile 的 credential_process)'
      }
      $sub = Read-Answer "  $(L '选择' 'Choose')" 'a'
      if ($sub -notmatch '^[a-e]$') { throw (L '无效选择' 'invalid choice') }
      $region = Select-Region
      switch ($sub) {
        'a' {
          $awsProf = Read-Answer "  $(L 'profile 名称' 'profile name')" 'codex-bedrock'
          Write-Host ''
          $run = Read-Answer "  $(L '现在用 aws configure 交互式配置该 profile? (y/N)' 'Run aws configure for this profile now? (y/N)')" 'N'
          if ($run -match '^(y|yes)$') { $awsDo = 'configure' }
          else { Write-Dim "  $(L "跳过: 假定 ~/.aws 已配好 profile '$awsProf'" "skip: assuming ~/.aws already has profile '$awsProf'")" }
        }
        'b' {
          $awsProf = Read-Answer "  $(L 'SSO profile 名称' 'SSO profile name')" 'codex-bedrock'
          Write-Host ''
          $run = Read-Answer "  $(L "现在执行 aws sso login --profile $awsProf? (Y/n)" "Run aws sso login --profile $awsProf now? (Y/n)")" 'Y'
          if ($run -match '^(n|no)$') { Write-Dim "  $(L "跳过, 记得自行: aws sso login --profile $awsProf" "skipped; run later: aws sso login --profile $awsProf")" }
          else { $awsDo = 'sso' }
        }
        'c' {
          Write-Host ''
          Write-Title (L '  长期 AK/SK 二选一:' '  Long-term AK/SK, pick one:')
          Write-Host "    1) $(L '粘贴密钥, 由脚本写入 ~/.aws (aws configure set, 推荐, 不进环境变量)' "paste keys, written to ~/.aws via 'aws configure set' (recommended, not in env vars)")"
          Write-Host "    2) $(L '我已配好 ~/.aws, 只设 profile + region' 'I already configured ~/.aws, just set profile + region')"
          $how = Read-Answer "  $(L '选择' 'Choose')" '1'
          if ($how -eq '1') {
            $awsProf = Read-Answer "  $(L '写入哪个 profile' 'write to which profile')" 'codex-bedrock'
            $ak = Read-Answer '  AWS_ACCESS_KEY_ID'
            $sk = Read-Answer '  AWS_SECRET_ACCESS_KEY'
            if (-not $ak -or -not $sk) { throw (L 'AK/SK 不能为空' 'AK/SK must not be empty') }
            $awsDo = 'set'
          } else {
            $awsProf = Read-Answer "  $(L 'profile 名称' 'profile name')" 'codex-bedrock'
          }
        }
        'd' {
          Write-Host ''
          Write-Warn (L '  临时凭证会过期, 不写入文件; 仅把 region 写入配置。' '  Temp creds expire; not written to files. Only region is saved.')
          Write-Title (L '  把下面三件套粘到 PowerShell 再跑 codex (值自行替换):' '  Paste these in PowerShell, then run codex (replace values):')
          Write-Host ''
          Write-Host '  $env:AWS_ACCESS_KEY_ID="<your-access-key-id>"'
          Write-Host '  $env:AWS_SECRET_ACCESS_KEY="<your-secret-access-key>"'
          Write-Host '  $env:AWS_SESSION_TOKEN="<your-session-token>"'
          Write-Host "  `$env:AWS_REGION=`"$region`""
          Write-Host ''
        }
        'e' {
          Write-Host ''
          Write-Warn (L '  联合身份: 在 ~/.aws/config 的 profile 里配 credential_process,' '  Federated: configure credential_process in your ~/.aws/config profile,')
          Write-Warn (L '  把浏览器登录/令牌交换/缓存/刷新交给该 helper,SDK 自动解析。' '  let that helper handle browser login / token exchange / cache / refresh.')
          $awsProf = Read-Answer "  $(L '使用哪个 profile' 'which profile')" 'codex-bedrock'
          Write-Dim "  $(L '脚本仅设 AWS_PROFILE + AWS_REGION; credential_process 需你自行配置。' 'Script only sets AWS_PROFILE + AWS_REGION; configure credential_process yourself.')"
        }
      }
      if ($awsProf) { $vars['AWS_PROFILE'] = $awsProf }
      $vars['AWS_REGION'] = $region
    }
    default { throw (L '无效选择' 'invalid choice') }
  }

  # 2) 模型
  Write-Host ''
  $model = Select-Model

  # 3) 目标
  Write-Host ''
  $targets = Select-Targets
  $doCli = $targets -ne '3'
  $doEnv = $targets -ne '2'
  # 换成 SDK 凭证时清掉旧的 API key, 否则 Codex 仍会优先用它 (对应 bash 版 managed 块被整体替换)
  $dropBearer = $doCli -and -not $vars.Contains('AWS_BEARER_TOKEN_BEDROCK') -and [bool](Get-UserEnv 'AWS_BEARER_TOKEN_BEDROCK')

  # 4) 摘要确认
  Write-Host ''
  Write-Title (L '==> 即将应用:' '==> About to apply:')
  Write-Host '  - config.toml: model_provider = "amazon-bedrock"'
  if ($model) { Write-Host "  - config.toml: model = `"$model`"" } else { Write-Host "  - config.toml: $(L 'model 不变' 'model unchanged')" }
  Write-Host "  - Region: $region"
  if ($awsProf) { Write-Host "  - AWS_PROFILE: $awsProf" }
  switch ($awsDo) {
    'configure' { Write-Host "  - $(L '将运行' 'will run'): aws configure --profile $awsProf" }
    'set'       { Write-Host "  - $(L '将运行' 'will run'): aws configure set (AK/SK -> ~/.aws, profile $awsProf)" }
    'sso'       { Write-Host "  - $(L '将运行' 'will run'): aws sso login --profile $awsProf" }
  }
  if ($doCli) { Write-Host "  - $(L '写入' 'write') CLI: $(L '用户环境变量' 'user environment variables') ($($vars.Keys -join ', '))" }
  if ($dropBearer) { Write-Host "  - $(L '删除' 'remove') $(L '用户环境变量' 'user env var') AWS_BEARER_TOKEN_BEDROCK" }
  if ($doEnv) { Write-Host "  - $(L '写入' 'write') Desktop/IDE: $EnvFile ($(L '仅当前用户可访问' 'current user only'))" }
  Write-Host ''
  $go = Read-Answer "  $(L '确认应用? (y/N)' 'Apply? (y/N)')" 'N'
  if ($go -notmatch '^(y|yes)$') { Write-Warn (L '已取消,未改动任何文件。' 'Cancelled, no files changed.'); return }

  # 5) 应用
  Write-Host ''
  Write-Title (L '==> 应用中...' '==> Applying...')

  Backup-File $ConfigToml
  Set-TomlKey $ConfigToml 'model_provider' 'model_provider = "amazon-bedrock"'
  if ($model) { Set-TomlKey $ConfigToml 'model' "model = `"$model`"" }
  Write-Ok "  config.toml $(L '已更新' 'updated')"

  # 执行延迟的 aws 命令
  switch ($awsDo) {
    'configure' {
      Assert-AwsCli
      & aws configure --profile $awsProf
      & aws configure set region $region --profile $awsProf
      Write-Ok "  aws configure $(L '完成' 'done') (profile $awsProf)"
    }
    'set' {
      Assert-AwsCli
      & aws configure set aws_access_key_id $ak --profile $awsProf
      & aws configure set aws_secret_access_key $sk --profile $awsProf
      & aws configure set region $region --profile $awsProf
      $ak = ''; $sk = ''
      Write-Ok "  AK/SK $(L '已写入 ~/.aws' 'written to ~/.aws') (profile $awsProf)"
    }
    'sso' {
      Assert-AwsCli
      & aws sso login --profile $awsProf
      if ($LASTEXITCODE -eq 0) { Write-Ok "  aws sso login $(L '完成' 'done')" }
    }
  }

  if ($doCli) {
    foreach ($k in $vars.Keys) { Set-UserEnv $k $vars[$k] }
    if ($dropBearer) { Set-UserEnv 'AWS_BEARER_TOKEN_BEDROCK' $null }
    Write-Ok "  $(L '用户环境变量已更新' 'user environment variables updated')"
  }
  if ($doEnv) {
    $content = foreach ($k in $vars.Keys) { "export $k='$($vars[$k])'" }
    Backup-File $EnvFile
    Set-ManagedBlock $EnvFile @($content)
    Protect-File $EnvFile
    Write-Ok "  $EnvFile $(L '已更新' 'updated') ($(L '仅当前用户可访问' 'current user only'))"
  }

  # 6) 收尾
  Write-Host ''
  Write-Ok (L '==> 完成' '==> Done')
  Write-Host ''
  if ($LangV -eq 'en') {
    Write-Host 'Next, make it take effect:'
    Write-Host '  - Terminal (CLI):  open a NEW terminal window (env vars load at startup), run codex; use /status to confirm provider is amazon-bedrock'
    Write-Host "  - Desktop app/IDE: fully quit (including the tray icon), then reopen (it reads $EnvFile)"
    Write-Host ''
    Write-Host 'Troubleshooting:'
    Write-Host '  - model ID must match exactly (openai.gpt-5.5 / openai.gpt-5.4)'
    Write-Host '  - region must be a US region where the model is available'
    Write-Host '  - API key / temp creds must not be expired ("token expired" => regenerate)'
    Write-Host '  - re-run this script anytime to rotate; values are replaced in place'
  } else {
    Write-Host '下一步让配置生效:'
    Write-Host '  - 终端 (CLI):    新开一个终端窗口 (环境变量在启动时加载), 运行 codex, 用 /status 确认 provider 是 amazon-bedrock'
    Write-Host "  - 桌面 App/IDE:  完全退出 (包括托盘图标) 后重开 (它读 $EnvFile)"
    Write-Host ''
    Write-Host '排错清单:'
    Write-Host '  - model ID 必须精确匹配 (openai.gpt-5.5 / openai.gpt-5.4)'
    Write-Host '  - region 必须是模型可用的美区'
    Write-Host '  - API key / 临时凭证未过期 ("token expired" 即过期,需重新生成)'
    Write-Host '  - 重新运行本脚本可随时轮换, 配置会被就地替换'
  }
  if ($auth -eq '1') { Write-Warn (L '注意: short-term API key 最长 ~12h 过期; 常用建议生成 long-term key。' 'Note: short-term API keys expire in ~12h; for regular use generate a long-term key.') }
}

$prevEncoding = $null
try {
  # PowerShell 5.1 控制台默认非 UTF-8, 中文会乱码
  try { $prevEncoding = [Console]::OutputEncoding; [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
  Invoke-CodexBedrockSetup
} catch {
  Write-Host $_.Exception.Message -ForegroundColor Red
} finally {
  if ($null -ne $prevEncoding) { try { [Console]::OutputEncoding = $prevEncoding } catch { } }
}
