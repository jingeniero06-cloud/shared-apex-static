# Shared Apex Static — fleet Worker for many domains
#
# Architecture: ONE Worker + ONE KV + ONE R2
# Keys: `{hostname}:html:{path}` and `{hostname}:asset:{path}`
#
# Separate from `static-conversion`. Do not modify that folder for fleet work.

**New teammate?** Start with the combined handoff package:  
`..\static-fleet-handoff\README.md` (also see [`HANDOFF.md`](./HANDOFF.md)).

## Can the team use this?

Yes. Clone this repo, add a local `.env` (never commit it), then run provision/migrate scripts against Michael’s Cloudflare account.

Fleet infra already exists in Cloudflare:

| Resource | Name / id |
| --- | --- |
| Worker | `fleet-static-worker` |
| KV | `HTML_FLEET` |
| R2 | `fleet-static-assets` |
| Hosting IP | `174.136.29.214` |

## Setup

1. Clone:

```powershell
git clone https://github.com/jingeniero06-cloud/shared-apex-static.git
cd shared-apex-static
git checkout cursor/shared-fleet-worker
```

2. Create `.env` from the example (account id + fleet names are pre-filled):

```powershell
Copy-Item .env.example .env
```

3. Paste `CLOUDFLARE_API_TOKEN` into `.env` (get the token from the team lead — **do not commit `.env`**).

Token needs Workers, KV, R2, and Zone routes edit on the account.

4. Only re-run provision if the Worker/KV/R2 are missing:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-ProvisionFleet.ps1
```

5. Migrate sites (CSV with a `Domain` column):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-MigrateSitesToFleet.ps1 -SitesCsv .\reports\spike-50-sites.csv -Limit 50
```

## Verify

Homepage should return `x-source: kv` (or warm into KV) and `x-fleet-host: <domain>`.

```powershell
curl.exe -sI https://example-domain.com/ | findstr /i "x-source x-fleet-host HTTP"
```

## Notes

- Prefer copying real page HTML from the old per-site KV into the shared store, then switching routes. Warm-only cutover without HTML copy can 403 at origin.
- `reports/` is local/gitignored — regenerate CSVs as needed.
- Spike migrate of 50 sites may already be in progress or partially complete; check live `x-fleet-host` before re-running.
