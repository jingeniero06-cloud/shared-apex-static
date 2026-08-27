#Requires -Version 5.1
<#
.SYNOPSIS
  Create shared KV + R2 and deploy a fleet Worker (same HTML_FLEET + fleet-static-assets).
.NOTES
  Default Worker is fleet-static-worker. Pass -WorkerName to deploy another script
  (e.g. fleet-static-worker-server-1) without moving live routes or overwriting fleet-infra.json.
#>
param(
  [string] $EnvFile,
  [string] $WorkerName,
  [string] $StateFile,
  [switch] $SkipWranglerUpdate,
  [switch] $Force
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $EnvFile) { $EnvFile = Join-Path $Root '.env' }

$vars = @{}
Get-Content $EnvFile -Encoding UTF8 | ForEach-Object {
  $l = $_.Trim(); if (-not $l -or $l.StartsWith('#')) { return }
  $i = $l.IndexOf('='); if ($i -ge 1) { $vars[$l.Substring(0, $i).Trim()] = $l.Substring($i + 1).Trim().Trim('"') }
}

$AccountId = $vars['CLOUDFLARE_ACCOUNT_ID']
$Token = $vars['CLOUDFLARE_API_TOKEN']
$DefaultWorker = 'fleet-static-worker'
if (-not $WorkerName) {
  $WorkerName = if ($vars['FLEET_WORKER_NAME']) { $vars['FLEET_WORKER_NAME'] } else { $DefaultWorker }
}
$KvTitle = if ($vars['FLEET_KV_TITLE']) { $vars['FLEET_KV_TITLE'] } else { 'HTML_FLEET' }
$R2Name = if ($vars['FLEET_R2_BUCKET']) { $vars['FLEET_R2_BUCKET'] } else { 'fleet-static-assets' }
$HostingIp = if ($vars['HOSTING_IP']) { $vars['HOSTING_IP'] } else { '174.136.29.214' }

if (-not $AccountId -or -not $Token) { throw 'Missing CLOUDFLARE_ACCOUNT_ID / CLOUDFLARE_API_TOKEN in .env' }

$headers = @{ Authorization = "Bearer $Token"; 'Content-Type' = 'application/json' }

function Invoke-Cf([string]$Method, [string]$Uri, $Body = $null, [string]$ContentType = 'application/json') {
  $p = @{ Uri = $Uri; Method = $Method; Headers = @{ Authorization = "Bearer $Token" }; TimeoutSec = 120 }
  if ($null -ne $Body) {
    if ($ContentType -eq 'application/json') {
      $p.Headers['Content-Type'] = 'application/json'
      $p.Body = if ($Body -is [string]) { $Body } else { ($Body | ConvertTo-Json -Depth 20 -Compress) }
    } else {
      $p.Headers['Content-Type'] = $ContentType
      $p.Body = $Body
    }
  }
  return Invoke-RestMethod @p
}

Write-Host "==> Ensure KV namespace $KvTitle" -ForegroundColor Cyan
$kvId = $null
$page = 1
do {
  $list = Invoke-Cf GET "https://api.cloudflare.com/client/v4/accounts/$AccountId/storage/kv/namespaces?per_page=100&page=$page"
  foreach ($ns in @($list.result)) {
    if ([string]$ns.title -eq $KvTitle) { $kvId = $ns.id; break }
  }
  if ($kvId) { break }
  $totalPages = 1
  if ($list.result_info -and $list.result_info.total_pages) { $totalPages = [int]$list.result_info.total_pages }
  $page++
} while ($page -le $totalPages)

if (-not $kvId) {
  $created = Invoke-Cf POST "https://api.cloudflare.com/client/v4/accounts/$AccountId/storage/kv/namespaces" @{ title = $KvTitle }
  $kvId = $created.result.id
  Write-Host "Created KV $KvTitle id=$kvId" -ForegroundColor Green
} else {
  Write-Host "Reusing KV $KvTitle id=$kvId" -ForegroundColor Green
}

Write-Host "==> Ensure R2 bucket $R2Name" -ForegroundColor Cyan
try {
  Invoke-Cf GET "https://api.cloudflare.com/client/v4/accounts/$AccountId/r2/buckets/$R2Name" | Out-Null
  Write-Host "Reusing R2 $R2Name" -ForegroundColor Green
} catch {
  Invoke-Cf POST "https://api.cloudflare.com/client/v4/accounts/$AccountId/r2/buckets" @{ name = $R2Name } | Out-Null
  Write-Host "Created R2 $R2Name" -ForegroundColor Green
}

$workerPath = Join-Path $Root 'src\worker.js'
$code = [System.IO.File]::ReadAllText($workerPath)
$metadata = @{
  main_module = 'worker.js'
  compatibility_date = '2024-11-11'
  compatibility_flags = @('nodejs_compat')
  bindings = @(
    @{ type = 'kv_namespace'; name = 'HTML_KV'; namespace_id = $kvId },
    @{ type = 'r2_bucket'; name = 'ASSETS_BUCKET'; bucket_name = $R2Name },
    @{ type = 'plain_text'; name = 'ORIGIN_PROTOCOL'; text = 'https' },
    @{ type = 'plain_text'; name = 'HOSTING_IP'; text = $HostingIp }
  )
} | ConvertTo-Json -Depth 10 -Compress

$boundary = '----FleetBoundary' + [guid]::NewGuid().ToString('N')
$nl = "`r`n"
$body = "--$boundary$nl" +
  "Content-Disposition: form-data; name=`"metadata`"$nl" +
  "Content-Type: application/json$nl$nl" +
  "$metadata$nl" +
  "--$boundary$nl" +
  "Content-Disposition: form-data; name=`"worker.js`"; filename=`"worker.js`"$nl" +
  "Content-Type: application/javascript+module$nl$nl" +
  "$code$nl" +
  "--$boundary--$nl"

Write-Host "==> Deploy Worker $WorkerName" -ForegroundColor Cyan
$uri = "https://api.cloudflare.com/client/v4/accounts/$AccountId/workers/scripts/$WorkerName"
$resp = Invoke-RestMethod -Method PUT -Uri $uri -Headers @{ Authorization = "Bearer $Token" } -ContentType "multipart/form-data; boundary=$boundary" -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 180
if (-not $resp.success) { throw ($resp.errors | ConvertTo-Json -Compress) }
Write-Host "Deployed $WorkerName" -ForegroundColor Green

if (-not $SkipWranglerUpdate -and $WorkerName -eq $DefaultWorker) {
  $wrangler = Join-Path $Root 'wrangler.jsonc'
  $txt = Get-Content $wrangler -Raw
  $txt = $txt -replace '"id":\s*"[^"]*"', "`"id`": `"$kvId`""
  Set-Content -LiteralPath $wrangler -Value $txt -Encoding UTF8
}

$state = [ordered]@{
  timestamp = (Get-Date).ToString('o')
  workerName = $WorkerName
  kvNamespaceId = $kvId
  kvTitle = $KvTitle
  r2Bucket = $R2Name
  hostingIp = $HostingIp
  sharesStorageWith = $DefaultWorker
  routesAttached = $false
}
if (-not $StateFile) {
  if ($WorkerName -eq $DefaultWorker) {
    $StateFile = Join-Path $Root 'reports\fleet-infra.json'
  } else {
    $StateFile = Join-Path $Root ("reports\fleet-infra-{0}.json" -f $WorkerName)
  }
} elseif (-not [IO.Path]::IsPathRooted($StateFile)) {
  $StateFile = Join-Path $Root $StateFile
}
New-Item -ItemType Directory -Path (Split-Path $StateFile) -Force | Out-Null
($state | ConvertTo-Json -Depth 5) | Set-Content $StateFile -Encoding UTF8
Write-Host "State: $StateFile" -ForegroundColor Magenta
Write-Host "FLEET_READY worker=$WorkerName kv=$kvId r2=$R2Name (no routes attached)" -ForegroundColor Green
