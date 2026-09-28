[CmdletBinding()]
param(
    [string]$DshHome = $(if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $HOME '.dsh' })
)

$ErrorActionPreference = 'Stop'
$encoding = New-Object System.Text.UTF8Encoding($false)
$sourceRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'seagull-files\claude-config-bundle'
$claudePath = Join-Path $sourceRoot 'CLAUDE.md'
$systemPath = Join-Path $sourceRoot 'system-prompt.md'
if (!(Test-Path $claudePath) -or !(Test-Path $systemPath)) { throw 'SeaGull source files were not found.' }

New-Item -ItemType Directory -Force -Path $DshHome | Out-Null
$agentsPath = Join-Path $DshHome 'AGENTS.md'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
$backup = Join-Path $DshHome ('backups\seagull-' + $stamp)
New-Item -ItemType Directory -Force -Path $backup | Out-Null
if (Test-Path $agentsPath) { Copy-Item $agentsPath (Join-Path $backup 'AGENTS.md') -Force }

$start = '<!-- SEAGULL-2:START -->'
$end = '<!-- SEAGULL-2:END -->'
$claude = Get-Content -Raw -Encoding UTF8 $claudePath
$system = Get-Content -Raw -Encoding UTF8 $systemPath
$block = @($start, '# 海鸥 2.0 — DSH 全局适配', '', '以下为完整海鸥人格、术语映射、few-shot 示例和领域上下文。保留 DSH 原生工具、权限与插件机制。', '', $claude.TrimEnd(), '', $system.TrimEnd(), $end) -join [Environment]::NewLine

$existing = if (Test-Path $agentsPath) { Get-Content -Raw -Encoding UTF8 $agentsPath } else { '' }
$pattern = '(?s)<!-- SEAGULL-2:START -->.*?<!-- SEAGULL-2:END -->'
if ($existing -match $pattern) { $updated = [regex]::Replace($existing, $pattern, $block) }
elseif ([string]::IsNullOrWhiteSpace($existing)) { $updated = $block + [Environment]::NewLine }
else { $updated = $existing.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine + $block + [Environment]::NewLine }
[System.IO.File]::WriteAllText($agentsPath, $updated, $encoding)

$purgeDetected = (Test-Path (Join-Path $DshHome 'dsh-purge\applied.json')) -or (Test-Path (Join-Path $DshHome 'profiles\desktop\node_modules\dsh-purge'))
Write-Host "DSH AGENTS installed: $agentsPath" -ForegroundColor Green
Write-Host "Backup: $backup" -ForegroundColor DarkGray
if ($purgeDetected) { Write-Warning 'dsh-purge is installed. It may prioritize prompt-inject.md for identity. This installer intentionally does not overwrite prompt-inject.md.' }
Write-Host 'Restart DSH Desktop and start a new conversation.' -ForegroundColor Green
