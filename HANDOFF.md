# Handoff package

**Start here for the combined convert + fleet handoff:**

`..\static-fleet-handoff\README.md`

This folder (`shared-apex-static`) is **Part B — shared fleet migrate only**.  
WordPress → static conversion lives in `static-conversion` (Part A).

**New machine setup:**  
[`docs/SOP-MACHINE-SETUP.html`](./docs/SOP-MACHINE-SETUP.html) · [PDF](./docs/SOP-MACHINE-SETUP.pdf)

**Operating SOP** (preview → apex cutover → origin-IP rescrape, including rollback-to-WP edit loop):  
[`docs/SOP-CONVERT-PREVIEW-CUTOVER-RESCRAPE.html`](./docs/SOP-CONVERT-PREVIEW-CUTOVER-RESCRAPE.html)

**aaPanel staging** (`dev.` / `static.` / apex diagrams):  
[`docs/aapanel-dev-workflows.html`](./docs/aapanel-dev-workflows.html)

**How teammates get this:** kit zip / shared drive (not GitHub). Strip `.env` before sharing.

Do not modify `static-conversion` for fleet Worker/KV/R2 work.
