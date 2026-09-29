# Prompt-only production

New posts default to text-only prompt packages (PROMPT_ONLY=true). They never call an image provider or render PNGs. Existing rendered posts remain viewable. Model failures fail the job instead of creating an offline substitute.

Image packages include self-contained English visual prompts, separate Persian on-image copy and captions. Carousel packages keep the requested cover/body/CTA frame count. Video packages use a fixed 8-second dialogue scene and 2-second end card. Existing male/female character references must be supplied to the external production tool; no appearance or voice match is claimed before references are available.

The new view exposes copyable cards with content-specific text direction. Arabic yeh/kaf and common Persian verb spacing are normalized without changing handles or URLs. Prices must come from the supplied brand brief. Relevant products are ranked by the topic, with at most five catalog records sent to the model.

Validation includes no-render/no-image-call regression tests, malformed-response rejection, model-failure propagation and fixed timing/reference requirements. Production smoke tests must produce source=model and no slide media.
