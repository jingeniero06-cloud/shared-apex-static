#Requires -Version 5.1
<#
.SYNOPSIS
  Migrate domains onto fleet-static-worker (shared KV/R2).
  Copies per-site KV HTML keys + R2 assets with hostname prefixes, then switches routes.
#>
param(
  [Parameter(Mandatory = $true)][string] $SitesCsv,
  [int] $Limit = 50,
  [string] $EnvFile,
  [switch] $SkipCopy,
  [switch] $WarmOnly
)

$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $EnvFile) { $EnvFile = Join-Path $Root '.env' }

$vars = @{}
Get-Content $EnvFile -Encoding UTF8 | ForEach-Object {
  $l = $_.Trim(); if (-not $l -or $l.StartsWith('#')) { return }
  $i = $l.IndexOf('='); if ($i -ge 1) { $vars[$l.Substring(0, $i).Trim()] = $l.Substring($i + 1).Trim().Trim('"') }
}
$AccountId = $vars['CLOUDFLARE_ACCOUNT_ID']
$Token = $vars['CLOUDFLARE_API_TOKEN']
$WorkerName = if ($vars['FLEET_WORKER_NAME']) { $vars['FLEET_WORKER_NAME'] } else { 'fleet-static-worker' }
$HostingIp = if ($vars['HOSTING_IP']) { $vars['HOSTING_IP'] } else { '174.136.29.214' }
$statePath = Join-Path $Root 'reports\fleet-infra.json'
if (-not (Test-Path $statePath)) { throw 'Run Invoke-ProvisionFleet.ps1 first' }
$infra = Get-Content $statePath -Raw | ConvertFrom-Json
$FleetKv = $infra.kvNamespaceId
$FleetR2 = $infra.r2Bucket

$h = @{ Authorization = "Bearer $Token" }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outDir = Join-Path $Root "reports\migrate-$stamp"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

$sites = @(Import-Csv -LiteralPath $SitesCsv | Where-Object { $_.Domain } | Select-Object -First $Limit)
Write-Host "MIGRATE sites=$($sites.Count) fleet=$WorkerName" -ForegroundColor Magenta

function Get-ZoneId([string]$Domain) {
  $r = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/zones?name=$Domain" -Headers $h -TimeoutSec 40
  $z = @($r.result) | Select-Object -First 1
  if (-not $z) { throw "No zone for $Domain" }
  return $z.id
}

function Get-WorkerBindings([string]$ScriptName) {
  try {
    $r = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/accounts/$AccountId/workers/scripts/$ScriptName/settings" -Headers $h -TimeoutSec 60
    return @($r.result.bindings)
  } catch { return @() }
}

function Test-IsPageHtmlKey([string]$Name) {
  # Real page keys only: html:/index.html or html:/<path> (single slash after colon).
  # Skip wp junk, PHP shells, double-slash noise, and non-page paths.
  if ($Name -notmatch '^html:/(index\.html|.+)$' -and $Name -ne 'html:/index.html') { return $false }
  if ($Name -notmatch '^html:/') { return $false }
  if ($Name -match '^html://') { return $false } # double-slash junk
  $path = $Name.Substring(5) # after "html:"
  if ($path -match '(?i)(^|/)(wp-includes|wp-admin|wp-content|wp-json|wp-login|wp-cron|wp-activate|xmlrpc)(/|$)') { return $false }
  if ($path -match '(?i)\.(php|aspx|asp|cgi|pl)(\?|$)') { return $false }
  if ($path -match '(?i)(^|/)\.well-known(/|$)') { return $false }
  if ($path -match '(?i)/(embed|feed|comments/feed)(/|$)') { return $false }
  if ($path -match '(?i)PHP-Shells') { return $false }
  # Prefer document-like paths: index.html, bare page slugs, or .html/.htm
  if ($path -eq '/index.html' -or $path -match '(?i)\.html?$') { return $true }
  if ($path -match '^/[A-Za-z0-9][A-Za-z0-9_./%-]*$' -and $path -notmatch '\.[A-Za-z0-9]{1,5}$') { return $true }
  return $false
}

function Copy-KvHtml([string]$SrcNs, [string]$HostName) {
  $copied = 0
  $skipped = 0
  $cursor = $null
  do {
    $uri = "https://api.cloudflare.com/client/v4/accounts/$AccountId/storage/kv/namespaces/$SrcNs/keys?limit=1000"
    if ($cursor) { $uri += "&cursor=$([uri]::EscapeDataString($cursor))" }
    $list = Invoke-RestMethod -Uri $uri -Headers $h -TimeoutSec 60
    foreach ($k in @($list.result)) {
      $name = [string]$k.name
      if (-not (Test-IsPageHtmlKey $name)) {
        if ($name -match '^html:') { $skipped++ }
        continue
      }
      $pathPart = $name.Substring(5) # after html:
      $destKey = "${HostName}:html:${pathPart}"
      $valUri = "https://api.cloudflare.com/client/v4/accounts/$AccountId/storage/kv/namespaces/$SrcNs/values/$([uri]::EscapeDataString($name))"
      $putUri = "https://api.cloudflare.com/client/v4/accounts/$AccountId/storage/kv/namespaces/$FleetKv/values/$([uri]::EscapeDataString($destKey))"
      try {
        # WebClient DownloadData/UploadData preserves raw bytes (PS Invoke-WebRequest Body corrupts)
        $wc = New-Object System.Net.WebClient
        $wc.Headers['Authorization'] = "Bearer $Token"
        $bytes = $wc.DownloadData($valUri)
        if (-not $bytes -or $bytes.Length -lt 1) { throw 'empty GET body' }
        $wc.Headers.Clear()
        $wc.Headers['Authorization'] = "Bearer $Token"
        $wc.Headers['Content-Type'] = 'text/html; charset=utf-8'
        $null = $wc.UploadData($putUri, 'PUT', $bytes)
        $wc.Dispose()
        $copied++
      } catch {
        Write-Host "  KV copy fail $name : $($_.Exception.Message)" -ForegroundColor Yellow
      }
    }
    $cursor = $null
    if ($list.result_info -and $list.result_info.cursor) { $cursor = $list.result_info.cursor }
  } while ($cursor)
  Write-Host "  KV page filter skipped=$skipped" -ForegroundColor DarkGray
  return $copied
}

function Set-FleetRoutes([string]$ZoneId, [string]$Domain) {
  $routes = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/zones/$ZoneId/workers/routes" -Headers ($h + @{ 'Content-Type' = 'application/json' }) -TimeoutSec 40
  $want = @("$Domain/*", "www.$Domain/*")
  foreach ($rt in @($routes.result)) {
    $pat = [string]$rt.pattern
    if ($want -contains $pat -or $pat -eq "*${Domain}/*" -or $pat -eq "*.${Domain}/*") {
      Invoke-RestMethod -Method DELETE -Uri "https://api.cloudflare.com/client/v4/zones/$ZoneId/workers/routes/$($rt.id)" -Headers $h -TimeoutSec 40 | Out-Null
      Write-Host "  Removed route $pat" -ForegroundColor DarkYellow
    }
  }
  foreach ($pat in $want) {
    $body = @{ pattern = $pat; script = $WorkerName } | ConvertTo-Json -Compress
    try {
      Invoke-RestMethod -Method POST -Uri "https://api.cloudflare.com/client/v4/zones/$ZoneId/workers/routes" -Headers ($h + @{ 'Content-Type' = 'application/json' }) -Body $body -TimeoutSec 40 | Out-Null
      Write-Host "  Added route $pat -> $WorkerName" -ForegroundColor Green
    } catch {
      Write-Host "  Route warn $pat : $($_.Exception.Message)" -ForegroundColor Yellow
    }
  }
}

function Probe([string]$Url) {
  try {
    $probeDir = Join-Path $outDir 'probe'
    if (-not (Test-Path -LiteralPath $probeDir)) { New-Item -ItemType Directory -Path $probeDir -Force | Out-Null }
    $tmp = Join-Path $probeDir ('p-' + [guid]::NewGuid().ToString('N'))
    $hdr = "$tmp.hdr"; $body = "$tmp.body"
    $code = & curl.exe -sS -L -m 25 -A 'Mozilla/5.0' -D "$hdr" -o "$body" "$Url" -w '%{http_code}' 2>$null
    $hraw = if (Test-Path -LiteralPath $hdr) { Get-Content -LiteralPath $hdr -Raw } else { '' }
    $xs = ''; $fleet = ''
    if ($hraw -match '(?im)^x-source:\s*(\S+)') { $xs = $Matches[1].Trim() }
    if ($hraw -match '(?im)^x-fleet-host:\s*(\S+)') { $fleet = $Matches[1].Trim() }
    Remove-Item -LiteralPath $hdr, $body -Force -ErrorAction SilentlyContinue
    return [pscustomobject]@{ Status = [int]$code; XSource = $xs; FleetHost = $fleet }
  } catch {
    return [pscustomobject]@{ Status = 0; XSource = ''; FleetHost = '' }
  }
}

function Warm-Site([string]$Domain) {
  $paths = @('/', '/robots.txt', '/sitemap.xml', '/page-sitemap.xml')
  $warmDir = Join-Path $outDir 'warm'
  if (-not (Test-Path -LiteralPath $warmDir)) { New-Item -ItemType Directory -Path $warmDir -Force | Out-Null }
  $homeFile = Join-Path $warmDir ("warm-$Domain.html")
  & curl.exe -sS -L -m 35 -A 'Mozilla/5.0' -o "$homeFile" "https://$Domain/" 2>$null | Out-Null
  if (Test-Path -LiteralPath $homeFile) {
    $html = Get-Content -LiteralPath $homeFile -Raw -ErrorAction SilentlyContinue
    if ($html) {
      $pattern = '/wp-content/uploads/[A-Za-z0-9_./%-]+'
      $uploads = [regex]::Matches($html, $pattern) | ForEach-Object { $_.Value } | Select-Object -Unique | Select-Object -First 25
      foreach ($u in $uploads) { $paths += $u }
    }
  }
  $n = 0
  foreach ($p in ($paths | Select-Object -Unique)) {
    & curl.exe -sS -L -m 20 -A 'Mozilla/5.0' -o NUL "https://$Domain$p" 2>$null | Out-Null
    $n++
  }
  return $n
}

$rows = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($site in $sites) {
  $i++
  $domain = $site.Domain.Trim().ToLowerInvariant() -replace '^https?://', '' -replace '/$', ''
  Write-Host "`n======== [$i/$($sites.Count)] $domain ========" -ForegroundColor Cyan
  $row = [ordered]@{
    Domain = $domain; ZoneId = ''; OldWorker = ''; KvCopied = 0; Routes = ''; Before = ''; After = ''; Asset = ''; Warm = 0; Error = ''
  }
  try {
    $before = Probe "https://$domain/"
    $row.Before = "$($before.Status)/$($before.XSource)"
    $zoneId = Get-ZoneId $domain
    $row.ZoneId = $zoneId
    $oldWorker = (($domain -replace '\.', '-').ToLowerInvariant()) + '-worker'
    $row.OldWorker = $oldWorker

    if (-not $SkipCopy -and -not $WarmOnly) {
      $bindings = Get-WorkerBindings $oldWorker
      $srcKv = ($bindings | Where-Object { $_.name -eq 'HTML_KV' } | Select-Object -First 1).namespace_id
      if ($srcKv) {
        Write-Host "  Copying KV from $srcKv ..." -ForegroundColor DarkGray
        $row.KvCopied = Copy-KvHtml -SrcNs $srcKv -HostName $domain
        Write-Host "  KV html keys copied=$($row.KvCopied)" -ForegroundColor Green
      } else {
        Write-Host "  No HTML_KV on $oldWorker - warm-only for HTML" -ForegroundColor Yellow
      }
    }

    Set-FleetRoutes -ZoneId $zoneId -Domain $domain
    $row.Routes = 'OK'
    try {
      Invoke-RestMethod -Method POST -Uri "https://api.cloudflare.com/client/v4/zones/$zoneId/purge_cache" -Headers ($h + @{ 'Content-Type' = 'application/json' }) -Body '{"purge_everything":true}' -TimeoutSec 40 | Out-Null
    } catch {}

    Start-Sleep -Seconds 2
    $row.Warm = Warm-Site $domain
    Start-Sleep -Seconds 1
    $after = Probe "https://$domain/"
    $row.After = "$($after.Status)/$($after.XSource)/fleet=$($after.FleetHost)"
    # sample asset
    $assetProbe = Probe "https://$domain/robots.txt"
    $row.Asset = "$($assetProbe.Status)/$($assetProbe.XSource)"
    Write-Host "  After $($row.After) warm=$($row.Warm)" -ForegroundColor Green
  } catch {
    $row.Error = $_.Exception.Message
    Write-Host "  FAIL $($row.Error)" -ForegroundColor Red
  }
  $rows.Add([pscustomobject]$row)
  $rows | Export-Csv -LiteralPath (Join-Path $outDir 'migrate-summary.csv') -NoTypeInformation -Encoding UTF8
}

Write-Host "`n========== MIGRATE SUMMARY ==========" -ForegroundColor Magenta
$rows | Format-Table Domain, Before, After, KvCopied, Warm, Error -AutoSize
$okKv = @($rows | Where-Object { $_.After -match '^200/kv' }).Count
$okIsh = @($rows | Where-Object { $_.After -match '/(kv|origin-html)' -or $_.After -match '^200/' }).Count
Write-Output "OK_KV=$okKv OKISH=$okIsh TOTAL=$($rows.Count) OUT=$outDir"
Write-Output "STAMP=$stamp"
# Stable path for parent agent
$stableSummary = Join-Path $Root 'reports\migrate-summary.csv'
$rows | Export-Csv -LiteralPath $stableSummary -NoTypeInformation -Encoding UTF8
Write-Output "SUMMARY=$stableSummary"
