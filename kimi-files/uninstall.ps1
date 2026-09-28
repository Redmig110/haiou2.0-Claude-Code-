[CmdletBinding()]
param(
    [string]$KimiCodeHome = $(if ($env:KIMI_CODE_HOME) { $env:KIMI_CODE_HOME } else { Join-Path $HOME '.kimi-code' }),
    [string]$KimiShareDir = $env:KIMI_SHARE_DIR,
    [string]$DaimonCli,
    [string]$NodeBin,
    [switch]$SkipKimiCode,
    [switch]$SkipKimiWork
)

$ErrorActionPreference = 'Stop'
$onWindows = $env:OS -eq 'Windows_NT' -or [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
$driveRoots = @(Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Root })

function Write-Utf8NoBom([string]$Path, [string]$Content) {
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}
if (!$DaimonCli) { foreach ($root in $driveRoots) { $candidate = Join-Path $root 'KimiData\daimon-bundle\bin\kimi-daimon.cmd'; if (Test-Path $candidate) { $DaimonCli = $candidate; break } } }
if (!$NodeBin) { foreach ($root in $driveRoots) { $candidate = Join-Path $root 'Program Files\Kimi\resources\resources\runtime\node.exe'; if (Test-Path $candidate) { $NodeBin = $candidate; break } } }
if (!$NodeBin) { $nodeCommand = Get-Command node -ErrorAction SilentlyContinue; if ($nodeCommand) { $NodeBin = $nodeCommand.Source } }
if (!$KimiShareDir) { foreach ($root in $driveRoots) { $candidate = Join-Path $root 'KimiData\daimon-share'; if (Test-Path $candidate) { $KimiShareDir = $candidate; break } } }

$workFailed = $false
$workReloadPending = $false
if ($SkipKimiWork) {
    Write-Host 'Skipping Kimi Work removal.' -ForegroundColor DarkGray
} elseif ($KimiShareDir) {
    if ($onWindows) {
        $stableDir = Join-Path $HOME '.kimi-seagull'
        $pidPath = Join-Path $stableDir 'watcher.pid'
        if (Test-Path $pidPath) {
            $watcherPid = Get-Content -Raw $pidPath
            if ($watcherPid -match '^\d+$') { Stop-Process -Id ([int]$watcherPid) -Force -ErrorAction SilentlyContinue }
        }
        $startupFile = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\SeaGull-Kimi-Override.cmd'
        if (Test-Path $startupFile) { Remove-Item -LiteralPath $startupFile -Force }
    }
    if (!$DaimonCli -or !$NodeBin) {
        Write-Warning 'Kimi Work was detected, but Daimon CLI or Node could not be resolved. Pass -DaimonCli and -NodeBin, then retry.'
        $workFailed = $true
    }
    $statePath = Join-Path $KimiShareDir 'daimon\agents\main\runner.state.json'
    if (!$workFailed) {
        $daimonBundle = Split-Path (Split-Path $DaimonCli -Parent) -Parent
        $wsModule = Join-Path $daimonBundle 'app\daimon\node_modules\ws'
        if (!(Test-Path $statePath) -or !(Test-Path $wsModule)) {
            Write-Warning 'Kimi Work control endpoint is unavailable. Start Kimi Desktop, then rerun uninstall.'
            $workFailed = $true
        } else {
            & $NodeBin (Join-Path $PSScriptRoot 'personal-plugin-control.cjs') remove $statePath $wsModule seagull-2
            $controlExit = $LASTEXITCODE
            if ($controlExit -eq 3) {
                Write-Warning 'Kimi Work plugin was removed, but active-session reload failed. Restart Kimi Desktop.'
                $workReloadPending = $true
            } elseif ($controlExit -ne 0) {
                Write-Warning 'Kimi Work plugin removal failed. Start Kimi Desktop and retry.'
                $workFailed = $true
            }

            $overridePath = Join-Path $PSScriptRoot 'seagull-2\full-system-prompt.md'
            & $NodeBin (Join-Path $PSScriptRoot 'personal-plugin-control.cjs') restore-override $statePath $wsModule $overridePath
            if ($LASTEXITCODE -ne 0) {
                Write-Warning 'Kimi Work system prompt override restore failed.'
                $workFailed = $true
            }

            if ($onWindows) {
                if (Test-Path $stableDir) { Remove-Item -LiteralPath $stableDir -Recurse -Force }
            }
        }
    }
} else {
    Write-Host 'Kimi Work data directory was not detected; skipping Kimi Work removal.' -ForegroundColor DarkGray
}

$installedPath = Join-Path $KimiCodeHome 'plugins\installed.json'
$managedPath = Join-Path $KimiCodeHome 'plugins\managed\seagull-2'
if (!$SkipKimiCode -and (Test-Path $installedPath)) {
    $backup = "$installedPath.seagull-backup-$(Get-Date -Format 'yyyyMMdd-HHmmssfff')"
    Copy-Item $installedPath $backup -Force
    $doc = Get-Content -Raw -Encoding UTF8 $installedPath | ConvertFrom-Json
    $doc.plugins = @($doc.plugins | Where-Object { $_.id -ne 'seagull-2' })
    Write-Utf8NoBom $installedPath (($doc | ConvertTo-Json -Depth 20) + [Environment]::NewLine)
}
if (!$SkipKimiCode -and (Test-Path $managedPath)) { Remove-Item -LiteralPath $managedPath -Recurse -Force }

$agentsPath = Join-Path $KimiCodeHome 'AGENTS.md'
if (!$SkipKimiCode -and (Test-Path $agentsPath)) {
    $agentsContent = Get-Content -Raw -Encoding UTF8 $agentsPath
    $expectedLoader = (@('# 海鸥 2.0', '', '完整人格和 few-shot 示例由已启用的 seagull-2 插件无损加载。', 'systemPromptPath 注入核心人格，sessionStart.skill 自动加载完整原始语料。', '不要在本文件重复完整语料，以免重复注入和触发单文件 32 KB 性能提示。') -join [Environment]::NewLine) + [Environment]::NewLine
    if ($agentsContent -eq $expectedLoader) {
        $backupRoot = Join-Path $KimiCodeHome 'backups'
        $latest = if (Test-Path $backupRoot) { Get-ChildItem $backupRoot -Directory -Filter 'seagull-plugin-migration-*' | Sort-Object LastWriteTime -Descending | Select-Object -First 1 } else { $null }
        $backupAgents = if ($latest) { Join-Path $latest.FullName 'AGENTS.md' } else { $null }
        if ($backupAgents -and (Test-Path $backupAgents)) { Copy-Item $backupAgents $agentsPath -Force }
        else { Remove-Item -LiteralPath $agentsPath -Force }
    } else {
        Write-Warning 'Kimi Code AGENTS.md is not the exact SeaGull loader file; leaving it unchanged.'
    }
}

if ($SkipKimiCode) { Write-Host 'Skipping Kimi Code removal.' -ForegroundColor DarkGray }

if ($workFailed) {
    Write-Error 'Kimi Code removal completed, but Kimi Work removal did not complete.'
    exit 1
}
if ($workReloadPending) {
    Write-Warning 'SeaGull plugin removed; restart Kimi Desktop and Kimi Code to finish unloading.'
    exit 3
}
Write-Host 'SeaGull 2.0 plugin removed. Restart Kimi Code.' -ForegroundColor Green
