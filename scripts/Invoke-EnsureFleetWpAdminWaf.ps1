#Requires -Version 5.1
<#
.SYNOPSIS
  Enable "DevSecSi: block WordPress admin on static apex" on every zone
  currently routed to fleet-static-worker.
#>
param(
  [string] $EnvFile,
  [string] $RuleDescription = 'DevSecSi: block WordPress admin on static apex',
  [string] $AllowIps = '210.1.100.84,138.84.112.81,136.158.2.183',
  [string] $WorkerName = 'fleet-static-worker'
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
if ($vars['FLEET_WORKER_NAME']) { $WorkerName = $vars['FLEET_WORKER_NAME'] }
$headers = @{ Authorization = "Bearer $Token"; 'Content-Type' = 'application/json' }
$AllowIpList = @($AllowIps -split '[,;\s]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$ipClause = 'not ip.src in {' + ($AllowIpList -join ' ') + '}'

function Get-WpAdminExpression([string]$Domain) {
  $hosts = @($Domain, "www.$Domain") | Select-Object -Unique
  $quoted = ($hosts | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ' '
  return ('(http.host in {' + $quoted + '} and (http.request.uri.path contains "/wp-admin" or http.request.uri.path contains "/wp-login.php") and ' + $ipClause + ')')
}

function Get-Apex([string]$Pattern) {
  $p = $Pattern.Trim().ToLowerInvariant()
  $p = $p -replace '/\*$', '' -replace '^\*\.', '' -replace '^www\.', ''
  return $p
}

Write-Host "Listing routes for $WorkerName ..." -ForegroundColor Magenta
$routeUri = "https://api.cloudflare.com/client/v4/accounts/$AccountId/workers/scripts/$WorkerName/routes"
$allRoutes = New-Object System.Collections.Generic.List[object]
$page = 1
do {
  $uri = "$routeUri`?per_page=100&page=$page"
  try {
    $r = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec 60
  } catch {
    # Fallback: some accounts use workers/routes without pagination
    $r = Invoke-RestMethod -Uri $routeUri -Headers $headers -TimeoutSec 60
    $page = 999
  }
  foreach ($rt in @($r.result)) { $allRoutes.Add($rt) }
  $totalPages = 1
  if ($r.result_info -and $r.result_info.total_pages) { $totalPages = [int]$r.result_info.total_pages }
  $page++
} while ($page -le $totalPages)

$byDomain = @{}
foreach ($rt in $allRoutes) {
  $script = [string]$rt.script
  if ($script -and $script -ne $WorkerName) { continue }
  $apex = Get-Apex ([string]$rt.pattern)
  if (-not $apex -or $apex -notmatch '\.') { continue }
  $zid = [string]$rt.zone_id
  if (-not $byDomain.ContainsKey($apex)) {
    $byDomain[$apex] = $zid
  } elseif (-not $byDomain[$apex] -and $zid) {
    $byDomain[$apex] = $zid
  }
}

$domains = @($byDomain.Keys | Sort-Object)
Write-Host "Fleet domains from routes: $($domains.Count)" -ForegroundColor Magenta
if ($domains.Count -lt 1) { throw 'No fleet routes found' }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outDir = Join-Path $Root "reports\waf-fleet-$stamp"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$summary = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($domain in $domains) {
  $i++
  $zoneId = $byDomain[$domain]
  $row = [ordered]@{ Domain = $domain; ZoneId = $zoneId; Action = ''; WasEnabled = ''; Error = '' }
  try {
    if (-not $zoneId) {
      $z = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/zones?name=$domain" -Headers $headers -TimeoutSec 30
      $zoneId = @($z.result) | Select-Object -First 1 -ExpandProperty id
      if (-not $zoneId) { throw "No zone for $domain" }
      $row.ZoneId = $zoneId
    }
    $entryUri = "https://api.cloudflare.com/client/v4/zones/$zoneId/rulesets/phases/http_request_firewall_custom/entrypoint"
    $entry = Invoke-RestMethod -Uri $entryUri -Headers $headers -TimeoutSec 30
    $rulesetId = $entry.result.id
    $rule = $null
    if ($entry.result.rules) {
      $rule = @($entry.result.rules | Where-Object { $_.description -eq $RuleDescription } | Select-Object -First 1)
      if ($rule.Count -eq 0) { $rule = $null } else { $rule = $rule[0] }
    }
    $expression = Get-WpAdminExpression $domain
    if ($rule) {
      $row.WasEnabled = [string][bool]$rule.enabled
      $needs = (-not $rule.enabled) -or ($rule.action -ne 'block') -or ($rule.expression -notmatch [regex]::Escape($ipClause))
      if (-not $needs) {
        $row.Action = 'OK_ALREADY_ENABLED'
      } else {
        $row.Action = if (-not $rule.enabled) { 'ENABLE_EXISTING' } else { 'UPDATE_EXPRESSION' }
        $body = @{
          action = 'block'; expression = $expression
          description = $RuleDescription; enabled = $true; id = $rule.id
        }
        if ($rule.ref) { $body.ref = $rule.ref }
        Invoke-RestMethod -Method PATCH `
          -Uri "https://api.cloudflare.com/client/v4/zones/$zoneId/rulesets/$rulesetId/rules/$($rule.id)" `
          -Headers $headers -Body ($body | ConvertTo-Json -Compress) -TimeoutSec 30 | Out-Null
      }
    } else {
      $row.Action = 'CREATE_ENABLED'
      $postBody = @{
        action = 'block'; expression = $expression
        description = $RuleDescription; enabled = $true
        position = @{ index = 1 }
      }
      Invoke-RestMethod -Method POST `
        -Uri "https://api.cloudflare.com/client/v4/zones/$zoneId/rulesets/$rulesetId/rules" `
        -Headers $headers -Body ($postBody | ConvertTo-Json -Compress -Depth 5) -TimeoutSec 30 | Out-Null
    }
    Write-Host ("[{0}/{1}] {2} :: {3}" -f $i, $domains.Count, $domain, $row.Action) -ForegroundColor Green
  } catch {
    $row.Action = 'FAIL'
    $row.Error = $_.Exception.Message
    Write-Host ("[{0}/{1}] {2} :: FAIL {3}" -f $i, $domains.Count, $domain, $_.Exception.Message) -ForegroundColor Red
  }
  $summary.Add([pscustomobject]$row) | Out-Null
  Start-Sleep -Milliseconds 60
}

$csv = Join-Path $outDir 'waf-fleet-summary.csv'
$summary | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
Write-Host "`n========== FLEET WAF SUMMARY ==========" -ForegroundColor Magenta
$summary | Group-Object Action | Sort-Object Count -Descending | Format-Table Name, Count -AutoSize
$fail = @($summary | Where-Object { $_.Action -eq 'FAIL' }).Count
$ok = @($summary | Where-Object { $_.Action -match 'OK_ALREADY|ENABLE|CREATE|UPDATE' }).Count
Write-Output "OK=$ok FAIL=$fail TOTAL=$($summary.Count) OUT=$csv"
