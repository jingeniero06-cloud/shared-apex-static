#Requires -Version 5.1
<#
.SYNOPSIS
  Keep the 208-site WP-origin-to-fleet scrape running.
  Restarts it if the process dies. Independent of Cursor chat.
#>
$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $PSScriptRoot
$Log = Join-Path $Root 'reports\wp-origin-keepalive.log'
$Status = Join-Path $Root 'LIVE-208-STATUS.txt'
$QueueCsv = Join-Path $Root 'reports\fleet-on-shared-remain-after-canary.csv'
$RemainCsv = Join-Path $Root 'reports\fleet-on-shared-remain-keepalive.csv'
$ScrapeScript = Join-Path $Root 'scripts\Invoke-WpOriginToFleet.ps1'
$CanvasScript = Join-Path $Root 'scripts\Update-WpOriginFleetCanvas.ps1'
$StayWpFile = 'C:\Users\My PC\Downloads\static-conversion\reports\batch1-7-convert-20260808-173900\exclude-stay-wordpress.txt'
$QueueN = 208
$Canary = @('bedfordtreeservicecompany.com', 'abilenedrivewayrepair.com', 'cocoafoundationrepair.com')
$SafeTemp = Join-Path $env:USERPROFILE 'AppData\Local\Temp'
New-Item -ItemType Directory -Path $SafeTemp -Force | Out-Null
$env:TEMP = $SafeTemp
$env:TMP = $SafeTemp

function Write-KeepLog([string]$Msg) {
  $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Msg
  Add-Content -LiteralPath $Log -Value $line -Encoding UTF8
}

$mutex = New-Object System.Threading.Mutex($false, 'Global\CityThriveWpOriginToFleetKeepAlive')
$created = $false
try {
  $created = $mutex.WaitOne(0)
} catch [System.Threading.AbandonedMutexException] {
  $created = $true
} catch {
  $created = $false
}
if (-not $created) {
  Write-KeepLog 'keepalive already running; exiting'
  exit 0
}

function Get-ScrapeProcess {
  @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and ($_.CommandLine -like '*Invoke-WpOriginToFleet.ps1*') })
}

function Test-ScrapeHealthy {
  if ((Get-ScrapeProcess).Count -gt 0) { return $true }
  $newest = Get-ChildItem (Join-Path $Root 'reports') -Directory -Filter 'wp-to-fleet-20*' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime | Select-Object -Last 1
  if (-not $newest) { return $false }
  $html = Get-ChildItem $newest.FullName -Recurse -Filter 'page-*.html' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime | Select-Object -Last 1
  if ($html -and $html.LastWriteTime -gt (Get-Date).AddMinutes(-15)) { return $true }
  return $false
}

function Get-StayWp {
  $set = @{}
  foreach ($c in $Canary) { $set[$c] = $true }
  if (Test-Path -LiteralPath $StayWpFile) {
    Get-Content -LiteralPath $StayWpFile | ForEach-Object {
      $d = $_.Trim().ToLower()
      if ($d) { $set[$d] = $true }
    }
  }
  return $set
}

function Get-FinishedOk {
  $ok = @{}
  $dirs = @(Get-ChildItem (Join-Path $Root 'reports') -Directory -Filter 'wp-to-fleet-20*' -ErrorAction SilentlyContinue)
  foreach ($d in $dirs) {
    $sumPath = Join-Path $d.FullName 'summary.csv'
    if (-not (Test-Path $sumPath)) { continue }
    foreach ($r in @(Import-Csv $sumPath)) {
      if (-not $r.Domain) { continue }
      $dom = $r.Domain.Trim().ToLower()
      if ($r.After -match '200') { $ok[$dom] = $true }
    }
  }
  return $ok
}

function Get-RemainingRows {
  $stay = Get-StayWp
  $ok = Get-FinishedOk
  if (-not (Test-Path -LiteralPath $QueueCsv)) { return @() }
  @(Import-Csv -LiteralPath $QueueCsv | Where-Object {
    $_.Domain -and
    -not $stay.ContainsKey($_.Domain.Trim().ToLower()) -and
    -not $ok.ContainsKey($_.Domain.Trim().ToLower())
  })
}

function Write-LiveStatus([bool]$Alive, [int]$RemainCount) {
  $ok = Get-FinishedOk
  $done = @($ok.Keys | Where-Object { $Canary -notcontains $_ }).Count
  $outRoot = Join-Path $Root 'reports'
  $dirs = @(Get-ChildItem $outRoot -Directory -Filter 'wp-to-fleet-20*' -ErrorAction SilentlyContinue)
  $newest = $null
  $bestHtml = $null
  foreach ($d in $dirs) {
    $html = Get-ChildItem $d.FullName -Recurse -Filter 'page-*.html' -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime | Select-Object -Last 1
    if ($html -and (-not $bestHtml -or $html.LastWriteTime -gt $bestHtml.LastWriteTime)) {
      $bestHtml = $html
      $newest = $d
    }
  }
  if (-not $newest) {
    $newest = $dirs | Sort-Object LastWriteTime | Select-Object -Last 1
  }
  $current = '-'
  $pages = 0
  $last = '-'
  if ($newest) {
    $siteDirs = @(Get-ChildItem $newest.FullName -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    if ($siteDirs.Count -gt 0) {
      $current = $siteDirs[0].Name
      $pages = @(Get-ChildItem $siteDirs[0].FullName -Filter 'page-*.html' -EA SilentlyContinue).Count
    }
    $sumPath = Join-Path $newest.FullName 'summary.csv'
    if (Test-Path $sumPath) {
      $rows = @(Import-Csv $sumPath)
      if ($rows.Count -gt 0) { $last = $rows[-1].Domain }
    }
  }
  $job = if ($Alive) { 'RUNNING' } elseif ($RemainCount -le 0) { 'DONE' } else { 'RESTARTING' }
  @"
208-site WP -> fleet refresh
Updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Job: $job
Finished sites: $done / $QueueN
Current: $current (html pages on disk: $pages)
Last finished: $last
Keepalive: ON (auto-restart if scrape dies)
"@ | Set-Content -LiteralPath $Status -Encoding UTF8
}

Write-KeepLog 'keepalive started'
$canvasTick = 0
try {
  while ($true) {
    $remain = @(Get-RemainingRows)
    $scrapes = Get-ScrapeProcess
    $alive = Test-ScrapeHealthy

    if ($remain.Count -eq 0) {
      Write-KeepLog '208 queue complete; keepalive idle'
      Write-LiveStatus $false 0
      break
    }

    if ($scrapes.Count -gt 1) {
      Write-KeepLog ("WARN extra scrape processes={0}; not starting another" -f $scrapes.Count)
    }

    if (-not $alive -and $scrapes.Count -eq 0) {
      $remain | Export-Csv -LiteralPath $RemainCsv -NoTypeInformation -Encoding UTF8
      Write-KeepLog ("scrape dead; restarting remaining={0} first={1}" -f $remain.Count, $remain[0].Domain)
      $arg = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -SitesCsv "{1}" -HostingIp 174.136.29.214 -MaxPages 150' -f $ScrapeScript, $RemainCsv
      $psi = New-Object System.Diagnostics.ProcessStartInfo
      $psi.FileName = 'powershell.exe'
      $psi.Arguments = $arg
      $psi.WorkingDirectory = $Root
      $psi.UseShellExecute = $true
      $psi.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
      [void][Diagnostics.Process]::Start($psi)
      Start-Sleep -Seconds 8
      $alive = (Get-ScrapeProcess).Count -gt 0
      Write-KeepLog ("restart scrape_alive={0}" -f $alive)
    }

    if ($alive) {
      $pids = @($scrapes | ForEach-Object { $_.ProcessId }) -join ','
      if ($canvasTick -eq 0) { Write-KeepLog ("scrape healthy pids={0} remaining={1}" -f $pids, $remain.Count) }
    }
    Write-LiveStatus $alive $remain.Count
    $canvasTick++
    if (($canvasTick % 3) -eq 0 -and (Test-Path -LiteralPath $CanvasScript)) {
      try { powershell -NoProfile -ExecutionPolicy Bypass -File $CanvasScript | Out-Null } catch {}
    }
    Start-Sleep -Seconds 45
  }
} finally {
  try { $mutex.ReleaseMutex() } catch {}
  $mutex.Dispose()
  Write-KeepLog 'keepalive exit'
}
