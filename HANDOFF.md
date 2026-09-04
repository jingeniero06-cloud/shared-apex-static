# Handoff — shared-apex-static (Part B)

**Start here for the combined convert + fleet kit:**  
`..\static-fleet-handoff\README.md`

This folder is **fleet ops only** (Workers, KV, R2, preview/cutover/rescrape).  
WordPress → Cyotek static conversion lives in `static-conversion` (Part A). Do not mix those jobs.

## Operators

| Role | Who |
|------|-----|
| Conversion / Cloudflare | John |
| WordPress origin | Usman |
| QA | Sean |
| Lead / Adam API | Mike / Adam |

Full RACI + process map: [`README.md`](./README.md).

## Docs (open these — don’t reinvent)

| Need | Link |
|------|------|
| New machine | [SOP-MACHINE-SETUP.html](./docs/SOP-MACHINE-SETUP.html) · [PDF](./docs/SOP-MACHINE-SETUP.pdf) |
| Convert / preview / cutover / rescrape | [SOP-CONVERT-PREVIEW-CUTOVER-RESCRAPE.html](./docs/SOP-CONVERT-PREVIEW-CUTOVER-RESCRAPE.html) |
| Process guide | [conversion-process-guide.html](./docs/conversion-process-guide.html) |
| aaPanel `dev.` / `static.` / apex | [aapanel-dev-workflows.html](./docs/aapanel-dev-workflows.html) |
| Cursor setup | [SOP-CURSOR-SETUP.html](./docs/SOP-CURSOR-SETUP.html) |
| Live example | [SOP-LIVE-EXAMPLE.html](./docs/SOP-LIVE-EXAMPLE.html) |

## Share the kit

Zip / shared drive (GitHub not required). **Strip `.env` before sharing.** Teammates create their own `.env` from `.env.example` and paste the Cloudflare token from the team lead.
