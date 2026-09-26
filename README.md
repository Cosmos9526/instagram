<p align="center"><img src="branding/postyar-wordmark.png" alt="Postyar" height="96"></p>

# Postyar

Postyar is a daily Instagram content studio for businesses. You define a business once: products, audience, tone, brand colors and forbidden topics. Every morning it prepares ready-to-post content:

- **Post types:** educational, news, promotional and sales.
- **Formats:** single slide or carousel.
- **Video prompt packages:** for 10–40 second Reels, split into 2–4 continuous clips.
- **Languages:** Persian (RTL) and English content.

## What's inside

| Part | Path | Stack |
|---|---|---|
| Backend API, worker, scheduler | `backend/` | Python 3.12, FastAPI, SQLAlchemy, PostgreSQL, Playwright (headless Chromium) |
| App (PWA for iPhone + Android, optional native builds) | `mobile/` | Flutter, Persian RTL, light/dark theme |
| Brand assets (logo, icons) | `branding/` | — |
| Architecture and product design | `docs/ARCHITECTURE.md` | — |
| Helper scripts (template previews, demo slides) | `tools/` | — |

## Features

### Accounts and projects
- Email/password sign-up and login, with signed tokens valid for 30 days.
- Each user has multiple **projects**. A project is one business or brand, with:
  - a profile: name, industry, description, website, Instagram handle, products, audience, tone, colors, forbidden topics, call to action (CTA) and fixed hashtags
  - a **weekly plan**: which post types to create on which days
- Users can only see and edit their own projects.

### Content generation
- **Slides:** the text model writes copy into fixed template **slots** with hard character limits. Code checks the limits, asks the model once to fix any violation, then truncates safely.
- **Rendering:** slides are HTML/CSS templates rendered to 1080×1350 PNG by headless Chromium with the bundled Vazirmatn font, so Persian shaping and RTL are always correct. Text is never drawn by an image model.
- **18 slide templates:** tip, numbered list, checklist, step-by-step guide, myth vs fact, FAQ, big stat, news flash, event announcement, product hero, before/after, testimonial, quote card, poll question, sales offer, and a carousel family (cover, body, CTA).
- **Template choice:** when no template is chosen, the daily batch rotates templates so posts don't look alike.
- **Background images:** optional, from Cloudflare Workers AI (Flux). Without them, a gradient in the brand colors is used.
- **Video prompt packages:**
  - a **continuity bible** (characters, wardrobe, location, lighting, camera) that the code copies byte-for-byte into every clip prompt
  - clips that each start from the previous clip's last frame
  - Persian voice-over and caption lines
  - **14 video styles** to shape the clips: POV, before/after, tutorial, UGC testimonial, unboxing, ASMR, behind the scenes, founder story, trend hook and more
- **Review:** users edit the text (re-rendering is free), approve, reject or regenerate.

### Market research
- **Web research:** Gemini with Google Search grounding finds:
  - facts about the business and products online
  - competitors
  - audience interests
  - this week's trends
  - keywords and hashtags, with sources
- **Social listening:** the most-viewed recent videos for the top keywords (YouTube Data API), plus top Instagram posts for the top hashtags (optional, through Apify).
- **Video style analysis:** a model maps what the top videos do to the video-style catalog.
- **Used everywhere:** the latest research goes into every generation prompt. The daily batch refreshes research older than 3 days.

### App (Flutter)
- **Screens:** login/sign-up → projects → inside a project: **Posts**, **Create**, **Market** (research) and **Settings**, plus a template gallery and a profile screen.
- **Research shortcut:** any trend, content idea or video style from research opens Create with the topic already filled in.
- **Install:** served by the backend as a PWA. On iPhone use Safari → *Add to Home Screen*; on Android use Chrome → *Install app*.
- **Demo mode:** `--dart-define=DEMO=true` runs the whole app with sample data and no server.

## Run with Docker

```bash
cp .env.example .env        # set ADMIN_TOKEN, SECRET_KEY, LLM_API_KEY (+ optional YOUTUBE_API_KEY, APIFY_TOKEN)
docker compose up -d --build
curl localhost:8710/health  # API health; the app itself is at http://localhost:8710/
```

The stack is built for a small shared server:
- hard memory and CPU limits (about 1.6 GB RAM in total)
- a single worker that runs one rendering job at a time
- the API bound to `127.0.0.1:8710`

To expose it, add `Caddyfile.snippet` to Caddy as a new site block. No other routes are touched.

## API overview

All endpoints except `/health`, `/catalog` and `/auth/*` need `Authorization: Bearer <token>` from login.

| Method | Path | Purpose |
|---|---|---|
| POST | `/auth/register`, `/auth/login` | Create an account / log in, returns a token |
| GET, PUT | `/auth/me` | Profile, change name or password |
| GET, POST | `/brands` | List / create projects |
| GET, PUT, DELETE | `/brands/{id}` | Read / update / delete a project |
| POST | `/brands/{id}/generate` | `{"post_type": "educational\|news\|promo\|sales\|video_prompt", "mode": "single\|carousel", "template": "...", "video_style": "...", "topic_hint": "...", "n_body": 4, "target_seconds": 24}` |
| GET | `/brands/{id}/posts` | Posts of a project |
| GET, PUT | `/posts/{id}` | Read a post / edit its text (free re-render) |
| POST | `/posts/{id}/approve\|reject\|regenerate` | Review actions |
| POST, GET | `/brands/{id}/research` | Start / list market research |
| GET | `/catalog` | All slide templates (with previews) and video styles |
| POST | `/admin/run-daily` | Run the daily batch now (`ADMIN_TOKEN`) |

`weekly_plan` keys are Python weekdays (0 = Monday … 5 = Saturday, 6 = Sunday):
```json
{"5": ["educational:carousel"], "6": ["news"], "0": ["promo"], "1": ["educational"], "2": ["sales"], "3": ["video_prompt"]}
```

## Configuration

See `.env.example`. Main settings:

| Variable | Purpose |
|---|---|
| `LLM_BASE_URL`, `LLM_API_KEY`, `LLM_MODEL` | Any OpenAI-compatible chat endpoint (default: Gemini) |
| `RESEARCH_PROVIDER` | `gemini` (Google Search grounding), `llm` (no web access) |
| `YOUTUBE_API_KEY` | Most-viewed videos (free quota) |
| `APIFY_TOKEN` | Instagram top posts (optional, paid) |
| `IMAGE_PROVIDER`, `CF_ACCOUNT_ID`, `CF_API_TOKEN` | Background images via Cloudflare Workers AI |
| `SECRET_KEY`, `ALLOW_SIGNUP` | Login token signing, open/closed sign-up |
| `DAILY_RUN_HOUR`, `TIMEZONE` | When the daily batch runs (default 07:00 Asia/Tehran) |

## Development

```bash
# backend
cd backend
pip install -r requirements.txt && playwright install chromium
python -m pytest -q          # fake LLM, SQLite, real Chromium rendering

# app
cd mobile
flutter pub get
flutter test && flutter analyze
flutter run                  # phone / emulator
flutter build web --release --no-web-resources-cdn   # PWA
```

Regenerate template previews after editing a template: `cd backend && python ../tools/make_previews.py`.
