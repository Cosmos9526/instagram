# Rival price audit — 2026-09-30

Scope: all 16 saved competitor sites, with **Claude Max** and exact **20x** matching. Other products use the same generic discovery and WooCommerce parsing, but this audit does not certify every product on every site.

Three local runs and three isolated-server runs were requested. Raw, timestamped server results are stored in `server-audit-2026-09-30.json` after completion. Prices are snapshots, not a promise of stock or an interchangeable offer. Keep first-order, renewal, duration, and other conditions in the offer name.

| Site | Strategy and evidence | Claude Max outcome / limitation |
|---|---|---|
| parspremium.ir | Product option state, numeric unit checked against displayed Toman price | Separate 5x / 20x offers; aggregate Pro-to-Max range is not used |
| cafearz.com | `/services/ai/claude`, also inspected public order page | Max mentioned; no verifiable public price exposed. Show price unavailable |
| dicardo.com | Visible product option cards at `/product/claude-ai` | 5x price; never reuse Pro amount for Max; no priced 20x card in inspected page |
| numberland.ir | Visible option cards at `/account/claude-ai` | Three distinct Max offers; preserve conditions, including no-warranty labels already in the product name |
| license-market.ir | `/product/Claude-AI`, product state and schema | No exact Max price verified; do not call the whole site unavailable |
| asangem.com | Visible catalogue priceboxes at `/game/claude/` | 5x / 20x. JSON-LD incorrectly says IRR; visible amounts are Toman. Values changed between audit runs |
| account4all.ir | Claude product and WooCommerce options | Pro options observed; no exact Max offer verified |
| g1verify.ir | `/product/claude-max/`, visible inquiry text | Product exists; seller requires a quote. No invented number |
| kharidaccount.ir | Selected WooCommerce option `price_html` | Four Max options, first order / renewal. Raw display_price is Rials while rendered price_html is Toman |
| licenseyar.ir | Direct Claude Pro product and discovery | Pro observed locally; intermittent server access. No exact Max price verified |
| premium24.ir | `/product/calude-ai-pricing`, product options | Pro options observed; no exact Max price verified |
| codinocard.ir | Public `/api/products` on api.codinocard.ir; compared with browser product page | 5x / 20x. Selling price is Toman; variant currency denotes USD face value. Static HTML is stale |
| majazite.com | `/product/claude-ai/`, selected option price_html | Separate 5x / 20x; Pro prices excluded |
| giftpin.ir | `/product/claude-pro`, schema and page | Pro observed; no exact Max price verified |
| khanehlicense.ir | `/product/claude-pro/`, product options | Pro observed; no exact Max price verified |
| iranicard.ir | Public page response | Browser-verification challenge. Mark blocked, not product absent |

## Verification

- Saved minimal public markup fixtures cover the two factor-of-ten failures, exact variant matching, option conditions, inquiry-only products, and Codinocard's selling price versus USD face value.
- No hardcoded live price, exchange-rate estimate, fabricated availability, authenticated competitor session, or third-party proxy is used.
- Discovery rejects cart, checkout, comment-pagination and action-query links. Bounded requests retry transient empty responses once.
- `not_found` means the bounded lookup could not verify a matching price; it does not prove the competitor does not sell the product.
- Reproduce a targeted read-only server check with `python -m app.admin_price_check --sites asangem.com,majazite.com --products "Claude Max"`.
- The previously added admin_price_probe and admin_price_check tools are preserved.

## Intermittent access

The second server run missed Majazite after the first run found both plans; the third run found 20x again. Premium24 also changed from a readable page to unreachable. The app therefore preserves a verified snapshot for up to 24 hours **with a stale label and its original timestamp** if a subsequent request fails. It never labels that snapshot as a fresh price, never crosses queries, and never reuses legacy results from before these currency corrections.

## Round 2 (stability and coverage)

- `admin_price_check` now prints a `reason` column (`timeout_connect`, `timeout_read`, `dns`, `tls`, `connect_error`, `empty_body`, `http_NNN`, `challenge`, `budget_exhausted`) and the offer `duration`. Each price row also carries `reason` in the API result (added field only).
- Stability: each page is tried up to 3 times with 0.6 s / 1.2 s backoff (not for permanent 4xx/DNS). A slow response extends that site's budget from 40 s up to 65 s.
- Numeric pagination of one product page (`/product/claude-ai/2`, `/3`) is one page and is fetched once.
- numberland.ir: `duration` is filled only when the card name or tooltip states it; otherwise it stays empty (never assumed).
- **Not yet certified:** the full 16 sites x 7 products matrix (ChatGPT Plus, Claude Pro, Claude Max, Gemini, Cursor, Midjourney, Perplexity) needs a run on the server. The parspremium.ir 255,500 Toman value for ChatGPT Plus / Cursor / Perplexity is unresolved until its product pages are inspected; the current adapter lists every product option with its own price rather than one "from" value.

Run the matrix: `python -m app.admin_price_check` (no arguments = all 16 sites, default products).
