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
   - OAuth2 (standard web flow — good for services with official APIs)
   - API key (look in account settings → Developer → API Keys)
   - Username/password direct auth (basic auth header, or form-based login)
   - Browser session (Playwright MCP tools log in → session persists via browser profile)
   - No auth required (public data)

   **Browser automation is a primary strategy, not a fallback.** For any service with a web UI,
   driving the browser via the Playwright MCP tools is a valid first approach — especially when
   API access is locked down, requires app registration, or the auth flow is easier to automate
   in a browser. The persistent browser profile at `~/workspace/browser-profile/` means the user
   authenticates once and stays logged in across pod restarts. Prefer browser automation early
   when the service's web login is simpler than its API auth.

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

For browser-based auth, navigate with the Playwright MCP tools and call `browser_snapshot` to read the page:

```
mcp__playwright__browser_navigate(url="https://example.com/login")
mcp__playwright__browser_snapshot()   # read the page — accessibility tree, not raw HTML
```

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
| CAPTCHA or login wall | Need browser session | Switch to browser automation via Playwright MCP tools |

## Phase 4: Adapt

Don't wait until 3 API failures before trying browser automation. If research shows the service
has a simpler web login than an API auth flow, start there. Switch strategies as soon as
you have evidence the current approach won't work — not after exhausting it.

**API approach blocked → try browser automation via Playwright MCP tools:**

```
mcp__playwright__browser_navigate(url="https://example.com/login")
mcp__playwright__browser_snapshot()
# Read the snapshot to find the email/password field refs, then:
mcp__playwright__browser_type(element="email field", ref="<ref from snapshot>", text=email)
mcp__playwright__browser_type(element="password field", ref="<ref from snapshot>", text=password)
mcp__playwright__browser_click(element="submit button", ref="<ref from snapshot>")
mcp__playwright__browser_wait_for(...)
mcp__playwright__browser_snapshot()   # confirm you reached the dashboard
```

Never write Playwright Python in a Bash heredoc. Use the MCP tools.

**Browser automation blocked by MFA → raise a challenge:**

```
mcp__aegis__raise_challenge(
    challenge_type="mfa_code",
    prompt="I reached the two-factor authentication step. Please enter your 6-digit code."
)
# Stop here — the code arrives as the next /prompt call
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

Surface challenges via `mcp__aegis__raise_challenge` — never by printing JSON lines.

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

3. **Use `aegis:verification-before-completion` before reporting the result**

4. **Call `mcp__aegis__report_result` to end the task:**
```
mcp__aegis__report_result(
    status="succeeded",
    summary="Connected to <Service>. I can <list key actions>.",
    service_name="<service>",
    strategy_type="<oauth2 | api_key | playwright | browser_session>",
    connection_code="<full module contents>"
)
```

## If You Get Stuck

Use `superpowers:systematic-debugging`. The four phases apply directly:
1. **Root cause** — what exactly is the error? Read it fully.
2. **Pattern** — find a working example of what you're trying to do
3. **Hypothesis** — state your theory, test it minimally
4. **Implementation** — fix at root cause, not symptom

If 3+ approaches fail at the same layer, step back. The auth mechanism you assumed may not exist for this service — research again from scratch.

**Final fallback:** If no automated path exists (service requires physical 2FA, enterprise SSO only, legal block), raise a `manual_required` challenge with specific instructions for what the user needs to do, then call `mcp__aegis__report_result(status="blocked", ...)`.
