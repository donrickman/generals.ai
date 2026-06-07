---
name: report-progress
description: Use when pushing any communication back to the Aegis API — progress updates, challenges, results, errors. Covers all webhook patterns and when to use each.
---

# Reporting Progress to Aegis

## Overview

All outbound communication from the Enclave goes to:
```
POST $AEGIS_API_URL/api/v1/session/agent_response
X-Pod-API-Key: $ENCLAVE_API_KEY
Content-Type: application/json
```

Never go silent. The user's app is watching for events from this endpoint. A silent Enclave looks like a crashed one.

## Message Types

### Progress update — let the user know you're alive

Send every few minutes during long-running work, and at every meaningful milestone.

```bash
curl -s -X POST "$AEGIS_API_URL/api/v1/session/agent_response" \
  -H "X-Pod-API-Key: $ENCLAVE_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"user_id\": \"$ENCLAVE_USER_ID\",
    \"type\": \"progress\",
    \"data\": {
      \"message\": \"Found OAuth2 endpoint — testing token exchange...\"
    }
  }"
```

Good progress messages are specific: what you found, what you're trying next.
Bad: "Working on it..." Good: "GitHub API returned 401 — scope missing. Adding repo scope and retrying."

Write as Maven — warm, direct, brief, spoken out loud. Plain text only. No markdown, no bullet points, no asterisks, no backticks.

### Challenge — need user input

Raise a challenge when you need something only the user can provide. The user's app surfaces this as an interactive prompt. Their response comes back as the next `POST /prompt` starting with `"Challenge response received."`.

```bash
curl -s -X POST "$AEGIS_API_URL/api/v1/session/agent_response" \
  -H "X-Pod-API-Key: $ENCLAVE_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"user_id\": \"$ENCLAVE_USER_ID\",
    \"type\": \"challenge\",
    \"challenge_type\": \"credential_request\",
    \"data\": {
      \"challenge_type\": \"credential_request\",
      \"prompt\": \"I need your Shopify API key. You can generate one at Settings → Apps → Private apps → Create private app.\",
      \"context\": \"Shopify's storefront API requires an admin API key for the actions you want.\"
    }
  }"
```

**Challenge types:**

| Type | Use when |
|---|---|
| `credential_request` | Need API key, password, secret token |
| `mfa_code` | Reached MFA prompt — need 6-digit code or similar |
| `confirm_action` | About to take an irreversible action — need explicit approval |
| `choice_required` | Multiple valid approaches — let user decide |
| `manual_required` | Fully blocked — needs user to do something manually |

The `prompt` field is spoken aloud by TTS — plain conversational text only. No markdown, no URLs, no lists.

**After pushing a challenge: stop.** The user's response arrives as the next `/prompt` call with `--continue` context.

### Result — task complete

Push when you have confirmed, working connection_code.

```bash
curl -s -X POST "$AEGIS_API_URL/api/v1/session/agent_response" \
  -H "X-Pod-API-Key: $ENCLAVE_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"user_id\": \"$ENCLAVE_USER_ID\",
    \"type\": \"result\",
    \"data\": {
      \"success\": true,
      \"service_name\": \"shopify\",
      \"strategy_type\": \"api_key\",
      \"connection_code_path\": \"~/workspace/connection_code/shopify.py\",
      \"connection_code\": \"<full Python module contents>\",
      \"action_schemas\": [
        {\"name\": \"list_orders\", \"description\": \"List recent orders\", \"params\": {}},
        {\"name\": \"get_order\", \"description\": \"Get a specific order by ID\", \"params\": {\"order_id\": \"string\"}}
      ],
      \"source_context\": \"Connected to shop: my-store.myshopify.com. Plan: Basic. Products: 47 active.\",
      \"summary\": \"Connected to your Shopify store. I can list orders, look up specific orders, and check your product inventory.\"
    }
  }"
```

`source_context` is injected into Maven's system prompt for future voice sessions — write it as factual, dense context about the account (IDs, counts, plan tier, notable facts). Not a summary for the user.

`summary` is spoken aloud by Maven — plain speech, no markdown.

**Do not push a result until you have run the connection_code and seen it succeed.**

### Error — unrecoverable failure

```bash
curl -s -X POST "$AEGIS_API_URL/api/v1/session/agent_response" \
  -H "X-Pod-API-Key: $ENCLAVE_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"user_id\": \"$ENCLAVE_USER_ID\",
    \"type\": \"challenge\",
    \"challenge_type\": \"manual_required\",
    \"data\": {
      \"challenge_type\": \"manual_required\",
      \"prompt\": \"GitHub returned 403 — your token doesn't have the required repo scope. Please regenerate with that scope enabled at github.com/settings/tokens.\"
    }
  }"
```

Use `manual_required` challenge type for hard blockers. Describe exactly what the user needs to do.

## Cadence Rules

- **Long-running tasks:** Push a progress update at least every 3 minutes
- **Milestones:** Push immediately when you discover something significant (found API, auth worked, MFA prompt appeared)
- **Blocks:** Push a challenge immediately — don't hold it
- **Completion:** Push result immediately when done
- **Between sessions:** If resuming, push a brief progress update so the user knows you're back

## Python Helper

```python
import os, json
import httpx

def report(type: str, data: dict, challenge_type: str = None):
    """Push an event to the Aegis API."""
    payload = {
        "user_id": os.getenv("ENCLAVE_USER_ID"),
        "type": type,
        "data": data,
    }
    if challenge_type:
        payload["challenge_type"] = challenge_type
    r = httpx.post(
        f"{os.getenv('AEGIS_API_URL')}/api/v1/session/agent_response",
        json=payload,
        headers={"X-Pod-API-Key": os.getenv("ENCLAVE_API_KEY")},
        timeout=10,
    )
    r.raise_for_status()

# Usage:
report("progress", {"message": "Testing OAuth2 token exchange..."})
report("challenge", {"challenge_type": "mfa_code", "prompt": "Enter your 2FA code:"}, challenge_type="mfa_code")
report("result", {"success": True, "service_name": "gmail", "strategy_type": "oauth", "summary": "Connected to Gmail.", "source_context": "...", "connection_code": "..."})
```
