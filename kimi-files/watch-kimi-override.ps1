[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$StatePath,
    [Parameter(Mandatory = $true)][string]$NodeBin,
    [Parameter(Mandatory = $true)][string]$HelperPath,
    [Parameter(Mandatory = $true)][string]$PromptPath,
    [Parameter(Mandatory = $true)][string]$WsModulePath,
    [string]$LogPath,
    [string]$PidPath
)

$ErrorActionPreference = 'SilentlyContinue'
$lastEndpoint = ''

if ($PidPath) {
    [System.IO.File]::WriteAllText($PidPath, [string]$PID, (New-Object System.Text.UTF8Encoding($false)))
}

function Write-WatcherLog([string]$Message) {
    if (!$LogPath) { return }
    $line = ('{0:o} {1}' -f (Get-Date), $Message)
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}

while ($true) {
    try {
        if (Test-Path -LiteralPath $StatePath) {
            $state = Get-Content -Raw -Encoding UTF8 $StatePath | ConvertFrom-Json
            $endpoint = $state.control.endpoint
            if ($endpoint -and $endpoint.url -and $endpoint.startedAt) {
                $fingerprint = '{0}|{1}|{2}' -f $endpoint.pid, $endpoint.startedAt, $endpoint.url
                if ($fingerprint -ne $lastEndpoint) {
                    Start-Sleep -Seconds 2
                    $output = & $NodeBin $HelperPath set-override $StatePath $WsModulePath $PromptPath 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        $lastEndpoint = $fingerprint
                        Write-WatcherLog 'SeaGull systemPromptOverride applied.'
                    } else {
                        Write-WatcherLog ('Override apply failed: ' + ($output -join ' '))
                    }
                }
            }
        }
    } catch {
        Write-WatcherLog ('Watcher error: ' + $_.Exception.Message)
    }
    Start-Sleep -Seconds 5
}
