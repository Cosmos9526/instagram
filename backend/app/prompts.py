"""All prompts in one place. Outputs for end users are Persian when brand.language == 'fa'."""

import json

from .models import Brand
from .template_registry import TEMPLATES, slot_spec_text
from .video_styles import STYLE_BY_ID

FA_RULES = """Write in fluent, natural Persian as used by good Iranian Instagram brands
(polite-colloquial, never translated-sounding). Use Persian digits (۰-۹), the zero-width
non-joiner correctly (می‌خواهید، محصول‌ها), Persian punctuation (، ؛ ؟ « »), and the Persian
letters ی and ک (never Arabic ي ك). Do not mix in English words except brand/product names."""

EN_RULES = "Write in clear, natural, native English for Instagram."

TYPE_BRIEF = {
    "educational": """EDUCATIONAL post: teach the audience something genuinely useful related to
the brand's field (a tip, a mistake to avoid, a how-to, a myth vs fact). Value first; mention the
product at most once, softly. The reader should want to SAVE this post.""",
    "news": """NEWS post: a timely item about the brand's industry. If a topic_hint is given, it is the
news/trend to cover — explain it briefly and say why it matters to this audience. If no hint is
given, pick an evergreen "did you know" industry fact and do NOT invent specific dates, numbers,
companies or events. Never fabricate news.""",
    "promo": """PROMOTIONAL post: present ONE product/service from the list: the problem it solves,
the main benefit, and why this brand. Aspirational, not pushy. End with the brand CTA.""",
    "sales": """SALES post: a direct offer to buy now for ONE product. Use urgency honestly (no fake
deadlines or discounts that the brand did not provide — if no discount is known, use a benefit
or free consultation as the hook instead of a percentage). Strong single CTA.""",
}


def brand_block(b: Brand) -> str:
    return json.dumps(
        {
            "name": b.name,
            "industry": b.industry,
            "about": b.description,
            "products": b.products,
            "audience": b.audience,
            "tone": b.tone,
            "cta_style": b.cta,
            "forbidden_topics": b.forbidden_topics,
            "fixed_hashtags": b.hashtags,
        },
        ensure_ascii=False,
        indent=1,
    )


def system_prompt(b: Brand) -> str:
    return f"""You are the senior social-media copywriter for the brand below. You produce ready-to-post
Instagram content that fits the brand exactly.
{FA_RULES if b.language == 'fa' else EN_RULES}

Hard rules:
- Never mention or allude to any forbidden topic: {', '.join(b.forbidden_topics) or 'none listed'}.
  Also avoid politics, religion, tragedies, and health or legal claims.
- Only state facts about products that appear in the brand data. No invented prices or discounts.
- Headlines: no emojis, no trailing period. Captions: max 2 emojis.
- Character limits are HARD: count every character including spaces.
- image_prompt fields are always in ENGLISH, describe a photo/illustration with subject,
  composition, lighting and mood, and must never ask for text, letters, logos or signs.
- Output ONLY valid JSON matching the requested schema.

<brand>
{brand_block(b)}
</brand>"""


def research_block(research: str) -> str:
    if not research:
        return ""
    return f"""
<market_research>
{research}
</market_research>
Use this research: prefer its trends and keywords when they fit the brief, and weave 1-3 of the keywords
naturally into the caption and hashtags. Never contradict the brand data.
"""


def single_post_prompt(b: Brand, post_type: str, topic_hint: str, recent_headlines: list[str],
                       code: str, research: str = "") -> str:
    spec = TEMPLATES[code]
    return f"""{TYPE_BRIEF[post_type]}
Visual format: "{spec['name_fa']}" — {spec['desc_fa']}. Write copy that suits this format.
{research_block(research)}
<topic_hint>{topic_hint or 'none'}</topic_hint>
<avoid_repeating>Recent headlines of this brand (do not repeat their angle): {json.dumps(recent_headlines, ensure_ascii=False)}</avoid_repeating>

Fill the "{code}" template. Slots: {slot_spec_text(code)}.
Return JSON:
{{
  "template": "{code}",
  "slots": {{ ...the slots above... }},
  "image_prompt": "English visual description, or empty string if the template has no image",
  "caption": "3-6 short lines: hook first, value, CTA last",
  "hashtags": ["10-15 relevant hashtags without #, Persian ones use _ instead of spaces"],
  "alt_text": "one-sentence accessibility description"
}}"""


def carousel_prompt(b: Brand, post_type: str, topic_hint: str, recent_headlines: list[str], n_body: int,
                    research: str = "") -> str:
    return f"""{TYPE_BRIEF[post_type]}
{research_block(research)}
Format: a CAROUSEL of {n_body + 2} slides — 1 cover, {n_body} body slides, 1 CTA slide.
Cover headline = a curiosity hook that makes people swipe (≤ 8 words).
Each body slide delivers exactly ONE idea and builds on the previous one.

<topic_hint>{topic_hint or 'none'}</topic_hint>
<avoid_repeating>{json.dumps(recent_headlines, ensure_ascii=False)}</avoid_repeating>

Slot limits — cover: {slot_spec_text('car_cover')}; body: {slot_spec_text('car_body')}; cta: {slot_spec_text('car_cta')}.
Return JSON:
{{
  "cover": {{"headline": "..."}},
  "body": [{{"headline": "...", "body": "..."}}],
  "cta": {{"headline": "...", "cta": "..."}},
  "image_prompt": "English visual for the cover image",
  "caption": "...",
  "hashtags": ["..."],
  "alt_text": "..."
}}"""


def repair_prompt(original_json: dict, errors: list[str]) -> str:
    return f"""These slots exceed their hard character limits: {', '.join(errors)}.
Shorten ONLY those fields, keep the meaning and language, and return the same JSON structure.
<json>{json.dumps(original_json, ensure_ascii=False)}</json>"""


def video_prompt(b: Brand, topic_hint: str, target_seconds: int, style_id: str = "", research: str = "") -> str:
    clips = max(1, min(4, round(target_seconds / 8)))
    lang_name = "Persian" if b.language == "fa" else "English"
    style = STYLE_BY_ID.get(style_id)
    style_block = (
        f"""
Video style: {style['name_en']} — {style['description_en']}
Beat structure to follow (one beat per clip, merge or extend if the clip count differs): {'; '.join(style['beats'])}
Camera language: {style['camera']}. Pacing: {style['pacing']}.
"""
        if style
        else ""
    )
    return f"""{style_block}{research_block(research)}
Create a PROMPT PACKAGE for a vertical 9:16 Instagram Reel of about {target_seconds} seconds
for this brand. The user will paste each clip prompt into an AI video model (Veo / Kling / Sora)
that makes ~8-second clips with no memory between clips. The clips will be joined into ONE
continuous video, so continuity is everything.

Idea/topic: {topic_hint or 'choose a strong idea that shows the brand’s main product in use'}

Rules:
- Exactly {clips} clips. One location. Max 2 characters, adults, no real/famous people, no children.
- "bible_text": ONE dense English paragraph (120-200 words), present tense, describing characters
  (age range, face, skin tone, hair, eye colour, build, every clothing item with colour and
  material), location, props, lighting (direction, colour temperature in K), camera (lens mm,
  height, movement style) and visual style. No clip-specific action in it. It will be pasted
  VERBATIM at the start of every clip prompt.
- Every clip ends on a near-still 0.7 s "hold" (stable pose, face visible) so its last frame can
  seed the next clip. Clip i+1 "start_state" must equal clip i "end_state".
- No readable text, logos or signs inside the video (captions are added in editing).
- Avoid anything likely to be refused by video-model safety filters.
- "voiceover" and "caption_text" are in {lang_name}; everything else in English.

Return JSON:
{{
  "title": "short {lang_name} title for the panel",
  "idea": "one-sentence {lang_name} summary",
  "total_seconds": {target_seconds},
  "bible_text": "...",
  "keyframe_prompt": "English image prompt for the very first frame (bible_text + opening pose)",
  "clips": [
    {{"n": 1, "seconds": 8, "start_state": "...", "action": "...", "camera": "...",
      "end_state": "...", "voiceover": "...", "caption_text": "short on-screen caption"}}
  ],
  "music_mood": "e.g. warm acoustic, 90 bpm",
  "caption": "Instagram caption in {lang_name}",
  "hashtags": ["..."]
}}"""


def assemble_clip_prompt(bible_text: str, clip: dict, n: int, total: int) -> str:
    """Built in code (not by the model) so the bible is always byte-identical."""
    seed = (
        "Start from the provided image as frame 1."
        if n == 1
        else "Use the LAST FRAME of the previous clip as the input image; this shot continues it directly."
    )
    return (
        f"{bible_text}\n\n"
        f"SHOT {n}/{total} ({clip.get('seconds', 8)}s, 9:16, no cuts). {seed} "
        f"Start: {clip.get('start_state', '')} Action: {clip.get('action', '')} "
        f"Camera: {clip.get('camera', '')} End on a near-still hold: {clip.get('end_state', '')}\n"
        "Avoid: text, logos, extra people, face or outfit changes, morphing, jump cuts."
    )
