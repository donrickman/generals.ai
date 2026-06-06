---
name: report-progress
description: Use when pushing any communication back to the Aegis API — progress updates, challenges, results, errors. Covers all webhook patterns and when to use each.
---

# Reporting Progress to Aegis

## Overview

All outbound communication from the Enclave goes to:
```
POST $AEGIS_API_URL/api/v1/session/agent_response
X-Enclave-Key: $ENCLAVE_API_KEY
Content-Type: application/json
```

Never go silent. The user's app is watching for events from this endpoint. A silent Enclave looks like a crashed one.

## Message Types

### Progress update — let the user know you're alive

Send every few minutes during long-running work, and at every meaningful milestone.

```bash
curl -s -X POST "$AEGIS_API_URL/api/v1/session/agent_response" \
  -H "X-Enclave-Key: $ENCLAVE_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"user_id\": \"$ENCLAVE_USER_ID\",
    \"type\": \"progress\",
    \"message\": \"Found OAuth2 endpoint — testing token exchange...\"
  }"
```

Good progress messages are specific: what you found, what you're trying next.
Bad: "Working on it..." Good: "GitHub API returned 401 — scope missing. Adding repo scope and retrying."

### Challenge — need user input

Raise a challenge when you need something only the user can provide. The user's app surfaces this as an interactive prompt. Their response comes back as the next `POST /prompt`.

```bash
curl -s -X POST "$AEGIS_API_URL/api/v1/session/agent_response" \
  -H "X-Enclave-Key: $ENCLAVE_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"user_id\": \"$ENCLAVE_USER_ID\",
    \"type\": \"challenge\",
    \"challenge_type\": \"credential_request\",
    \"prompt\": \"I need your Shopify API key. You can generate one at: Settings → Apps → Private apps → Create private app.\",
    \"context\": \"Shopify's storefront API requires an admin API key for the actions you want (read orders, update inventory).\"
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

**Write challenges the user can actually act on.** Include:
- Exactly what you need
- Why you need it
- Where they can find it (Settings page, account URL, etc.)

### Result — task complete

Push when you have confirmed, working connection_code.

```bash
curl -s -X POST "$AEGIS_API_URL/api/v1/session/agent_response" \
  -H "X-Enclave-Key: $ENCLAVE_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"user_id\": \"$ENCLAVE_USER_ID\",
    \"type\": \"result\",
    \"success\": true,
    \"summary\": \"Connected to Shopify. Strategy: API key. Available actions: list_orders, get_order, update_fulfillment, list_products, update_inventory.\",
    \"connection_code_path\": \"~/workspace/connection_code/shopify.py\",
    \"strategy_type\": \"api_key\"
  }"
```

**Do not push a result until you have run the connection_code and seen it succeed.** Use `aegis:verification-before-completion`.

### Error — something went wrong that you can't recover from

```bash
curl -s -X POST "$AEGIS_API_URL/api/v1/session/agent_response" \
  -H "X-Enclave-Key: $ENCLAVE_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"user_id\": \"$ENCLAVE_USER_ID\",
    \"type\": \"error\",
    \"message\": \"GitHub returned 403 — your token doesn't have the required 'repo' scope. Please regenerate with that scope enabled.\",
    \"recoverable\": true
  }"
```

Set `recoverable: true` if the user can fix it and retry. `false` if it's a hard blocker (service doesn't offer API access, account suspended, etc.).

## Cadence Rules

- **Long-running tasks:** Push a progress update at least every 3 minutes
- **Milestones:** Push immediately when you discover something significant (found API, auth worked, MFA prompt appeared)
- **Blocks:** Push a challenge or error immediately — don't hold it
- **Completion:** Push result immediately when done — don't do cleanup first, then report
- **Between sessions:** Your memory persists across pod restarts. If you're resuming, push a brief progress update so the user knows you're back

## Python Helper

For complex tasks it can be cleaner to use Python than bash:

```python
import os
import httpx

def report(type: str, **kwargs):
    """Push an event to the Aegis API."""
    payload = {
        "user_id": os.getenv("ENCLAVE_USER_ID"),
        "type": type,
        **kwargs,
    }
    r = httpx.post(
        f"{os.getenv('AEGIS_API_URL')}/api/v1/session/agent_response",
        json=payload,
        headers={"X-Enclave-Key": os.getenv("ENCLAVE_API_KEY")},
        timeout=10,
    )
    r.raise_for_status()

# Usage:
report("progress", message="Testing OAuth2 token exchange...")
report("challenge", challenge_type="mfa_code", prompt="Enter your 2FA code:")
report("result", success=True, summary="Connected to Gmail.", connection_code_path="~/workspace/connection_code/gmail.py")
```
