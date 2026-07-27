# kie.ai model catalog (read on demand — chosen by kie-media)

kie.ai fronts many upstream models at 30–80% below official pricing. Base URL is `$KIE_BASE_URL`
(the local proxy — never a key). All generation is async: create a task → poll the query-record
endpoint with the returned `task_id` → download the output URL. Each model has its own parameters;
the authoritative per-model request/response shape (exact create-task path, params) is at
**https://docs.kie.ai/market/quickstart** and the model's own page. Confirm the exact endpoint/params
for the model you pick from those docs before calling — do not guess parameter names.

## DEFAULT TO CHEAP + FAST (this is a hard rule, not a preference)
This is shared, company-paid compute. **Always default to the cheapest, fastest model that can
plausibly do the job** — a Lite/fast image model, a short cheap video model, a fast TTS. Do NOT pick
a pro/ultra/premium or a slow model unless the user *explicitly* named it or asked for that quality.
If a user wants consistently high-end output, say they can connect their own media account (their own
kie.ai or provider key) — we do not default to expensive models on their behalf.

Recommended cheap defaults by type: **image →** Seedream Lite (or imagen4-fast / Nano Banana);
**video →** Wan (short) over Veo/Runway premium; **speech/audio →** ElevenLabs turbo TTS. Avoid
4o Image as a default — it is both pricier and slow. Escalate ONLY on an explicit request, and even
then prefer the lowest tier that meets it.

Cost note: kie's `record-info` does NOT report per-task cost. Report the model's ACTUAL published
price in the telemetry call — take it from the model's own doc page (each model page lists its price;
do NOT guess a round number). Convert to USD if it's quoted in credits. This number is what the user
is billed, so use the real per-generation price for the model you actually ran — not a placeholder.
`GET /api/v1/chat/credit` returns the remaining account balance (a useful pre-flight check, and the
before/after delta is the ground-truth credits spent if you ever need to reconcile a single run).
(Backend note: reported costs are validated in aggregate against kie's real account billing by the
usage-reconciliation job, so a systematically wrong price will surface there — report honestly.)

## Images (text→image, and image edit)
| Model | Good for | Notes |
|---|---|---|
| Seedream 5.0 Lite | fast, cheap general images | text→image and image→image variants |
| Seedream 5.0 Pro | higher quality general images | costs more than Lite |
| Google Nano Banana / Nano Banana 2 | strong prompt adherence, edits | "Edit" variant takes an input image |
| Google Imagen4 / imagen4-ultra / imagen4-fast | photoreal, quality tiers | ultra = best/most expensive, fast = cheapest |
| Flux Kontext | precise editing / style transfer | dedicated `/flux-kontext-api/` endpoints |
| Qwen Image / Qwen2 | image + image-edit | alternative image family |
| 4o Image | GPT-4o image generation | dedicated `/4o-image-api/` endpoints |

Image edit (change an existing image): use an "Edit" / image→image model and pass the input image.
Upload local inputs first via the File Upload API if the model needs a URL.

## Video (text→video, image→video, upscale)
| Model | Good for | Notes |
|---|---|---|
| Runway | general text/image→video | dedicated `/runway-api/`; supports extend |
| Veo | high-quality text→video | premium tier |
| Wan 2.7 | text/image→video | cheaper video option |
| Topaz Video Upscale | upscale an existing video | input is a video, not a prompt |
| Infinitalk (from audio) | talking-avatar video from audio | input is an audio clip |

Video is the slowest/most expensive class — expect minutes. Report progress while polling.

## Music & audio
| Model | Good for | Notes |
|---|---|---|
| ElevenLabs TTS (turbo) | text→speech, voiceover | fast, natural speech |
| ElevenLabs (STT / audio isolation) | transcription, clean-up | non-generative audio tasks |
| Suno-style music models | songs / jingles with lyrics + style | lyric + style params |

## Chat (rarely needed here — you are already an LLM)
Gemini 2.5 Flash / Pro are available via the Market chat models, but you normally answer directly;
only route to these if the user explicitly wants a specific model's output.
