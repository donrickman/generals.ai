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
strategy: <oauth2 | api_key | playwright | cookie_session>
discovered: <YYYY-MM-DD>
scope: <what auth scope was granted, or "n/a">
actions:
  - authenticate() -> client
  - <action_name>(<params>) -> <return_type>
  - ...
notes: |
  Any quirks, rate limits, known issues, or re-auth instructions.
  E.g. "Token expires every 60 minutes — re-call authenticate()"
"""

import os
import httpx  # or requests, or playwright — whatever works

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

3. **Browser profile** (for Playwright cookie sessions):
   ```python
   # The persistent browser profile at ~/workspace/browser-profile/ holds the session
   # No credentials needed in code — just use the profile
   browser = p.chromium.launch_persistent_context("~/workspace/browser-profile/")
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

## Playwright Pattern

For services that require browser automation:

```python
import os
from playwright.sync_api import sync_playwright, BrowserContext

PROFILE_DIR = os.path.expanduser("~/workspace/browser-profile/example")

def authenticate() -> BrowserContext:
    """
    Return a persistent browser context with active session.
    On first run: completes login flow.
    On subsequent runs: resumes from saved profile (cookies/localStorage).
    """
    p = sync_playwright().start()
    context = p.chromium.launch_persistent_context(
        PROFILE_DIR,
        headless=False,  # Xvfb handles display — don't change this
        args=["--no-sandbox", "--disable-dev-shm-usage"],
    )
    page = context.new_page()
    page.goto("https://example.com")
    
    # Check if already logged in
    if "dashboard" in page.url:
        return context
    
    # Login flow
    email = os.getenv("EXAMPLE_EMAIL")
    password = os.getenv("EXAMPLE_PASSWORD")
    page.fill('input[type="email"]', email)
    page.fill('input[type="password"]', password)
    page.click('button[type="submit"]')
    page.wait_for_url("**/dashboard", timeout=15000)
    
    return context


def scrape_data(context: BrowserContext) -> list[dict]:
    """Extract data from the dashboard."""
    page = context.new_page()
    page.goto("https://example.com/data")
    # ... scrape logic
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

Before pushing a result, you MUST:

1. Run `python ~/workspace/connection_code/<service>.py` and see it complete without errors
2. Verify at least one read action returned real data (not empty)
3. If write actions exist, test them and clean up (delete test records you created)
4. Use `superpowers:verification-before-completion` — no completion claims without evidence

The self-test block (`if __name__ == "__main__":`) must be comprehensive enough that passing it proves the connection works end-to-end.
