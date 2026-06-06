---
name: connect-api-key
description: Use when connecting any service that authenticates with an API key, bearer token, or basic auth. Covers credential discovery, storage, testing, and the standard connection_code pattern.
---

# Connecting via API Key

## When to Use This

Use for services that authenticate with:
- An API key in a header (`Authorization: Bearer`, `X-API-Key`, `Api-Key`, `Authorization: Token`)
- Basic auth (username + password in Authorization header)
- Query parameter token (`?api_key=...`, `?token=...`)
- A static secret injected at request time

## Step 1: Find Where the Key Lives

Check in this order:
1. Service docs → Settings → Developer / API → API Keys
2. Account settings → Integrations → Tokens
3. Search docs for "API key" or "access token"

Common locations by service type:
- **SaaS tools** (Notion, Airtable, Linear): Settings → API → Generate token
- **Cloud APIs** (Stripe, Twilio, SendGrid): Dashboard → Developers → API Keys
- **Data platforms** (Snowflake, BigQuery): Security → Service accounts / API tokens
- **Social/comms** (Slack, Discord): App settings → Bot tokens / OAuth tokens

If you can't find it, surface a challenge:
```bash
curl -s -X POST "$AEGIS_API_URL/api/v1/session/agent_response" \
  -H "X-Enclave-Key: $ENCLAVE_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"user_id\": \"$ENCLAVE_USER_ID\",
    \"type\": \"challenge\",
    \"challenge_type\": \"credential_request\",
    \"prompt\": \"I need your <Service> API key to connect. You can generate one at: <URL>.\",
    \"context\": \"The key will be stored in environment variables — never written to disk as plaintext.\"
  }"
```

## Step 2: Test the Key Before Building Anything

Always verify the key works before writing the full module:

```python
import httpx
import os

token = os.getenv("SERVICE_API_KEY")
r = httpx.get(
    "https://api.example.com/v1/me",
    headers={"Authorization": f"Bearer {token}"},
    timeout=10,
)
print(r.status_code, r.json())
```

| Response | Meaning |
|---|---|
| 200 + data | Key works — build the module |
| 401 | Wrong header format, or key invalid |
| 403 | Key valid but lacks permission — check scope/tier |
| 404 | Wrong base URL — check API version |

## Step 3: Connection Code Template

```python
"""
connection_code: <ServiceName>
strategy: api_key
discovered: YYYY-MM-DD
scope: n/a
actions:
  - authenticate() -> client
  - <list your actions here>
notes: |
  API key read from <SERVICE>_API_KEY env var.
  Rate limit: <X> requests/minute — backoff built in.
"""

import os
import time
import httpx

BASE_URL = "https://api.example.com/v1"


def authenticate() -> httpx.Client:
    """Return authenticated client. Raises if key missing or invalid."""
    token = os.getenv("SERVICE_API_KEY")
    if not token:
        raise ValueError("SERVICE_API_KEY environment variable not set")
    
    client = httpx.Client(
        base_url=BASE_URL,
        headers={"Authorization": f"Bearer {token}"},
        timeout=30,
    )
    # Verify immediately — fail fast rather than on first real call
    r = client.get("/me")
    if r.status_code == 401:
        raise ValueError("API key invalid or expired")
    if r.status_code == 403:
        raise ValueError("API key lacks required permissions")
    r.raise_for_status()
    return client


def _get_with_backoff(client: httpx.Client, url: str, params: dict = None, max_retries: int = 3):
    """GET with automatic rate-limit backoff."""
    for attempt in range(max_retries):
        r = client.get(url, params=params)
        if r.status_code == 429:
            wait = int(r.headers.get("Retry-After", 60))
            time.sleep(wait)
            continue
        r.raise_for_status()
        return r
    raise RuntimeError(f"Rate limited after {max_retries} retries on {url}")


# ---------------------------------------------------------------------------
# Actions — add the ones that matter for this service
# ---------------------------------------------------------------------------

def list_items(client: httpx.Client, limit: int = 20) -> list[dict]:
    """Return up to limit items."""
    r = _get_with_backoff(client, "/items", params={"limit": limit})
    return r.json().get("items", r.json() if isinstance(r.json(), list) else [])


def get_item(client: httpx.Client, item_id: str) -> dict:
    """Get a single item by ID."""
    r = _get_with_backoff(client, f"/items/{item_id}")
    return r.json()


def create_item(client: httpx.Client, **fields) -> dict:
    """Create an item. Returns created item dict."""
    r = client.post("/items", json=fields)
    r.raise_for_status()
    return r.json()


def delete_item(client: httpx.Client, item_id: str) -> bool:
    """Delete item. Returns True on success."""
    r = client.delete(f"/items/{item_id}")
    return r.status_code in (200, 204)


# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    print("Testing <ServiceName> connection_code")
    client = authenticate()
    print("  ✓ authenticated")

    items = list_items(client, limit=3)
    print(f"  ✓ list_items → {len(items)} items")
    if not items:
        print("  ⚠ list returned empty — verify the account has data")

    # Test write actions only if safe to clean up
    created = create_item(client, name="__aegis_test__")
    print(f"  ✓ create_item → id={created.get('id')}")

    deleted = delete_item(client, created["id"])
    print(f"  ✓ delete_item → {deleted}")

    print("All checks passed ✓")
