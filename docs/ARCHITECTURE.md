# Postyar — v1 Architecture & Product Design

Instagram/Telegram content-automation studio. Two v1 features:
**A. Trend-to-Content Engine** (single slide + carousel) and
**B. Long-form AI video from short clips** (continuity-preserving multi-clip video).

Decisions at a glance:

| Concern | Choice | Why |
|---|---|---|
| API | FastAPI (Python 3.12), Pydantic v2, SQLAlchemy 2 + Alembic | async I/O for API-bound work; one language across pipeline |
| DB | PostgreSQL 16 (single container, `shared_buffers=128MB`) | durable jobs + ledger in one transactional store |
| Queue | **Postgres job table + `SELECT … FOR UPDATE SKIP LOCKED`** (via a ~150-line worker, or `procrastinate`) | no extra Redis process (~50–100MB saved), job state and credit holds commit in the *same transaction*, trivially inspectable with SQL. Celery is overkill (broker + beat + result backend, ~300MB+ idle). RQ needs Redis and loses jobs on Redis restart without AOF. |
| Media storage | Local volume `/data/media` (v0) → S3-compatible (Cloudflare R2) in v1 | R2 has free egress; Instagram Graph API needs a public URL anyway |
| Slide renderer | HTML/CSS templates rendered by **Playwright Chromium** (single persistent browser, 1 page at a time) | best RTL/Persian shaping (HarfBuzz), web fonts (Vazirmatn), CSS layout; Pillow cannot shape Persian correctly without extra work |
| Video | **FFmpeg 7** (static build) in a dedicated worker container, concurrency = 1 | deterministic, no GPU needed for stitching at 1080p/30s |
| LLM text | existing model gateway (Claude / Gemini) | reliability handled there |
| Vision QA | multimodal LLM via same gateway | frames are images; cheap relative to video |
| Image gen | external API (e.g. Imagen / GPT-Image / Flux via fal.ai) behind an adapter | swappable |
| Video gen | external image-to-video API (Veo 3 / Kling 2.x / Runway Gen-4 via fal.ai) behind an adapter; must support **first-frame image conditioning** | last-frame seeding is non-negotiable |
| Frontend | Flutter (mobile + web build), `flutter_localizations`, `intl`, `Directionality` driven by brand/UI locale | requirement |
| Edge | existing Caddy; **add one site block only** (`api.postyar.<domain>`) | never touch other routes |

---

## 1. SYSTEM ARCHITECTURE

```
                         ┌────────────────────────────── Flutter app (fa/en, RTL/LTR) ──────────────────────────────┐
                         │  Brand Kit · Single-Slide Studio · Carousel Studio · Video Studio · Approvals · Credits  │
                         └───────────────────────────────────────┬──────────────────────────────────────────────────┘
                                                                 │ HTTPS (existing Caddy, new site block only)
┌────────────────────────────────────────── docker-compose "postyar" (hard limits: 2.5GB RAM / 3 CPU total) ──────────────┐
│                                                                                                                          │
│  ┌──────────────┐  enqueue(job) + credit HOLD in 1 tx   ┌─────────────────────────── PostgreSQL ──────────────────────┐ │
│  │ api (FastAPI)│──────────────────────────────────────▶│ brands · templates · trends · scenarios · generation_jobs    │ │
│  │ 256MB/0.5cpu │◀──── poll / SSE job status ───────────│ video_clips · continuity_bibles · credit_ledger · posts      │ │
│  └──────┬───────┘                                       │ jobs (queue table)            384MB / 0.5cpu                  │ │
│         │                                               └──────▲──────────────▲─────────────────▲─────────────────────┘ │
│         │ CRUD                                                  │ SKIP LOCKED  │                 │                       │
│         ▼                                                       │              │                 │                       │
│  Brand Kit store (tables + /media/brand assets)                 │              │                 │                       │
│                                                                 │              │                 │                       │
│  ┌────────────────────────── worker-io (async, conc=8) 384MB/0.75cpu ─────────┐ │   ┌─ worker-heavy (conc=1) 1.2GB/1.5cpu ─┐│
│  │ Trend ingestion   → Telegram (Telethon), IG (manual paste / Apify)          │ │   │ Template engine (Playwright render)  ││
│  │ Scenario engine   → LLM gateway (match, write, slot-fill)                   │ │   │ FFmpeg stitcher/effects worker       ││
│  │ Image gen         → image API                                               │ │   │  - last-frame extract                ││
│  │ Video clip orchestrator → video API (poll/webhook)                          │─┼──▶│  - frame sampling for QA             ││
│  │ Continuity validator    → vision LLM on sampled frames                      │ │   │  - xfade stitch, audio, captions     ││
│  │ Publisher         → Instagram Graph API / Telegram Bot API                  │ │   │  - pixelate/blur/freeze/zoom         ││
│  └─────────────────────────────────────────────────────────────────────────────┘ │   └──────────────────────────────────────┘│
│  ┌──────────── scheduler (APScheduler, 64MB) ──────────┐                          │                                           │
│  │ cron: trend refresh, scheduled_posts → enqueue,      │─────────────────────────┘                                           │
│  │ template-of-the-day recompute, stale-hold reaper     │                                                                      │
│  └──────────────────────────────────────────────────────┘      volume: /data/media (clips, frames, renders)                   │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
          external: LLM gateway · image API · video API · vision LLM · IG Graph API · Telegram
```

The key structural decision: **two worker pools split by resource profile**.
Everything that just waits on an HTTP API (LLM, image, video gen polling) runs
in an async `worker-io` process that can hold many jobs at once for ~0 CPU.
Everything that burns RAM/CPU locally (Chromium, FFmpeg) runs in `worker-heavy`
with **concurrency 1**, enforced twice: the worker only claims `queue='heavy'`
jobs one at a time, and a Postgres advisory lock (`pg_try_advisory_lock(4242)`)
guards the section in case someone scales the container.

| Component | Calls | Stores | Coordinated by | Why this shape (low-RAM, no GPU, shared box) |
|---|---|---|---|---|
| **Brand Kit store** | nothing (pure CRUD); optionally LLM once to "normalize" free-text tone into structured fields | `brands`, logo/fonts in `/media/brands/{id}` | api | Loaded into every prompt; kept as structured JSON so prompts are deterministic and cacheable (prompt caching on the brand block). |
| **Trend ingestion** | Telegram: Telethon reading public channels you list; IG: manual paste in v0, Apify IG hashtag/reels actor later | `trends` (normalized, deduped by `content_hash`, `expires_at = fetched+24h`) | scheduler (every 3h) → `worker-io` | No official IG trends API; isolate scraping behind one adapter so breakage is contained. Text-only storage, tiny footprint. |
| **Scenario engine** | LLM gateway: trend-match → scenario → slot-fill (3 calls) | `scenarios` (JSON), prompt+response logs | job pipeline in `worker-io` | Cheap text calls first; expensive image calls only after scenario passes validation. |
| **Template engine** | Playwright Chromium (local) | `templates` (HTML + slot schema), rendered PNGs | `worker-heavy`, conc=1 | Text rendered by HTML/CSS = pixel-perfect brand fonts and correct Persian shaping. One persistent browser (~250MB), pages reused, restarted every 200 renders to cap leaks. |
| **Image gen** | image API (text-to-image, no text in image; negative prompt "no text, no letters") | `generation_jobs` output → `/media/img` | `worker-io` | Generative pixels only for the background/hero image slot. |
| **Video clip orchestrator** | video API (image-to-video / first-frame conditioning), enqueues heavy FFmpeg subjobs | `video_clips`, `continuity_bibles` | state machine per `generation_job` in `worker-io` | Long-running (1–5 min/clip) polling → must be async and cheap to hold. |
| **Continuity validator** | vision LLM with (bible text, prev last frame, 4 sampled frames of new clip) | `video_clips.qa_report` JSON + scores | orchestrator | Decides accept / regenerate one clip; budgets enforce stop. |
| **FFmpeg stitcher/effects worker** | ffmpeg/ffprobe (local) | final MP4, thumbnails, frames | `worker-heavy`, conc=1, `-threads 2`, `nice 10` | Deterministic, CPU-only; 30s 1080p stitch ≈ 20–60s at `-preset veryfast`. Memory ~300–500MB peak. |
| **Credit/billing ledger** | nothing external (payment gateway e.g. Zarinpal/Stripe later) | `credit_ledger` (append-only), `credit_balances` (materialized) | api + workers, same DB tx as job state | HOLD before expensive call, CAPTURE on success, RELEASE on platform failure. Append-only = auditable. |
| **Scheduler** | enqueues jobs only | `scheduled_posts`, `schedules` | APScheduler in its own tiny container, jobstore = Postgres | Does no work itself so a crash never kills heavy jobs. |
| **Approval/publish queue** | IG Graph API (container → publish), Telegram Bot API `sendPhoto/sendMediaGroup/sendVideo` | `scheduled_posts` status | api (approve) → scheduler (due) → `worker-io` | Human-in-the-loop by default; auto-publish is a per-brand opt-in later. |

**Compose resource limits (sum ≈ 2.4 GB, 3.25 CPU):**
```yaml
services:
  db:            { mem_limit: 384m, cpus: 0.5 }
  api:           { mem_limit: 256m, cpus: 0.5 }
  worker-io:     { mem_limit: 384m, cpus: 0.75 }
  worker-heavy:  { mem_limit: 1200m, memswap_limit: 1200m, cpus: 1.5, pids_limit: 256 }
  scheduler:     { mem_limit: 96m,  cpus: 0.25 }
```
`memswap_limit == mem_limit` so the container is OOM-killed *inside its own
cgroup* instead of pressuring the host (no host swap exists). Set
`oom_score_adj: 500` on worker-heavy so the kernel sacrifices it before GitLab.
All services on an internal network; only `api` joins the network Caddy uses.

Caddy — append only this block (separate file via `import`):
```
api.postyar.example.com {
    reverse_proxy postyar-api:8000
    request_body max_size 50MB
}
```

---

## 2. DATA MODEL (PostgreSQL)

```sql
-- tenancy
CREATE TABLE users (
  id uuid PRIMARY KEY, email citext UNIQUE, ui_locale text DEFAULT 'fa', created_at timestamptz DEFAULT now());

CREATE TABLE brands (
  id uuid PRIMARY KEY, owner_id uuid REFERENCES users,
  name text NOT NULL, industry text NOT NULL,
  content_language text NOT NULL CHECK (content_language IN ('fa','en','fa+en')),
  tone jsonb NOT NULL,             -- {"formality":"friendly","humor":"light","voice_examples":["..."]}
  audience jsonb NOT NULL,         -- {"age":"22-35","city":"Tehran","interests":[...]}
  products jsonb NOT NULL,         -- [{"id":"p1","name":"...","desc":"...","price":"...","url":"..."}]
  colors jsonb NOT NULL,           -- {"primary":"#0E7C66","secondary":"#F4B400","bg":"#FFFFFF","text":"#111"}
  fonts jsonb DEFAULT '{"fa":"Vazirmatn","en":"Inter"}',
  logo_path text,
  forbidden_topics text[] NOT NULL DEFAULT '{}',
  cta_style jsonb NOT NULL,        -- {"type":"dm|link|call|visit","phrase_examples":["..."]}
  hashtags_fixed text[] DEFAULT '{}',
  ig_account_id text, tg_channel_id text,
  created_at timestamptz DEFAULT now(), updated_at timestamptz);

CREATE TABLE templates (
  id uuid PRIMARY KEY,
  code text UNIQUE,                -- 'quote_bold_01'
  mode text NOT NULL CHECK (mode IN ('single','carousel_cover','carousel_body','carousel_cta')),
  format text NOT NULL,            -- 'quote','listicle','before_after','tip','promo','news_hook'
  aspect text NOT NULL DEFAULT '4:5',  -- 1080x1350
  html text NOT NULL,              -- Jinja2 HTML/CSS using brand vars
  slots jsonb NOT NULL,            -- [{"key":"headline","type":"text","max_chars":{"fa":40,"en":45},"required":true},
                                   --  {"key":"body","type":"text","max_chars":{"fa":140,"en":160}},
                                   --  {"key":"image","type":"image","aspect":"1:1","style_hint":"product hero, no text"}]
  supports_rtl boolean DEFAULT true,
  perf_score real DEFAULT 0,       -- recomputed daily (template-of-the-day)
  active boolean DEFAULT true);

CREATE TABLE template_performance (   -- feeds Template of the Day
  template_id uuid REFERENCES templates, day date, source text,  -- 'own_posts'|'trend_sample'
  impressions int, engagement_rate real, saves int, n_posts int,
  PRIMARY KEY (template_id, day, source));

CREATE TABLE trends (
  id uuid PRIMARY KEY, source text CHECK (source IN ('instagram','telegram','manual')),
  source_ref text, title text, summary text, hashtags text[], lang text,
  format_detected text,            -- 'reel','carousel','meme','quote'...
  engagement jsonb, content_hash text UNIQUE,
  fetched_at timestamptz DEFAULT now(), expires_at timestamptz);
CREATE INDEX ON trends (expires_at);

CREATE TABLE scenarios (
  id uuid PRIMARY KEY, brand_id uuid REFERENCES brands, trend_id uuid REFERENCES trends NULL,
  mode text CHECK (mode IN ('single','carousel','video')),
  match_report jsonb,              -- output of trend-matching prompt
  body jsonb NOT NULL,             -- scenario JSON
  status text DEFAULT 'draft',     -- draft|rendered|approved|rejected
  created_at timestamptz DEFAULT now());

CREATE TABLE generation_jobs (          -- one per user-visible "generate" action
  id uuid PRIMARY KEY, brand_id uuid REFERENCES brands, user_id uuid REFERENCES users,
  kind text CHECK (kind IN ('single','carousel','video')),
  state text NOT NULL,             -- state machine, see §3/§4
  input jsonb,                     -- user idea, template choice, slide count...
  scenario_id uuid REFERENCES scenarios,
  credit_hold_id uuid,             -- ledger row of the HOLD
  cost_estimate int, cost_actual int,
  regen_budget_remaining int DEFAULT 0,
  output jsonb,                    -- {"slides":["/media/..png"],"video":"/media/..mp4"}
  error text, created_at timestamptz DEFAULT now(), updated_at timestamptz);

CREATE TABLE jobs (                     -- the queue
  id bigserial PRIMARY KEY, queue text NOT NULL,   -- 'io'|'heavy'
  task text NOT NULL, payload jsonb NOT NULL,
  generation_job_id uuid REFERENCES generation_jobs,
  status text DEFAULT 'queued',    -- queued|running|done|failed
  attempts int DEFAULT 0, max_attempts int DEFAULT 3,
  run_after timestamptz DEFAULT now(), locked_at timestamptz, last_error text);
CREATE INDEX jobs_claim ON jobs (queue, run_after) WHERE status='queued';

CREATE TABLE continuity_bibles (
  id uuid PRIMARY KEY, generation_job_id uuid UNIQUE REFERENCES generation_jobs,
  bible_text text NOT NULL,        -- the VERBATIM block injected into every clip prompt
  bible_json jsonb NOT NULL,       -- structured: characters, wardrobe, location, lighting, camera, style, palette
  reference_image_path text,       -- optional keyframe generated first (character ref)
  aspect text DEFAULT '9:16', fps int DEFAULT 24, resolution text DEFAULT '1080x1920');

CREATE TABLE video_clips (
  id uuid PRIMARY KEY, generation_job_id uuid REFERENCES generation_jobs,
  idx smallint NOT NULL,           -- 0..3
  attempt smallint NOT NULL DEFAULT 1,
  action_prompt text NOT NULL,     -- per-clip action/camera text
  full_prompt text NOT NULL,       -- bible_text + action_prompt, as sent
  seed_frame_path text,            -- previous accepted clip's last frame (null for idx 0 → ref image)
  provider text, provider_job_id text, duration_s real,
  raw_path text, normalized_path text, last_frame_path text,
  qa_scores jsonb,                 -- {"face":0.9,"clothing":0.8,...,"overall":0.86}
  qa_report jsonb, status text,    -- pending|generating|qa|accepted|rejected|failed|refused
  cost_credits int, created_at timestamptz DEFAULT now(),
  UNIQUE (generation_job_id, idx, attempt));

CREATE TABLE effect_passes (
  id uuid PRIMARY KEY, generation_job_id uuid REFERENCES generation_jobs,
  effects jsonb NOT NULL,          -- output of effect-detection prompt, validated
  status text, output_path text);

-- credits: append-only ledger + cached balance
CREATE TABLE credit_ledger (
  id uuid PRIMARY KEY, user_id uuid REFERENCES users,
  entry_type text CHECK (entry_type IN ('purchase','grant','hold','capture','release','refund','adjust')),
  amount int NOT NULL,             -- +purchase/grant/release/refund, -hold; capture is 0-amount status marker
  hold_ref uuid,                   -- capture/release point to their hold
  generation_job_id uuid, reason text, created_at timestamptz DEFAULT now());
CREATE TABLE credit_balances (user_id uuid PRIMARY KEY, available int NOT NULL CHECK (available >= 0));

CREATE TABLE scheduled_posts (
  id uuid PRIMARY KEY, brand_id uuid REFERENCES brands, generation_job_id uuid REFERENCES generation_jobs,
  channel text CHECK (channel IN ('instagram','telegram')),
  caption text, hashtags text[], publish_at timestamptz,
  status text DEFAULT 'pending_approval',  -- pending_approval|approved|publishing|published|failed|rejected
  approved_by uuid, external_post_id text, error text);

CREATE TABLE schedules (               -- "generate 3 posts/week"
  id uuid PRIMARY KEY, brand_id uuid REFERENCES brands, cron text, kind text, params jsonb, active boolean);
```

Relationships: `brand 1─* scenario 1─1 generation_job 1─* video_clips`,
`generation_job 1─1 continuity_bible`, `generation_job 1─* jobs`,
`generation_job 1─* scheduled_posts`, `user 1─* credit_ledger`.

`credit_balances.available >= 0` CHECK makes overdraft impossible: a HOLD is
`UPDATE credit_balances SET available = available - :n` in the same
transaction as `INSERT INTO jobs`; if the check fails, nothing is enqueued.

---

## 3. FEATURE A — TREND-TO-CONTENT ENGINE

### 3.1 Flow

```
[User taps Generate] (Single Studio or Carousel Studio — separate screens, separate template sets)
  │
  1. API: estimate cost (§5) → TX{ HOLD credits ; INSERT generation_job(state=queued) ; INSERT jobs(io,'trend_match') }
  │
  2. worker-io: load brand + candidate trends (not expired, lang matches; or user-pasted trend; or "no trend, evergreen")
  │     top 15 by recency×engagement, pre-filtered by forbidden_topics keyword blocklist (cheap, deterministic)
  3. LLM ▶ PROMPT A1 Trend-Matching → JSON {matches[], rejected[]}
  │     if no match with fit_score ≥ 0.6 → fallback "evergreen" scenario on best product (no trend) and tell user
  4. TEMPLATE-OF-THE-DAY: SQL picks top template per (mode, format) by perf_score;
  │     Flutter shows it pre-selected with a ⭐ "Template of the Day" badge; user may override (no extra cost).
  │     For auto/scheduled runs it's chosen automatically.
  5. LLM ▶ PROMPT A2 Scenario-Writing (mode-aware: single → 1 slide; carousel → N slides, cover/body/CTA roles)
  6. LLM ▶ PROMPT A3 Slot-Filling per template (receives exact slot schema + char limits)
  │     Validator (Python): len(text) ≤ max_chars[lang] (grapheme count), required slots present,
  │     forbidden words absent, no Latin digits in fa text (convert to ۰-۹). On failure: one LLM repair call
  │     with the exact errors; if still failing → hard truncate at word boundary + "…".
  7. Image gen: for every image slot → image API with scenario.image_prompt + brand palette, "no text".
  │     carousel: ONE shared style_seed / style prefix across slides for visual coherence.
  8. enqueue heavy 'render_slides' → Playwright renders HTML templates → PNG 1080×1350.
  9. Caption + hashtags (from A2 output) attached; state=ready_for_approval; CAPTURE credits.
  10. scheduled_posts row(status=pending_approval). Flutter push notification. User Approves / Edits text
      (edit re-renders only; free) / Rejects.
```

Single vs carousel branching:

| | Single-slide studio | Carousel studio |
|---|---|---|
| Templates | `mode='single'` | cover + body + cta families that share a design system (`family` in code prefix) |
| Scenario | 1 hook + 1 message | narrative arc: hook → 3–8 value slides → CTA |
| Images | 0–1 | 0–N (default: image on cover only; body slides typographic to save credits) |
| Template of the Day | ranked by `format` | ranked by family |
| Cost | fixed | per-slide + per-image |

**Template of the Day** (daily 04:00 cron):
`perf_score = 0.6 * z(own_engagement_rate, 14d, decayed) + 0.4 * z(trend_format_share, 48h)`,
where `trend_format_share` = share of recent high-engagement trends whose
`format_detected` matches the template's `format`. Cold start: trend signal only.
Add ε-greedy 10% exploration so a new template can get data.

### 3.2 Prompt A1 — Trend-Matching (English output, JSON)

```
SYSTEM:
You are the brand-safety and relevance editor for Postyar, an Instagram content studio.
Your job is to decide which current trends this specific brand can credibly use. You are
strict: a missed trend costs nothing, a bad-fit or off-brand post damages the brand.

USER:
<brand>
{brand_json}            # name, industry, products[], audience, tone, forbidden_topics[], content_language
</brand>

<trends>
{trends_json}           # [{id, source, title, summary, hashtags, format_detected, age_hours, engagement}]
</trends>

Evaluate EVERY trend. For each, reason about:
1. SAFETY: does it touch, even indirectly, any forbidden topic? Also reject by default:
   politics, religion, ethnic/national conflict, tragedy/death/disaster, sexual content,
   health claims, gambling, and anything mocking a real private person. If unsure → reject.
2. PRODUCT FIT: name the ONE concrete product/service from <brand>.products that this trend
   connects to, and the mechanism of connection in one sentence. If you must stretch
   ("everyone needs coffee during X"), the fit is weak → score below 0.5.
3. AUDIENCE FIT: would <brand>.audience plausibly know and care about this trend?
4. FRESHNESS: trends older than 24h lose value; > 36h → reject.
5. TONE FIT: can it be treated in the brand's tone without sarcasm the brand wouldn't use?

fit_score = 0.4*product_fit + 0.3*audience_fit + 0.2*tone_fit + 0.1*freshness, each 0..1.

Return ONLY this JSON, no prose:
{
  "matches": [
    {"trend_id": "...", "fit_score": 0.0, "product_id": "...",
     "angle": "one sentence: how the brand joins this trend",
     "recommended_format": "quote|tip|listicle|before_after|promo|news_hook|meme",
     "risk_notes": "anything the writer must avoid"}
  ],
  "rejected": [
    {"trend_id": "...", "reason_code": "forbidden_topic|unsafe|weak_product_fit|audience_mismatch|stale|tone_clash",
     "reason": "short explanation"}
  ]
}
Sort matches by fit_score desc. Include at most 3 matches. Only include a match if fit_score >= 0.6.
Every input trend must appear in exactly one of the two lists.
```

### 3.3 Prompt A2 — Scenario-Writing (**Persian-output prompt when `content_language='fa'`**)

```
SYSTEM:
You are the lead copywriter of {brand.name}. You write native, natural {LANG_NAME} for
Instagram — never translated-sounding. {IF fa: "Write in fluent colloquial-but-polished Persian
(محاوره‌ای مؤدبانه) as used by Iranian Instagram brands. Use Persian digits (۰-۹), the Persian
zero-width non-joiner correctly (می‌خواهم، کتاب‌ها), Persian punctuation (، ؛ ؟ « »). Do not
use Arabic ي or ك; use ی and ک. Do not mix English words unless they are brand/product names."}

Tone: {brand.tone}. Audience: {brand.audience}.
Never mention or allude to: {brand.forbidden_topics}.
CTA style: {brand.cta_style} — the CTA must ask for exactly one action.
Do not make factual claims about the product beyond what is in its description. No prices unless given.
No emojis in headlines; at most 2 emojis in the caption.

USER:
<product>{product_json}</product>
<trend_angle>{match.angle}</trend_angle>     (or "none — evergreen post")
<trend>{trend.title} — {trend.summary}</trend>
<risk_notes>{match.risk_notes}</risk_notes>
<mode>{single|carousel}</mode>
<slide_count>{N}</slide_count>               (single → 1; carousel → 4..10 incl. cover and CTA)
<format>{template.format}</format>

Write a post scenario. Rules for carousel: slide 1 = hook (a curiosity gap or bold claim that
makes people swipe, ≤ 8 words); slides 2..N-1 each deliver exactly ONE idea that builds on the
previous; slide N = CTA. Rules for single: one hook + one supporting line + CTA in caption.

Return ONLY JSON:
{
  "language": "fa|en",
  "concept": "one sentence in English for internal logs",
  "slides": [
    {"n": 1, "role": "cover|body|cta",
     "headline": "...", "body": "... (optional)", "kicker": "... (optional short label)",
     "needs_image": true,
     "image_prompt": "ENGLISH visual description for an image model. Describe subject, composition,
                      lighting, lens, mood. Must NOT contain any text, letters, logos, signs, or
                      watermarks. Leave clean negative space {top|bottom|left|right} for text overlay."}
  ],
  "caption": "full Instagram caption in {LANG_NAME}, 3-6 short lines, hook first, CTA last",
  "hashtags": ["8-15 hashtags, mix of trend + niche + brand; Persian hashtags use _ not spaces"],
  "alt_text": "accessibility description in {LANG_NAME}"
}
```

### 3.4 Prompt A3 — Template-Slot-Filling (**Persian-output when fa**)

```
SYSTEM:
You fit approved copy into a fixed visual template. You never change meaning, you only
compress, split, or reword to fit. Character limits are HARD: count every character including
spaces and punctuation; the Persian zero-width non-joiner counts as 0.
{IF fa: Output Persian. Keep ی/ک Persian forms and Persian digits.}

USER:
<template code="{template.code}" role="{slide.role}">
{slots_json}
  # e.g. [{"key":"kicker","max_chars":18,"required":false},
  #       {"key":"headline","max_chars":40,"required":true},
  #       {"key":"body","max_chars":140,"required":false},
  #       {"key":"image","type":"image","required":true}]
</template>
<slide_copy>{slide_json_from_A2}</slide_copy>
<brand_cta_examples>{brand.cta_style.phrase_examples}</brand_cta_examples>

Instructions:
- Fill every required text slot. Leave optional slots as "" if they would only add noise.
- headline: the single most important idea, punchy, no trailing period.
- If body copy exceeds the limit, cut filler first, then merge clauses; never drop the key fact.
- Do not put line breaks unless the slot has "multiline": true; then max 3 lines.
- For the image slot, output the image_prompt unchanged unless the template's style_hint
  requires a composition change (e.g., "subject on right, empty left third").
- Also return the character count you computed for each text slot.

Return ONLY JSON:
{"slots": {"kicker": "...", "headline": "...", "body": "...", "image": {"prompt": "..."}},
 "char_counts": {"kicker": 0, "headline": 0, "body": 0}}
```

The Python validator is the source of truth (grapheme count via `regex` `\X`,
ZWNJ excluded); the model's `char_counts` is only used to detect when it was
confused. Repair call text: *"These slots exceed limits: headline 47/40, body
151/140. Shorten only those slots. Return the same JSON."*

Rendering notes (template HTML):
```html
<html lang="{{lang}}" dir="{{ 'rtl' if lang=='fa' else 'ltr' }}">
<style>
  @font-face{font-family:Vazirmatn;src:url(file:///fonts/Vazirmatn[wght].woff2)}
  body{width:1080px;height:1350px;margin:0;font-family:{{fonts[lang]}};
       background:{{colors.bg}};color:{{colors.text}}}
  .headline{font-weight:800;font-size:clamp(56px, 7vw, 96px);line-height:1.25} /* Persian needs ≥1.25 */
</style>
```
Auto-fit: after `page.set_content`, a small JS loop shrinks `.headline` font-size
until `scrollHeight <= clientHeight` (min size floor; below floor → fail → shorten via A3 repair).

---

## 4. FEATURE B — LONG-FORM AI VIDEO (priority)

### 4.1 Core idea

A long video is **N clips (2–4, 5–8 s each) generated sequentially**, where:
1. every clip prompt = `BIBLE_TEXT` (identical bytes) + `CLIP_i_ACTION`;
2. clip *i>0* is generated **image-to-video from the last frame of accepted clip i-1**;
3. clip 0 is generated image-to-video from a **reference keyframe** (generated
   first with the image model from the bible, and shown to the user to approve
   — cheap, and it locks face/outfit/location before any video money is spent);
4. every clip passes a vision QA gate before the next one starts;
5. clips are designed so each **ends on a stable, low-motion pose** ("hold" beat
   in the last ~0.7 s) — this makes the last frame sharp (no motion blur) and a
   good seed, and makes the crossfade invisible.

### 4.2 State machine (one `generation_job`, kind='video')

```
draft
 └─(user submits idea)──▶ planning ──LLM B1──▶ plan_ready
      (Flutter shows: "Postyar can generate a longer version (≈24s, 3 clips) — want that?"
       with cost for 1 clip vs N clips. User picks.)
 └─▶ keyframe ──image API──▶ keyframe_review (user approves / regenerates keyframe — image price)
 └─▶ HOLD video credits (N × clip + regen reserve + stitch)
 └─▶ clip_loop:
        for i in 0..N-1:
          gen_clip(i)      [io]   video API, seed = keyframe (i=0) or clips[i-1].last_frame
          normalize(i)     [heavy] ffmpeg → 1080x1920, 24fps, yuv420p, SAR 1, no audio
          sample_frames(i) [heavy] ffmpeg → first, 33%, 66%, last-0.1s
          qa(i)            [io]   vision LLM B2
            pass  → extract last frame → accepted → next i
            fail  → if regen_budget>0 and attempts<3: regen with fix-hints (B2.fix_prompt_addendum) → gen_clip(i)
                    else → degrade (see failure modes): accept best-scoring attempt or truncate video at i-1
 └─▶ stitching [heavy] xfade chain
 └─▶ effects_detect [io] (optional, user-toggled) B3 on sampled frames → validated effect list
 └─▶ effects_apply [heavy] ffmpeg filter graph
 └─▶ audio_captions [io+heavy] TTS/music + burned or sidecar captions
 └─▶ ready_for_approval → CAPTURE actual cost, RELEASE unused regen reserve
```

**Proactive "longer version" detection:** B1 returns `estimated_duration_s`
and `min_clips`. If `min_clips > 1`, Flutter shows the offer. A deterministic
backup: if the idea contains ≥2 temporal/sequence markers ("then", "after",
"بعد", "سپس", "وقتی", numbered steps) or > 40 words, the offer is shown even if
the model said 1.

### 4.3 Prompt B1 — Continuity Bible + Clip Split

```
SYSTEM:
You are a film director and continuity supervisor preparing a short vertical video that will be
produced by an AI video model in separate {CLIP_LEN}-second clips and stitched into ONE
continuous shot sequence. The model has no memory between clips. Continuity is only possible if
(1) the same exhaustive description is repeated word-for-word in every clip prompt and
(2) each clip begins exactly where the previous one ended.

Hard rules:
- Maximum {MAX_CLIPS} clips. Prefer the fewest clips that tell the idea well.
- ONE location for the whole video unless the idea truly requires otherwise; if it does,
  change location only via a clip that walks through a doorway/turns a corner on camera.
- Maximum 2 characters. No crowds with visible faces. No children. No real, famous, or
  named real people. No logos or readable text in the scene (text is added later in editing).
- Describe characters with concrete, visual, invariant details: apparent age range, face shape,
  skin tone, hair (color, length, style), eye color, facial hair, build, height relative to scene,
  and outfit item by item with colors and materials. No vague words ("stylish", "beautiful").
- Lighting: fixed time of day, light source direction, color temperature in Kelvin, contrast.
- Camera: lens (mm), height, one movement vocabulary for the whole video (e.g. "slow handheld
  push-in"); aspect 9:16; no cuts inside a clip.
- Each clip's action must be physically continuous from the previous clip's final pose.
- Each clip's final ~0.7 s must be a near-still "hold": subject stable, camera nearly still,
  face visible if a character is present. Describe that end pose precisely.
- Brand safety: never include {brand.forbidden_topics}. Avoid violence, weapons, medical,
  alcohol/drugs, revealing clothing, and anything likely to trip video-model safety filters.
- The "bible_text" must be written as a single dense English paragraph, 120–200 words,
  present tense, no clip-specific action in it.

USER:
<brand>{name, industry, products, colors, audience}</brand>
<idea>{user_idea}</idea>                     (may be Persian — understand it, but write prompts in English)
<target>{9:16, platform: Instagram Reels, clip_len: {CLIP_LEN}s, max_clips: {MAX_CLIPS}}</target>

Return ONLY JSON:
{
  "estimated_duration_s": 0,
  "min_clips": 1,
  "offer_longer_version": true,
  "logline_user_language": "one-sentence summary in the user's language, for the confirmation UI",
  "bible": {
    "characters": [{"id":"A","face":"...","hair":"...","build":"...","wardrobe":["..."],"distinguishing":"..."}],
    "location": "...", "props": ["..."],
    "lighting": "...", "camera": "...", "color_grade": "...", "style": "photoreal, 35mm film look",
    "negative": "no text, no logos, no extra people, no cuts, no morphing, no face change"
  },
  "bible_text": "SINGLE PARAGRAPH — copied verbatim into every clip",
  "keyframe_prompt": "image-model prompt for the opening frame: bible_text + exact opening pose",
  "clips": [
    {"idx": 0, "duration_s": {CLIP_LEN},
     "start_state": "exact pose/position/camera framing at t=0 (for idx>0 must equal previous end_state)",
     "action": "what happens, 1-3 sentences, one continuous motion",
     "camera_move": "...",
     "end_state": "exact near-still final pose and framing",
     "voiceover_user_language": "optional line spoken/captioned over this clip, in the brand language",
     "sfx": "ambient sound description"}
  ]
}
```

The orchestrator (Python, **not** the model) builds each clip prompt:
```python
full_prompt = (
  f"{bible.bible_text}\n\n"
  f"SHOT {i+1}/{n}. Continues directly from the input image, which is frame 1 of this shot. "
  f"Start: {clip.start_state} Action: {clip.action} Camera: {clip.camera_move} "
  f"End on a near-still hold: {clip.end_state}\n"
  f"Avoid: {bible.bible['negative']}"
)
```
`bible_text` is stored once in `continuity_bibles.bible_text`; a unit test asserts
every `video_clips.full_prompt` starts with it byte-for-byte.

### 4.4 Prompt B2 — Per-clip Continuity QA (vision)

Inputs: `bible_text`, image **REF** (keyframe for i=0, previous clip's last frame for i>0),
the **character reference** (keyframe crop, always), and 4 frames of the new clip
(F1=first, F2=33%, F3=66%, F4=last). Frames downscaled to 540px wide JPEG q85.

```
SYSTEM:
You are a strict film continuity supervisor doing QA on an AI-generated video clip that must
join seamlessly with the previous clip. You compare images carefully and report concrete,
visible differences only. Do not reward artistic quality; judge continuity and correctness.

USER:
<continuity_bible>{bible_text}</continuity_bible>
<clip_intent>start: {start_state} | action: {action} | end: {end_state}</clip_intent>
Image 1: REF — the frame this clip must continue from.
Image 2: CHARACTER_REF — canonical appearance of the character(s).
Images 3-6: F1, F2, F3, F4 of the new clip, in time order.

Score each dimension 0.0-1.0 (1.0 = indistinguishable / fully correct):
- face: same person as CHARACTER_REF in F1..F4? (face shape, skin tone, eyes, hair, facial hair, age)
- clothing: every wardrobe item in the bible present, same colors/materials, nothing added?
- location: same place, props, layout as REF and bible?
- lighting: same direction, color temperature, contrast as REF? (no sudden day/night, no color shift)
- camera: lens feel, height and movement consistent with bible; no hard cuts within the clip?
- action: does the clip perform the intended action and end near the intended end_state?
- join: does F1 visually continue REF (same pose/framing) so a 0.5s crossfade will not look like a cut?
- artifacts: 1.0 = none; lower for morphing limbs, extra fingers, melting faces, flicker,
  readable text/logos, extra people.

A dimension scores below 0.6 only if you can name the specific visible difference.
pass = (face >= 0.75 AND clothing >= 0.7 AND location >= 0.7 AND lighting >= 0.65
        AND join >= 0.6 AND artifacts >= 0.6 AND action >= 0.5).

Return ONLY JSON:
{
  "scores": {"face":0,"clothing":0,"location":0,"lighting":0,"camera":0,"action":0,"join":0,"artifacts":0},
  "overall": 0,
  "pass": false,
  "issues": [{"dimension":"clothing","frame":"F3","observed":"jacket turned blue","expected":"olive green jacket"}],
  "fix_prompt_addendum": "one or two imperative sentences to append to the regeneration prompt that
                          directly prevent the observed issues, e.g. 'The jacket stays olive green the
                          entire shot. Keep the camera at chest height; do not tilt up.'",
  "retry_advice": "regenerate|regenerate_shorter|simplify_action|accept_minor"
}
```
Python recomputes `pass` from the scores (model's boolean is advisory);
`overall = weighted mean (face .25, clothing .15, location .1, lighting .15, join .15, artifacts .1, action .1)`.
Also a cheap deterministic pre-check before paying for vision QA:
**SSIM/histogram between REF and F1** (`ffmpeg -lavfi ssim`); if SSIM < 0.35 the
image-to-video conditioning obviously failed → regenerate without calling QA.

### 4.5 Prompt B3 — Effect Detection (timestamped boxes)

Inputs: stitched video sampled at **2 fps** (≤ 60 frames for 30 s), each frame
labelled `t=12.5s`, plus the user's effect request (free text, e.g. "blur the
face of the man in the back", "freeze when she smiles", "zoom-punch on the
product") and output video size.

```
SYSTEM:
You are a video-editing assistant that PLANS deterministic edits. You never draw or change pixels;
a separate tool executes your plan exactly. You output WHAT and WHERE, precisely, in machine
format. Coordinates are in pixels of the OUTPUT video ({W}x{H}), origin top-left, integers.
Boxes must fully contain the target with ~10% padding and stay inside the frame.

USER:
<video>duration={D}s, fps=24, size={W}x{H}, frames sampled every 0.5s, each labeled with t.</video>
<request>{user_effect_request}</request>
<auto_rules>Always pixelate any readable third-party logo, license plate, or face of a
person who is not a bible character.</auto_rules>
[frames…]

Allowed effect types and fields:
- "pixelate" | "blur": {"target":"short label","keyframes":[{"t":sec,"x":int,"y":int,"w":int,"h":int}, ...]}
    one keyframe per sampled frame where the target is visible; the tool linearly interpolates
    between keyframes and holds the box ±0.25s around them. Start/end = first/last keyframe t.
- "freeze":     {"t": sec, "hold_s": 0.5-2.0, "reason": "..."}
- "speed_ramp": {"start": sec, "end": sec, "speed": 0.25-4.0}
- "zoom_punch": {"t": sec, "duration_s": 0.2-0.6, "scale": 1.1-1.5, "cx": int, "cy": int}

Constraints: effects must not overlap in time except pixelate/blur (which may overlap anything).
Max 1 freeze, 2 speed_ramps, 4 zoom_punches per 30s. If the request is impossible or the target is
not visible, return it in "unfulfilled" with a reason instead of guessing.

Return ONLY JSON:
{"effects":[{"type":"pixelate","target":"man in grey hoodie, background","keyframes":[{"t":3.0,"x":612,"y":402,"w":180,"h":210}]}],
 "unfulfilled":[{"request":"...","reason":"..."}]}
```
Validation (Pydantic): clamp boxes to frame, even-align w/h, enforce limits,
sort by t, reject overlaps. Boxes from a VLM at 2 fps are coarse — for v1 add an
optional OpenCV CSRT tracker pass (CPU, cheap at 540p) that refines the box on
every frame between VLM keyframes; the VLM stays the "what", the tracker the "where".

### 4.6 FFmpeg command patterns

All run in `worker-heavy` with `nice -n 10 ffmpeg -hide_banner -threads 2 …`.

**Normalize every clip** (providers differ in fps/size/SAR/pix_fmt — a top cause of stitch failures):
```bash
ffmpeg -i raw_$i.mp4 -an \
  -vf "scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1,fps=24,format=yuv420p" \
  -c:v libx264 -preset veryfast -crf 18 -g 24 clip_$i.mp4
```
(If the provider returns 9:16 already, the pad is a no-op; if a clip needs padding at all → aspect mismatch alarm, see failure modes.)

**Last-frame extraction** (exact last decoded frame, robust to VFR):
```bash
ffmpeg -sseof -0.5 -i clip_$i.mp4 -update 1 -q:v 1 -frames:v 999 last_$i.png
# -sseof seeks to 0.5s before end, decodes forward, -update 1 overwrites so the file ends as the LAST frame.
# Seed image for the next clip = PNG (lossless). If the API needs JPEG: -q:v 2 last_$i.jpg
```

**Sample frames for QA:**
```bash
D=$(ffprobe -v error -show_entries format=duration -of csv=p=0 clip_$i.mp4)
for p in 0 0.33 0.66; do ffmpeg -ss $(echo "$D*$p"|bc) -i clip_$i.mp4 -frames:v 1 -vf scale=540:-2 f_${p}.jpg; done
ffmpeg -sseof -0.1 -i clip_$i.mp4 -update 1 -frames:v 99 -vf scale=540:-2 f_last.jpg
```

**Crossfade stitching** (N clips, XF=0.4s; offset_k = sum of durations of clips 0..k − (k+1)·XF):
```bash
# 3 clips of durations d0,d1,d2:
ffmpeg -i clip_0.mp4 -i clip_1.mp4 -i clip_2.mp4 -filter_complex "
  [0:v][1:v]xfade=transition=fade:duration=0.4:offset=$(d0-0.4)[v01];
  [v01][2:v]xfade=transition=fade:duration=0.4:offset=$(d0+d1-0.8)[v]" \
  -map "[v]" -c:v libx264 -preset veryfast -crf 19 -pix_fmt yuv420p -movflags +faststart stitched.mp4
```
Python generates the chain for any N. Because clip *i+1* starts from clip *i*'s
exact last frame, the join is already near-identical — use a **short** crossfade
(0.25–0.4 s); long fades look like ghosting. Optionally trim the first 2 frames of
clip i+1 (`trim=start_frame=2`) since some i2v models "settle" in the first frames.

**Tracked pixelate from timestamped boxes.** Python expands the VLM/tracker
keyframes into per-segment boxes (every 1/12 s, linearly interpolated) and
emits one overlay per segment:
```bash
ffmpeg -i stitched.mp4 -filter_complex "
  [0:v]split=2[base][px];
  [px]scale=iw/24:ih/24:flags=neighbor,scale=iw*24:ih*24:flags=neighbor[pixfull];
  [base][pixfull]overlay=0:0:enable='between(t,3.000,3.083)':shortest=1 ... " out.mp4
```
The cleaner and scalable form uses **`crop` with time-varying expressions** so
it's ONE crop + ONE overlay regardless of segment count:
```bash
# X(t),Y(t) piecewise-linear expressions generated in Python from keyframes, e.g.
# X='if(lt(t,3.5),612+(t-3.0)*(640-612)/0.5, if(lt(t,4.0),640+(t-3.5)*(655-640)/0.5, 655))'
ffmpeg -i stitched.mp4 -filter_complex "
  [0:v]split[base][src];
  [src]crop=w=180:h=210:x='$X':y='$Y',
       scale=iw/12:ih/12:flags=neighbor,scale=180:210:flags=neighbor[mask];
  [base][mask]overlay=x='$X':y='$Y':enable='between(t,3.0,6.5)':eval=frame,format=yuv420p[v]" \
  -map "[v]" -map 0:a? -c:v libx264 -preset veryfast -crf 19 -c:a copy out.mp4
```
(Box size fixed per effect = max w/h across keyframes, so crop dims stay constant;
only position animates. For blur swap the pixel chain for `boxblur=20:2`.
Multiple targets = chain more split/crop/overlay branches.)

**Freeze-frame at t=T for H seconds:**
```bash
ffmpeg -i in.mp4 -filter_complex "
  [0:v]trim=0:T,setpts=PTS-STARTPTS[a];
  [0:v]trim=T,setpts=PTS-STARTPTS[b];
  [b]split[b1][b2];[b1]trim=end_frame=1,loop=loop=H*24:size=1,setpts=N/24/TB[f];
  [a][f][b2]concat=n=3:v=1:a=0[v]" -map "[v]" out.mp4
```
**Speed ramp** (segment S..E at speed k): split into 3 trims, middle `setpts=(PTS-STARTPTS)/k`, concat.
**Zoom-punch** at T, duration P, scale s, center cx,cy:
```bash
-vf "zoompan=z='if(between(it,T,T+P),1+(s-1)*sin(PI*(it-T)/P),1)':x='cx-iw/zoom/2':y='cy-ih/zoom/2':d=1:s=1080x1920:fps=24"
```
(`it` = input timestamp in zoompan.) Apply effects in order: speed/freeze (time-changing)
→ **recompute** box timestamps through the time map → zoom → pixelate last (so
privacy blur is never undone by a zoom).

**Audio + captions:**
```bash
ffmpeg -i fx.mp4 -i music.mp3 -i vo.wav -filter_complex "
  [1:a]volume=0.25,afade=t=out:st=$(D-1.5):d=1.5[m];
  [2:a]adelay=300|300[vo];
  [m][vo]amix=inputs=2:duration=first:dropout_transition=0,loudnorm=I=-14:TP=-1.5[a];
  [0:v]subtitles=captions.ass:fontsdir=/fonts[v]" \
  -map "[v]" -map "[a]" -c:v libx264 -preset veryfast -crf 19 -c:a aac -b:a 160k -shortest final.mp4
```
Captions: `.ass` with Vazirmatn; libass + HarfBuzz handle Persian shaping/RTL
(build ffmpeg with `--enable-libass --enable-libharfbuzz`; the johnvansickle static
build includes libass). Voice-over via TTS API from the per-clip `voiceover` lines,
timing = clip offsets; captions timed from TTS word timestamps. Music from a licensed
royalty-free library tagged by mood (never AI-generated per job in v1 — cost).
Video-model native audio is **dropped** (`-an`) because it never matches across clips.

### 4.7 Failure modes & automatic mitigations

| # | Failure | Detection | Automatic mitigation |
|---|---|---|---|
| 1 | **Face drift** (identity changes gradually across clips) | QA `face` vs CHARACTER_REF (always the original keyframe, not the previous frame — prevents compounding drift) | Regen with addendum; if provider supports reference images ("ingredients"/subject ref), pass the keyframe crop as reference too; 2nd failure → shorten clip to 5 s (less time to drift). |
| 2 | **Lighting/colour jump** at the join | QA `lighting`, plus deterministic mean-luma/colour-histogram delta between REF and F1 | Small deltas: auto colour-match via ffmpeg `colorbalance`/`eq` computed from histograms; large: regen. |
| 3 | **Clothing change** | QA `clothing` | Regen with explicit wardrobe addendum; bible must list items with colors (enforced by B1 schema validator: every character needs ≥3 wardrobe items with a color word). |
| 4 | **Location / prop change** | QA `location` | Regen; B1 rule "one location" reduces incidence. |
| 5 | **Join looks like a hard cut** (clip ignores seed image) | SSIM(REF, F1) < 0.35 pre-check | Regen immediately (no QA cost); if provider repeatedly ignores seed → switch to provider fallback that supports first-frame conditioning. |
| 6 | **Motion-blurred last frame** → poor seed | Laplacian-variance sharpness on last frame (OpenCV) | Walk back up to 12 frames to the sharpest frame, trim the clip to end there. |
| 7 | **Aspect/resolution/fps mismatch** | ffprobe after download | Always normalize (4.6); request 9:16 from provider; if clip came back 16:9 → regen (don't letterbox a reel). |
| 8 | **Audio mismatch** (per-clip generated audio jumps) | n/a — by design | Strip clip audio; one continuous music bed + TTS over full timeline. |
| 9 | **Model refusal / safety block** | provider error code / empty output | B1 already avoids risky content; on refusal: 1× auto-rewrite of the action with a "safety rephrase" LLM call (removes flagged nouns), then try fallback provider; refusal never consumes user credits beyond the hold (released). |
| 10 | **Action not performed / wrong end pose** | QA `action`, `retry_advice=simplify_action` | Regen with simpler action (LLM rewrites one clip only); if still failing, accept if continuity is good (action ≥0.4) — continuity matters more than exact choreography. |
| 11 | **Artifacts** (extra fingers, morphing, readable text) | QA `artifacts` | Regen; if text/logo only → accept and auto-pixelate via effect pass. |
| 12 | **Cost blowup from regenerations** | per-job `regen_budget_remaining` (credits), per-clip max 3 attempts, per-job max N+2 regenerations | Budget exhausted → take best-scoring attempt if overall ≥ 0.6; else end the video at the last good clip, deliver a shorter video, refund unused clip credits. Daily per-user and global provider-spend circuit breaker. |
| 13 | **Provider timeout / job lost** | poll > 10 min | Re-poll by provider_job_id; after 15 min cancel + resubmit once (platform cost, not user). |
| 14 | **Cumulative drift over 4 clips** even if each join passes | QA compares to CHARACTER_REF, not only prev frame | Cap MAX_CLIPS=4 in v1. |
| 15 | **OOM in worker-heavy** | exit code 137 | Job auto-retried once with `-threads 1` and 720p intermediate; container restarts only itself (cgroup). |
| 16 | **Crossfade offset math wrong** (clip shorter than expected) | ffprobe actual durations | Offsets always computed from ffprobe, never from requested durations. |
| 17 | **Effect boxes wrong / drift off target** | tracker confidence < threshold | Grow box 30% and extend ±0.3 s (fail safe: over-blur, never under-blur for privacy). |
| 18 | **Persian captions broken** (disconnected letters/LTR) | render test frame at startup + OCR-less pixel check in CI | Bundle fonts, ffmpeg with libass+harfbuzz; ASS `Encoding=1`, `\\an2`, no manual reversing of strings. |

---

## 5. CREDIT / COST MODEL

Assumed provider costs (order-of-magnitude, tune monthly): LLM call ≈ $0.002–0.01,
image ≈ $0.03–0.04, vision QA ≈ $0.01, 8 s video clip ≈ $0.25–0.60 (720p–1080p i2v).
**1 credit ≈ $0.01 of provider cost × ~2.5 markup** (i.e. sell 1 credit ≈ $0.025).

| Operation | Credits | Notes |
|---|---|---|
| Scenario (trend match + write + slot fill) | **2** | text only |
| Single slide (scenario + 1 image + render) | **8** | 2 + 5 image + 1 render |
| Single slide, text-only template | **3** | no image |
| Carousel, N slides | **2 + 1·N + 5·(images)** | default 1 image (cover): 7-slide = 2+7+5 = **14** |
| Re-render after user text edit | **0** | local CPU only |
| Image regenerate (user-requested) | **4** | |
| Video plan (bible + split) + keyframe | **6** | lets user commit before video spend |
| Video clip (≤8 s) | **40** | ≈ 8× an image |
| Continuity regeneration (auto, QA-failed) | **15** | ≈ 1/3 of a clip; platform absorbs the rest. Pre-held in the reserve. |
| User-requested "reroll" of a clip that *passed* QA | **30** | discourages exploration-by-reroll |
| Stitch + music + captions | **5** | CPU + TTS |
| Effect pass (detect + apply) | **6** | + 2 per extra effect target |

Example: 3-clip video = 6 + 3·40 + 5 = **131** credits; **hold** = 131 + regen
reserve 2·15 = 161; capture actual; unused reserve released. Regen budget per
job = `ceil(N/2)+1` automatic regenerations charged at 15; any beyond that are
free to the user but counted against a platform spend circuit breaker (and
alert you — it signals a prompt/provider problem).

Starter plan idea: 300 credits/month (≈ 20 carousels or 2 videos).

---

## 6. MVP SCOPE CUT (1–2 weeks, one developer + AI assistants)

**Build:**
- Auth: single email magic link or even a single admin token (you're the tester).
- Brand Kit: one form screen in Flutter (fa/en), stored as JSON.
- **Feature A v0:** manual trend paste (text box: "what's trending?") or "no trend";
  prompts A1–A3; **6 templates total** (3 single, 1 carousel family = cover/body/cta);
  1 image per post (cover only); Playwright render; results gallery + download.
  Template of the Day = **manual flag** in DB (admin sets it) — the badge UI exists, the scoring doesn't.
- **Feature B v0:** idea → B1 → user confirms plan + keyframe → **2–3 clips** sequential i2v from
  last frame → B2 QA with auto-regen (max 2 per clip) → normalize → xfade stitch →
  one music track + optional captions from voiceover lines → download MP4.
  **One** video provider (via fal.ai so switching later is a config change).
- Credits: ledger + hold/capture/release, manual top-up by admin SQL. No payment gateway.
- Queue: Postgres `jobs` table, two worker containers, concurrency 1 for heavy.
- Job progress: Flutter polls `/jobs/{id}` every 3 s (no websockets).
- Publish: **none** — "Download" + "Share" sheet. Human posts it manually.

**Defer:** automatic IG/Telegram trend scraping (Telegram via Telethon is the first to add), scheduler
& scheduled posts, auto-publishing (IG Graph API requires business account + app review),
Template-of-the-Day scoring, all bonus effects (pixelate/freeze/zoom/speed) and B3, OpenCV tracker,
TTS voice-over (music only), multi-provider fallback, R2 storage, payments, multi-user teams,
analytics ingestion.

Day plan: D1–2 infra/compose/DB/queue/ledger · D3–5 Feature A end-to-end + Flutter screens ·
D6–9 Feature B pipeline + QA loop · D10 stitch/music/captions · D11–12 Flutter video studio,
RTL polish · D13–14 hardening, cost caps, a 20-idea evaluation run to measure QA pass rate.

Success metric for the demo: ≥ 70% of 3-clip videos pass QA within budget and a
non-technical viewer can't point to the joins.

---

## 7. OPEN RISKS

| Risk | Why it's big | Concrete mitigation |
|---|---|---|
| **1. Continuity drift despite bible + last-frame seeding** | i2v models honor the first frame but drift within 8 s; faces are the weakest point | Plan clips with **low motion + face-visible holds**, cap at 4 clips, QA against the *original* character ref every time, and pick a provider supporting reference-image/subject conditioning in addition to first-frame. Run the 20-idea benchmark per provider before committing. |
| **2. Video-model refusals & latency** | refusals waste time; 1–5 min per clip × sequential = 5–15 min per video | B1 safety rules pre-empt refusals; auto safety-rephrase + fallback provider; UX sets expectations ("≈10 min, we'll notify you") and generates keyframe first so users commit early. Track refusal rate per prompt category. |
| **3. Cost blowup from regenerations** | sequential dependency means a late failure can trigger many retries | Hard per-clip (3) and per-job (N+2) attempt caps, credit hold includes a bounded reserve, graceful degrade to shorter video, global daily provider-spend circuit breaker that pauses video jobs. |
| **4. Trend-scraping fragility (no official IG trends API)** | scrapers break, ToS risk, account bans | v0 manual paste; v1 Telegram public channels via Telethon (stable, allowed) + a paid Apify actor for IG behind a single `TrendSource` interface; if it breaks, product degrades to evergreen + manual — never blocks generation. |
| **5. RAM contention with GitLab on the shared host** | no swap; host OOM killer could hit GitLab | Per-container `mem_limit`/`memswap_limit`, `oom_score_adj` high on worker-heavy, concurrency 1 + advisory lock for Chromium/FFmpeg, `-threads 2`, 720p intermediates if needed, and a pre-flight check that refuses heavy jobs when host `MemAvailable` < 800 MB (read `/proc/meminfo` via bind mount). Also: add 2 GB swapfile on the host as a safety net. |
