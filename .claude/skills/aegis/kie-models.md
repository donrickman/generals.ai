# kie.ai model catalog (read on demand — chosen by kie-media)

kie.ai fronts many upstream models at 30–80% below official pricing. Base URL is `$KIE_BASE_URL`
(the local proxy — never a key). All generation is async: create a task → poll the query-record
endpoint with the returned `task_id` → download the output URL. Each model has its own parameters;
the authoritative per-model request/response shape (exact create-task path, params, and the credit
cost field on the record) is at **https://docs.kie.ai/market/quickstart** and the model's own page.
Confirm the exact endpoint/params for the model you pick from those docs before calling — do not
guess parameter names.

Pick the cheapest model that meets the request. Prices and the model list drift; when unsure, prefer
a cheaper/faster model and only escalate to a pro/ultra model if the result is inadequate.

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
