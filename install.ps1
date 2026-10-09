# install.ps1 - pure-ASCII bootstrap for setup-codex-bedrock.ps1
#
# Why this exists:
#   setup-codex-bedrock.ps1 is UTF-8 WITH BOM (needed so -File / double-click
#   parse Chinese text correctly on GBK locales). But `irm <url> | iex` on
#   Windows PowerShell 5.1 mis-decodes that BOM and corrupts the first line,
#   so the one-liner fails to parse. This bootstrap is pure ASCII, so it pipes
#   into iex cleanly, then downloads the real script to a temp file and runs it
#   with -File (which handles the BOM correctly).
#
# Usage:
#   irm https://raw.githubusercontent.com/hnewcity/setup-codex-bedrock/main/install.ps1 | iex

$ErrorActionPreference = 'Stop'

# PowerShell 5.1 on older Windows defaults to TLS 1.0; GitHub needs TLS 1.2+.
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072 } catch {}

$url = 'https://raw.githubusercontent.com/hnewcity/setup-codex-bedrock/main/setup-codex-bedrock.ps1'
$dest = Join-Path ([IO.Path]::GetTempPath()) ('setup-codex-bedrock-' + [IO.Path]::GetRandomFileName() + '.ps1')

Write-Host 'Downloading setup-codex-bedrock.ps1 ...'
Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $dest

try {
    powershell -NoProfile -ExecutionPolicy Bypass -File $dest
} finally {
    Remove-Item -LiteralPath $dest -ErrorAction SilentlyContinue
}
