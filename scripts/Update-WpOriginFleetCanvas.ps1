# Regenerates wp-origin-to-fleet.canvas.tsx from the newest wp-to-fleet-* summary.
$ErrorActionPreference = 'Continue'
$Root = 'C:\Users\My PC\Downloads\shared-apex-static'
$CanvasPath = 'C:\Users\My PC\.cursor\projects\c-Users-My-PC-Downloads-shared-apex-static\canvases\wp-origin-to-fleet.canvas.tsx'
$Canary = @('bedfordtreeservicecompany.com', 'abilenedrivewayrepair.com', 'cocoafoundationrepair.com')
$QueueCsv = Join-Path $Root 'reports\fleet-on-shared-remain-after-canary.csv'
$B4 = 97; $B5 = 95; $B6 = 64
$TotalStatic = 467
$OnFleet = 211
$RefreshQueue = 208
$CanaryDone = 3

$dirs = @(Get-ChildItem -LiteralPath (Join-Path $Root 'reports') -Directory -Filter 'wp-to-fleet-20*' |
  Sort-Object LastWriteTime -Descending)
$dir = $dirs | Select-Object -First 1
$stamp = if ($dir) { $dir.Name -replace '^wp-to-fleet-', '' } else { '' }
$byDomain = @{}
foreach ($d in ($dirs | Sort-Object LastWriteTime)) {
  $csvPath = Join-Path $d.FullName 'summary.csv'
  if (-not (Test-Path $csvPath)) { continue }
  foreach ($r in @(Import-Csv -LiteralPath $csvPath | Where-Object { $_.Domain })) {
    $dom = $r.Domain.Trim().ToLower()
    if ($Canary -contains $dom) { continue }
    $byDomain[$dom] = $r
  }
}
$rows = @($byDomain.Values)

$proc = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -match 'fleet-on-shared-remain-after-canary|Invoke-WpOriginToFleet' } |
  Select-Object -First 1
$running = $null -ne $proc

$finished = $rows.Count
$hardFail = @($rows | Where-Object { $_.Error -and $_.Error -notmatch 'MYPC~1' -and $_.After -notmatch '200/kv' }).Count
$okAfter = @($rows | Where-Object { $_.After -match '200/kv' }).Count

$queue = @()
if (Test-Path $QueueCsv) {
  $queue = @(Import-Csv -LiteralPath $QueueCsv | ForEach-Object { $_.Domain.Trim().ToLower() })
}
$currentDomain = ''
$currentIdx = $finished
$currentPages = 0
if ($running) {
  $currentIdx = [Math]::Min($finished + 1, $RefreshQueue)
  if ($finished -lt $queue.Count) { $currentDomain = $queue[$finished] }
  elseif ($dir) {
    $siteDir = Get-ChildItem $dir.FullName -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($siteDir) { $currentDomain = $siteDir.Name }
  }
  if ($dir -and $currentDomain) {
    $pdir = Join-Path $dir.FullName $currentDomain
    if (Test-Path $pdir) {
      $currentPages = @(Get-ChildItem $pdir -Filter 'page-*.html' -ErrorAction SilentlyContinue).Count
    }
  }
}

$elapsedMin = 0.0
if ($proc) {
  try { $elapsedMin = [math]::Round(((Get-Date) - (Get-Process -Id $proc.ProcessId).StartTime).TotalMinutes, 1) } catch {}
}
if ($elapsedMin -eq 0 -and $stamp -match '^\d{8}-\d{6}$') {
  try {
    $started = [datetime]::ParseExact($stamp, 'yyyyMMdd-HHmmss', $null)
    $elapsedMin = [math]::Round(((Get-Date) - $started).TotalMinutes, 1)
  } catch {}
}
$etaMin = $null
if ($running -and $finished -ge 2 -and $elapsedMin -gt 0) {
  $rate = $finished / $elapsedMin
  $left = $RefreshQueue - $finished
  if ($rate -gt 0 -and $left -gt 0) { $etaMin = [math]::Round($left / $rate, 1) }
}

$inProgress = if ($running -and $currentDomain) { 1 } else { 0 }
$queuedRefresh = [Math]::Max(0, $RefreshQueue - $finished - $inProgress)
$wpSynced = $CanaryDone + $finished
$runStatus = if ($running) { 'running' } elseif ($finished -ge $RefreshQueue) { 'succeeded' } else { 'idle' }

$recent = @()
$idx = 0
foreach ($r in @($rows | Select-Object -Last 12)) {
  $idx++
  $recent += [ordered]@{
    Domain = [string]$r.Domain
    Pages = [string]$r.Pages
    Assets = [string]$r.Assets
    AssetFail = [string]$r.AssetFail
    After = [string]$r.After
  }
}

$snap = [ordered]@{
  updatedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz')
  runStamp = $stamp
  runStatus = $runStatus
  totalStatic = $TotalStatic
  onFleet = $OnFleet
  canaryDone = $CanaryDone
  refreshQueue = $RefreshQueue
  refreshFinished = $finished
  refreshFail = $hardFail
  refreshOk = $okAfter
  inProgress = $inProgress
  queuedRefresh = $queuedRefresh
  currentIdx = $currentIdx
  currentDomain = $currentDomain
  currentPages = $currentPages
  elapsedMin = $elapsedMin
  etaMin = $etaMin
  b4 = $B4; b5 = $B5; b6 = $B6
  wpSynced = $wpSynced
  recent = $recent
}
$json = ($snap | ConvertTo-Json -Depth 6 -Compress)
if (-not (Test-Path -LiteralPath $CanvasPath)) {
  Write-Output 'CANVAS_SKIP missing canvas file'
  exit 1
}
$tsx = [IO.File]::ReadAllText($CanvasPath)
if ($tsx.Length -lt 200) {
  Write-Output 'CANVAS_SKIP canvas file too short; not overwriting'
  exit 1
}
$patched = [regex]::Replace($tsx, 'const SNAPSHOT: Snapshot = \{.*?\};', ('const SNAPSHOT: Snapshot = ' + $json + ';'), 1)
if ($patched.Length -lt 200 -or $patched -notmatch 'export default') {
  Write-Output 'CANVAS_SKIP patch failed'
  exit 1
}
$utf8 = New-Object System.Text.UTF8Encoding $false
[IO.File]::WriteAllText($CanvasPath, $patched, $utf8)
Write-Output ("CANVAS_OK done={0}/208 current={1} status={2}" -f $finished, $currentDomain, $runStatus)
