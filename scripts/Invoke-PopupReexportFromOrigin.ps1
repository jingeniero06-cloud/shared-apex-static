#Requires -Version 5.1
<#
.SYNOPSIS
  Rescrape popup-fixed WordPress into HTML_FLEET + R2 via hosting IP.
  Does not scrape public HTTPS (that would recopy stale KV popups).
  Does not change Worker routes (sites already on fleet).
  Server 2 origin: 174.136.29.214. Server 1 origin: 165.140.157.43.
#>
param(
  [ValidateSet('pilot', 's2', 's1', 'all')]
  [string] $Lane = 'pilot',
  [string] $HostingIpS2 = '174.136.29.214',
  [string] $HostingIpS1 = '165.140.157.43',
  [int] $MaxPages = 150,
  [switch] $SkipOriginCheck,
  [switch] $SkipAssets,
  [switch] $InjectFormValidation
)

$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $PSScriptRoot
$Preview = 'C:\Users\My PC\Downloads\fleet-static-preview'
$Sites = Join-Path $Preview 'sites'
$Scrape = Join-Path $Root 'scripts\Invoke-WpOriginToFleet.ps1'
$TestOrigin = Join-Path $Root 'scripts\Test-WpOriginAccess.ps1'
$Inject = Join-Path $Preview 'scripts\Invoke-InjectFleetFormValidation.ps1'
$LogDir = Join-Path $Root 'reports'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$Status = Join-Path $LogDir 'popup-reexport-status.txt'

function Write-Status([string]$Msg) {
  $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Msg
  try {
    Add-Content -LiteralPath $Status -Value $line -Encoding UTF8 -ErrorAction Stop
  } catch {
    Write-Host "(status file locked) $line" -ForegroundColor DarkYellow
  }
  Write-Host $line
}

function Get-FirstDomain([string]$CsvPath) {
  $row = @(Import-Csv -LiteralPath $CsvPath | Where-Object { $_.Domain }) | Select-Object -First 1
  if ($row) { return [string]$row.Domain }
  return $null
}

$map = @{
  pilot = @(
    @{ Csv = (Join-Path $Sites 'popup-reexport-pilot-s2.csv'); Worker = 'fleet-static-worker'; HostingIp = $HostingIpS2 }
    @{ Csv = (Join-Path $Sites 'popup-reexport-pilot-s1.csv'); Worker = 'fleet-static-worker-server-1'; HostingIp = $HostingIpS1 }
  )
  s2 = @(
    @{ Csv = (Join-Path $Sites 'popup-reexport-s2-b17.csv'); Worker = 'fleet-static-worker'; HostingIp = $HostingIpS2 }
  )
  s1 = @(
    @{ Csv = (Join-Path $Sites 'popup-reexport-s1.csv'); Worker = 'fleet-static-worker-server-1'; HostingIp = $HostingIpS1 }
  )
  all = @(
    @{ Csv = (Join-Path $Sites 'popup-reexport-s2-b17.csv'); Worker = 'fleet-static-worker'; HostingIp = $HostingIpS2 }
    @{ Csv = (Join-Path $Sites 'popup-reexport-s1.csv'); Worker = 'fleet-static-worker-server-1'; HostingIp = $HostingIpS1 }
  )
}

if (-not $SkipOriginCheck) {
  foreach ($job in $map[$Lane]) {
    $probe = Get-FirstDomain $job.Csv
    if (-not $probe) { continue }
    Write-Status "origin-check ip=$($job.HostingIp) domain=$probe"
    & $TestOrigin -HostingIp $job.HostingIp -Domain $probe
    if ($LASTEXITCODE -ne 0) {
      Write-Status "blocked: origin $($job.HostingIp) not reachable for $probe. Do not scrape public HTTPS. Lane=$Lane"
      exit 2
    }
  }
}

foreach ($job in $map[$Lane]) {
  if (-not (Test-Path -LiteralPath $job.Csv)) {
    Write-Status "missing csv $($job.Csv)"
    exit 1
  }
  Write-Status "start lane=$Lane worker=$($job.Worker) ip=$($job.HostingIp) csv=$($job.Csv) skipAssets=$SkipAssets"
  $scrapeSplat = @{
    SitesCsv   = $job.Csv
    HostingIp  = $job.HostingIp
    MaxPages   = $MaxPages
    WorkerName = $job.Worker
    SkipRoutes = $true
  }
  if ($SkipAssets) { $scrapeSplat.SkipAssets = $true }
  & $Scrape @scrapeSplat
  $scrapeExit = $LASTEXITCODE
  Write-Status "finished scrape worker=$($job.Worker) exit=$scrapeExit"
  if ($InjectFormValidation -and $scrapeExit -eq 0 -and (Test-Path -LiteralPath $Inject)) {
    Write-Status "inject form-validation csv=$($job.Csv)"
    & $Inject -SitesCsv $job.Csv
    Write-Status "finished inject exit=$LASTEXITCODE"
  }
}

Write-Status "done lane=$Lane"
exit 0
