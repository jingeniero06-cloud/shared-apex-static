# Shared Apex Static — fleet Worker for many domains

CityThrive fleet static: one (or two) Cloudflare Workers serve many apex domains from shared `HTML_FLEET` (KV) + `fleet-static-assets` (R2).

**Keys:** `{hostname}:html:{path}` · `{hostname}:asset:{path}` · preview uses `static.{domain}:…`

This folder is **fleet ops** (Part B). Do not use it to edit `static-conversion` (Part A Cyotek path). WordPress on the hosting IP is always the source of truth — never scrape public HTTPS when the host already returns `x-source: kv`.

---

## Operators

| Role | Who | Owns |
|------|-----|------|
| Conversion / Cloudflare | **John** | `static.*` preview scrape, apex cutover, origin-IP rescrape, form-validation inject, fleet Workers / routes |
| WordPress origin | **Usman** | Live WP edits, WPVivid backups, aaPanel `dev.`, DB/hosting, stay-WordPress exceptions |
| QA | **Sean** | Eyeball + 26-check before apex cutover; fail = do not promote |
| Lead / provision API | **Mike / Adam** | Adam `provision-originless` / scrape API, account infra |
| Kit / token | **Team lead** | Shared kit zip, Cloudflare API token (never commit `.env`) |

When John is out: follow the SOPs below; Usman still owns any WordPress change; Sean still signs off before live cutover.

---

## Conversion process (where to look)

Do not copy long SOPs into chat or this README — open the doc for the job:

| Job | Doc |
|-----|-----|
| **New machine** (kit, `fleet\` links, `.env`, smoke) | [SOP-MACHINE-SETUP](./docs/SOP-MACHINE-SETUP.md) · [HTML](./docs/SOP-MACHINE-SETUP.html) · [PDF](./docs/SOP-MACHINE-SETUP.pdf) |
| **Day-to-day convert** (`static.*` → apex cutover → rescrape → rollback edit loop) | [SOP-CONVERT-PREVIEW-CUTOVER-RESCRAPE](./docs/SOP-CONVERT-PREVIEW-CUTOVER-RESCRAPE.md) · [HTML](./docs/SOP-CONVERT-PREVIEW-CUTOVER-RESCRAPE.html) · [PDF](./docs/SOP-CONVERT-PREVIEW-CUTOVER-RESCRAPE.pdf) |
| **Full process guide** (diagrams, checklist narrative) | [conversion-process-guide.html](./docs/conversion-process-guide.html) |
| **aaPanel `dev.` / `static.` / apex** | [aapanel-dev-workflows.html](./docs/aapanel-dev-workflows.html) · [meeting script](./docs/meeting-script-aapanel-workflows.html) |
| **Cursor / agent setup** | [SOP-CURSOR-SETUP.html](./docs/SOP-CURSOR-SETUP.html) |
| **Worked live example** | [SOP-LIVE-EXAMPLE.html](./docs/SOP-LIVE-EXAMPLE.html) |
| **Combined handoff kit** (Parts A+B) | `..\static-fleet-handoff\README.md` · this repo [HANDOFF.md](./HANDOFF.md) |
| **Architecture / SEO exemptions** | `..\static-fleet-handoff\SOP-FLEET-STATIC-WORKFLOW.md` |

### Paths at a glance

```text
Path A — New convert (apex still WordPress)
  WP on hosting IP → scrape → static.{domain} only → QA → apex+www cutover → inject form-validation.js

Path B — Rescrape (already fleet)
  Scrape via hosting IP (--resolve) into HTML_FLEET + R2 → re-inject form JS → verify 200 / x-source:kv

Path C — Edit loop (default for fleet sites)
  Rollback Worker routes to WP → edit on live WP → Path B rescrape → restore fleet routes
  (aaPanel dev. is optional staging when apex must stay static)
```

**Stay-WordPress** domains in `fleet-static-preview\sites\exclude-stay-wordpress.txt` are never converted.

---

## Fleet infra

| Resource | Value |
|----------|--------|
| Worker (Batches 1–7 live apex) | `fleet-static-worker` · origin `174.136.29.214` |
| Worker (new batches) | `fleet-static-worker-server-1` · origin `165.140.157.43` |
| KV | `HTML_FLEET` |
| R2 | `fleet-static-assets` |

Do **not** move Batches 1–7 live apex onto server 1. Both Workers share the same KV + R2.

**Proof a host is on fleet:** `HTTP 200` · `x-source: kv` · `x-fleet-host: <domain>`

---

## Setup (this machine)

1. Kit path:

```text
C:\Users\<You>\Downloads\shared-apex-static
```

(alongside `fleet-static-preview`, `static-conversion`, `static-fleet-handoff`)

2. Local secrets:

```powershell
cd "C:\Users\<You>\Downloads\shared-apex-static"
Copy-Item .env.example .env
# Paste CLOUDFLARE_API_TOKEN — never share or commit .env
```

Token needs Workers, KV, R2, and Zone routes edit.

3. Prefer the **operating SOP** scripts in `fleet-static-preview` (preview / cutover / origin-IP rescrape). Do **not** use `Invoke-MigrateSitesToFleet.ps1` to refresh content (that copies stale per-site KV).

4. Re-provision only if Worker/KV/R2 are missing:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-ProvisionFleet.ps1
```

---

## Adam API (`fleet: true`)

Preview only (`static.{domain}/*`). Does not touch apex/www. Shared `HTML_FLEET` + `fleet-static-assets`.

| Batch | `workerName` |
|-------|----------------|
| Batches 1–7 | omit → `fleet-static-worker` |
| New sites | `"fleet-static-worker-server-1"` |

Never omit `workerName` on a new-batch domain (it would land on server 2).

---

## Guardrails

- Scrape with `curl --resolve` to the correct hosting IP; WordPress is source of truth.
- After every HTML scrape, re-inject `/form-validation.js` (or CF7/WPForms variant when those field names are used).
- SVGs must be `image/svg+xml` (never `application/xml`).
- Strip `.env` before sharing the kit. No GitHub required for teammates — zip / shared drive is enough.

## Verify

```powershell
curl.exe -sI -A "Mozilla/5.0" https://example-domain.com/ | findstr /i "x-source x-fleet-host HTTP"
```
