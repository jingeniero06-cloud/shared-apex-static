# SOP: Convert, Preview (`static.*`), Apex Cutover, and Rescrape

| | |
|--|--|
| **Document ID** | CT-SOP-FLEET-CONVERT-2026-08 |
| **Version** | 1.0 |
| **Effective** | 28 August 2026 |
| **Owners** | John (conversion / Cloudflare) · Usman (WordPress origin) · Sean (QA) |
| **Audience** | Conversion operators, WordPress, QA, backups covering when John is out |
| **HTML / PDF** | [SOP-CONVERT-PREVIEW-CUTOVER-RESCRAPE.html](./SOP-CONVERT-PREVIEW-CUTOVER-RESCRAPE.html) · [SOP-CONVERT-PREVIEW-CUTOVER-RESCRAPE.pdf](./SOP-CONVERT-PREVIEW-CUTOVER-RESCRAPE.pdf) |

This is the **operating workflow** for fleet static. It replaces “straight to live apex” for new converts. WordPress on the hosting IP is always the source of truth.

New machine first: [SOP-MACHINE-SETUP.pdf](./SOP-MACHINE-SETUP.pdf).

---

## 1. Purpose

Define one path for:

1. **New convert** — live WordPress → `static.{domain}` preview → apex static after QA
2. **Rescrape** — refresh an already-static site from current WordPress (popups, copy, pages)
3. **Edit loop** — roll apex back to WordPress, edit, rescrape, restore fleet routes

Static is a snapshot of the public frontend. It is not WordPress. wp-admin does not run on Cloudflare.

---

## 2. Architecture

```text
Visitor
   │
   ▼
fleet-static-worker          Batches 1–7 live apex     origin 174.136.29.214
fleet-static-worker-server-1 New batches               origin 165.140.157.43
   │
   ├── HTML_FLEET (KV)            {host}:html:{path}
   └── fleet-static-assets (R2)   {host}:asset:{path}

Preview host keys: static.{domain}:html:… and static.{domain}:asset:…
```

Do **not** move Batches 1–7 live apex onto `fleet-static-worker-server-1`.

**Proof a public host is on fleet**

```text
HTTP 200
x-source: kv
x-fleet-host: example.com
```

`x-source: kv` without `x-fleet-host` means the old **per-site Worker**, not the fleet.

---

## 3. Origin IPs

| Lane | Worker | WordPress origin IP | Use for |
|------|--------|---------------------|---------|
| Server 2 | `fleet-static-worker` | `174.136.29.214` | Batches 1–7 live apex |
| Server 1 | `fleet-static-worker-server-1` | `165.140.157.43` | New batches after B1–7 |

Scrape with `curl --resolve {domain}:443:{origin-ip}`. Never scrape public HTTPS when live already returns `x-source: kv` — that recopies the old static snapshot (including old popups).

---

## 4. Path A — New convert (apex is still WordPress)

1. Confirm the domain is **not** stay-WordPress. WPVivid backup. Fix pages/forms/CallRail on **live WP**.
2. Scrape WordPress via the correct origin IP into `HTML_FLEET` + `fleet-static-assets`.
3. Attach **`static.{domain}/*` only**. Apex and www stay on WordPress.
4. QA on `https://static.{domain}/` against live WP: eyeball, 26-check, forms, images, CallRail.
5. After sign-off, cut over **apex + www** to the same fleet Worker (`-IConfirmApexCutover`).
6. Inject `form-validation.js` (origin WP never includes the tag).
7. Verify live: `200`, `x-source: kv`, `x-fleet-host`, `/form-validation.js` 200.

```powershell
cd "C:\Users\<You>\Downloads\fleet-static-preview"

# Preview only — apex stays WordPress
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-PreviewStaticOnFleet.ps1 `
  -SitesCsv .\sites\YOUR.csv `
  -OriginIp 174.136.29.214 `
  -WorkerName fleet-static-worker
# Server 1: -OriginIp 165.140.157.43 -WorkerName fleet-static-worker-server-1

# After QA
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-CutoverApexToFleet.ps1 `
  -SitesCsv .\sites\YOUR.csv -IConfirmApexCutover

powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-InjectFleetFormValidation.ps1 `
  -SitesCsv .\sites\YOUR.csv
```

Adam `POST …/provision-originless` (and `/scrape` with `"fleet": true`) attaches **preview only**. It does **not** take an origin IP. Omit `workerName` only for B1–7. New batches must send `"workerName":"fleet-static-worker-server-1"`. Apex cutover stays on us.

---

## 5. Path B — Rescrape (already static)

Use when the database/popup is already correct on WordPress and live is (or will be) fleet.

- HTML / popup / copy only → **HTML-only** (`-SkipAssets`), then inject form-validation.
- Theme, CSS, JS, or media change → **full HTML + R2**, then inject form-validation.
- If apex is already fleet → **`-SkipRoutes`**. Do not retarget B1–7 onto server 1.
- If apex is not fleet yet (`x-source: kv` missing `x-fleet-host`, or no fleet headers) → scrape into fleet KV first; cut over apex only after QA.

```powershell
cd "C:\Users\<You>\Downloads\shared-apex-static"

powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-WpOriginToFleet.ps1 `
  -SitesCsv .\reports\YOUR.csv `
  -HostingIp 174.136.29.214 `
  -WorkerName fleet-static-worker `
  -SkipRoutes -SkipAssets

# Server 1
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-WpOriginToFleet.ps1 `
  -SitesCsv .\reports\YOUR.csv `
  -HostingIp 165.140.157.43 `
  -WorkerName fleet-static-worker-server-1 `
  -SkipRoutes -SkipAssets

powershell -ExecutionPolicy Bypass -File `
  "C:\Users\<You>\Downloads\fleet-static-preview\scripts\Invoke-InjectFleetFormValidation.ps1" `
  -SitesCsv .\reports\YOUR.csv
```

Popup re-export wrapper (picks IP from lane):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-PopupReexportFromOrigin.ps1 `
  -Lane s2 -SkipAssets -InjectFormValidation
# -Lane s1  → 165.140.157.43 + fleet-static-worker-server-1
```

After every HTML scrape, **re-inject** `/form-validation.js`. The origin snapshot never contains the fleet snippet.

---

## 6. Path C — Edit loop (need WordPress CMS)

1. Rollback Worker routes so apex hits WordPress (keep KV/R2).
2. Edit and verify on live WP.
3. Rescrape (Path B) via hosting IP.
4. Restore fleet routes (B1–7 → server 2 Worker; new batches → server 1 Worker).
5. Verify `200` / `kv` / `x-fleet-host` and form-validation.

Do not delete WordPress until QA has passed and a lead says so. Keep old per-site Workers at least 48 hours after a fleet cutover.

---

## 7. Form validation

The delegated script (`form-validation.js` with document-level listeners) covers the **main form and Elementor popups**.

| Site type | Who injects | File |
|-----------|-------------|------|
| Remaining WordPress | Usman | `C:\Users\<You>\Downloads\fleet\assets\form-validation.js` |
| Fleet / static | Conversion (Cloudflare KV + R2) | Same file, via `Invoke-InjectFleetFormValidation.ps1` |

Do not send copies under `Downloads\form-validation.js` or `static-conversion` — those lack popup listeners.

---

## 8. Stay-WordPress (never convert)

Hard excludes:

- `roundrockfoundationrepairexperts.com`
- `solidfoundationrepairofsavannah.com`
- `solidfoundationrepairoflakeworth.com`
- `azaleaparkfoundationrepair.com`

Full list: `static-conversion\reports\batch1-7-convert-20260808-173900\exclude-stay-wordpress.txt`

---

## 9. Do not

| Do not | Why |
|--------|-----|
| Scrape public HTTPS on a live fleet site | Recopies old KV (stale popups) |
| `Invoke-MigrateSitesToFleet.ps1` to refresh content | Copies stale per-site KV |
| `Invoke-DeepAssetSync.ps1` on fleet sites | Writes `{domain}-worker` keys, not `{host}:html:` / `{host}:asset:` |
| Adam `/provision-originless` to refresh live fleet | No origin IP; fetches the public hostname |
| Omit `workerName` on a new-batch domain | Lands `static.*` on server 2 |
| Move B1–7 live apex to `fleet-static-worker-server-1` | Locked split |
| Skip form-validation inject after an HTML scrape | Origin WP never has the tag |
| Store rating SVGs as `application/xml` | Broken `<img>` badges; must be `image/svg+xml` |

---

## 10. Go-live checklist

- [ ] Correct origin IP for the lane
- [ ] Stay-WP exclude checked
- [ ] `static.*` QA vs origin (new converts) **or** SkipRoutes confirmed (rescrape)
- [ ] Homepage `200` + `x-source: kv` + `x-fleet-host: {domain}`
- [ ] `/form-validation.js` HTTP 200; snippet in HTML
- [ ] Main form and popup validate (not native HTML5-only)
- [ ] Images `x-source: r2` (full scrape) or existing R2 left in place (HTML-only)
- [ ] Cache purged; hard-refresh verified

---

## 11. Related docs

- [SOP-MACHINE-SETUP.pdf](./SOP-MACHINE-SETUP.pdf) — new Windows PC kit, junctions, `.env`
- [SOP-FLEET-STATIC-WORKFLOW.md](./SOP-FLEET-STATIC-WORKFLOW.md) — 13 Aug architecture SOP
- [01-big-picture.md](./01-big-picture.md) — Model A vs B
- [07-rollback-and-edit.md](./07-rollback-and-edit.md) — revert scripts
- `shared-apex-static\scripts\Invoke-WpOriginToFleet.ps1`
- `fleet-static-preview\scripts\Invoke-PreviewStaticOnFleet.ps1`
- `fleet-static-preview\scripts\Invoke-CutoverApexToFleet.ps1`
