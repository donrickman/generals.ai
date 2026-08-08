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
1. **Reuse a saved recipe if you have one — do NOT re-research every request.** Confirming a model's
   exact create-task path/params and looking up its price from the docs is the SLOW part; doing it on
   EVERY request makes a simple image take minutes. So FIRST check `~/.aegis/kie_recipes.json` (keyed
   by media type: `image`/`video`/`music`/`audio`): if it holds a recipe for this type, use it and go
   straight to step 2 — do NOT read the catalog or re-fetch docs/pricing. Only when there is NO saved
   recipe for this type (or a saved one just failed) do the lookup below (then save it — step 4).
   **Pick a model — default to the cheapest, fastest one that can do the job.** Read `kie-models.md`
   (same folder) ONLY NOW. Always start from the cheap/fast tier (e.g. a Lite image model). Do NOT
   reach for premium/pro/ultra or slow models on your own — this is shared, company-paid compute.
   Only use a pricier model if the user *explicitly* asked for that model or that quality. If the
   user wants consistently higher-end generation, tell them they can connect their own media account
   (their own kie.ai or provider key) rather than us defaulting to expensive models.
2. **Create the task.** POST the model's create-task endpoint at `$KIE_BASE_URL` with the prompt and
   parameters. You get back a `task_id`. A 200 means *created*, not done.
3. **Poll AND download inside ONE bash command — never poll turn-by-turn.** Making a separate tool
   call per poll burns the turn budget and the whole task fails with "reached maximum number of
   turns" (this is the #1 cause of media failures). BEFORE the loop, send ONE progress update
   ("Rendering your image now — this can take a minute or two"). Then run a SINGLE bash loop that
   polls with sleeps and downloads the result the moment it's ready. Shape (adjust the endpoint and
   JSON fields to the model you used — confirm them from the model's doc):
   ```bash
   for i in $(seq 1 45); do
     resp=$(curl -s "$KIE_BASE_URL/<the model's query-record path>?taskId=$TASK_ID")
     state=$(printf '%s' "$resp" | python3 -c "import sys,json;d=json.load(sys.stdin).get('data',{});print(d.get('successFlag'),d.get('status'))" 2>/dev/null)
     echo "poll $i: $state"
     case "$state" in
       "1 "*|*SUCCESS*)
         url=$(printf '%s' "$resp" | python3 -c "import sys,json;print(json.load(sys.stdin)['data']['response']['resultUrls'][0])")
         curl -s "$url" -o ~/workspace/media/<descriptive-name>.<ext>; echo "DONE $url"; break;;
       *FAIL*) echo "GENERATION FAILED: $resp"; break;;
     esac
     sleep 8
   done
   ```
   `~/workspace/media/` is served to the app (History → Media). kie deletes outputs after ~14 days and
   the link expires in ~20 minutes — this loop downloads immediately, which is why it must be one
   command. If the loop ends without `DONE`, the render is still running or failed — report honestly.
4. **Save the recipe, then report the cost.** Immediately after a successful generation: FIRST, if you
   just did a fresh lookup (no saved recipe), SAVE the working recipe to `~/.aegis/kie_recipes.json`
   keyed by media type — the create-task path, the exact param names you used, the model id, and its
   per-generation USD price — so the next request of this type skips the whole catalog/doc/pricing
   lookup (step 1). THEN record the cost so the user's
   account is charged — call the tool (do NOT curl the telemetry endpoint; you don't hold the key):
   ```
   mcp__aegis__report_media_usage(cost_usd=<USD>, model="<model id>", task_id="<task id>")
   ```
   `record-info` does NOT include a cost field — set `cost_usd` from the model you used: its fixed
   credit price (see kie.ai/pricing / the catalog) converted to USD. Ask the user nothing about cost.
   The system records it with the key you don't have. Call this ONCE, right before report_result.
5. **Finish.** Call `mcp__aegis__report_result(status="succeeded", summary="<spoken, plain text>")`.
   The summary is spoken aloud — say what you made, not a file path, and never name the vendor
   (see "What to call it").

## Rules
- **ONLY generate via the `$KIE_BASE_URL` API. NEVER draw or render the media yourself with code
  (PIL, matplotlib, SVG, HTML canvas, ffmpeg-synthesized frames) and NEVER web-search for or
  download an existing image/clip. A hand-drawn or downloaded file is NOT a generation — it is a
  wrong answer. If the API fails or you can't reach it, report failure honestly; do not substitute.**
- Never say "kie"/"kie.ai" or any vendor/model name to the user — it's your own capability (see "What to call it").
- Never generate content that is disallowed (sexual content involving minors, real-person deepfakes,
  etc.). Decline briefly and stop.
- One generation per request unless asked for variations. Match effort to the ask (don't render a
  4-minute video for "make a quick icon").
