#Requires -Version 5.1
<#
.SYNOPSIS
  Verify public fleet static matches live WordPress on the hosting IP.
#>
param(
  [Parameter(Mandatory = $true)][string] $SitesCsv,
  [string] $HostingIp = '174.136.29.214',
  [string] $OutDir
)

$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $OutDir) {
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $OutDir = Join-Path $Root "reports\wp-fleet-verify-$stamp"
}
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

function Get-SafeTempDir {
  $p = Join-Path $env:USERPROFILE 'AppData\Local\Temp'
  New-Item -ItemType Directory -Path $p -Force | Out-Null
  return $p
}

function Get-PublicHeaders([string]$Domain) {
  $hdr = Join-Path (Get-SafeTempDir) ('vh-' + [guid]::NewGuid().ToString('N'))
  $code = & curl.exe -sS -L -m 25 -A 'Mozilla/5.0' -D $hdr -o NUL "https://$Domain/" -w '%{http_code}' 2>$null
  $raw = if (Test-Path $hdr) { Get-Content $hdr -Raw } else { '' }
  Remove-Item $hdr -Force -ErrorAction SilentlyContinue
  $xs = ''; $fh = ''
  if ($raw -match '(?im)^x-source:\s*(\S+)') { $xs = $Matches[1].Trim() }
  if ($raw -match '(?im)^x-fleet-host:\s*(\S+)') { $fh = $Matches[1].Trim() }
  return [pscustomobject]@{ Status = [int]$code; XSource = $xs; FleetHost = $fh }
}

function Get-Html([string]$Url, [string[]]$ResolveArgs, [string]$OutFile) {
  $args = @('-skL', '-m', '45', '-A', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0', '-o', $OutFile) + $ResolveArgs + @($Url)
  & curl.exe @args 2>$null | Out-Null
  if ((Test-Path $OutFile) -and (Get-Item $OutFile).Length -gt 200) {
    return [IO.File]::ReadAllText($OutFile)
  }
  return ''
}

function Get-Title([string]$html) {
  if ($html -match '(?is)<title[^>]*>(.*?)</title>') { return ($Matches[1] -replace '\s+', ' ').Trim() }
  return ''
}

function Test-HasForm([string]$html) { return [bool]($html -match '(?i)<form[\s>]') }
function Test-HasPhone([string]$html) { return [bool]($html -match '(?i)name=["''][^"'']*phone|type=["'']tel["'']') }
function Test-HasCaptcha([string]$html) { return [bool]($html -match '(?i)recaptcha|hcaptcha|turnstile|cf-turnstile') }
function Test-HasCallRail([string]$html) { return [bool]($html -match '(?i)cdn.callrail|calltrk|swap\.js') }

function Get-AssetPaths([string]$html) {
  $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  if ([string]::IsNullOrEmpty($html)) { return @() }
  foreach ($m in [regex]::Matches($html, '(?:src|href)=["'']([^"'']+\.(?:css|js|png|jpe?g|webp|gif|svg|woff2?))(?:\?[^"'']*)?["'']', 'IgnoreCase')) {
    $u = $m.Groups[1].Value.Trim()
    try { if ($u -match '^https?://') { $u = ([uri]$u).AbsolutePath } } catch { continue }
    if ($u.StartsWith('/') -and -not $u.StartsWith('//')) { [void]$seen.Add($u.Split('?')[0]) }
  }
  return @($seen)
}

function Test-PublicAsset([string]$Domain, [string]$Path) {
  $url = "https://$Domain$Path"
  $hdr = Join-Path (Get-SafeTempDir) ('va-' + [guid]::NewGuid().ToString('N'))
  $code = & curl.exe -sS -L -m 20 -A 'Mozilla/5.0' -D $hdr -o NUL $url -w '%{http_code}' 2>$null
  $raw = if (Test-Path $hdr) { Get-Content $hdr -Raw } else { '' }
  Remove-Item $hdr -Force -ErrorAction SilentlyContinue
  $xs = ''
  if ($raw -match '(?im)^x-source:\s*(\S+)') { $xs = $Matches[1].Trim() }
  return [pscustomobject]@{ Status = [int]$code; XSource = $xs }
}

$sites = @(Import-Csv -LiteralPath $SitesCsv | Where-Object { $_.Domain })
$rows = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($site in $sites) {
  $i++
  $d = $site.Domain.Trim().ToLowerInvariant()
  Write-Host "`n======== VERIFY [$i/$($sites.Count)] $d ========" -ForegroundColor Cyan
  $dir = Join-Path $OutDir $d
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  $row = [ordered]@{
    Domain = $d; Http = ''; XSource = ''; FleetHost = ''
    TitleMatch = ''; FormMatch = ''; PhoneMatch = ''; CaptchaMatch = ''; CallRailMatch = ''
    AssetsChecked = 0; AssetsOk = 0; AssetsFail = 0; AssetR2 = 0
    OriginLen = 0; StaticLen = 0; Verdict = ''; Notes = ''
  }
  $notes = New-Object System.Collections.Generic.List[string]
  $h = Get-PublicHeaders $d
  $row.Http = $h.Status
  $row.XSource = $h.XSource
  $row.FleetHost = $h.FleetHost
  if ($h.Status -ne 200) { $notes.Add("http $($h.Status)") }
  if ($h.XSource -ne 'kv') { $notes.Add("x-source=$($h.XSource)") }
  if (-not $h.FleetHost) { $notes.Add('missing x-fleet-host') }

  $originFile = Join-Path $dir 'origin-home.html'
  $staticFile = Join-Path $dir 'static-home.html'
  $originHtml = Get-Html "https://$d/" @('--resolve', "${d}:443:$HostingIp", '--resolve', "www.${d}:443:$HostingIp") $originFile
  $staticHtml = Get-Html "https://$d/" @() $staticFile
  $row.OriginLen = $originHtml.Length
  $row.StaticLen = $staticHtml.Length
  if ($originHtml.Length -lt 800) { $notes.Add('thin origin HTML') }
  if ($staticHtml.Length -lt 800) { $notes.Add('thin static HTML') }

  $ot = Get-Title $originHtml; $st = Get-Title $staticHtml
  $row.TitleMatch = [bool]($ot -and $ot -eq $st)
  if (-not $row.TitleMatch) { $notes.Add("title origin='$ot' static='$st'") }
  $row.FormMatch = ((Test-HasForm $originHtml) -eq (Test-HasForm $staticHtml))
  $row.PhoneMatch = ((Test-HasPhone $originHtml) -eq (Test-HasPhone $staticHtml))
  $row.CaptchaMatch = ((Test-HasCaptcha $originHtml) -eq (Test-HasCaptcha $staticHtml))
  $row.CallRailMatch = ((Test-HasCallRail $originHtml) -eq (Test-HasCallRail $staticHtml))
  if (-not $row.FormMatch) { $notes.Add('form mismatch') }
  if (-not $row.PhoneMatch) { $notes.Add('phone-field mismatch') }
  if (-not $row.CaptchaMatch) { $notes.Add('captcha mismatch') }
  if (-not $row.CallRailMatch) { $notes.Add('callrail mismatch') }

  $assets = @(Get-AssetPaths $staticHtml | Select-Object -First 18)
  $ok = 0; $fail = 0; $r2 = 0
  foreach ($p in $assets) {
    $a = Test-PublicAsset $d $p
    if ($a.Status -eq 200) {
      $ok++
      if ($a.XSource -match 'r2') { $r2++ }
    } else {
      $fail++
      $notes.Add("asset $($a.Status) $p")
    }
  }
  $row.AssetsChecked = $assets.Count
  $row.AssetsOk = $ok
  $row.AssetsFail = $fail
  $row.AssetR2 = $r2

  $headerOk = ($h.Status -eq 200 -and $h.XSource -eq 'kv' -and $h.FleetHost)
  $contentOk = [bool]$row.TitleMatch -and [bool]$row.FormMatch -and $fail -eq 0
  $row.Verdict = if ($headerOk -and $contentOk) { 'PASS' } else { 'FAIL' }
  $row.Notes = ($notes | Select-Object -First 8) -join '; '
  Write-Host ("  {0} http={1} xs={2} fleet={3} title={4} assets={5}/{6}" -f $row.Verdict, $row.Http, $row.XSource, $row.FleetHost, $row.TitleMatch, $row.AssetsOk, $row.AssetsChecked)
  $rows.Add([pscustomobject]$row)
}

$csv = Join-Path $OutDir 'summary.csv'
$rows | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
$pass = @($rows | Where-Object { $_.Verdict -eq 'PASS' }).Count
Write-Host "`nVERIFY PASS=$pass TOTAL=$($rows.Count) OUT=$OutDir" -ForegroundColor Magenta
$rows | Format-Table Domain, Verdict, Http, XSource, FleetHost, TitleMatch, FormMatch, AssetsOk, AssetsFail -AutoSize
