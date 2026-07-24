---
name: kie-media
description: Use when the user asks to generate or edit an image, a video, music, or audio (make/create/generate a picture, art, clip, song, jingle, voiceover). Produces a media file the user can open.
---

# Generate media (image · video · music · audio)

You can generate images, video, music, and audio. The generator API is reached at `$KIE_BASE_URL`
(a local proxy that holds the key — you never need a key, never put one in code). If `$KIE_BASE_URL`
is unset, this capability is unavailable — tell the user briefly and stop.

## What to call it — NEVER say the vendor name
To the user this is **your own capability**: "my image generation," "my video generation," "my media
tools." NEVER say "kie", "kie.ai", or name any vendor or model — not in speech, progress updates,
results, errors, or challenge text. The user should believe *you* make the media.
- ✅ "I'm rendering your video now." · "My video generator hit a snag — want me to retry?"
- ❌ "kie.ai kicked the session." · "kie.ai flaked on us." · "Digging through kie.ai history."

`$KIE_BASE_URL`, the `"source":"kie"` telemetry, and model IDs are INTERNAL plumbing — fine in code
and telemetry, never spoken. Generation runs on the API key at `$KIE_BASE_URL` — there is NO login,
NO browser sign-in, and NO credentials to collect. If you find yourself opening a browser or raising
a login/OTP challenge for media, you are on the wrong path — stop and use the `$KIE_BASE_URL` API.

## Flow
1. **Pick a model — default to the cheapest, fastest one that can do the job.** Read `kie-models.md`
   (same folder) ONLY NOW. Always start from the cheap/fast tier (e.g. a Lite image model). Do NOT
   reach for premium/pro/ultra or slow models on your own — this is shared, company-paid compute.
   Only use a pricier model if the user *explicitly* asked for that model or that quality. If the
   user wants consistently higher-end generation, tell them they can connect their own media account
   (their own kie.ai or provider key) rather than us defaulting to expensive models.
2. **Create the task.** POST the model's create-task endpoint at `$KIE_BASE_URL` with the prompt and
   parameters. You get back a `task_id`. A 200 means *created*, not done.
3. **Poll for completion.** GET the query-record endpoint with the `task_id`, backing off (e.g. 3s,
   then 5s, then 10s). Call `mcp__aegis__report_progress` while waiting ("Still rendering your
   video…") so you are never silent > ~30s. Do NOT busy-loop with no sleep.
4. **Download immediately.** When complete, the response has an output URL AND the credit
   consumption. kie deletes outputs after ~14 days and the link expires in ~20 minutes — download
   the file NOW into `~/workspace/media/` with a descriptive filename (e.g. `sunset-city.mp4`). That
   directory is served to the app; the user opens it from History → Media.
5. **Report the cost.** Immediately after a successful generation, emit usage telemetry so the
   user's account is charged (this is the ONLY place cost is recorded — the proxy does not do it):
   ```bash
   curl -s -X POST "$AEGIS_API_URL/api/v1/telemetry" \
     -H "X-Telemetry-Key: $TELEMETRY_KEY" -H "Content-Type: application/json" \
     -d '{"event_type":"enclave.media_usage","source":"kie","user_id":"'"$ENCLAVE_USER_ID"'",
          "data":{"cost_usd": <USD>, "service":"kie", "method":"api_key",
                  "model":"<model id>", "task_id":"<task id>"}}'
   ```
   `record-info` does NOT include a cost field — set `cost_usd` from the model you used: its fixed
   credit price (see kie.ai/pricing / the catalog) converted to USD. Ask the user nothing about cost.
   Best-effort — if the POST fails, still report the result.
6. **Finish.** Call `mcp__aegis__report_result(status="succeeded", summary="<spoken, plain text>")`.
   The summary is spoken aloud — say what you made, not a file path, and never name the vendor
   (see "What to call it").

## Rules
- Never say "kie"/"kie.ai" or any vendor/model name to the user — it's your own capability (see "What to call it").
- Never generate content that is disallowed (sexual content involving minors, real-person deepfakes,
  etc.). Decline briefly and stop.
- One generation per request unless asked for variations. Match effort to the ask (don't render a
  4-minute video for "make a quick icon").
