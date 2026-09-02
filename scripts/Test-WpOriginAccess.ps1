#Requires -Version 5.1
<#
.SYNOPSIS
  Check whether this PC can fetch WordPress via hosting IP (not Cloudflare KV).
#>
param(
  [string] $HostingIp = '174.136.29.214',
  [string] $Domain = 'aberdeenfoundationrepair.com',
  [int] $TimeoutSec = 15
)

$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Test-TcpPort([string]$Ip, [int]$Port, [int]$Ms) {
  $client = New-Object System.Net.Sockets.TcpClient
  try {
    $iar = $client.BeginConnect($Ip, $Port, $null, $null)
    $ok = $iar.AsyncWaitHandle.WaitOne($Ms, $false)
    if (-not $ok) { return $false }
    $client.EndConnect($iar)
    return $true
  } catch {
    return $false
  } finally {
    $client.Close()
  }
}

$tmp = Join-Path $env:TEMP ('wp-origin-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$body = Join-Path $tmp 'body.html'
$hdr = Join-Path $tmp 'hdr.txt'

$tcp80 = Test-TcpPort $HostingIp 80 4000
$tcp443 = Test-TcpPort $HostingIp 443 4000

$code = & curl.exe -sk --resolve "${Domain}:443:${HostingIp}" --resolve "www.${Domain}:443:${HostingIp}" `
  "https://${Domain}/" -A 'Mozilla/5.0' --max-time $TimeoutSec -D $hdr -o $body -w '%{http_code}' 2>$null
$rawHdr = if (Test-Path $hdr) { Get-Content $hdr -Raw -ErrorAction SilentlyContinue } else { '' }
$len = if (Test-Path $body) { (Get-Item $body).Length } else { 0 }
$xs = ''
if ($rawHdr -match '(?im)^x-source:\s*(\S+)') { $xs = $Matches[1].Trim() }
$snippet = ''
if ($len -gt 80) {
  $snippet = ([IO.File]::ReadAllText($body)).Substring(0, [Math]::Min(120, $len)) -replace '\s+', ' '
}
$looksWp = $false
if ($len -gt 500 -and (Test-Path $body)) {
  $html = [IO.File]::ReadAllText($body)
  $looksWp = ($html -match 'wp-content' -or $html -match 'wordpress') -and $xs -ne 'kv'
}
$open = ($code -eq '200' -or $code -eq '301' -or $code -eq '302') -and $len -gt 500 -and $xs -ne 'kv' -and $tcp443

$result = [pscustomobject]@{
  HostingIp = $HostingIp
  Domain    = $Domain
  Tcp80     = $tcp80
  Tcp443    = $tcp443
  HttpCode  = $code
  Bytes     = $len
  XSource   = $xs
  LooksWp   = $looksWp
  OriginOpen = [bool]$open
  Snippet   = $snippet
}

$result | Format-List
if ($open) {
  Write-Host 'ORIGIN_OPEN=1' -ForegroundColor Green
  exit 0
}
Write-Host 'ORIGIN_OPEN=0' -ForegroundColor Yellow
exit 2
