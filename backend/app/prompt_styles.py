"""Original reusable visual briefs; no third-party prompt scraping or model calls."""
from .video_styles import VIDEO_STYLES

IMAGE_DIRECTIONS = [
    ("studio", "Premium studio", "استودیویی لوکس", "A single hero subject on a warm-white seamless backdrop. Soft overhead key light, controlled rim light, realistic microtexture, a subtle grounded shadow. 85mm product-photography composition; generous breathing room."),
    ("editorial", "Editorial portrait", "پرترهٔ مجله‌ای", "Editorial portrait with a 50mm lens at eye level, soft window light, natural skin texture, restrained warm grading, authentic expression, a quiet out-of-focus workspace. Keep the subject clearly separated from the background."),
    ("isometric", "Isometric 3D", "سه‌بعدی ایزومتریک", "An isometric miniature scene with coherent scale, clean rounded geometry, matte materials, ambient occlusion and soft studio shadows. Use a limited orange, charcoal and cream palette. One clear visual metaphor."),
    ("paper", "Paper cutout", "کاغذبری لایه‌ای", "Layered paper-cut illustration with tactile paper grain, precise cut edges, shallow cast shadows and an orange-to-cream palette. Use three to five depth layers and a readable central silhouette."),
    ("clay", "Clay miniature", "مینیاتور خمیری", "Handcrafted clay miniature with soft rounded silhouettes, subtle fingerprints and matte surfaces. Warm tabletop lighting, shallow depth of field and a playful, balanced composition. Avoid plastic gloss."),
    ("neon", "Neon technology", "فناوری نئونی", "A dark charcoal environment with restrained cyan and orange edge lighting, a single luminous subject and physically plausible reflections. Maintain deep blacks and a clear focal point; avoid random dashboards or invented interface text."),
    ("flat", "Minimal vector", "وکتور مینیمال", "Flat editorial illustration using crisp geometric shapes, uniform line weight, high contrast and a maximum of four colors. No faux photorealism or texture. Make the central idea understandable at thumbnail size."),
    ("macro", "Macro detail", "جزئیات ماکرو", "Extreme close-up using a 100mm macro lens, a thin plane of sharp focus, carefully controlled highlights and tactile surface detail. Keep the subject recognizable; foreground and background bokeh should support the hero detail."),
    ("collage", "Editorial collage", "کلاژ مجله‌ای", "A deliberate editorial collage with cut photographic elements, torn-paper edges and layered geometric accents. One main subject, two supporting elements, consistent light direction and generous negative space. No borrowed logos or headlines."),
    ("comic", "Graphic comic", "کمیک گرافیکی", "Graphic comic illustration with confident ink contours, controlled halftone shading, dynamic perspective and an expressive central subject. Keep the visual readable in one panel; do not render speech bubbles or text."),
    ("glass", "Glass and light", "شیشه و نور", "A sculptural transparent-glass subject with realistic refraction, soft caustics and restrained orange highlights on a cream studio background. Clean silhouette, subtle depth and no floating decorative clutter."),
    ("film", "Analog cinematic", "سینمایی آنالوگ", "Cinematic still with a 35mm lens, warm practical lighting, subtle film grain, restrained contrast and motivated framing. Natural anatomy and material detail; no excessive bloom, lens flare or artificial sharpness."),
]

IMAGE_BASE = """Create ONE original Instagram visual, 1080x1350, 4:5 portrait.
Brand context: {{brand}}
User creative brief (preserve its specific subject and supplied facts):
{{brief}}
ART DIRECTION: {direction}
COMPOSITION: One main focal point, no more than two secondary elements. Leave the upper 20% uncluttered for a headline to be added in the editor. Keep important elements inside 8% safe margins. Balance the subject and negative space; avoid a crowded poster.
BRAND: Orange, charcoal and white accents. If a reference image is attached, preserve its identity, proportions and colors. Never invent or redraw a supplied logo. Do not add names, pricing, badges, guarantees or product-interface text absent from the brief.
OUTPUT: A clean background/hero visual. Add exact Persian headline and original logo later as separate editor layers for reliable spelling. No generated typography, watermark, fake buttons, extra limbs, malformed hands or unrelated objects.
"""

VIDEO_BASE = """Produce a vertical Instagram advertising sequence, 9:16, 1080x1920, 24fps. Total edit length exactly 10 seconds: an 8-second scene followed by a separate 2-second silent end card.
Brand context: {{brand}}
USER BRIEF: {{brief}}
Preserve all explicit subject, dialogue, reference and visual requirements in this brief. Use only supplied facts. Do not invent features, pricing, benchmark numbers, testimonials or promises.
STYLE: {name}. CAMERA: {camera}. RHYTHM: {pacing}.
SCENE TIMELINE:
0.0–2.0s — {first}. Establish one clear subject and one recognizable action; create a visual hook without fake statistics.
2.0–5.0s — {second}. Continue the same action with matching object positions, lighting and character identity. No unexplained scene jumps.
5.0–8.0s — {third}. Resolve the visual idea and settle camera motion; complete any spoken line by 7.6s.
LIGHT: Motivated soft key, controlled edge light, consistent exposure and natural textures. Orange accents, charcoal and cream support the Rahboom brand without overwhelming the scene.
CHARACTERS: When people are required, use the attached Raha and Arian references. Preserve their face, hair, age, clothing and screen position across frames. Do not claim reference identity is matched if no reference is attached. For product-only or hands-only briefs, do not introduce unrelated people.
AUDIO: If the brief supplies Persian dialogue, speak those exact words naturally in Persian with clear turn-taking and synchronized lips. No English speech, simultaneous voices or extra narration. If no dialogue is supplied, use subtle scene-specific sound and no invented speech. Keep music below dialogue.
8.0–10.0s END CARD: Assemble this separately if the model cannot reliably render it. Static warm-white background, the attached original Rahboom logo centered at its correct aspect ratio, generous margins. Add exact text 'rahboom.com' as an editor overlay. No dialogue, no additional claim, no logo morphing or camera movement.
CONTINUITY/NEGATIVE: No face drift, flicker, warped hands, unreadable interface text, random signage, watermark, unrequested subtitles, extra fingers, excessive cuts or music over speech. Export the scene and end card in the same frame size; join them without extending beyond 10 seconds.
"""

COVER = """Create an Instagram reel cover, 1080x1920, 9:16.
Brand: {{brand}}. Topic: {{brief}}.
Use this art direction: {direction}. One clear focal subject; strong thumbnail readability. Preserve supplied character references if used in the video. Keep the main subject inside the central square crop. Reserve the upper-middle area for a short Persian headline added later in the editor; keep top 15% and bottom 20% free of essential details. Orange, charcoal and white accents. Add the supplied original logo as an editor layer; never invent its geometry. No generated text, watermark, fake product claim or busy background.
"""


def prompt_styles():
    videos = [dict(id="video_" + s["id"], kind="video", name_en=s["name_en"],
                   name_fa=s["name_fa"], description=s["description_en"], video_style=s["id"],
                   prompt=VIDEO_BASE.replace("{name}", s["name_en"]).replace("{camera}", s["camera"])
                     .replace("{pacing}", s["pacing"]).replace("{first}", s["beats"][0])
                     .replace("{second}", s["beats"][1]).replace("{third}", s["beats"][2]),
                   cover_prompt=COVER.replace("{direction}", s["camera"] + "; " + s["name_en"]),
                   provenance="Original Rahboom template") for s in VIDEO_STYLES]
    images = [dict(id="image_" + key, kind="image", name_en=name, name_fa=fa,
                   description=direction, video_style="",
                   prompt=IMAGE_BASE.replace("{direction}", direction),
                   cover_prompt=COVER.replace("{direction}", direction),
                   provenance="Original Rahboom template") for key, name, fa, direction in IMAGE_DIRECTIONS]
    return videos + images
