#Requires -Version 5.1
<#
.SYNOPSIS
  Scrape live WordPress (via hosting IP) into fleet KV/R2, then point routes at fleet-static-worker.
  Use when the site has no per-site Worker (SkipProvision / migrate-from-KV cannot run).
#>
param(
  [Parameter(Mandatory = $true)][string] $SitesCsv,
  [int] $MaxPages = 150,
  [string] $EnvFile,
  [string] $HostingIp = '174.136.29.214'
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
if ($vars['HOSTING_IP']) { $HostingIp = $vars['HOSTING_IP'] }
$infra = Get-Content (Join-Path $Root 'reports\fleet-infra.json') -Raw | ConvertFrom-Json
$FleetKv = $infra.kvNamespaceId
$FleetR2 = $infra.r2Bucket
$h = @{ Authorization = "Bearer $Token" }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outDir = Join-Path $Root "reports\wp-to-fleet-$stamp"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$sites = @(Import-Csv -LiteralPath $SitesCsv | Where-Object { $_.Domain })
Write-Host "WP→FLEET sites=$($sites.Count) worker=$WorkerName kv=$FleetKv r2=$FleetR2" -ForegroundColor Magenta

function Get-ContentType([string]$Path) {
  switch -Regex ($Path.ToLowerInvariant()) {
    '\.png$'   { return 'image/png' }
    '\.jpe?g$' { return 'image/jpeg' }
    '\.webp$'  { return 'image/webp' }
    '\.gif$'   { return 'image/gif' }
    '\.svg$'   { return 'image/svg+xml' }
    '\.avif$'  { return 'image/avif' }
    '\.ico$'   { return 'image/x-icon' }
    '\.css$'   { return 'text/css; charset=utf-8' }
    '\.js$'    { return 'application/javascript; charset=utf-8' }
    '\.woff2$' { return 'font/woff2' }
    '\.woff$'  { return 'font/woff' }
    '\.ttf$'   { return 'font/ttf' }
    '\.eot$'   { return 'application/vnd.ms-fontobject' }
    '\.otf$'   { return 'font/otf' }
    '\.xml$'   { return 'application/xml; charset=utf-8' }
    '\.xsl$'   { return 'application/xml; charset=utf-8' }
    '\.txt$'   { return 'text/plain; charset=utf-8' }
    '\.pdf$'   { return 'application/pdf' }
    default    { return 'application/octet-stream' }
  }
}

function Normalize-PagePath([string]$path) {
  if ([string]::IsNullOrWhiteSpace($path)) { return $null }
  try { if ($path -match '^https?://') { $path = ([uri]$path).AbsolutePath } } catch { return $null }
  $path = $path.Split('?')[0].Split('#')[0]
  if (-not $path.StartsWith('/')) { $path = '/' + $path }
  if ($path -ne '/' -and $path.EndsWith('/')) { $path = $path.TrimEnd('/') }
  if ($path -eq '') { $path = '/' }
  return $path
}

function Test-SkipPage([string]$path) {
  $p = $path.ToLowerInvariant()
  if ($p -match '\.(kml|xml|xsl|css|js|map|woff2?|ttf|eot|png|jpe?g|webp|gif|svg|avif|ico|pdf|zip|mp4)(\?|$)') { return $true }
  if ($p -match '/wp-admin|/wp-login|/feed|/wp-json|/xmlrpc|/cdn-cgi/') { return $true }
  if ($p -match '^/wp-(content|includes|admin)/') { return $true }
  return $false
}

function Get-FleetHtmlKey([string]$HostName, [string]$PagePath) {
  $np = if ($PagePath -eq '/') { '/index.html' } else { $PagePath }
  return "${HostName}:html:${np}"
}

function Get-CurlOrigin([string]$Domain, [string]$PathOrUrl, [string]$OutFile, [int]$MaxTime = 60) {
  $url = if ($PathOrUrl -match '^https?://') { $PathOrUrl } else { "https://${Domain}$PathOrUrl" }
  & curl.exe -skL --resolve "${Domain}:443:${HostingIp}" --resolve "www.${Domain}:443:${HostingIp}" `
    $url -A 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0' `
    --max-time $MaxTime -o $OutFile 2>$null | Out-Null
}

function Extract-InternalLinks([string]$html, [string]$Domain) {
  $links = New-Object System.Collections.Generic.List[string]
  if ([string]::IsNullOrEmpty($html)) { return @() }
  $domEsc = [regex]::Escape($Domain)
  foreach ($m in [regex]::Matches($html, 'href=["'']([^"'']+)["'']', 'IgnoreCase')) {
    $href = $m.Groups[1].Value.Trim()
    if ($href -match '^(mailto:|tel:|javascript:|#)') { continue }
    $path = $null
    if ($href -match "^https?://(?:www\.)?$domEsc(/.*)?$") {
      $path = if ($Matches[1]) { $Matches[1] } else { '/' }
    } elseif ($href.StartsWith('/') -and -not $href.StartsWith('//')) {
      $path = $href
    }
    $np = Normalize-PagePath $path
    if ($np -and -not (Test-SkipPage $np)) { $links.Add($np) }
  }
  return @($links)
}

function Extract-AssetPaths([string]$html) {
  $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  if ([string]::IsNullOrEmpty($html)) { return @() }
  foreach ($m in [regex]::Matches($html, '(?:src|href|content|srcset)=["'']([^"'']+)["'']', 'IgnoreCase')) {
    foreach ($part in @($m.Groups[1].Value -split '[\s,]+')) {
      $u = $part.Trim()
      try { if ($u -match '^https?://') { $u = ([uri]$u).AbsolutePath } } catch { continue }
      $u = $u.Split('?')[0].Split('#')[0]
      if ($u -match '^/wp-(content|includes)/' -and $u -match '\.(png|jpe?g|webp|gif|svg|avif|ico|css|js|mjs|woff2?|ttf|eot|otf)$') {
        [void]$seen.Add($u)
      }
    }
  }
  foreach ($m in [regex]::Matches($html, 'url\(([^)]+)\)', 'IgnoreCase')) {
    $u = $m.Groups[1].Value.Trim().Trim('"').Trim("'").Split('?')[0].Split('#')[0]
    try { if ($u -match '^https?://') { $u = ([uri]$u).AbsolutePath } } catch { continue }
    if ($u -match '^/wp-(content|includes)/' -and $u -match '\.(png|jpe?g|webp|gif|svg|avif|ico|css|js|mjs|woff2?|ttf|eot|otf)$') {
      [void]$seen.Add($u)
    }
  }
  $rx2 = '/wp-content/uploads/[0-9]{4}/[0-9]{2}/[A-Za-z0-9_\-\.%]+\.(?:png|jpe?g|webp|gif|svg|avif|ico)'
  foreach ($m in [regex]::Matches($html, $rx2, 'IgnoreCase')) { [void]$seen.Add($m.Value) }
  return @($seen)
}

function Extract-CssUrlPaths([string]$Css, [string]$CssPath) {
  $found = New-Object System.Collections.Generic.List[string]
  if ([string]::IsNullOrEmpty($Css) -or [string]::IsNullOrEmpty($CssPath)) { return @() }
  $slash = $CssPath.LastIndexOf('/')
  $cssDir = if ($slash -gt 0) { $CssPath.Substring(0, $slash) } else { '/' }
  foreach ($m in [regex]::Matches($Css, 'url\(([^)]+)\)', 'IgnoreCase')) {
    $raw = $m.Groups[1].Value.Trim().Trim('"').Trim("'")
    if ($raw -match '^(data:|#)') { continue }
    $raw = $raw.Split('?')[0].Split('#')[0]
    $path = $raw
    if ($raw -notmatch '^https?://' -and -not $raw.StartsWith('/')) {
      try { $path = [uri]::new([uri]("https://local.invalid$cssDir/"), $raw).AbsolutePath } catch { continue }
    } elseif ($raw -match '^https?://') {
      try { $path = ([uri]$raw).AbsolutePath } catch { continue }
    }
    if ($path -match '^/wp-(content|includes)/' -and $path -match '\.(png|jpe?g|webp|gif|svg|avif|ico|css|js|mjs|woff2?|ttf|eot|otf)$') {
      $found.Add($path)
    }
  }
  return @($found)
}

function Put-FleetKv([string]$Key, [byte[]]$Bytes) {
  $putUri = "https://api.cloudflare.com/client/v4/accounts/$AccountId/storage/kv/namespaces/$FleetKv/values/$([uri]::EscapeDataString($Key))"
  $wc = New-Object System.Net.WebClient
  $wc.Headers['Authorization'] = "Bearer $Token"
  $wc.Headers['Content-Type'] = 'text/html; charset=utf-8'
  $null = $wc.UploadData($putUri, 'PUT', $Bytes)
  $wc.Dispose()
}

function Put-FleetR2([string]$ObjectKey, [byte[]]$Bytes, [string]$ContentType, [string]$TmpDir) {
  if ($ObjectKey -match '(?i)\.svg$') { $ContentType = 'image/svg+xml' }
  $tmp = Join-Path $TmpDir ('r2-' + [guid]::NewGuid().ToString('N'))
  [IO.File]::WriteAllBytes($tmp, $Bytes)
  try {
    $uri = "https://api.cloudflare.com/client/v4/accounts/$AccountId/r2/buckets/$FleetR2/objects/$([uri]::EscapeDataString($ObjectKey))"
    Invoke-RestMethod -Method PUT -Uri $uri -Headers @{ Authorization = "Bearer $Token"; 'Content-Type' = $ContentType } `
      -InFile $tmp -TimeoutSec 180 | Out-Null
  } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
}

function Set-FleetRoutes([string]$ZoneId, [string]$Domain) {
  $routes = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/zones/$ZoneId/workers/routes" -Headers ($h + @{ 'Content-Type' = 'application/json' }) -TimeoutSec 40
  $want = @("$Domain/*", "www.$Domain/*")
  foreach ($rt in @($routes.result)) {
    $pat = [string]$rt.pattern
    if ($want -contains $pat) {
      Invoke-RestMethod -Method DELETE -Uri "https://api.cloudflare.com/client/v4/zones/$ZoneId/workers/routes/$($rt.id)" -Headers $h -TimeoutSec 40 | Out-Null
      Write-Host "  Removed route $pat" -ForegroundColor DarkYellow
    }
  }
  foreach ($pat in $want) {
    $body = @{ pattern = $pat; script = $WorkerName } | ConvertTo-Json -Compress
    Invoke-RestMethod -Method POST -Uri "https://api.cloudflare.com/client/v4/zones/$ZoneId/workers/routes" -Headers ($h + @{ 'Content-Type' = 'application/json' }) -Body $body -TimeoutSec 40 | Out-Null
    Write-Host "  Added route $pat -> $WorkerName" -ForegroundColor Green
  }
}

function Probe([string]$Url) {
  $probeDir = Join-Path $env:USERPROFILE 'AppData\Local\Temp'
  New-Item -ItemType Directory -Path $probeDir -Force | Out-Null
  $hdr = Join-Path $probeDir ('p-' + [guid]::NewGuid().ToString('N') + '.hdr')
  $code = & curl.exe -sS -L -m 25 -A 'Mozilla/5.0' -D $hdr -o NUL $Url -w '%{http_code}' 2>$null
  $raw = if (Test-Path $hdr) { Get-Content $hdr -Raw } else { '' }
  Remove-Item $hdr -Force -ErrorAction SilentlyContinue
  $xs = ''; $fh = ''
  if ($raw -match '(?im)^x-source:\s*(\S+)') { $xs = $Matches[1].Trim() }
  if ($raw -match '(?im)^x-fleet-host:\s*(\S+)') { $fh = $Matches[1].Trim() }
  return [pscustomobject]@{ Status = [int]$code; XSource = $xs; FleetHost = $fh }
}

$rows = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($site in $sites) {
  $i++
  $domain = $site.Domain.Trim().ToLowerInvariant() -replace '^https?://', '' -replace '^www\.', '' -replace '/$', ''
  Write-Host "`n======== [$i/$($sites.Count)] $domain ========" -ForegroundColor Cyan
  $siteDir = Join-Path $outDir $domain
  New-Item -ItemType Directory -Path $siteDir -Force | Out-Null
  $row = [ordered]@{ Domain = $domain; ZoneId = ''; Pages = 0; Assets = 0; AssetFail = 0; After = ''; Error = '' }
  try {
    $z = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/zones?name=$domain" -Headers $h -TimeoutSec 40
    $zoneId = @($z.result)[0].id
    $row.ZoneId = $zoneId

    $pages = New-Object System.Collections.Generic.List[string]
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    [void]$seen.Add('/'); $pages.Add('/')

    $homeFile = Join-Path $siteDir 'origin-home.html'
    Get-CurlOrigin $domain '/' $homeFile 60
    $homeHtml = if ((Test-Path $homeFile) -and (Get-Item $homeFile).Length -gt 500) { [IO.File]::ReadAllText($homeFile) } else { '' }
    if (-not $homeHtml) { throw 'Origin homepage empty (hosting IP fetch failed)' }
    foreach ($lk in (Extract-InternalLinks $homeHtml $domain)) {
      if ($seen.Count -ge $MaxPages) { break }
      if ($seen.Add($lk)) { $pages.Add($lk) }
    }
    foreach ($sm in @('/sitemap.xml', '/page-sitemap.xml', '/sitemap_index.xml', '/robots.txt')) {
      $sf = Join-Path $siteDir ('sm-' + ($sm.Trim('/') -replace '[^a-z0-9.-]', '-'))
      Get-CurlOrigin $domain $sm $sf 45
      if ((Test-Path $sf) -and (Get-Item $sf).Length -gt 40) {
        $txt = [IO.File]::ReadAllText($sf)
        foreach ($m in [regex]::Matches($txt, 'https?://[^<\s]+')) {
          try {
            $u = [uri]$m.Value
            if ($u.Host -notmatch [regex]::Escape($domain)) { continue }
            $np = Normalize-PagePath $u.AbsolutePath
            if ($np -and -not (Test-SkipPage $np) -and $seen.Count -lt $MaxPages -and $seen.Add($np)) { $pages.Add($np) }
          } catch {}
        }
      }
    }
    Write-Host "  Discovered pages=$($pages.Count)" -ForegroundColor DarkGray

    $allAssets = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $pageOk = 0
    foreach ($p in $pages) {
      $safe = if ($p -eq '/') { 'home' } else { ($p.Trim('/') -replace '[^a-z0-9-]', '-') }
      $tmp = Join-Path $siteDir "page-$safe.html"
      Get-CurlOrigin $domain $p $tmp 55
      if (-not (Test-Path $tmp) -or (Get-Item $tmp).Length -lt 600) { continue }
      $bytes = [IO.File]::ReadAllBytes($tmp)
      $html = [IO.File]::ReadAllText($tmp)
      $key = Get-FleetHtmlKey $domain $p
      Put-FleetKv $key $bytes
      foreach ($a in (Extract-AssetPaths $html)) { [void]$allAssets.Add($a) }
      $pageOk++
    }
    $row.Pages = $pageOk
    Write-Host "  KV html pages=$pageOk" -ForegroundColor Green

    foreach ($extra in @('/robots.txt', '/sitemap.xml', '/sitemap_index.xml', '/page-sitemap.xml', '/main-sitemap.xsl', '/wp-includes/js/jquery/jquery.min.js', '/wp-includes/js/jquery/jquery-migrate.min.js')) {
      [void]$allAssets.Add($extra)
    }
    $okA = 0; $failA = 0
    $queue = New-Object System.Collections.Generic.Queue[string]
    $queued = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($ap0 in @($allAssets)) { if ($queued.Add($ap0)) { $queue.Enqueue($ap0) } }
    while ($queue.Count -gt 0) {
      $ap = $queue.Dequeue()
      $dl = Join-Path $siteDir ('dl-' + [guid]::NewGuid().ToString('N'))
      try {
        Get-CurlOrigin $domain $ap $dl 50
        if (-not (Test-Path $dl) -or (Get-Item $dl).Length -lt 20) { throw 'empty' }
        $b = [IO.File]::ReadAllBytes($dl)
        $head = [Text.Encoding]::ASCII.GetString($b, 0, [Math]::Min(80, $b.Length)).ToLowerInvariant()
        $isSeo = $ap -match '(?i)\.(xml|txt)$'
        if (-not $isSeo -and ($head -match '<!doctype\s+html' -or $head -match '<html')) { throw 'html-not-asset' }
        Put-FleetR2 "${domain}:asset:${ap}" $b (Get-ContentType $ap) $siteDir
        $okA++
        if ($ap -match '(?i)\.css$') {
          foreach ($extraCss in (Extract-CssUrlPaths ([Text.Encoding]::UTF8.GetString($b)) $ap)) {
            if ($queued.Add($extraCss)) { $queue.Enqueue($extraCss) }
          }
        }
      } catch {
        $failA++
        Write-Host "  asset fail $ap : $($_.Exception.Message)" -ForegroundColor DarkYellow
      } finally { Remove-Item $dl -Force -ErrorAction SilentlyContinue }
    }
    $row.Assets = $okA
    $row.AssetFail = $failA
    Write-Host "  R2 assets ok=$okA fail=$failA" -ForegroundColor Green

    Set-FleetRoutes $zoneId $domain
    try {
      Invoke-RestMethod -Method POST -Uri "https://api.cloudflare.com/client/v4/zones/$zoneId/purge_cache" `
        -Headers ($h + @{ 'Content-Type' = 'application/json' }) -Body '{"purge_everything":true}' -TimeoutSec 40 | Out-Null
    } catch {}
    Start-Sleep 3
    $after = Probe "https://$domain/"
    $row.After = "$($after.Status)/$($after.XSource)/fleet=$($after.FleetHost)"
    Write-Host "  After $($row.After)" -ForegroundColor Green
  } catch {
    $row.Error = $_.Exception.Message
    Write-Host "  FAIL $($row.Error)" -ForegroundColor Red
  }
  $rows.Add([pscustomobject]$row)
  $rows | Export-Csv -LiteralPath (Join-Path $outDir 'summary.csv') -NoTypeInformation -Encoding UTF8
}

Write-Host "`n========== WP→FLEET SUMMARY ==========" -ForegroundColor Magenta
$rows | Format-Table Domain, Pages, Assets, AssetFail, After, Error -AutoSize
$ok = @($rows | Where-Object { $_.After -match '200/kv' }).Count
Write-Output "OK_KV=$ok TOTAL=$($rows.Count) OUT=$outDir"
