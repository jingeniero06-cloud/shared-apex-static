# Regenerates canvases/fleet-migrate-50.canvas.tsx from the latest migrate run.
# Uses a single-quoted template file so PowerShell never expands JS ${...} / backticks.
$ErrorActionPreference = 'Stop'
$Root = if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { 'C:\Users\My PC\Downloads\shared-apex-static' }
if (-not (Test-Path (Join-Path $Root 'reports'))) {
  $Root = 'C:\Users\My PC\Downloads\shared-apex-static'
}

$CanvasPath = 'C:\Users\My PC\.cursor\projects\c-Users-My-PC-Downloads-shared-apex-static\canvases\fleet-migrate-50.canvas.tsx'
$TemplatePath = Join-Path $PSScriptRoot 'fleet-migrate-50.canvas.template.tsx'
if (-not (Test-Path $TemplatePath)) {
  throw "Missing canvas template: $TemplatePath"
}

$Spike = Import-Csv (Join-Path $Root 'reports\spike-50-sites.csv')
$runDir = Get-ChildItem (Join-Path $Root 'reports') -Directory -Filter 'migrate-*' |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1
if (-not $runDir) { throw 'No migrate-* report folder found' }

$sumPath = Join-Path $runDir.FullName 'migrate-summary.csv'
$sum = if (Test-Path $sumPath) { @(Import-Csv $sumPath) } else { @() }
$byDomain = @{}
foreach ($r in $sum) { $byDomain[$r.Domain] = $r }

$termDir = 'C:\Users\My PC\.cursor\projects\c-Users-My-PC-Downloads-shared-apex-static\terminals'
$log = ''
$term = Get-ChildItem $termDir -Filter '*.txt' -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending |
  Where-Object {
    $h = Get-Content $_.FullName -TotalCount 8 -ErrorAction SilentlyContinue | Out-String
    $h -match 'Invoke-MigrateSitesToFleet' -and $h -match 'status: running'
  } |
  Select-Object -First 1
if ($term) { $log = Get-Content $term.FullName -Raw -ErrorAction SilentlyContinue }

$currentIdx = 0
$currentDomain = ''
if ($log) {
  $m = [regex]::Matches($log, '======== \[(\d+)/50\] ([^\s=]+)')
  if ($m.Count) {
    $currentIdx = [int]$m[$m.Count - 1].Groups[1].Value
    $currentDomain = $m[$m.Count - 1].Groups[2].Value
  }
}

$rows = foreach ($s in $Spike) {
  $r = $byDomain[$s.Domain]
  $status = if ($r -and $r.After -match '200/kv/fleet=') { 'ok' }
    elseif ($currentDomain -and $s.Domain -eq $currentDomain) { 'active' }
    elseif ($r -and $r.Error) { 'error' }
    elseif ($r) { 'partial' }
    else { 'pending' }
  [ordered]@{
    Domain   = $s.Domain
    Batch    = $s.Batch
    SiteName = $s.'Site Name'
    Status   = $status
    KvCopied = if ($r) { [string]$r.KvCopied } else { '' }
    After    = if ($r) { [string]$r.After } else { '' }
    Asset    = if ($r) { [string]$r.Asset } else { '' }
    Warm     = if ($r) { [string]$r.Warm } else { '' }
    Error    = if ($r) { [string]$r.Error } else { '' }
  }
}

$ok = @($rows | Where-Object { $_.Status -eq 'ok' }).Count
$fail = @($rows | Where-Object { $_.Status -eq 'error' }).Count
$worker = 'fleet-static-worker'
$kv = 'HTML_FLEET'
$r2 = 'fleet-static-assets'
$infraPath = Join-Path $Root 'reports\fleet-infra.json'
if (Test-Path $infraPath) {
  $infra = Get-Content $infraPath -Raw | ConvertFrom-Json
  if ($infra.workerName) { $worker = [string]$infra.workerName }
  if ($infra.kvTitle) { $kv = [string]$infra.kvTitle }
  if ($infra.r2Bucket) { $r2 = [string]$infra.r2Bucket }
}

$updatedAt = (Get-Date).ToString('o')
$snapObj = [ordered]@{
  updatedAt     = $updatedAt
  runStamp      = $runDir.Name
  currentIdx    = $currentIdx
  currentDomain = $currentDomain
  total         = 50
  ok            = $ok
  fail          = $fail
  done          = $sum.Count
  worker        = $worker
  kv            = $kv
  r2            = $r2
  sites         = @($rows)
}
($snapObj | ConvertTo-Json -Depth 6 -Compress) |
  Set-Content (Join-Path $Root 'reports\migrate-live-snapshot.json') -Encoding utf8

function JsonStr([string]$s) { return ($s | ConvertTo-Json -Compress) }

$sitesJson = ($rows | ConvertTo-Json -Depth 5 -Compress)
$template = [System.IO.File]::ReadAllText($TemplatePath)
$tsx = $template.
  Replace('__UPDATED_AT__', (JsonStr $updatedAt)).
  Replace('__RUN_STAMP__', (JsonStr $runDir.Name)).
  Replace('__CURRENT_IDX__', [string]$currentIdx).
  Replace('__CURRENT_DOMAIN__', (JsonStr $currentDomain)).
  Replace('__TOTAL__', '50').
  Replace('__OK__', [string]$ok).
  Replace('__FAIL__', [string]$fail).
  Replace('__DONE__', [string]$sum.Count).
  Replace('__WORKER__', (JsonStr $worker)).
  Replace('__KV__', (JsonStr $kv)).
  Replace('__R2__', (JsonStr $r2)).
  Replace('__SITES_JSON__', $sitesJson)

[System.IO.File]::WriteAllText($CanvasPath, $tsx, [System.Text.UTF8Encoding]::new($false))
Write-Output "CANVAS_UPDATED ok=$ok fail=$fail current=$currentIdx/50 domain=$currentDomain run=$($runDir.Name)"
