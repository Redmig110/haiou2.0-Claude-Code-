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
$pluginDir = Join-Path $PSScriptRoot 'seagull-2'
if (!(Test-Path (Join-Path $pluginDir 'kimi.plugin.json'))) { throw "Kimi plugin manifest not found: $pluginDir" }

function Write-Utf8NoBom([string]$Path, [string]$Content) {
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Normalize-Newlines([string]$Content) {
    $cr = [char]13
    $lf = [char]10
    return $Content.Replace("$cr$lf", "$lf").Replace("$cr", "$lf")
}

function Find-FirstExistingPath([string[]]$Candidates) {
    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return (Resolve-Path -LiteralPath $candidate).Path }
    }
    return $null
}

$driveRoots = @(Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Root })
if (!$DaimonCli) {
    $candidates = @()
    foreach ($root in $driveRoots) { $candidates += Join-Path $root 'KimiData\daimon-bundle\bin\kimi-daimon.cmd' }
    $DaimonCli = Find-FirstExistingPath $candidates
}
if (!$NodeBin) {
    $candidates = @()
    foreach ($root in $driveRoots) { $candidates += Join-Path $root 'Program Files\Kimi\resources\resources\runtime\node.exe' }
    $NodeBin = Find-FirstExistingPath $candidates
    if (!$NodeBin) { $nodeCommand = Get-Command node -ErrorAction SilentlyContinue; if ($nodeCommand) { $NodeBin = $nodeCommand.Source } }
}
if (!$KimiShareDir) {
    $candidates = @()
    foreach ($root in $driveRoots) { $candidates += Join-Path $root 'KimiData\daimon-share' }
    $KimiShareDir = Find-FirstExistingPath $candidates
}
if (!$DaimonCli -or !$NodeBin) { throw 'Kimi Daimon CLI or Node runtime was not found. Start Kimi Desktop once, or pass -DaimonCli and -NodeBin.' }

if (!$SkipKimiCode) {
    New-Item -ItemType Directory -Force -Path $KimiCodeHome | Out-Null
    & $DaimonCli --node $NodeBin kimi-plugin install $pluginDir --home $KimiCodeHome --json
    if ($LASTEXITCODE -ne 0) { throw 'Kimi Code plugin installation failed.' }

    $agentsPath = Join-Path $KimiCodeHome 'AGENTS.md'
    if ((Test-Path $agentsPath) -and (Get-Item $agentsPath).Length -gt 32768) {
        $legacySource = Join-Path (Split-Path $PSScriptRoot -Parent) 'seagull-files\claude-config-bundle\CLAUDE.md'
        $targetContent = Get-Content -Raw -Encoding UTF8 $agentsPath
        $legacyContent = if (Test-Path $legacySource) { Get-Content -Raw -Encoding UTF8 $legacySource } else { $null }
        $isExactLegacyContent = $legacyContent -ne $null -and (Normalize-Newlines $targetContent) -ceq (Normalize-Newlines $legacyContent)
        if ($isExactLegacyContent) {
            $backup = Join-Path $KimiCodeHome ('backups\seagull-plugin-migration-' + (Get-Date -Format 'yyyyMMdd-HHmmssfff'))
            New-Item -ItemType Directory -Force -Path $backup | Out-Null
            Copy-Item $agentsPath (Join-Path $backup 'AGENTS.md') -Force
            $loader = @('# 海鸥 2.0', '', '完整人格和 few-shot 示例由已启用的 seagull-2 插件无损加载。', 'systemPromptPath 注入核心人格，sessionStart.skill 自动加载完整原始语料。', '不要在本文件重复完整语料，以免重复注入和触发单文件 32 KB 性能提示。') -join [Environment]::NewLine
            Write-Utf8NoBom $agentsPath ($loader + [Environment]::NewLine)
            Write-Host "Migrated oversized Seagull AGENTS.md to plugin; backup: $backup" -ForegroundColor Yellow
        } else {
            Write-Warning 'AGENTS.md exceeds 32 KB but is not an exact legacy SeaGull file. It was preserved unchanged to avoid losing user instructions.'
        }
    }
    Write-Host 'Kimi Code installed. Restart Kimi Code or run /plugins reload, then open a new session.' -ForegroundColor Green
}

if (!$SkipKimiWork) {
    if (!$KimiShareDir) { Write-Warning 'Kimi Work share directory was not found; Kimi Code installation is complete.' }
    else {
        & $DaimonCli --node $NodeBin kimi-plugin register-personal $pluginDir --share-dir $KimiShareDir --json
        if ($LASTEXITCODE -ne 0) { throw 'Kimi Work personal plugin registration failed.' }
        $statePath = Join-Path $KimiShareDir 'daimon\agents\main\runner.state.json'
        $daimonBundle = Split-Path (Split-Path $DaimonCli -Parent) -Parent
        $wsModule = Join-Path $daimonBundle 'app\daimon\node_modules\ws'
        if ((Test-Path $statePath) -and (Test-Path $wsModule)) {
            & $NodeBin (Join-Path $PSScriptRoot 'personal-plugin-control.cjs') install $statePath $wsModule seagull-2
            $controlExit = $LASTEXITCODE
            if ($controlExit -eq 3) { Write-Warning 'Kimi Work plugin installed, but active-session reload failed. Start a new conversation or restart Kimi Desktop.' }
            elseif ($controlExit -ne 0) { throw 'Kimi Work plugin control installation failed.' }
            else { Write-Host 'Kimi Work installed and active sessions reloaded.' -ForegroundColor Green }
        } else {
            Write-Host 'Kimi Work plugin registered. Open the Personal plugins tab and install SeaGull 2.0.' -ForegroundColor Yellow
            Write-Host 'kimi-work://plugin?id=seagull-2'
        }
    }
}
