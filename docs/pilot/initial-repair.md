# Initial usability repair — 2026-09-28

Observed deployment: /opt/postyar, main at 3d6a4ea, own API on 127.0.0.1:8200. Existing HTTPS proxy is unchanged. Handoff predates merged competitor work.

Observed UX: first load showed a blank page before login; whole app was constrained to 480px even on desktop. The dark-mode image wordmark had poor contrast. Two Rahboom-related projects exist; neither contains competitors. No project data has been edited pending owner's selection.

Changes: neutral visible title pending naming decision; loading/retry shell; desktop sidebar at 900px and wider with mobile navigation retained; readable login branding; corrected bottom-nav text overflow; HTTP timeout covers complete response body; invalid JSON becomes an actionable API error. Static precompressed files now go through StaticFiles path containment checks.

Prepared content: rahboom-start.md. Contains editorial draft material, no claimed current trends, verified pricing or promised product availability. Competitor seeds are owner-supplied and must not be marked verified merely because they are present.

This is a first repair, not a complete product redesign. Still needed: owner selection of the intended Rahboom project; confirm actual catalog; import competitors; review authenticated workflow with real data; add per-slide image-prompt display and a standalone cover workflow; distinguish fresh news from evidenced trends; improve production status and calendar experience. The existing schema mixes video format with content objective, which warrants a separately tested migration rather than an incidental rename.

Low-resource deployment: build web locally using Flutter, gzip JS/WASM/JSON/font/HTML files; package under /opt/postyar/releases/<release>/web, include static.py and deploy/Dockerfile.prebuilt. Tag the project's current image for rollback; build this Dockerfile with BASE_IMAGE set to that tag and output postyar-app:latest. Only recreate api, worker and scheduler using `docker compose -p postyar up -d --no-build --no-deps api worker scheduler`. Do not change Caddy, ports or database. Roll back by retagging the saved project image to postyar-app:latest and repeating that same targeted compose command.
