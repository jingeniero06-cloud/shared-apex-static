# Shared Apex Static — fleet Worker for many domains
#
# Architecture: ONE Worker + ONE KV + ONE R2
# Keys: `{hostname}:html:{path}` and `{hostname}:asset:{path}`
#
# Separate from `static-conversion`. Do not modify that folder for fleet work.

**New teammate?** Start with the combined handoff package:  
`..\static-fleet-handoff\README.md` (also see [`HANDOFF.md`](./HANDOFF.md)).

**Team SOP** (fleet decision, convert/rollback loop, SEO exemptions):  
`..\static-fleet-handoff\SOP-FLEET-STATIC-WORKFLOW.md`

## Can the team use this?

Yes. **No GitHub required.** Receive this folder in the kit zip / shared drive, add a local `.env` (never share `.env`), then run provision/migrate scripts against Michael’s Cloudflare account.

Fleet infra already exists in Cloudflare:

| Resource | Name / id |
| --- | --- |
| Worker | `fleet-static-worker` |
| KV | `HTML_FLEET` |
| R2 | `fleet-static-assets` |
| Hosting IP | `174.136.29.214` |

## Setup

1. Unzip the kit so this folder sits at:

```text
C:\Users\<You>\Downloads\shared-apex-static
```

(alongside `static-conversion` and `static-fleet-handoff`)

2. Create `.env` from the example (account id + fleet names are pre-filled):

```powershell
cd "C:\Users\<You>\Downloads\shared-apex-static"
Copy-Item .env.example .env
```

3. Paste `CLOUDFLARE_API_TOKEN` into `.env` (get the token from the team lead — **do not share or email `.env`**).

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

Homepage should return `x-source: kv` (or warm into KV) and `x-fleet-host: <domain>`. Use a browser User-Agent (some zones block bare `curl`):

```powershell
curl.exe -sI -A "Mozilla/5.0" https://example-domain.com/ | findstr /i "x-source x-fleet-host HTTP"
```

## Notes

- Prefer copying real page HTML from the old per-site KV into the shared store, then switching routes. Warm-only cutover without HTML copy can 403 at origin.
- Keep `reports\option-a-queues\` in the shared kit if continuing Option A migrate waves.
- Check live `x-fleet-host` before re-running migrate on a domain that may already be on the fleet.
