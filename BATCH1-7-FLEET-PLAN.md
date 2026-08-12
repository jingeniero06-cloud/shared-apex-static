# Batch 1–7 → Shared Fleet Plan (1 Worker / 1 KV / 1 R2)

**Status:** PLAN ONLY — do not run until approved  
**Date:** 2026-08-12  
**Repo:** `shared-apex-static` (do not modify `static-conversion`)

## Verdict

**Yes — this is a good plan** for Batch 1–7 live-static sites, with the guardrails below.

You already proved it on a **50/50 spike** (`fleet-static-worker` + `HTML_FLEET` + `fleet-static-assets`, all `x-source: kv`).

---

## Target architecture (1:1)

| Piece | Name | Role |
| --- | --- | --- |
| **1 Worker** | `fleet-static-worker` | Serves every migrated hostname |
| **1 KV** | `HTML_FLEET` | Keys `{host}:html:{path}` |
| **1 R2** | `fleet-static-assets` | Keys `{host}:asset:{path}` |

Per-site `{domain}-worker` / `HTML_{domain}` / `{domain}-assets` become **legacy** after cutover (delete later to free the 500 Worker / 1000 KV caps).

---

## Scope (Batch 1–7)

| Set | Count | Notes |
| --- | ---: | --- |
| Live static (Aug 10 list) | **467** | `Batch1-7_Static_Sites_20260810-171123.csv`, mostly `x-source: kv` |
| Already on fleet (spike) | **50** | Done — skip on re-run |
| Remaining from that list | **~417** | Primary migrate queue |
| Stay-WordPress excludes | **23** | Never migrate / never convert |
| Batch 7 | mostly WP | Not in the 467 static list — convert later **into fleet**, not new per-site Workers |

**Do not migrate:** stay-WP excludes, known rollbacks still on WordPress, zones without a working per-site KV (nothing to copy).

---

## Cloudflare limits (why this works)

| Limit | Cap | Your situation |
| --- | ---: | --- |
| Workers / account | 500 | At cap today — fleet frees slots after old Workers deleted |
| KV namespaces | 1,000 | ~654 now — fleet collapses many into 1 |
| **Routed zones / Worker** | **1,000** | 467 ≪ 1000 — **one Worker is enough for Batch 1–7 static** |
| Zones on account | ~1,628 | Full portfolio later may need a **2nd fleet Worker** if >1000 routed zones |

---

## Cutover method (required)

**Copy-then-switch** (proven). Do **not** warm-only / route-first.

1. Resolve old per-site Worker → its KV namespace  
2. Copy **page HTML only** into `HTML_FLEET` as `{host}:html:{path}` (skip wp-includes / junk)  
3. Optionally copy R2 assets as `{host}:asset:{path}` (or warm after)  
4. Replace zone routes: `domain/*` + `www.domain/*` → `fleet-static-worker`  
5. Verify: `200` + `x-source: kv` + `x-fleet-host: {domain}`  
6. Log row to migrate-summary CSV  

Origin fill via hosting IP often **403** — HTML must be in KV before route flip.

---

## Rollout waves (suggested)

| Wave | Sites | Purpose |
| --- | --- | --- |
| 0 | 50 spike | **DONE** |
| 1 | Batch 1 remain (~19−overlap) | Small canary |
| 2 | Batch 2–3 remain | Medium |
| 3 | Batch 4–5 remain | Medium |
| 4 | Batch 6 remain | Finish Aug-10 static list |
| 5 | Cleanup | Delete idle per-site Workers/KV (after soak) |
| 6 | New converts / B7 WP→static | Scrape **directly into fleet** + add routes only |

Pause between waves if failure rate &gt; 0 or verify flakes.

---

## Success criteria

- Homepage `200`, `x-source: kv`, `x-fleet-host` set  
- Assets `200` / `x-source: r2` (or warm to r2)  
- No mass 403 “Origin error”  
- Summary CSV: OK count = attempted  
- Stay-WP list untouched  

## Post-cutover audit checklist

Run Sean’s audit (`Invoke-AuditStaticSite.ps1` / portfolio audit) and fail the site if any of these are true:

| Flag | Fail when |
| --- | --- |
| Missing files | CSS/JS/fonts/other assets 404 |
| Pictures not showing | Image URLs on the page 404 |
| Logo | Header/logo image missing or 404 |
| No phone field | Contact form has no phone / tel input |
| CallRail form tracking not detected on the page | No CallRail/CallTrk form-capture or swap script |
| No reCAPTCHA spam protection on the form | No reCAPTCHA, hCaptcha, or Turnstile |
| No form on this page | Homepage has no contact form markup |  

---

## Risks & mitigations

| Risk | Mitigation |
| --- | --- |
| Route flip before KV copy → 403 | Enforce copy-then-switch; refuse WarmOnly for bulk |
| KV API rate / slow copy | Batch waves; page-filter already reduces junk |
| &gt;1000 routed zones later | Split to `fleet-static-worker-2` by letter/batch |
| Accidental stay-WP migrate | Exclude file + preflight domain denylist |
| Delete old Worker too early | Soak ≥48h; keep old KV until verify pass |
| Single Worker blast radius | Canary waves; keep rollback = restore old routes |

---

## Explicit non-goals (for this plan)

- Do **not** buy Workers for Platforms yet  
- Do **not** create new per-site Workers for Batch 7 / new sites  
- Do **not** edit `static-conversion` for fleet work  
- Do **not** downgrade/delete Business on `citythrive.com` as part of this migrate (separate billing decision)  

---

## When you say go

1. Build CSV = Aug-10 static list − spike − excludes − known WP rollbacks  
2. Dry-run first 10 of Batch 1 remain  
3. Proceed wave-by-wave with summary + canvas/verify  
4. After soak, delete orphan per-site Workers to free the 500 cap  

**Estimated remaining:** ~417 sites from the current static list (plus later B7 converts into the same fleet).
