"""Reviewed starter week for Rahboom. Explicit editorial content, never an AI fallback."""
from datetime import date, timedelta
from urllib.parse import urlparse
from sqlalchemy import select
from .models import Post

SERIES = 'rahboom-video-week-v1'

# Saturday first. Each day has its own product, hook, dialogue and physical action.
DAYS = [
    ('sales', 'کلاد مکس؛ انتخاب پلن با توجه به استفاده', 'Claude Max',
     'رها: «کلاد مکس پنج ایکس یا بیست ایکس؟»\nآرین: «اول میزان استفاده‌ت رو بگو؛ راه بوم راهنمایی می‌کنه.»',
     'Raha holds her phone low beside the desk and tilts it slightly toward Arian, without revealing screen text. Arian counts two options with a restrained two-finger gesture, then lowers his hand.',
     'Do not claim unlimited use or equate 5x and 20x. No numeric price is approved for this video.'),
    ('educational', 'پرامپت بهتر؛ سؤال مبهم نپرس', 'ChatGPT',
     'رها: «چرا جواب چت‌جی‌پی‌تی کلیه؟»\nآرین: «هدف، مخاطب و شکل خروجی رو دقیق بگو.»',
     'Raha looks from the laptop to Arian with a puzzled eyebrow. Arian makes three small fingertip beats above the desk, one for each suggestion, without touching or covering either face.',
     'Present this as a practical prompting tip, not a guaranteed result or exclusive paid feature.'),
    ('promo', 'کرسر؛ کد را قبل از قبول‌کردن بخوان', 'Cursor',
     'رها: «کرسر کد نوشت؛ مستقیم اجرا کنم؟»\nآرین: «اول بخون، تست کن، بعد قبولش کن.»',
     'Raha pauses with her right hand beside the laptop, then turns to Arian. He gives one gentle wait gesture near his torso and nods toward the laptop. The screen stays defocused.',
     'Avoid invented interfaces, autonomous-developer claims or guarantees that generated code is correct.'),
    ('educational', 'تولید ویدیو؛ اول سناریو را روشن کن', 'Google Flow',
     'رها: «برای ویدیوی خوب از کجا شروع کنم؟»\nآرین: «سناریوی کوتاه، مرجع ثابت، دیالوگ مشخص.»',
     'Raha puts her phone flat on the desk before speaking. Arian traces a short left-to-right motion with one hand, suggesting a simple sequence, then returns both hands to rest.',
     'This is a workflow tip. Never show a fake Google Flow interface or promise perfect face or voice consistency.'),
    ('news', 'خبر هوش مصنوعی؛ اول منبع اصلی', 'AI news',
     'رها: «این خبر هوش مصنوعی واقعیه؟»\nآرین: «اول منبع اصلی و تاریخ انتشار رو ببین.»',
     'Raha notices a notification on her phone and glances at Arian with curiosity, not alarm. Arian leans forward a few centimetres and gives a thoughtful nod toward the phone.',
     'News-literacy content, not a breaking-news report. Do not invent an announcement, date, benchmark or headline.'),
    ('promo', 'خرید اشتراک؛ ابزار مناسب کارت را انتخاب کن', 'AI subscriptions',
     'رها: «همهٔ اشتراک‌ها رو بخرم؟»\nآرین: «نه؛ اول بگو برای چه کاری می‌خوای.»',
     'Raha holds the phone with both hands, briefly amused by her own question. Arian responds with a small friendly head shake and a relaxed open palm. Keep the humour understated.',
     'A practical buying conversation. No disparaging competitors, fake discount or pressure to purchase.'),
    ('sales', 'راه بوم؛ از انتخاب ابزار تا سفارش', 'Rahboom',
     'رها: «برای انتخاب ابزار هنوز مرددم.»\nآرین: «به راه بوم پیام بده؛ از نیازت شروع کنیم.»',
     'Raha rests the phone on the desk and turns toward Arian. After answering her, Arian briefly looks toward the camera; Raha gives one small agreeing nod. Hold both positions for the cut.',
     'Invite a consultation without promising free service, delivery time or warranty that has not been confirmed.'),
]

# A second reviewed week prevents the next seven days recycling the first week's scripts.
NEXT_DAYS = [
    ('sales', 'کلاد؛ قبل از انتخاب پلن، کارت را مشخص کن', 'Claude',
     'رها: «برای نوشتن و تحقیق کدوم کلاد رو بگیرم؟»\nآرین: «نوع کار و حجم استفاده‌ت رو به راه بوم بگو.»',
     'Raha slides a closed notebook toward Arian. He gestures toward the notebook and then her phone, inviting a needs-based conversation.',
     'Do not invent plan differences, prices or guaranteed research accuracy.'),
    ('educational', 'پایان‌نامه؛ منبع ساختگی را وارد نکن', 'AI research',
     'رها: «این منبع پایان‌نامه رو هوش مصنوعی داده؛ کافیه؟»\nآرین: «نه؛ اصل مقاله و مشخصاتش رو خودت بررسی کن.»',
     'Raha points once at a page in her notebook. Arian lightly taps the closed notebook with one finger, then looks back to her.',
     'Do not display invented papers or citations. This is source verification advice.'),
    ('promo', 'گوگل فلو؛ مرجع شخصیتت را آماده کن', 'Google Flow',
     'رها: «برای ویدیوم از کجا شروع کنم؟»\nآرین: «عکس مرجع و سناریوت رو آماده کن؛ انتخاب اشتراک با راه بوم.»',
     'Raha raises her phone beside her shoulder without showing screen text. Arian frames a small rectangle with his hands below chest level.',
     'Do not promise perfect consistency or imply this reference workflow is a paid-only feature.'),
    ('educational', 'کد ناشناس؛ اول توضیحش را بخواه', 'AI coding',
     'رها: «این کد رو نمی‌فهمم؛ اجراش کنم؟»\nآرین: «اول توضیح خط‌به‌خط بخواه؛ بعد توی محیط آزمایشی تست کن.»',
     'Raha draws her hand away from the laptop keyboard. Arian points toward the defocused laptop and makes a small measured pause gesture.',
     'No invented code on screen. Never claim an AI explanation guarantees safety.'),
    ('educational', 'جمینی؛ فایل حساس را بی‌فکر آپلود نکن', 'Gemini',
     'رها: «فایل مشتری رو بدم به جمینی؟»\nآرین: «اول اطلاعات حساس رو حذف کن و اجازهٔ استفاده رو بررسی کن.»',
     'Raha holds a plain unmarked document folder closed. Arian keeps an open hand near the folder without taking it, signalling a considered pause.',
     'General privacy advice only; do not assert specific provider retention policies.'),
    ('promo', 'اشتراک هوش مصنوعی؛ از کاربردت شروع کن', 'AI subscriptions',
     'رها: «برای طراحی و کدنویسی یک ابزار کافیه؟»\nآرین: «نیازت فرق داره؛ راه بوم کمک می‌کنه انتخابت کنی.»',
     'Raha places a pencil beside the laptop. Arian gestures once between the pencil and laptop, visually contrasting two tasks.',
     'Do not promise one tool covers every task or invent product capabilities.'),
    ('sales', 'راه بوم؛ قبل از خرید، سؤال‌هایت را بپرس', 'Rahboom',
     'رها: «قبل از خرید اشتراک چی بپرسم؟»\nآرین: «پلن، مدت و شرایط فعال‌سازی؛ از راه بوم بپرس.»',
     'Raha makes a small three-point counting gesture while looking at Arian. He nods and turns gently toward the camera at the end.',
     'Do not state unverified activation terms, delivery times or warranty promises.'),
]

STYLE = '''CHARACTER AND SET CONTINUITY
Use the supplied reference frame from the owner's 122.MP4 as the visual source of truth. Two adult presenters remain seated throughout: Raha on frame-left, Arian on frame-right. Raha has long loose wavy blonde-brown hair with darker roots, a centre part, dark rounded rectangular glasses, a fitted white short-sleeved crew-neck top and dark high-waisted trousers. Arian has short textured silver-grey hair with trimmed sides, a neat dark beard and moustache, dark rectangular glasses, an open light-blue short-sleeved shirt over a white T-shirt, dark trousers and a dark watch on his left wrist. Match reference faces and proportions; do not redesign either presenter.
Keep the same home office: light wooden desk across the foreground, dark desk mat, partial laptop at far left, dark coding monitors behind the presenters, pale walls, curtain, and illuminated white/cyan/lavender hexagonal wall panels. Preserve soft daylight from frame-left and gentle cool ambient light. Do not turn the room orange. Use a realistic eye-level vertical medium two-shot, equivalent to a 40 mm lens; keep both faces in focus, natural skin texture, stable exposure and restrained contrast. Keep faces inside the central 70% of the frame, with bottom space clear for interface overlays. No reverse angle or crossing the screen axis.'''


def is_rahboom(brand):
    return (urlparse(brand.website).hostname or '').removeprefix('www.') == 'rahboom.com'


def package(index, day):
    week = (day - date(2026, 9, 26)).days // 7
    purpose, title, product, dialogue, action, claim_rule = (DAYS if week % 2 == 0 else NEXT_DAYS)[index]
    full = f'''GOOGLE FLOW — RAHBOOM VERTICAL VIDEO
Creative concept: {title}
Product/topic: {product}. Purpose: {purpose}.
Deliverable: a 9:16, 1080 × 1920 finished advertisement, maximum 10 seconds: one eight-second spoken scene followed by a two-second silent end card. Generate the scene in Flow using the attached character frame. Assemble the supplied logo and exact end-card text in editing; do not rely on a video model to typeset Persian.

{STYLE}

ACTION AND TIMING
0.00–0.45 s: establish the existing seated two-shot; natural breathing, lips at rest. Start the day's physical action: {action}
0.45–3.10 s: Raha speaks only her line below. Arian listens silently, with lips at rest and a natural eyeline toward Raha.
3.10–3.35 s: brief turn-taking pause; no extra words.
3.35–7.35 s: Arian speaks only his line. Raha listens without mouthing his words. Use the restrained gestures above, never exaggerated sales acting.
7.35–8.00 s: both settle and hold the composition for a clean cut. No speech after 7.35 s. Camera is locked off except for an optional imperceptible 2% push-in across the whole shot.

EXACT SPOKEN IRANIAN PERSIAN
{dialogue}
Speaker names identify the speaker and must not be spoken. Preserve the words verbatim; do not translate, paraphrase, repeat or add a narrator. Use conversational Iranian Persian, a warm clear adult female voice for Raha and a calm clear adult male voice for Arian. No overlapping speech. Synchronise visible lips to each speaker. Exact voice cloning is not requested. Keep consistent voice casting across this series using the approved reference if available. Record quiet room tone; no distracting music or sound effects. Do not speed up speech unnaturally; verify the generated clip against the eight-second target.

END CARD — 8.00–10.00 s
Hard cut at 8.00 s to a still off-white card. Composite the supplied original orange/amber Rahboom R mark and dark/orange wordmark, preserving its proportions. Logo centred in the upper-middle, product/topic beneath it, then ONE ordering line. Exact text layers:
{product}
سفارش و مشاوره: @rahboom1
Use correctly shaped Persian RTL typography. Keep {product} and @rahboom1 in separate LTR runs; never mirror or respell the handle. Dark text, one restrained orange accent, generous mobile-safe margins; no additional tagline, price, QR code or badge. Hold completely still for two seconds, with no speech. If Flow produces a longer clip, trim the scene to eight seconds and append this card in editing; the assembled result must not exceed ten seconds.

NEGATIVE CONSTRAINTS AND FINAL CHECK
No face drift, changing glasses, hair or outfits, deformed hands, duplicate phones, new people, moving furniture, shaky zoom, flickering screens or artificial beauty smoothing. Do not generate new letters, subtitles, logos or watermarks in the scene. Preserve existing reference lettering only when faithful; replace distorted lettering in editing with the real supplied asset. No unsupported claim, fabricated urgency or numeric price. {claim_rule}
Use only the attached reference frame and original logo for identity and branding. Review both faces, spoken words, lip-sync, product spelling, contact handle and final duration before publishing.'''
    cover = f"""RAHBOOM INSTAGRAM REEL COVER — 1080 × 1920, 9:16
Use the supplied reference frame to preserve adult presenters Raha on the left and Arian on the right, their faces, glasses, hair, clothing and original home-office set. Create a crisp editorial still, eye-level medium two-shot, soft daylight, natural skin, subtle cool ambient background, uncluttered composition. Express the day's idea through the same restrained action: {action}
Leave clean negative space in the upper central area for this exact Persian headline: «{title}». Use at most two lines, bold readable Persian typography, correct joined letters and RTL direction. Add text in editing if the image tool cannot typeset it accurately. Keep both faces and the entire headline inside the central 1080 × 1350 safe area for feed cropping; keep the bottom 250 pixels free of essential information.
Place the original supplied orange Rahboom logo small in the upper corner without redrawing or recolouring it. Off-white, charcoal and a restrained orange accent for text treatment. No invented UI, price, feature claims, extra people, fake badges, watermarks or decorative clutter. The cover must clearly communicate {product} and match the video, rather than introduce a different topic."""
    caption = f'{title}\nبرای انتخاب ابزار و استعلام شرایط، به راه بوم پیام بده.\nتلگرام: @rahboom1 | rahboom.com'
    return {'output_kind': 'prompt_package', 'source': 'editorial', 'editorial_review': True,
            'title': title, 'caption': caption, 'hashtags': ['راه_بوم', 'هوش_مصنوعی'],
            'full_prompt': full, 'cover_prompt': cover, 'blocks': [{'label': 'Full video prompt', 'text': full, 'language': 'en'},
                                          {'label': 'Persian dialogue', 'text': dialogue, 'language': 'fa'},
                                          {'label': 'Cover — prompt', 'text': cover, 'language': 'en'}],
            'target_seconds': 10, 'production_tool': 'Google Flow', 'weekly_series': SERIES,
            'purpose': purpose, 'scheduled_date': day.isoformat(), 'requires_character_references': True}


def prepare_week(db, brand, start):
    if not is_rahboom(brand):
        raise ValueError('This reviewed starter week is for Rahboom.')
    end = start + timedelta(days=6)
    existing = list(db.scalars(select(Post).where(Post.brand_id == brand.id,
                         Post.for_date >= start.isoformat(), Post.for_date <= end.isoformat())))
    result = []
    for offset in range(7):
        day = start + timedelta(days=offset)
        p = next((p for p in existing if p.for_date == day.isoformat() and
                  (p.content or {}).get('weekly_series') == SERIES), None)
        if p is None:
            content = package((day.weekday() + 2) % 7, day)
            p = Post(brand_id=brand.id, post_type='video_prompt', mode='video', status='ready',
                     for_date=day.isoformat(), topic_hint=content['title'], content=content)
            db.add(p)
        elif p.status == 'ready' and (p.content or {}).get('source') == 'editorial' and p.content.get('full_prompt') != package((day.weekday() + 2) % 7, day)['full_prompt']:
            p.content = package((day.weekday() + 2) % 7, day)
        if p.status != 'deleted':
            result.append(p)
    db.flush()
    return result
