# Hashtpa — پنل تولید محتوای روزانه‌ی اینستاگرام

شرکتت رو یک بار تعریف می‌کنی؛ هر روز صبح پست‌های مناسب آماده می‌شن:
**آموزشی، خبری، تبلیغاتی، فروش** (تک‌اسلاید یا کاروسل) و **پکیج پرامپت ویدیو** (۱۰ تا ۴۰ ثانیه، ۲ تا ۴ کلیپ پیوسته).

## How it works
- The text model writes the copy into fixed template **slots** with hard character limits
  (validated in code, one repair round, then safe truncation).
- Slides are HTML/CSS templates (`backend/app/templates/`) rendered to 1080×1350 PNG by headless
  Chromium, with the bundled Vazirmatn font — Persian shaping/RTL is always correct and text is never
  drawn by an image model.
- Optional background image per post (Cloudflare Workers AI Flux); otherwise a brand-colour gradient.
- Video: the model writes a **continuity bible** + per-clip actions; the code builds every clip prompt
  as `bible_text` (byte-identical) + shot instructions, each clip seeded from the previous clip's last frame.
- A daily scheduler creates posts from each brand's `weekly_plan`; one worker processes jobs one at a time.

## Run
```bash
cp .env.example .env   # fill ADMIN_TOKEN, LLM_API_KEY, ...
docker compose up -d --build
curl localhost:8710/health
```
Put `Caddyfile.snippet` into Caddy as a new site block.

## API (Bearer ADMIN_TOKEN)
| Method | Path | |
|---|---|---|
| POST/GET/PUT | `/brands`, `/brands/{id}` | brand profile incl. `weekly_plan` |
| POST | `/brands/{id}/generate` | `{"post_type":"educational|news|promo|sales|video_prompt","mode":"single|carousel","topic_hint":"...","n_body":4,"target_seconds":24}` |
| GET | `/brands/{id}/posts?date=YYYY-MM-DD` | today's posts |
| PUT | `/posts/{id}` | edit text → free re-render |
| POST | `/posts/{id}/approve \| reject \| regenerate` | |
| POST | `/admin/run-daily` | run the daily batch now |

`weekly_plan` keys are Python weekdays (0=Monday … 5=Saturday, 6=Sunday):
```json
{"5": ["educational:carousel"], "6": ["news"], "0": ["promo"], "1": ["educational"], "2": ["sales"], "3": ["video_prompt"]}
```

## Tests
```bash
cd backend && pip install -r requirements.txt && playwright install chromium
python -m pytest -q          # uses LLM_PROVIDER=fake, SQLite, real Chromium rendering
```

## Next
Flutter panel (fa/en, RTL) on top of this API · design docs: see `docs/ARCHITECTURE.md`.
