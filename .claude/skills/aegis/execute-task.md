---
name: execute-task
description: Use when picking up any task — governs how to triage, route, and drive tasks to completion without unnecessary stops. Covers dispatch logic, trivial vs. complex routing, and autonomous execution rules.
---

# Execute Task

## The Core Rule

Pick up a task. Run it to completion. Report result. Don't stop in the middle for things you can figure out yourself.

The test: **would a skilled contractor call the client for this?** If yes, surface a challenge. If no, handle it and keep going.

## Routing: Trivial vs. Complex

Before doing anything, classify the task:

**Trivial** (do it inline, no research needed):
- ≤ 3 file/code changes
- Known library or API you have working examples for
- No credentials needed (or already available in env)
- Can verify in < 2 minutes

**Complex** (run the full discovery loop):
- Connecting to a new external service
- Multi-step research required
- Credentials/auth needed
- Unknown failure mode

For **trivial** tasks:
1. Do the work directly
2. Verify it worked (run it, check output)
3. Report result via `aegis:report-progress` (type: result)

For **complex** tasks: use `aegis:connection-discovery`.

## Autonomous Execution Rules

Run autonomously through these transitions — do NOT stop between them:

```
understand → research → generate → test → observe → adapt → verify → report
```

Stop only when you hit a **genuine blocker** — something only the user can provide:
- Credential you don't have
- MFA code from their authenticator  
- Irreversible action needing approval
- Fully blocked after 3+ distinct approaches

Do NOT stop for:
- Which endpoint to try next
- Whether to install a missing package
- Rate limit backoff timing
- Trying a different auth scheme

## Progress Cadence

Long-running task rules:
- Push a progress update (type: progress) every 3 minutes
- Push immediately when you discover something significant
- Push immediately when blocked — don't sit on it
- Never go silent for > 5 minutes

## Handling Failures

When something fails, read the error completely before trying anything:

| Signal | Action |
|---|---|
| 401/403 | Wrong credentials or missing scope — check auth docs before retrying |
| 404 | Wrong endpoint — re-read docs |
| 429 | Rate limited — add backoff, don't hammer |
| 5xx | Service error — wait 30s, retry once, then try different approach |
| CAPTCHA / login wall | Switch to Playwright |
| Same error 3× | Change approach entirely — stop guessing |

After 3 failed attempts at the same layer, step back and rethink from first principles. Don't keep adjusting the same wrong approach.

## Output Discipline

Large command output floods context and degrades reasoning quality. Rules:
- Capture output, then analyze and summarize — don't dump raw bytes to context
- When running a command that might produce large output, pipe to a file and read selectively
- Print findings (what matters) not raw data (everything)
- `| head -20` loses the rest — capture the full output to a temp file, then extract what you need

```bash
# Instead of: curl ... | head -20
curl ... > /tmp/api_response.json
python3 -c "
import json
data = json.load(open('/tmp/api_response.json'))
print(f'Status: {data.get(\"status\")}')
print(f'Records: {len(data.get(\"items\", []))}')
# Print the specific things that matter
"
```

## Completion Gate

Before reporting success:
1. Did you actually run the code/connection/action?
2. Did it return real data (not empty, not mocked)?
3. Did you read the output and confirm it worked?

If any answer is no — you are not done. Use `superpowers:verification-before-completion`.
