[CmdletBinding()]
param(
    [string]$DshHome = $(if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $HOME '.dsh' })
)

$ErrorActionPreference = 'Stop'
$encoding = New-Object System.Text.UTF8Encoding($false)
$agentsPath = Join-Path $DshHome 'AGENTS.md'
if (!(Test-Path $agentsPath)) { Write-Host 'No DSH AGENTS.md found.'; exit 0 }

$content = Get-Content -Raw -Encoding UTF8 $agentsPath
$pattern = '(?s)<!-- SEAGULL-2:START -->.*?<!-- SEAGULL-2:END -->'
if ($content -notmatch $pattern) { Write-Host 'No SeaGull block found; AGENTS.md was not changed.'; exit 0 }

$backup = "$agentsPath.seagull-backup-$(Get-Date -Format 'yyyyMMdd-HHmmssfff')"
Copy-Item $agentsPath $backup -Force
$updated = [regex]::Replace($content, $pattern, '')
if ([string]::IsNullOrWhiteSpace($updated)) { Remove-Item -LiteralPath $agentsPath -Force }
else { [System.IO.File]::WriteAllText($agentsPath, $updated, $encoding) }
Write-Host "SeaGull block removed. Backup: $backup" -ForegroundColor Green
