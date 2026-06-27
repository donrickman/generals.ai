---
name: write-connection-code
description: Use when writing or finalizing a connection_code artifact — covers module format, action patterns, credential handling, and testing requirements
---

# Writing connection_code

## What It Is

`connection_code` is a self-contained Python module that encapsulates everything needed to authenticate and take actions on an external service. It is the permanent artifact produced by a discovery session. Future Aegis sessions — and the voice agent — import and call it directly.

Save to: `~/workspace/connection_code/<service_name>.py`
Use snake_case for the service name: `gmail.py`, `shopify.py`, `github.py`

## Module Format

```python
"""
connection_code: <ServiceName>
strategy: <oauth2 | api_key | browser_session | cookie_session>
browser: <headed | headless | n/a>   # REQUIRED for browser_session — the mode that WORKED. If the
                                     # site bot-blocked headless and you switched to headed, this is
                                     # "headed". Reuse MUST take this same path or it gets blocked.
auth: <password | oauth2 | email_code | magic_link | api_key | basic>   # the login method that WORKED
                                     # (e.g. "password" if you logged in with email+password; "oauth2"
                                     # if you used Sign-in-with-Google). Surfaced to the next agent.
preferences: <~/.claude/preferences/<service>.md, or "n/a">   # LINK ONLY to this app's per-user
                                     # preference file (how THIS user uses the service). The file
                                     # lives in ~/.claude/preferences/ and is LAZY: never auto-loaded;
                                     # you read it only when acting on this service. Full mechanism:
                                     # the aegis:application-preferences skill.
discovered: <YYYY-MM-DD>
scope: <what auth scope was granted, or "n/a">
actions:
  - authenticate() -> client
  - <action_name>(<params>) -> <return_type>
  - ...
notes: |
  Any quirks, rate limits, known issues, or re-auth instructions.
  E.g. "Token expires every 60 minutes — re-call authenticate()"
  For browser_session: record the EXACT login steps that worked (URL, fields, button, browser mode,
  how verification arrived) so another user can REPLAY it with their own credentials — do NOT write
  a placeholder that just assumes the profile is already logged in.
"""

import os
import httpx  # or requests — whatever works

# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------

def authenticate():
    """
    Return an authenticated client/session. Raises on failure.
    Credentials are read from environment — never hardcoded here.
    """
    token = os.getenv("EXAMPLE_API_KEY")
    if not token:
        raise ValueError("EXAMPLE_API_KEY not set")
    client = httpx.Client(
        base_url="https://api.example.com/v1",
        headers={"Authorization": f"Bearer {token}"},
        timeout=30,
    )
    # Verify credentials are valid immediately
    r = client.get("/me")
    r.raise_for_status()
    return client


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

def list_items(client, limit: int = 20) -> list[dict]:
    """Return up to `limit` items. Each item has id, name, created_at."""
    r = client.get("/items", params={"limit": limit})
    r.raise_for_status()
    return r.json()["items"]


def create_item(client, name: str, description: str = "") -> dict:
    """Create an item. Returns the created item dict with id."""
    r = client.post("/items", json={"name": name, "description": description})
    r.raise_for_status()
    return r.json()


def delete_item(client, item_id: str) -> bool:
    """Delete item by ID. Returns True on success."""
    r = client.delete(f"/items/{item_id}")
    return r.status_code == 204


# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    print("Testing connection_code: ExampleService")
    client = authenticate()
    print("  ✓ authenticated")

    items = list_items(client, limit=5)
    print(f"  ✓ list_items → {len(items)} items")

    # Avoid creating permanent state in tests — use a clearly named test item
    created = create_item(client, name="__aegis_test__", description="temporary")
    print(f"  ✓ create_item → id={created['id']}")

    deleted = delete_item(client, created["id"])
    print(f"  ✓ delete_item → {deleted}")

    print("All checks passed ✓")
```

## Credential Handling

**Never hardcode credentials.** Credentials come from one of:

1. **Environment variables** (preferred for API keys):
   ```python
   token = os.getenv("GITHUB_TOKEN")
   ```

2. **Passed as parameters** (for OAuth tokens that change):
   ```python
   def authenticate(access_token: str = None):
       token = access_token or os.getenv("GMAIL_ACCESS_TOKEN")
   ```

3. **Browser session** (for browser_session strategy):
   ```
   # The persistent browser profile holds the session via the Playwright MCP tools.
   # The connection_code's authenticate() function navigates to the service URL and
   # calls mcp__playwright__browser_snapshot() to verify the session is active.
   # No credentials are needed in the Python code itself.
   # Credentials are stored in ~/workspace/credentials/<service>.json (written by the
   # enclave after first successful login — never stored in connection_code).
   ```

Document which env vars are needed in the module docstring.

## Action Naming Conventions

Use verb_noun pattern. Make it obvious what each function does:

| Pattern | Examples |
|---|---|
| `list_<resource>` | `list_emails`, `list_orders`, `list_repos` |
| `get_<resource>` | `get_email`, `get_order`, `get_profile` |
| `search_<resource>` | `search_emails`, `search_products` |
| `send_<thing>` | `send_email`, `send_message` |
| `create_<resource>` | `create_issue`, `create_post` |
| `update_<resource>` | `update_order_status`, `update_contact` |
| `delete_<resource>` | `delete_draft`, `delete_webhook` |

## Browser Session Pattern

For services that require browser automation, the Playwright MCP tools drive the browser.
Do NOT write Playwright Python in connection_code — the MCP tools are the browser interface.

The connection_code for a browser_session service documents the MCP tool sequence and
wraps any HTTP extractions (using the session cookies captured after browser login):

```python
"""
connection_code: ExampleSite
strategy: browser_session
discovered: 2026-06-26
scope: n/a
actions:
  - verify_session() -> bool      # True if browser session is still active
  - get_balance() -> dict         # scrape balance from dashboard
notes: |
  Driven via Playwright MCP tools (mcp__playwright__browser_*).
  After first login, session persists in browser profile across pod restarts.
  Credentials stored in ~/workspace/credentials/examplesite.json.
  If verify_session returns False, re-run the login flow (see discovery notes).
"""

# This module documents the browser actions — call them via the MCP tools in your session.
# There is no runnable Python here for the browser; the MCP server handles it.

DASHBOARD_URL = "https://example.com/dashboard"
LOGIN_URL = "https://example.com/login"

# To verify session is active:
#   mcp__playwright__browser_navigate(url=DASHBOARD_URL)
#   snap = mcp__playwright__browser_snapshot()
#   check if snap contains dashboard indicators (not the login page)

# To get balance:
#   mcp__playwright__browser_navigate(url=DASHBOARD_URL)
#   snap = mcp__playwright__browser_snapshot()
#   parse balance from the snapshot accessibility tree
```

## Rate Limiting

Add backoff for services with rate limits:

```python
import time

def _get_with_backoff(client, url, max_retries=3):
    for attempt in range(max_retries):
        r = client.get(url)
        if r.status_code == 429:
            wait = int(r.headers.get("Retry-After", 60))
            time.sleep(wait)
            continue
        r.raise_for_status()
        return r
    raise RuntimeError(f"Rate limited after {max_retries} retries")
```

## Testing Requirements

Before calling `mcp__aegis__report_result`, you MUST:

1. Run `python ~/workspace/connection_code/<service>.py` and see it complete without errors
   (for browser_session modules: manually walk the MCP tool sequence and confirm the session is live)
2. Verify at least one read action returned real data (not empty)
3. If write actions exist, test them and clean up (delete test records you created)
4. Use `superpowers:verification-before-completion` — no completion claims without evidence

The self-test block (`if __name__ == "__main__":`) must be comprehensive enough that passing it proves the connection works end-to-end.
