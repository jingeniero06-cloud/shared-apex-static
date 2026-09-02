#Requires -Version 5.1
<#
.SYNOPSIS
  HTML-only origin scrape + form-validation inject, one Server 2 site at a time.
  Skips the 5 s2 sites already done. Does not change Worker routes.
#>
param(
  [string] $SitesCsv = 'C:\Users\My PC\Downloads\fleet-static-preview\sites\popup-reexport-s2-remain-180.csv',
  [string] $HostingIp = '174.136.29.214',
  [string] $WorkerName = 'fleet-static-worker',
  [int] $MaxPages = 150
)

$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $PSScriptRoot
$Preview = 'C:\Users\My PC\Downloads\fleet-static-preview'
$Scrape = Join-Path $Root 'scripts\Invoke-WpOriginToFleet.ps1'
$Inject = Join-Path $Preview 'scripts\Invoke-InjectFleetFormValidation.ps1'
$LogDir = Join-Path $Root 'reports'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$Status = Join-Path $LogDir 'popup-reexport-status.txt'
$Progress = Join-Path $LogDir 'popup-reexport-s2-remain-progress.csv'
$Live = Join-Path $LogDir 'popup-reexport-live.json'

function Write-Status([string]$Msg) {
  $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Msg
  try { Add-Content -LiteralPath $Status -Value $line -Encoding UTF8 -ErrorAction Stop } catch {}
  Write-Host $line
}

function Write-Live($obj) {
  ($obj | ConvertTo-Json -Compress) | Set-Content -LiteralPath $Live -Encoding UTF8
}

$mutex = New-Object System.Threading.Mutex($false, 'Global\CityThrivePopupReexportS2Remain')
if (-not $mutex.WaitOne(0)) {
  Write-Status 's2 remain loop already running'
  exit 0
}

try {
  if (-not (Test-Path -LiteralPath $SitesCsv)) { throw "missing $SitesCsv" }
  $sites = @(Import-Csv -LiteralPath $SitesCsv | Where-Object { $_.Domain })
  $doneSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  if (Test-Path -LiteralPath $Progress) {
    foreach ($row in @(Import-Csv -LiteralPath $Progress)) {
      if ($row.After -match '200/kv' -and $row.Error -eq '') { [void]$doneSet.Add($row.Domain) }
    }
  } else {
    'Domain,Idx,Pages,After,FvJs,FvTag,ElapsedSec,Error' | Set-Content -LiteralPath $Progress -Encoding UTF8
  }

  $total = $sites.Count
  $already = $doneSet.Count
  Write-Status "s2 remain HTML-only start total=$total alreadyOk=$already ip=$HostingIp"
  $tmpDir = Join-Path $env:TEMP ('popup-s2-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
  $i = 0
  $ok = $already
  $fail = 0
  $started = Get-Date
  foreach ($site in $sites) {
    $i++
    $apex = $site.Domain.Trim().ToLowerInvariant()
    if ($doneSet.Contains($apex)) {
      Write-Status "skip already-ok [$i/$total] $apex"
      continue
    }
    Write-Status "site [$i/$total] $apex"
    Write-Live ([ordered]@{
      asOf        = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
      status      = 'running'
      idx         = $i
      total       = $total
      ok          = $ok
      fail        = $fail
      current     = $apex
      started     = $started.ToString('s')
      elapsedMin  = [math]::Round(((Get-Date) - $started).TotalMinutes, 1)
    })
    $one = Join-Path $tmpDir 'one.csv'
    $site | Export-Csv -LiteralPath $one -NoTypeInformation -Encoding UTF8
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $err = ''
    $pages = ''
    $after = ''
    $fvJs = ''
    $fvTag = ''
    try {
      & $Scrape -SitesCsv $one -HostingIp $HostingIp -MaxPages $MaxPages `
        -WorkerName $WorkerName -SkipRoutes -SkipAssets
      $scrapeExit = $LASTEXITCODE
      $newest = Get-ChildItem (Join-Path $Root 'reports') -Directory -Filter 'wp-to-fleet-*' |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
      $sumPath = if ($newest) { Join-Path $newest.FullName 'summary.csv' } else { $null }
      if ($sumPath -and (Test-Path $sumPath)) {
        $sum = @(Import-Csv $sumPath | Where-Object { $_.Domain -eq $apex }) | Select-Object -First 1
        if ($sum) {
          $pages = $sum.Pages
          $after = $sum.After
          $err = $sum.Error
        }
      }
      if ($scrapeExit -ne 0 -and -not $err) { $err = "scrape-exit=$scrapeExit" }
      if ($err) { throw $err }
      & $Inject -SitesCsv $one
      $fvDir = Get-ChildItem (Join-Path $Preview 'reports') -Directory -Filter 'form-validation-*' |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
      $fvSum = if ($fvDir) { Join-Path $fvDir.FullName 'summary.csv' } else { $null }
      if ($fvSum -and (Test-Path $fvSum)) {
        $fv = @(Import-Csv $fvSum | Where-Object { $_.Domain -eq $apex }) | Select-Object -First 1
        if ($fv) {
          $fvJs = $fv.LiveJs
          $fvTag = $fv.LiveHtml
        }
      }
      $ok++
    } catch {
      $fail++
      if (-not $err) { $err = $_.Exception.Message }
      Write-Status "FAIL $apex $err"
    }
    $sw.Stop()
    $row = [pscustomobject]@{
      Domain     = $apex
      Idx        = $i
      Pages      = $pages
      After      = $after
      FvJs       = $fvJs
      FvTag      = $fvTag
      ElapsedSec = [int]$sw.Elapsed.TotalSeconds
      Error      = $err
    }
    $row | Export-Csv -LiteralPath $Progress -NoTypeInformation -Encoding UTF8 -Append
    Write-Status ("finished {0} after={1} fv={2} {3}s ok={4} fail={5}" -f $apex, $after, $fvJs, [int]$sw.Elapsed.TotalSeconds, $ok, $fail)
  }
  Write-Live ([ordered]@{
    asOf       = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    status     = 'done'
    idx        = $total
    total      = $total
    ok         = $ok
    fail       = $fail
    current    = ''
    started    = $started.ToString('s')
    elapsedMin = [math]::Round(((Get-Date) - $started).TotalMinutes, 1)
  })
  Write-Status "s2 remain HTML-only done ok=$ok fail=$fail total=$total"
  exit $(if ($fail -gt 0) { 1 } else { 0 })
} finally {
  try { $mutex.ReleaseMutex() } catch {}
  $mutex.Dispose()
}
