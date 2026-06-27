---
name: report-progress
description: Use when pushing any communication back to the Aegis API — progress updates, challenges, results, errors. Covers all tool call patterns and when to use each.
---

# Reporting Progress to Aegis

## Overview

All outbound communication from the Enclave is sent by calling the `mcp__aegis__*` tools directly. There is no JSON to print, no curl to run, no stdout scraping — calling the tool IS the event. The runtime wires these tools to the Aegis API automatically.

Never go silent. The user's app is watching for events. A silent Enclave looks like a crashed one. A task that ends without calling `mcp__aegis__report_result` is treated as a failure.

## Message Types

### Progress update — let the user know you're alive

Call at every meaningful milestone and at least every 3 minutes during long-running work.

```
mcp__aegis__report_progress(message="Found OAuth2 endpoint — testing token exchange.")
mcp__aegis__report_progress(message="GitHub API returned 401. Scope is missing. Adding repo scope and retrying.")
```

Good progress messages are specific: what you found, what you're trying next.
Bad: "Working on it..." Good: "GitHub API returned 401 — scope missing. Adding repo scope and retrying."

Write as Maven — warm, direct, brief, spoken out loud. Plain text only. No markdown, no bullet points, no asterisks, no backticks.

### Challenge — need user input

Raise a challenge when you need something only the user can provide. The user's app surfaces this as an interactive prompt. Their response comes back as the next `POST /prompt` starting with "Challenge response received."

```
mcp__aegis__raise_challenge(
    challenge_type="credential_request",
    prompt="I need your Shopify API key. You can generate one in your Shopify admin under Settings, then Apps, then Private apps.",
    fields=[
        {"name": "api_key", "label": "API Key", "secure": true}
    ]
)

mcp__aegis__raise_challenge(challenge_type="mfa_code", prompt="I reached the two-factor authentication step. Please enter your 6-digit code.")

mcp__aegis__raise_challenge(challenge_type="confirm_action", prompt="This will permanently delete 47 emails from your trash. Should I proceed?")

mcp__aegis__raise_challenge(
    challenge_type="choice_required",
    prompt="I found two accounts. Which one should I connect?",
    options=["work@company.com", "personal@gmail.com"]
)

mcp__aegis__raise_challenge(challenge_type="manual_required", prompt="GitHub returned 403. Your token lacks the repo scope. Please regenerate it at github.com/settings/tokens with that scope enabled, then let me know.")
```

**Challenge types:**

| Type | Use when |
|---|---|
| `credential_request` | Need API key, password, secret token — always supply `fields` |
| `mfa_code` | Reached MFA prompt — need 6-digit code or similar |
| `confirm_action` | About to take an irreversible action — need explicit approval |
| `choice_required` | Multiple valid approaches — let user decide — supply `options` |
| `manual_required` | Fully blocked — needs user to do something manually |

The `prompt` is spoken aloud by TTS — plain conversational text only. No markdown, no URLs, no lists.

**After raising a challenge: stop.** The user's response arrives as the next `/prompt` call.

### Result — task complete

Call `mcp__aegis__report_result` when you have confirmed, working results. This is TERMINAL — the task ends here.

```
mcp__aegis__report_result(
    status="succeeded",
    summary="Connected to your Shopify store. I can list orders, look up specific orders, and check your product inventory.",
    service_name="shopify",
    strategy_type="api_key",
    connection_code="<full Python module contents>"
)
```

`status` values:
- `"succeeded"` — task completed successfully
- `"failed"` — every approach was exhausted with no success
- `"blocked"` — a manual_required blocker stopped work; raise the challenge first, then report blocked

`summary` is spoken aloud by Maven — plain speech, no markdown.

`source_context` (optional) is injected into Maven's system prompt for future voice sessions — write it as factual, dense context about the account (IDs, counts, plan tier, notable facts). Not a summary for the user.

**Do not call report_result until you have run the connection_code and seen it succeed.**

### Error — unrecoverable failure

Use `mcp__aegis__raise_challenge` with `challenge_type="manual_required"` for hard blockers, then call `mcp__aegis__report_result(status="blocked", ...)`.

```
mcp__aegis__raise_challenge(
    challenge_type="manual_required",
    prompt="GitHub returned 403. Your token lacks the required repo scope. Please regenerate it at github.com/settings/tokens with that scope enabled."
)
mcp__aegis__report_result(status="blocked", summary="I need you to update your GitHub token before I can continue.")
```

## Cadence Rules

- **Long-running tasks:** Call `report_progress` at least every 3 minutes
- **Milestones:** Call immediately when you discover something significant (found API, auth worked, MFA prompt appeared)
- **Blocks:** Raise a challenge immediately — don't hold it
- **Completion:** Call `report_result` immediately when done
- **Between sessions:** If resuming, call `report_progress` briefly so the user knows you're back
- **End of every task:** Call `report_result`. Always. No exceptions.
