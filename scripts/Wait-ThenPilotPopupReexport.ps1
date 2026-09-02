#Requires -Version 5.1
<#
.SYNOPSIS
  Poll hosting IP until WordPress HTTP works, then run the 5-site popup pilot.
  Does not run the remaining 186 sites.
#>
param(
  [int] $IntervalSec = 90,
  [int] $MaxHours = 12
)

$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $PSScriptRoot
$Test = Join-Path $Root 'scripts\Test-WpOriginAccess.ps1'
$Pilot = Join-Path $Root 'scripts\Invoke-PopupReexportFromOrigin.ps1'
$Log = Join-Path $Root 'reports\popup-reexport-wait.log'
New-Item -ItemType Directory -Path (Split-Path $Log) -Force | Out-Null

function Write-WaitLog([string]$Msg) {
  $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'), $Msg
  Add-Content -LiteralPath $Log -Value $line -Encoding UTF8
}

$mutex = New-Object System.Threading.Mutex($false, 'Global\CityThrivePopupReexportWait')
if (-not $mutex.WaitOne(0)) {
  Write-WaitLog 'waiter already running'
  exit 0
}

$deadline = (Get-Date).AddHours($MaxHours)
try {
  while ((Get-Date) -lt $deadline) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Test | Out-Null
    if ($LASTEXITCODE -eq 0) {
      Write-WaitLog 'ORIGIN OPEN - starting pilot 5'
      & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Pilot -Lane pilot
      Write-WaitLog ('pilot exit=' + $LASTEXITCODE)
      exit $LASTEXITCODE
    }
    Write-WaitLog ('still blocked; sleep ' + $IntervalSec + 's')
    Start-Sleep -Seconds $IntervalSec
  }
  Write-WaitLog 'deadline reached; origin still blocked'
  exit 3
} finally {
  try { $mutex.ReleaseMutex() } catch {}
  $mutex.Dispose()
}
