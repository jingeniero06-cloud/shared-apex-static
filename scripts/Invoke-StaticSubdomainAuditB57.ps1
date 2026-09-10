#Requires -Version 5.1
<#
.SYNOPSIS
  Phase 1 mixed portfolio: HTML-only WP → static.* for Static Subdomain Audit B5-7.
  Then inject form-validation on static.* form pages (Elementor or CF7/WPForms).
  Apex untouched. Phase 2 full-assets is separate after fail list.
#>
param(
  [ValidateSet('s2', 's1', 'all')]
  [string] $Lane = 'all',
  [int] $MaxPages = 60,
  [switch] $SkipInject
)

$ErrorActionPreference = 'Continue'
$PreviewRoot = 'C:\Users\My PC\Downloads\fleet-static-preview'
$Sites = Join-Path $PreviewRoot 'sites'
$Scrape = Join-Path $PreviewRoot 'scripts\Invoke-PreviewStaticOnFleet.ps1'
$InjectEl = Join-Path $PreviewRoot 'scripts\Invoke-InjectFleetFormValidation.ps1'
$InjectCf7 = Join-Path $PSScriptRoot 'Invoke-InjectPreviewFormValidationAllPages.ps1'
$LogDir = Join-Path $PreviewRoot 'reports'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$Status = Join-Path $LogDir 'static-subdomain-audit-b57-status.txt'
$EnvFile = 'C:\Users\My PC\Downloads\shared-apex-static\.env'

function Write-Status([string]$Msg) {
  $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Msg
  try { Add-Content -LiteralPath $Status -Value $line -Encoding UTF8 } catch { Write-Host "(status locked) $line" -ForegroundColor DarkYellow }
  Write-Host $line
}

$jobs = @()
if ($Lane -in @('s2', 'all')) {
  $jobs += @{
    Csv = Join-Path $Sites 'static-subdomain-audit-b57-s2.csv'
    Worker = 'fleet-static-worker'
    Label = 's2'
  }
}
if ($Lane -in @('s1', 'all')) {
  $jobs += @{
    Csv = Join-Path $Sites 'static-subdomain-audit-b57-s1.csv'
    Worker = 'fleet-static-worker-server-1'
    Label = 's1'
  }
}

Write-Status "START lane=$Lane MaxPages=$MaxPages jobs=$($jobs.Count) HTML-only static.*"

foreach ($job in $jobs) {
  if (-not (Test-Path -LiteralPath $job.Csv)) {
    Write-Status "MISSING $($job.Csv)"
    continue
  }
  $n = @(Import-Csv -LiteralPath $job.Csv | Where-Object { $_.Domain }).Count
  Write-Status "SCRAPE start $($job.Label) n=$n worker=$($job.Worker) SkipAssets+InjectFV"
  & $Scrape -SitesCsv $job.Csv -MaxPages $MaxPages -WorkerName $job.Worker -EnvFile $EnvFile -SkipAssets -InjectFormValidation
  Write-Status "SCRAPE done $($job.Label) exit=$LASTEXITCODE"
}

Write-Status "PHASE1_COMPLETE lane=$Lane"
Write-Host "Status log: $Status" -ForegroundColor Green
