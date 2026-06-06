---
name: connect-oauth2-generic
description: Use when connecting any OAuth2 service that isn't Google Workspace — covers authorization code flow, PKCE, token storage, and refresh. Also covers services with non-standard OAuth flows (Salesforce, HubSpot, Shopify, QuickBooks, etc.)
---

# Connecting via OAuth2 (Generic)

## When to Use This vs. connect-google-oauth

Use this skill for any OAuth2 service that isn't Google. For Google (Gmail, Calendar, Drive), use `aegis:connect-google-oauth` which has the official Google client library already wired up.

This covers: Salesforce, HubSpot, Shopify, QuickBooks, Notion, Slack, GitHub, Microsoft/Azure, Dropbox, Box, Zoom, Stripe, LinkedIn, and any other OAuth2 service.

## The Standard Authorization Code Flow

```
1. Build authorization URL → user visits it in browser → approves
2. Service redirects to callback with ?code=<auth_code>
3. Exchange auth_code for access_token + refresh_token
4. Store tokens → use access_token for API calls
5. Refresh when access_token expires
```

The Enclave can't receive browser redirects. Two approaches:

**Approach A — localhost redirect (preferred for desktop OAuth apps):**
Start a local HTTP server to catch the callback. Works for apps registered with `http://localhost:PORT` as redirect URI.

**Approach B — manual code paste:**
Use `urn:ietf:wg:oauth:2.0:oob` or `http://localhost` as redirect URI, show the user the auth URL, ask them to paste the code back via challenge.

## Common OAuth2 Endpoints by Service

| Service | Auth URL | Token URL | Notes |
|---|---|---|---|
| GitHub | `github.com/login/oauth/authorize` | `github.com/login/oauth/access_token` | No refresh — tokens don't expire |
| Slack | `slack.com/oauth/v2/authorize` | `slack.com/api/oauth.v2.access` | Workspace-scoped |
| Notion | `api.notion.com/v1/oauth/authorize` | `api.notion.com/v1/oauth/token` | |
| HubSpot | `app.hubspot.com/oauth/authorize` | `api.hubapi.com/oauth/v1/token` | |
| Shopify | `{shop}.myshopify.com/admin/oauth/authorize` | `{shop}.myshopify.com/admin/oauth/access_token` | Per-shop |
| Salesforce | `login.salesforce.com/services/oauth2/authorize` | `login.salesforce.com/services/oauth2/token` | |
| Microsoft | `login.microsoftonline.com/{tenant}/oauth2/v2.0/authorize` | `login.microsoftonline.com/{tenant}/oauth2/v2.0/token` | |
| Zoom | `zoom.us/oauth/authorize` | `zoom.us/oauth/token` | |
| Dropbox | `www.dropbox.com/oauth2/authorize` | `api.dropbox.com/oauth2/token` | |
| QuickBooks | `appcenter.intuit.com/connect/oauth2` | `oauth.platform.intuit.com/op/v2/accessToken` | |

## Credential Discovery

Before writing any code, ask the user for the OAuth app credentials:

```bash
curl -s -X POST "$AEGIS_API_URL/api/v1/session/agent_response" \
  -H "X-Enclave-Key: $ENCLAVE_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"user_id\": \"$ENCLAVE_USER_ID\",
    \"type\": \"challenge\",
    \"challenge_type\": \"credential_request\",
    \"prompt\": \"I need your <Service> OAuth2 app credentials to connect. You can create an app at <developer portal URL>. I'll need: client_id and client_secret. Set the redirect URI to http://localhost:8765.\",
    \"context\": \"These are used once to authorize access. I'll store the resulting refresh token — you won't need to re-authorize unless you revoke access.\"
  }"
```

## Token Storage

Store tokens in `~/workspace/credentials/<service>_tokens.json`. Never hardcode. Read from file on each authenticate() call.

```python
import json, os

TOKEN_PATH = os.path.expanduser("~/workspace/credentials/<service>_tokens.json")

def _save_tokens(tokens: dict):
    os.makedirs(os.path.dirname(TOKEN_PATH), exist_ok=True)
    with open(TOKEN_PATH, "w") as f:
        json.dump(tokens, f)

def _load_tokens() -> dict:
    if not os.path.exists(TOKEN_PATH):
        raise FileNotFoundError(f"No tokens at {TOKEN_PATH} — run auth flow first")
    with open(TOKEN_PATH) as f:
        return json.load(f)
```

## Authorization Flow Implementation

```python
import httpx
import json
import os
import threading
import time
from urllib.parse import urlencode, parse_qs, urlparse
from http.server import HTTPServer, BaseHTTPRequestHandler

CLIENT_ID = os.getenv("SERVICE_CLIENT_ID")
CLIENT_SECRET = os.getenv("SERVICE_CLIENT_SECRET")
REDIRECT_URI = "http://localhost:8765"
SCOPES = ["scope1", "scope2"]  # service-specific

AUTH_URL = "https://service.com/oauth/authorize"
TOKEN_URL = "https://service.com/oauth/token"

_auth_code = None

class _CallbackHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        global _auth_code
        params = parse_qs(urlparse(self.path).query)
        _auth_code = params.get("code", [None])[0]
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"Authorization complete. Return to your app.")
    def log_message(self, *args):
        pass  # suppress server logs

def run_auth_flow() -> dict:
    """Full OAuth2 authorization code flow. Returns token dict."""
    global _auth_code
    _auth_code = None
    
    # Start callback server
    server = HTTPServer(("localhost", 8765), _CallbackHandler)
    t = threading.Thread(target=server.handle_request)
    t.daemon = True
    t.start()
    
    # Build auth URL
    params = {
        "client_id": CLIENT_ID,
        "redirect_uri": REDIRECT_URI,
        "response_type": "code",
        "scope": " ".join(SCOPES),
        "access_type": "offline",  # for refresh token — remove if service doesn't support
        "prompt": "consent",
    }
    auth_url = f"{AUTH_URL}?{urlencode(params)}"
    
    # Surface to user
    import subprocess
    subprocess.run(["curl", "-s", "-X", "POST",
        f"{os.getenv('AEGIS_API_URL')}/api/v1/session/agent_response",
        "-H", f"X-Enclave-Key: {os.getenv('ENCLAVE_API_KEY')}",
        "-H", "Content-Type: application/json",
        "-d", json.dumps({
            "user_id": os.getenv("ENCLAVE_USER_ID"),
            "type": "challenge",
            "challenge_type": "confirm_action",
            "prompt": f"Open this URL in your browser to authorize access:\n\n{auth_url}\n\nI'll receive the callback automatically.",
            "context": "After you click Authorize, the browser will show a confirmation page and I'll proceed automatically.",
        })
    ])
    
    # Wait for callback (60s timeout)
    for _ in range(120):
        if _auth_code:
            break
        time.sleep(0.5)
    
    if not _auth_code:
        raise TimeoutError("Authorization not completed within 60 seconds")
    
    # Exchange code for tokens
    r = httpx.post(TOKEN_URL, data={
        "grant_type": "authorization_code",
        "code": _auth_code,
        "redirect_uri": REDIRECT_URI,
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
    })
    r.raise_for_status()
    tokens = r.json()
    tokens["expires_at"] = time.time() + tokens.get("expires_in", 3600)
    _save_tokens(tokens)
    return tokens


def refresh_access_token(tokens: dict) -> dict:
    """Refresh expired access token using refresh_token."""
    r = httpx.post(TOKEN_URL, data={
        "grant_type": "refresh_token",
        "refresh_token": tokens["refresh_token"],
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
    })
    r.raise_for_status()
    new_tokens = {**tokens, **r.json()}
    new_tokens["expires_at"] = time.time() + new_tokens.get("expires_in", 3600)
    _save_tokens(new_tokens)
    return new_tokens


def authenticate() -> httpx.Client:
    """
    Return authenticated httpx client. Handles token refresh automatically.
    Runs auth flow on first call if no tokens exist.
    """
    try:
        tokens = _load_tokens()
    except FileNotFoundError:
        tokens = run_auth_flow()
    
    if time.time() >= tokens.get("expires_at", 0) - 60:
        tokens = refresh_access_token(tokens)
    
    client = httpx.Client(
        base_url="https://api.service.com/v1",
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
        timeout=30,
    )
    return client
```

## Service-Specific Notes

**GitHub** — tokens don't expire, no refresh needed:
```python
# GitHub uses personal access tokens OR OAuth; tokens don't expire
headers = {"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json"}
```

**Shopify** — shop-specific tokens:
```python
# Each shop is separate; token is permanent after installation
BASE_URL = f"https://{shop_domain}/admin/api/2024-01"
```

**Microsoft Graph** — tenant-aware:
```python
AUTH_URL = f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/authorize"
TOKEN_URL = f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token"
BASE_URL = "https://graph.microsoft.com/v1.0"
```

**Salesforce** — instance URL in token response:
```python
# Token response includes instance_url — use it as base URL
instance_url = tokens["instance_url"]
client = httpx.Client(base_url=f"{instance_url}/services/data/v59.0")
```
