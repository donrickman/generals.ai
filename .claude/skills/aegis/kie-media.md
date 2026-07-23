---
name: kie-media
description: Use when the user asks to generate or edit an image, a video, music, or audio (make/create/generate a picture, art, clip, song, jingle, voiceover). Produces a media file the user can open.
---

# Generate media with kie.ai

You can generate images, video, music, and audio. The kie.ai API is reached at `$KIE_BASE_URL`
(a local proxy that holds the key — you never need a key, never put one in code). If `$KIE_BASE_URL`
is unset, this capability is unavailable — tell the user briefly and stop.

## Flow
1. **Pick a model.** Read `kie-models.md` (same folder) ONLY NOW, to choose the right model for the
   request (image vs video vs music, quality vs speed/cost). Do not read it otherwise.
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
   Convert kie's reported credits to USD yourself if the response reports credits (ask nothing of the
   user). Best-effort — if the POST fails, still report the result.
6. **Finish.** Call `mcp__aegis__report_result(status="succeeded", summary="<spoken, plain text>")`.
   The summary is spoken aloud — say what you made, not a file path.

## Rules
- Never generate content that is disallowed (sexual content involving minors, real-person deepfakes,
  etc.). Decline briefly and stop.
- One generation per request unless asked for variations. Match effort to the ask (don't render a
  4-minute video for "make a quick icon").
