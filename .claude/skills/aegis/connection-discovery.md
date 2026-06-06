---
name: connection-discovery
description: Use when given any task to connect an external service — covers the full research → generate → test → iterate loop and when to surface challenges vs. keep going
---

# Aegis Connection Discovery

## Overview

Connection discovery is an autonomous reasoning loop. You research, generate code, run it, observe what fails, and adapt. You do not follow a fixed sequence of "try OAuth → try API key → try browser." You reason about what you observe and decide what to try next.

The artifact you produce is `connection_code` — a self-contained Python module that future sessions (and the Aegis voice agent) use to take actions on the service.

## The Loop

```
RESEARCH → GENERATE → TEST → OBSERVE → ADAPT → repeat
                                  ↓ (working)
                              COMMIT ARTIFACT → REPORT RESULT
```

Never claim the loop is done until you have run the connection_code and seen it succeed.

## Phase 1: Research

Before writing a single line of code, answer these questions:

1. **What does this service expose?**
   - Public REST API? GraphQL? SOAP? Unofficial mobile API?
   - Official Python SDK?
   - Search: `<service> API documentation`, `<service> Python library`, `<service> unofficial API`

2. **What auth mechanisms are available?**
   - OAuth2 (standard — prefer this if available)
   - API key (simple, look in account settings → Developer → API Keys)
   - Session cookie (Playwright login → extract cookie → use in requests)
   - Basic auth (username + password in HTTP header — becoming rare)
   - No auth required (public data)

3. **Are there existing examples?**
   - Check `~/workspace/connection_code/` — may already be solved
   - GitHub: search `<service> python oauth2 example`

4. **What's the data surface?**
   - What can you read? What can you write?
   - What actions matter to a voice assistant? (send, list, search, create, delete)

Document your research in a scratch file before writing code.

## Phase 2: Generate

Start with the minimum viable proof of auth — one API call that returns real data.

```python
# Minimum viable test — does auth work at all?
import httpx

headers = {"Authorization": f"Bearer {token}"}
r = httpx.get("https://api.example.com/v1/me", headers=headers)
print(r.status_code, r.json())
```

Run this immediately. Don't write the full module until you know auth works.

## Phase 3: Test and Observe

Run the code. Read the response carefully.

| Response | Meaning | Next step |
|---|---|---|
| 200 + real data | Auth works | Expand to full module |
| 401 Unauthorized | Wrong credentials or missing scope | Check token format, re-read auth docs |
| 403 Forbidden | Right credentials, wrong permissions | Check scope requirements, account tier |
| 404 Not Found | Wrong endpoint | Re-read docs, check API version |
| 429 Too Many Requests | Rate limited | Add `time.sleep(1)`, retry with backoff |
| 5xx | Service error | Wait 30s, retry once; then try different endpoint |
| Connection refused | Wrong host/port | Verify base URL |
| CAPTCHA or login wall | Need browser session | Switch to Playwright approach |

## Phase 4: Adapt

If the direct API approach isn't working after 2-3 attempts, switch strategy:

**Direct API failing → try Playwright:**
```python
from playwright.sync_api import sync_playwright

with sync_playwright() as p:
    browser = p.chromium.launch_persistent_context(
        "~/workspace/browser-profile/",
        headless=False  # Xvfb handles the display
    )
    page = browser.new_page()
    page.goto("https://example.com/login")
    page.fill("#email", email)
    page.fill("#password", password)
    page.click('button[type="submit"]')
    page.wait_for_url("**/dashboard")
    # Now extract session cookies for subsequent requests
    cookies = browser.cookies()
```

**Playwright blocked by MFA → surface challenge:**
```bash
curl -X POST "$AEGIS_API_URL/api/v1/session/agent_response" \
  -H "X-Enclave-Key: $ENCLAVE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "challenge",
    "challenge_type": "mfa_code",
    "prompt": "I reached the MFA step. Please enter your 6-digit code.",
    "context": "The browser is paused at the authenticator prompt."
  }'
# Wait for next /prompt call — it will contain the code
```

## When to Stop and Surface a Challenge

Stop and ask when you need something only the user has:
- Password, API key, secret token
- MFA code from their authenticator
- A decision with permanent consequences (broad OAuth scope authorization, data deletion)
- A physical action (scan QR code, tap physical security key)

Don't stop for things you can figure out yourself:
- Which endpoint to try next
- Whether to use OAuth vs. API key
- Rate limit backoff timing
- Installing a missing package

## Committing the Artifact

When connection_code works:

1. **Save it properly:**
```bash
mkdir -p ~/workspace/connection_code
# Write the full module — see aegis:write-connection-code for format
```

2. **Run the full test one final time before reporting:**
```bash
python ~/workspace/connection_code/<service>.py
# Must print "✓ connected" or equivalent
```

3. **Use `aegis:verification-before-completion` before pushing the result**

4. **Push result:**
```bash
curl -X POST "$AEGIS_API_URL/api/v1/session/agent_response" \
  -H "X-Enclave-Key: $ENCLAVE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "result",
    "success": true,
    "summary": "Connected to <Service>. Strategy: <oauth2/api_key/playwright>. Available actions: <list>.",
    "connection_code_path": "~/workspace/connection_code/<service>.py"
  }'
```

## If You Get Stuck

Use `superpowers:systematic-debugging`. The four phases apply directly:
1. **Root cause** — what exactly is the error? Read it fully.
2. **Pattern** — find a working example of what you're trying to do
3. **Hypothesis** — state your theory, test it minimally
4. **Implementation** — fix at root cause, not symptom

If 3+ approaches fail at the same layer, step back. The auth mechanism you assumed may not exist for this service — research again from scratch.

**Final fallback:** If no automated path exists (service requires physical 2FA, enterprise SSO only, legal block), surface `manual_required` with specific instructions for what the user needs to do.
