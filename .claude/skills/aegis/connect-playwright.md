---
name: connect-playwright
description: Use when a service has no usable API and requires browser automation — login walls, CAPTCHA-protected sites, services that only expose data through their web UI. Covers session persistence, login detection, and action extraction.
---

# Connecting via Browser Automation (Playwright)

## When to Use This

Use Playwright when:
- The service has no public API or the API is behind a paid tier
- Auth requires a login flow that an API can't replicate (SSO, SAML, complex JS)
- Data only exists in the web UI
- A CAPTCHA or bot-detection wall blocks direct API calls
- The service uses session cookies that can be extracted for subsequent requests

Do NOT use Playwright when a working API or API key approach exists — it's slower, more brittle, and harder to maintain.

## Environment

Playwright + Chromium are installed in every Enclave. Xvfb provides a virtual display — use `headless=False` and it will work. This is intentional: headed browsers are harder for target sites to detect.

```bash
# Xvfb is already running. Verify:
echo $DISPLAY   # should be :99 or similar
```

## Session Persistence

The persistent browser profile at `~/workspace/browser-profile/<service>/` stores cookies, localStorage, and session data. Reusing this profile means:
- First run: completes full login flow
- Subsequent runs: already logged in, skips login entirely

```python
PROFILE_DIR = os.path.expanduser("~/workspace/browser-profile/<service>")
```

## Login Detection Pattern

```python
def _is_logged_in(page) -> bool:
    """Check if session is active — adapt URL/selector to the service."""
    try:
        # Option 1: Check URL
        return "dashboard" in page.url or "home" in page.url or "app" in page.url
        
        # Option 2: Check for logout button / avatar
        # return page.locator('[data-testid="user-avatar"]').is_visible(timeout=2000)
        
        # Option 3: Check for login form absence
        # return not page.locator('input[type="password"]').is_visible(timeout=2000)
    except Exception:
        return False
```

## Full Connection Code Template

```python
"""
connection_code: <ServiceName>
strategy: playwright
discovered: YYYY-MM-DD
scope: n/a
actions:
  - authenticate() -> BrowserContext
  - scrape_<resource>(context) -> list[dict]
  - perform_<action>(context, ...) -> dict
notes: |
  Browser profile persists at ~/workspace/browser-profile/<service>.
  First run requires login — subsequent runs reuse saved session.
  If login breaks, delete the profile dir and re-run to get a fresh session.
  MFA: if the service uses TOTP, pass the code via challenge before calling authenticate().
"""

import os
from playwright.sync_api import sync_playwright, BrowserContext

PROFILE_DIR = os.path.expanduser("~/workspace/browser-profile/<service>")
SERVICE_URL = "https://example.com"
LOGIN_URL = "https://example.com/login"


def authenticate(mfa_code: str = None) -> BrowserContext:
    """
    Return authenticated browser context.
    On first run: completes login. On subsequent runs: resumes from saved profile.
    Pass mfa_code if MFA is required.
    """
    os.makedirs(PROFILE_DIR, exist_ok=True)
    p = sync_playwright().start()
    context = p.chromium.launch_persistent_context(
        PROFILE_DIR,
        headless=False,
        args=["--no-sandbox", "--disable-dev-shm-usage"],
        viewport={"width": 1280, "height": 800},
    )
    page = context.new_page()
    page.goto(SERVICE_URL, wait_until="networkidle", timeout=30000)
    
    if _is_logged_in(page):
        return context
    
    # Login flow
    email = os.getenv("SERVICE_EMAIL")
    password = os.getenv("SERVICE_PASSWORD")
    if not email or not password:
        raise ValueError("SERVICE_EMAIL and SERVICE_PASSWORD env vars required")
    
    page.goto(LOGIN_URL)
    page.wait_for_load_state("networkidle")
    
    # Fill credentials — adapt selectors to the service
    page.fill('input[type="email"], input[name="email"], #email', email)
    page.fill('input[type="password"], input[name="password"], #password', password)
    page.click('button[type="submit"], input[type="submit"], button:has-text("Sign in")')
    
    # Handle MFA if present
    try:
        mfa_input = page.wait_for_selector('input[name="code"], input[placeholder*="code"]',
                                            timeout=5000)
        if mfa_input and not mfa_code:
            raise ValueError("MFA required — pass mfa_code parameter")
        if mfa_code:
            mfa_input.fill(mfa_code)
            page.click('button[type="submit"]')
    except Exception as e:
        if "mfa_code" in str(e):
            raise
        pass  # No MFA prompt — continue
    
    # Wait for post-login redirect
    try:
        page.wait_for_url("**/dashboard/**", timeout=15000)
    except Exception:
        page.wait_for_load_state("networkidle", timeout=15000)
    
    if not _is_logged_in(page):
        raise RuntimeError("Login failed — check credentials or page structure changed")
    
    return context


def _is_logged_in(page) -> bool:
    try:
        return "login" not in page.url and "signin" not in page.url
    except Exception:
        return False


# ---------------------------------------------------------------------------
# Action pattern: scrape data from a page
# ---------------------------------------------------------------------------

def scrape_items(context: BrowserContext) -> list[dict]:
    """Extract items from the service's data page."""
    page = context.new_page()
    page.goto("https://example.com/items")
    page.wait_for_load_state("networkidle")
    
    items = []
    # Adapt selector to match the actual page structure
    rows = page.query_selector_all(".item-row, tr[data-id], [data-testid='item']")
    for row in rows:
        items.append({
            "id": row.get_attribute("data-id") or "",
            "name": row.query_selector(".name, td:nth-child(1)")
                      .inner_text() if row.query_selector(".name, td:nth-child(1)") else "",
        })
    page.close()
    return items


# ---------------------------------------------------------------------------
# Action pattern: intercept API calls made by the page
# ---------------------------------------------------------------------------

def get_data_via_network(context: BrowserContext) -> list[dict]:
    """
    Navigate to a page and capture its internal API calls.
    Many SPAs load data from internal REST endpoints — intercept those instead of scraping DOM.
    """
    captured = []
    
    def handle_response(response):
        if "/api/items" in response.url and response.status == 200:
            try:
                data = response.json()
                captured.extend(data.get("items", data if isinstance(data, list) else []))
            except Exception:
                pass
    
    page = context.new_page()
    page.on("response", handle_response)
    page.goto("https://example.com/items")
    page.wait_for_load_state("networkidle")
    page.close()
    return captured


# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    print("Testing <ServiceName> playwright connection_code")
    context = authenticate()
    print("  ✓ authenticated (browser session active)")
    
    items = scrape_items(context)
    print(f"  ✓ scrape_items → {len(items)} items")
    if not items:
        print("  ⚠ no items found — verify page structure hasn't changed")
    
    context.close()
    print("All checks passed ✓")
