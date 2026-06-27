---
name: auth-strategies
description: Use during connection discovery when deciding how to authenticate to a service. Covers why the browser login is the default, when an API/OAuth path is actually worth it, how to read failure signals, and when to change strategy.
---

# Auth Strategy: Research → Try → Read Signals → Adapt

## The Principle

You don't know what will work until you try it. Start with the simplest possible probe, read what the service tells you, and let the response guide your next move.

Never write a complete auth module until you have a working minimal proof first.

## Step 0: Research Before Touching the Service

Before any code, answer:
1. Has someone already solved this? (check `~/workspace/connection_code/` first)
2. Is this the user's own account behind a normal web login? (utilities, email, banking, retail — almost always yes) → that's a browser login; start there.
3. Only if a browser path is genuinely unworkable: does the service publish a real developer API for this account, and would it buy bulk/server-side filtering? (search: `<service> API docs`, `<service> developer`)
4. Is there a Python library or a ready-made MCP server for it? (search: `<service> python library pypi`, `<service> MCP server`)

The answers determine your starting point — and for a personal account that starting point is the browser, not a fixed sequence of API methods.

## Auth Method Signals

After your minimal probe, the response tells you what's actually happening:

| What you see | What it means | Next move |
|---|---|---|
| 200 + data | Auth works | Expand to full connection_code |
| 401 + "invalid token" | Wrong credential format or wrong header | Re-read auth docs on header format |
| 401 + "missing scope" | Credential valid but permission not granted | Find scope list, re-authorize |
| 403 | Right credential, wrong permission level | Check account tier or app permissions |
| 404 on `/me` or `/user` | Wrong base URL or API version | Check docs for current version |
| 429 | Rate limited on first call | Suspicious — check if auth even worked |
| CAPTCHA page in response body | Bot detection, not an API | Use browser automation via Playwright MCP tools |
| HTML login page returned | Service doesn't have a public API at this endpoint | Try different endpoint or browser automation |
| Empty 200 | Auth worked but no data | Check if account has any data |
| Connection refused | Wrong host or port | Verify base URL |

## The Strategies — Default to the Browser

Most Maven connections are the user's OWN account on a consumer service — utilities (SCE,
SoCalGas), email, banking, retail. There is no developer API for "my SCE account"; those are
browser logins. **Default to the browser.** Reach for an API/OAuth path ONLY when the service
genuinely publishes a developer API for that account AND the task needs server-side filtering of
a large dataset (e.g. searching a big mailbox). Do not probe REST/token endpoints first on a
personal-account login — that just burns attempts on a path that doesn't exist for that account.

### Strategy 1 (default): Browser Session (Playwright MCP tools)
**Use for:** any service with a web login — which is most personal accounts. This is the default,
not a fallback. If you can see a login form, log in through it.

Drive the browser via the Playwright MCP tools — never by writing Playwright Python in a Bash script. The persistent profile at `~/workspace/browser-profile/` means a logged-in session survives pod restarts.

Minimum viable probe:
```
mcp__playwright__browser_navigate(url="https://example.com")
mcp__playwright__browser_snapshot()
# Read the snapshot — check page URL/title for dashboard indicators (already logged in?)
```

If already logged in (the snapshot shows a dashboard/home page), the session is live — proceed to extract data.

If the login page appears, read the field refs from the snapshot and fill them:
```
mcp__playwright__browser_snapshot()
# identify email/password field refs, then:
mcp__playwright__browser_type(element="email field", ref="<ref>", text=email)
mcp__playwright__browser_type(element="password field", ref="<ref>", text=password)
mcp__playwright__browser_click(element="submit button", ref="<ref>")
mcp__playwright__browser_wait_for(...)
mcp__playwright__browser_snapshot()   # confirm you reached the dashboard
```

When you hit MFA or a hardware key prompt: raise a challenge immediately — don't sit on it.

Many SPAs load data from internal JSON endpoints. Check network requests before scraping the DOM. After navigating, use `browser_snapshot` to inspect what data is visible and what interactive elements exist.

### Strategy 2: API Key / Bearer Token
**Use when:** the service genuinely issues a developer key for THIS account (a developer portal / "API" section in settings) AND an API path is worth it for bulk or server-side filtering. Not for a plain consumer login — that has no key to issue.

Minimum viable probe:
```python
import httpx, os
token = os.getenv("SERVICE_API_KEY")  # or prompt user for it
r = httpx.get("https://api.example.com/v1/me",
               headers={"Authorization": f"Bearer {token}"}, timeout=10)
print(r.status_code, r.text[:500])
```

Try header variants if first fails:
- `Authorization: Bearer <token>`
- `Authorization: Token <token>`
- `X-API-Key: <token>`
- `Api-Key: <token>`
- `?api_key=<token>` (query param)

### Strategy 3: OAuth2
**Use when:** the service offers a real OAuth app registration / "Connect with <Service>" developer flow AND it buys server-side capability the browser can't. Browser redirects are awkward in the Enclave (see below), so prefer Strategy 1 for a plain login.

Key questions to answer before writing code:
- What are the authorization and token endpoints? (usually in docs under "OAuth" or "Authentication")
- What scopes exist? Which are needed for the actions you want?
- Does the service issue refresh tokens? (not all do)
- What redirect URI format does it expect?

Minimum viable probe — exchange a code for a token:
```python
import httpx
r = httpx.post("https://api.example.com/oauth/token",
    data={"grant_type": "authorization_code", "code": code,
          "client_id": CLIENT_ID, "client_secret": CLIENT_SECRET,
          "redirect_uri": REDIRECT_URI})
print(r.status_code, r.json())
```

The Enclave can't receive browser redirects directly. Options:
- Start a local HTTP server on an available port to catch the callback
- Use `run_console()` flow (prints URL, user pastes back the code) — surface as a challenge
- For services that support it, use device flow or out-of-band codes

If the service requires user authorization, raise a `confirm_action` or `credential_request` challenge via `mcp__aegis__raise_challenge` before starting the flow — don't silently open URLs.

Minimum viable probe:
```
mcp__playwright__browser_navigate(url="https://example.com")
mcp__playwright__browser_snapshot()
# Read the snapshot — check page URL/title for dashboard indicators (already logged in?)
```

If already logged in (the snapshot shows a dashboard/home page), the session is live — proceed to extract data.

If the login page appears, read the field refs from the snapshot and fill them:
```
mcp__playwright__browser_snapshot()
# identify email/password field refs, then:
mcp__playwright__browser_type(element="email field", ref="<ref>", text=email)
mcp__playwright__browser_type(element="password field", ref="<ref>", text=password)
mcp__playwright__browser_click(element="submit button", ref="<ref>")
mcp__playwright__browser_wait_for(...)
mcp__playwright__browser_snapshot()   # confirm you reached the dashboard
```

When you hit MFA or a hardware key prompt: raise a challenge immediately — don't sit on it.

Many SPAs load data from internal JSON endpoints. Check network requests before scraping the DOM. After navigating, use `browser_snapshot` to inspect what data is visible and what interactive elements exist.

### Strategy 4: Basic Auth or No Auth
**Try when:** Service docs mention HTTP Basic Auth, or endpoint is documented as public.

```python
import httpx
r = httpx.get("https://api.example.com/data",
              auth=("username", "password"), timeout=10)
# or for no-auth:
r = httpx.get("https://api.example.com/data", timeout=10)
print(r.status_code, r.text[:500])
```

## When to Switch Strategies

Switch when you see the **same failure type three times** from different angles. If 401s persist after trying all header variants and verifying the token format, the strategy itself is wrong — not the implementation.

Switch order to consider:
- Browser login failing on selectors/timing → re-snapshot and adjust refs (the page changed, the strategy didn't)
- Browser login blocked by MFA / a hardware key → raise a challenge; don't abandon the browser path
- Browser truly unusable (no web login, or a bot-wall you can't pass) → only THEN evaluate whether a real developer API exists for this account, and if so try API key / OAuth2
- All paths blocked → raise `manual_required` challenge with exact steps for the user, then call `mcp__aegis__report_result(status="blocked", ...)`

## When to Stop and Surface a Challenge

Stop and ask when you need something only the user has:
- The API key or OAuth credentials themselves
- An MFA code from their authenticator app
- Approval for an action with real consequences (sending emails, making purchases, posting publicly)
- A QR code scan or physical hardware tap

Don't stop for things you can resolve yourself:
- Which header format to use (try them)
- Which auth path to take (default to the browser login; only consider an API/OAuth if one genuinely exists for this account)
- Rate limit backoff (handle it in code)
- Installing a missing package (`pip install` it)

Raise challenges via `mcp__aegis__raise_challenge` — never by printing JSON lines.

## After You Have a Working Minimal Proof

Only after the minimal probe returns real data:
1. Check `aegis:write-connection-code` for the artifact format
2. Build out the action functions one at a time, verifying each
3. Write the self-test block
4. Run it end-to-end before reporting success via `mcp__aegis__report_result`
