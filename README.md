# Shared Apex Static — fleet Worker for many domains
#
# Architecture: ONE Worker + ONE KV + ONE R2
# Keys: {hostname}:html:{path}  and  {hostname}:asset:{path}
#
# This project is separate from static-conversion. Do not modify that folder.

## Setup

1. Copy `.env.example` → `.env` and fill Cloudflare account id + API token
2. Provision:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-ProvisionFleet.ps1
```

3. Migrate sites (CSV with Domain column):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-MigrateSitesToFleet.ps1 -SitesCsv .\reports\spike-50-sites.csv -Limit 50
```

## Verify

Homepage should return `x-source: kv` (or `origin-html` then `kv` after warm) and `x-fleet-host: <domain>`.
