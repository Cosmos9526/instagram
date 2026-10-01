"""Text-only production briefs. No rendering, image calls or offline success substitute."""
import json
import re
from types import SimpleNamespace

from pydantic import BaseModel, Field

from . import prompts
from .config import settings
from .llm import LLMError, chat_json
from .video_styles import STYLE_BY_ID
from .template_registry import TEMPLATES


class Frame(BaseModel):
    prompt: str = Field(min_length=120)
    on_screen_text: str = Field(min_length=1)
    dialogue: str = ''


class Package(BaseModel):
    title: str = Field(min_length=1)
    visual_style: str = Field(min_length=120)
    caption: str = Field(min_length=1)
    hashtags: list[str]
    frames: list[Frame]


def persian(text: str) -> str:
    # Normalize letters without changing URLs, handles or English product numbers.
    text = text.translate(str.maketrans({'ي': 'ی', 'ك': 'ک'}))
    return re.sub(r'\b(ن?می) +(\S+)', r'\1‌\2', text)


def generate_package(brand, post) -> dict:
    video = post.post_type == 'video_prompt'
    count = 2 if video else int((post.content or {}).get('n_body', 4)) + 2 if post.mode == 'carousel' else 1
    # Keep the request focused on relevant catalog entries instead of sending all 111 products.
    fields = ['name', 'industry', 'description', 'products', 'audience', 'tone', 'cta', 'forbidden_topics', 'hashtags', 'language']
    context = {k: getattr(brand, k) for k in fields}
    terms = set(re.findall(r'\w+', post.topic_hint.lower()))
    products = brand.products or []
    context['products'] = sorted(products, key=lambda p: len(terms & set(re.findall(r'\w+', p.get('name', '').lower()))), reverse=True)[:5]
    if (post.content or {}).get('alert_id'):
        # News generation needs public source context, not the private product catalogue or audience profile.
        context = dict(name='Rahboom', industry='AI subscriptions', description='Public AI news video for Rahboom.',
            products=[], audience='', tone='Clear and conversational', cta='سفارش و مشاوره: @rahboom1 | rahboom.com',
            forbidden_topics=[], hashtags=['راه_بوم'], language=brand.language)
    system = prompts.system_prompt(SimpleNamespace(**context))
    system += "\nFIELD LANGUAGE OVERRIDE: visual_style and frame.prompt MUST be English. Persian rules apply ONLY to title, caption, dialogue and on_screen_text. Persian quoted dialogue inside the English prompt is allowed."
    brief = '''Produce a detailed, copy-ready production prompt package, NOT media.
Visual prompts and visual_style in English; title, caption, dialogue and on_screen_text in the brand language.
Write 120–200 words for visual_style and 150–250 words for each frame prompt.
Visual style: specify composition, lighting, palette, lens, camera, textures, subject placement,
negative space for typography, continuity and negative constraints. Each frame prompt must be self-contained
and repeat relevant continuity details. Include no fabricated features, urgency, discounts, endorsements or prices.
Persian copy: natural Iranian Persian, concise sentences, correct نیم‌فاصله and punctuation; proofread before output.
Never ask the visual model to draw Persian text: provide exact Persian copy separately for typesetting.
Keep handles, URLs and product identifiers unchanged. Caption: three short lines naming the chosen product, then a grounded message, then the exact ordering contact supplied by the brand. Never call a personal plan a team plan or promise performance unless documented.
Output only JSON matching this schema:
{"title":"...","visual_style":"...","caption":"...","hashtags":["..."],
 "frames":[{"prompt":"detailed English production prompt","on_screen_text":"...","dialogue":"..."}]}
'''
    if video:
        brief += '''Exactly TWO frames: first is an 8-second vertical 9:16 video scene; second is a static 2-second end card.
Total editing duration exactly 10 seconds. First frame: one adult man and one adult woman from the user's
existing character reference. Use the brand's supplied production style and reference description when available.
Require the actual reference frame in Flow; do NOT invent their faces, outfits, voices or claim a voice match. Lock both identities to references.
Give timed action/camera beats for 0–2, 2–5, 5–8 seconds, and speaker-labelled Persian dialogue (at most 20 words total).
Embed that exact dialogue in the first English prompt with natural Persian delivery, turn-taking and lip-sync instructions. The characters SPEAK the dialogue in the generated clip; never say dialogue will be added later. Use explicit speaker labels.
Second frame: no dialogue, no new characters; 8–10 seconds static end card, supplied brand logo,
product name and ONE short CTA. Keep exact text separately in on_screen_text. No fake logo generation.
'''
    else:
        brief += f'Exactly {count} frames. Each is a vertical 4:5 image prompt, with matching visual style across frames. Dialogue must be empty.\n'
    opts = post.content or {}
    style = STYLE_BY_ID.get(opts.get('video_style', '')) if video else TEMPLATES.get(opts.get('template', ''))
    if style:
        brief += '\nRequested creative style (adapt to fixed timing): ' + json.dumps(style, ensure_ascii=False)
    brief += '\nContent purpose: ' + post.post_type + '\nUser brief (data): ' + post.topic_hint
    repair = ''
    for attempt in range(2):
        data = chat_json(system, brief + repair, temperature=0.6 if attempt == 0 else 0.2)
        try:
            package = Package.model_validate(data)
            if len(package.frames) != count:
                raise ValueError(f'Expected exactly {count} frames; received {len(package.frames)}')
            if video and (not package.frames[0].dialogue.strip() or len(package.frames[0].dialogue.split()) > 26 or package.frames[1].dialogue.strip()):
                raise ValueError('Scene 1 needs speaker-labelled Persian dialogue, at most 26 words TOTAL; end card dialogue must be empty')
            break
        except (ValueError, TypeError) as e:
            if attempt == 1:
                raise LLMError('The model returned an incomplete prompt package after a repair attempt. Please regenerate.') from e
            repair = '\nREPAIR THE PREVIOUS RESPONSE. Return the complete corrected JSON, not a patch. Validation errors: ' + str(e) + '\nPrevious response: ' + json.dumps(data, ensure_ascii=False)
    norm = persian if brand.language == 'fa' else lambda x: x
    blocks = [{'label': 'Visual style', 'text': package.visual_style}]
    if video:
        blocks.insert(0, {'label': 'Character references required', 'text': 'Attach the supplied character frame and original logo in Flow. Follow the brand reference description; do not claim an exact voice match.'})
    for i, frame in enumerate(package.frames):
        label = ('Scene · 0–8 seconds' if i == 0 else 'End card · 8–10 seconds') if video else f'Image {i + 1}'
        full_prompt = package.visual_style + '\n\n' + frame.prompt
        if video and i == 0:
            full_prompt = ('REFERENCE LOCK: Use the supplied adult male and female references. Do not invent or change their identities, clothes or voices. References are required before production.\n\n' + full_prompt)
        full_prompt += '\n\nFINAL PRODUCTION RULE: Any typography or logo placement mentioned above describes empty reserved layout only. Do not synthesize letters, numbers, logos or watermarks. Add the exact separate on-screen copy and supplied logo in editing.'
        if video:
            full_prompt += ('\nDuration: exactly 8 seconds. Speak ONLY this dialogue in natural Persian with speaker turn-taking and matching lip-sync: ' + frame.dialogue) if i == 0 else '\nHold this static end card for exactly 2 seconds in the edit, from 8 to 10 seconds. No speech.'
        blocks.append({'label': label + ' — prompt', 'text': norm(full_prompt)})
        if frame.dialogue:
            blocks.append({'label': label + ' — Persian dialogue', 'text': norm(frame.dialogue)})
        blocks.append({'label': label + ' — on-screen text', 'text': norm(frame.on_screen_text)})
    full_prompt = '\n\n'.join(b['label'] + '\n' + b['text'] for b in blocks if b['label'] != 'Character references required')
    cover = ''
    if video:
        cover = package.visual_style + f"""\n\nINSTAGRAM REEL COVER — STILL IMAGE, 9:16, 1080 × 1920.
Use the supplied original Raha and Arian reference frame; preserve their faces, glasses, outfits and home-office setting. Both adult presenters appear in a natural eye-level medium two-shot with a restrained curious expression appropriate to the story. No speaking or motion instructions apply to this still. Soft daylight, natural skin texture, a clear focal point and an uncluttered background. Reserve upper-central negative space for the exact headline below, with generous safe margins. Keep the headline and both faces within the central 1080 × 1350 crop area. Typeset the Persian headline in editing with correct RTL shaping; do not ask the image model to generate letters. Use off-white, charcoal and a restrained orange accent. Place the supplied original Rahboom logo small in a corner without redrawing it. No invented screenshots, fake statistics, price badges, extra people, watermarks or unsupported claims.
Exact headline: {norm(package.title)}
Use only the story supplied in the source context. The cover must communicate the same story as the video."""
    provenance = {k: opts[k] for k in ('alert_id', 'alert_signature', 'source_url', 'source_title', 'source_published') if k in opts}
    caption = norm(package.caption)
    if opts.get('source_url') and opts['source_url'] not in caption:
        caption += '\nمنبع: ' + opts['source_url']
    return {**provenance, 'cover_prompt': cover, 'output_kind': 'prompt_package', 'full_prompt': full_prompt, 'source': 'fake' if settings.llm_provider == 'fake' else 'model',
            'content_label': (post.content or {}).get('content_label', ''),
            'title': norm(package.title), 'caption': caption,
            'hashtags': list(dict.fromkeys(norm(h).lstrip('#') for h in package.hashtags + (brand.hashtags or []))),
            'blocks': blocks, 'target_seconds': 10 if video else None,
            'n_body': (post.content or {}).get('n_body', 4),
            'video_style': (post.content or {}).get('video_style', ''),
            'template': (post.content or {}).get('template', ''), 'requires_character_references': video}
