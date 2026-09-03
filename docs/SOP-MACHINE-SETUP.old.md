# SOP: Set up fleet conversion on your own Windows PC

| | |
|--|--|
| **Document ID** | CT-SOP-FLEET-MACHINE-SETUP-2026-09 |
| **Version** | 1.0 |
| **Effective** | 2 September 2026 |
| **Owners** | John (conversion / Cloudflare) |
| **Audience** | Anyone who will run preview, cutover, rescrape, or 26-check on their own PC |
| **HTML / PDF** | [SOP-MACHINE-SETUP.html](./SOP-MACHINE-SETUP.html) · [SOP-MACHINE-SETUP.pdf](./SOP-MACHINE-SETUP.pdf) |
| **After setup** | [SOP-CONVERT-PREVIEW-CUTOVER-RESCRAPE.pdf](./SOP-CONVERT-PREVIEW-CUTOVER-RESCRAPE.pdf) |

This SOP gets the kit onto a new Windows machine. It does **not** convert a site. When setup passes, use the convert / preview / cutover / rescrape SOP.

---

## 1. Purpose

A teammate can:

1. Copy the four project folders plus the `fleet` hub
2. Recreate folder links
3. Create `.env` (token from the vault only)
4. Prove APIs and tools work
5. Open the operating SOP and run jobs from `C:\Users\<You>\Downloads\fleet`

GitHub is not required.

---

## 2. What lives where

Unzip so these sit **next to each other** under Downloads:

```text
C:\Users\<You>\Downloads\
  fleet\                   Hub: SOPs, audits, CSVs, form JS. Run from here.
  shared-apex-static\      Fleet Worker, KV/R2 scrape (Invoke-WpOriginToFleet)
  fleet-static-preview\    static.* preview, DNS, apex cutover, form-validation inject
  static-conversion\       Per-site convert + 26-check audit
  static-fleet-handoff\    Team SOP copies
```

Inside `fleet\`, these names are **links** to the real folders (not copies):

| Link in `fleet\` | Real folder |
|------------------|-------------|
| `worker\` | `..\shared-apex-static\` |
| `preview\` | `..\fleet-static-preview\` |
| `conversion\` | `..\static-conversion\` |
| `handoff\` | `..\static-fleet-handoff\` |

If you skip the links, run the same scripts from the real folders. Paths in the convert SOP still work.

Do **not** put a `.env` in `fleet\`. Each project has its own.

---

## 3. Prerequisites

| Tool | Required? | Notes |
|------|-----------|-------|
| Windows 10/11 | Yes | |
| PowerShell 5.1+ | Yes | Built-in |
| `curl.exe` | Yes | Built-in on current Windows |
| Python 3.x | Yes | 26-check / Form QA (`requests`, `openpyxl`) |
| Cloudflare API token | Yes | From the vault. Never Slack, email, or git |
| Git / GitHub | No | Zip or shared drive |
| Node / Wrangler | No | Operators use PowerShell + the API token |
| Cyotek WebCopy | No | Not this workflow |

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
python --version
curl.exe --version
```

If Python is missing, install 3.12+ from python.org and tick **Add python.exe to PATH**. Then:

```powershell
python -m pip install requests openpyxl urllib3
```

---

## 4. Copy the kit

Ask the lead for:

1. The zip / shared-drive copy of the five folders above (**no `.env` files**)
2. Vault item for `CLOUDFLARE_API_TOKEN` (and DevSecSi key only if you will run old per-site convert)
3. Confirmation that `shared-apex-static\reports\fleet-infra.json` is in the zip

Unzip under `C:\Users\<You>\Downloads\` so the folder names match this SOP. Do not nest `Downloads\fleet\fleet\`.

If a copy of `fleet\` arrives with empty `worker`, `preview`, `conversion`, or `handoff` folders, those are broken links. Delete the empty folders, then recreate the links (next section).

---

## 5. Recreate the `fleet` links

Open **PowerShell** in `C:\Users\<You>\Downloads\fleet` (does not need “Run as administrator”):

```powershell
cd "C:\Users\<You>\Downloads\fleet"

foreach ($pair in @(
  @{ Name = 'worker';      Target = '..\shared-apex-static' },
  @{ Name = 'preview';     Target = '..\fleet-static-preview' },
  @{ Name = 'conversion';  Target = '..\static-conversion' },
  @{ Name = 'handoff';     Target = '..\static-fleet-handoff' }
)) {
  if (Test-Path -LiteralPath $pair.Name) {
    cmd /c "rmdir `"$($pair.Name)`""
  }
  New-Item -ItemType Junction -Path $pair.Name -Target (Resolve-Path $pair.Target) | Out-Null
  Write-Output ("OK {0} -> {1}" -f $pair.Name, (Resolve-Path $pair.Target))
}
```

Check: `dir worker` should show `README.md` and `scripts\` from shared-apex-static, not an empty directory.

---

## 6. Create `.env` in each project

### A) Fleet Worker — `shared-apex-static` (`fleet\worker`)

```powershell
cd "C:\Users\<You>\Downloads\shared-apex-static"
Copy-Item .env.example .env
notepad .env
```

Paste **only** `CLOUDFLARE_API_TOKEN` from the vault. Leave the rest as in `.env.example`:

```env
CLOUDFLARE_ACCOUNT_ID=f215f8ca79dd9d53b04618556593a581
CLOUDFLARE_API_TOKEN=
HOSTING_IP=174.136.29.214
HOSTING_IP_S1=165.140.157.43
FLEET_WORKER_NAME=fleet-static-worker
FLEET_KV_TITLE=HTML_FLEET
FLEET_R2_BUCKET=fleet-static-assets
```

Token needs: Workers Scripts, KV, R2, Zone DNS (read), Zone Workers Routes, Zone Cache Purge, Zone WAF (for wp-admin rules on rollback). Same Cloudflare account the live fleet already uses.

Fleet infra is **already live**. Do not re-provision unless `reports\fleet-infra.json` is missing:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-ProvisionFleet.ps1
```

### B) Preview / cutover — `fleet-static-preview` (`fleet\preview`)

```powershell
cd "C:\Users\<You>\Downloads\fleet-static-preview"
Copy-Item .env.example .env
```

Paste the **same** `CLOUDFLARE_API_TOKEN`. Account id, KV id, Worker name, and Server 2 hosting IP can match `shared-apex-static\.env`. Add Server 1 origin if missing:

```env
HOSTING_IP_S1=165.140.157.43
```

### C) 26-check / old convert — `static-conversion` (`fleet\conversion`)

```powershell
cd "C:\Users\<You>\Downloads\static-conversion"
Copy-Item .env.example .env
notepad .env
```

Same Cloudflare token. Fill `DEVSECSI_API_URL` and `DEVSECSI_API_KEY` from the vault **only** if you will call Adam’s provision API. Preview/cutover/rescrape of fleet sites do not need DevSecSi.

Smoke test (convert APIs):

```powershell
.\Invoke-TestApis.ps1
```

Expect all checks green. If this fails, stop and fix the token with the lead. Do not convert sites.

---

## 7. Constants

| Name | Value |
|------|--------|
| Server 2 origin (Batches 1–7 live apex) | `174.136.29.214` → Worker `fleet-static-worker` |
| Server 1 origin (new batches) | `165.140.157.43` → Worker `fleet-static-worker-server-1` |
| Shared KV | `HTML_FLEET` |
| Shared R2 | `fleet-static-assets` |
| Form JS (fleet inject) | `C:\Users\<You>\Downloads\fleet\assets\form-validation.js` |
| Stay-WordPress (never convert) | `roundrockfoundationrepairexperts.com`, `solidfoundationrepairofsavannah.com`, `solidfoundationrepairoflakeworth.com`, `azaleaparkfoundationrepair.com` |

Do not move Batches 1–7 live apex onto `fleet-static-worker-server-1`.

---

## 8. Prove the machine works

From `C:\Users\<You>\Downloads\fleet`:

```powershell
Test-Path .\worker\.env
Test-Path .\preview\.env
Test-Path .\conversion\.env
Test-Path .\worker\reports\fleet-infra.json
Test-Path .\assets\form-validation.js
Test-Path .\SOP-CONVERT-PREVIEW-CUTOVER-RESCRAPE.pdf
```

All should be `True`.

Cloudflare token (does not print the secret):

```powershell
cd "C:\Users\<You>\Downloads\shared-apex-static"
$tok = (Get-Content .env | Where-Object { $_ -match '^CLOUDFLARE_API_TOKEN=' }) -replace '^CLOUDFLARE_API_TOKEN=',''
$h = @{ Authorization = "Bearer $tok" }
(Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/accounts/f215f8ca79dd9d53b04618556593a581/workers/scripts/fleet-static-worker" -Headers $h).success
```

Expect `True`. If it errors, the token is wrong or missing Workers Scripts Read.

---

## 9. How you run jobs after setup

Always `cd` into `C:\Users\<You>\Downloads\fleet` first (or into `worker` / `preview` / `conversion`).

Examples (full steps are in the convert SOP):

```powershell
cd "C:\Users\<You>\Downloads\fleet\preview"
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-PreviewStaticOnFleet.ps1 -SitesCsv .\sites\YOUR.csv -OriginIp 174.136.29.214 -WorkerName fleet-static-worker

cd "C:\Users\<You>\Downloads\fleet\worker"
powershell -ExecutionPolicy Bypass -File .\scripts\Invoke-WpOriginToFleet.ps1 -SitesCsv .\reports\YOUR.csv -HostingIp 174.136.29.214 -SkipRoutes -SkipAssets
```

Put domain lists in `fleet\sites\` (column `Domain`). Copy finished spreadsheets into `fleet\audits\`.

---

## 10. Then read the operating SOP

Open:

`C:\Users\<You>\Downloads\fleet\SOP-CONVERT-PREVIEW-CUTOVER-RESCRAPE.pdf`

That document is Path A (new convert → `static.*` → apex), Path B (rescrape via hosting IP), Path C (rollback to WordPress, edit, rescrape), form-validation inject, and Stay-WordPress.

Do not convert or cut over apex until that SOP is clear. First real job: **one** non-critical site, `static.*` only.

---

## 11. Do not

| Do not | Why |
|--------|-----|
| Commit or zip `.env` | Token in git / shared drive |
| Paste the token into chat | Vault only |
| Re-provision fleet “to be safe” | Infra is already live; you can overwrite routes |
| Skip Stay-WordPress excludes | Never convert those four domains |
| Scrape public HTTPS on a live fleet site | Recopies stale KV |
| Use `Downloads\form-validation.js` | Missing popup listeners; use `fleet\assets\form-validation.js` |
| Omit `workerName` on a new-batch Adam scrape | Lands `static.*` on Server 2 |
| Cut over apex without `-IConfirmApexCutover` | Script will refuse; that is intentional |

---

## 12. Setup checklist

- [ ] Five folders under `Downloads\` with the names in section 2
- [ ] `fleet\worker`, `preview`, `conversion`, `handoff` point at the real projects
- [ ] `.env` in worker, preview, conversion — token from vault, not from chat
- [ ] `python --version` and `curl.exe --version` work
- [ ] `Invoke-TestApis.ps1` green if you will use conversion
- [ ] Cloudflare Workers script probe returns `True`
- [ ] `fleet-infra.json` and `fleet\assets\form-validation.js` exist
- [ ] Convert SOP PDF opens from `fleet\`
- [ ] No `.env` in the zip you send the next person

---

## 13. Related docs

- [SOP-CONVERT-PREVIEW-CUTOVER-RESCRAPE.pdf](./SOP-CONVERT-PREVIEW-CUTOVER-RESCRAPE.pdf) — operating workflow after this setup
- [SOP-CONVERT-PREVIEW-CUTOVER-RESCRAPE.md](./SOP-CONVERT-PREVIEW-CUTOVER-RESCRAPE.md)
- `static-fleet-handoff\02-pc-setup.md` — shorter sibling of this SOP
- `shared-apex-static\README.md` — fleet Worker folder
- `fleet-static-preview\README.md` — preview / cutover scripts
