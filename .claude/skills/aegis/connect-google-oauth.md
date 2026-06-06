---
name: connect-google-oauth
description: Use when connecting any Google Workspace service (Gmail, Calendar, Drive, Sheets, Docs) via OAuth2. Covers the full flow from credential setup through token storage and refresh.
---

# Connecting Google Workspace via OAuth2

## What This Covers

Gmail, Google Calendar, Google Drive, Google Sheets, Google Docs, Google Tasks, Google Contacts — all use the same OAuth2 flow. This skill covers the full cycle: credential setup → authorization → token storage → API usage → refresh.

## Prerequisites

The user needs a Google Cloud project with OAuth2 credentials. If they don't have one, surface this challenge immediately:

```bash
curl -s -X POST "$AEGIS_API_URL/api/v1/session/agent_response" \
  -H "X-Enclave-Key: $ENCLAVE_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"user_id\": \"$ENCLAVE_USER_ID\",
    \"type\": \"challenge\",
    \"challenge_type\": \"credential_request\",
    \"prompt\": \"I need your Google OAuth2 credentials (client_id and client_secret) to connect your Google account. You can create them at console.cloud.google.com → APIs & Services → Credentials → Create OAuth 2.0 Client ID. Choose 'Desktop app' as the type and download the JSON.\",
    \"context\": \"Google requires an OAuth2 app to authorize third-party access. The credentials are used once to get a refresh token that persists — you won't need to re-authorize.\"
  }"
```

## Required Scopes by Service

Pick only the scopes you need — fewer scopes = easier user approval:

| Service | Scope |
|---|---|
| Gmail read | `https://www.googleapis.com/auth/gmail.readonly` |
| Gmail send | `https://www.googleapis.com/auth/gmail.send` |
| Gmail full | `https://www.googleapis.com/auth/gmail.modify` |
| Calendar read | `https://www.googleapis.com/auth/calendar.readonly` |
| Calendar full | `https://www.googleapis.com/auth/calendar` |
| Drive read | `https://www.googleapis.com/auth/drive.readonly` |
| Drive full | `https://www.googleapis.com/auth/drive` |
| Sheets read | `https://www.googleapis.com/auth/spreadsheets.readonly` |
| Sheets full | `https://www.googleapis.com/auth/spreadsheets` |

## Step 1: Install Dependencies

```bash
pip install google-auth google-auth-oauthlib google-auth-httplib2 google-api-python-client
```

## Step 2: Authorization Flow

The first time requires user interaction — they need to click a link and paste back a code. Use the `credential_request` challenge for this:

```python
# auth_google.py — run this to get initial tokens
import os
import json
from google_auth_oauthlib.flow import InstalledAppFlow
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials

SCOPES = [
    "https://www.googleapis.com/auth/gmail.readonly",
    "https://www.googleapis.com/auth/gmail.send",
    "https://www.googleapis.com/auth/calendar",
]

TOKEN_PATH = os.path.expanduser("~/workspace/credentials/google_token.json")
CREDS_PATH = os.path.expanduser("~/workspace/credentials/google_oauth_creds.json")

def get_credentials():
    creds = None
    if os.path.exists(TOKEN_PATH):
        creds = Credentials.from_authorized_user_file(TOKEN_PATH, SCOPES)
    
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            flow = InstalledAppFlow.from_client_secrets_file(CREDS_PATH, SCOPES)
            # Use run_console() in Enclave — no browser redirect available
            creds = flow.run_console()
        
        os.makedirs(os.path.dirname(TOKEN_PATH), exist_ok=True)
        with open(TOKEN_PATH, "w") as f:
            f.write(creds.to_json())
    
    return creds

if __name__ == "__main__":
    creds = get_credentials()
    print("✓ Authorized. Token saved to", TOKEN_PATH)
```

**Surface the auth URL as a challenge.** The Enclave has no browser display for OAuth redirect. Use `run_console()` which prints a URL for the user to open, then asks for the code:

```bash
# Surface the challenge to the user before running auth flow
curl -s -X POST "$AEGIS_API_URL/api/v1/session/agent_response" \
  -H "X-Enclave-Key: $ENCLAVE_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"user_id\": \"$ENCLAVE_USER_ID\",
    \"type\": \"challenge\",
    \"challenge_type\": \"confirm_action\",
    \"prompt\": \"I'm ready to connect your Google account. I'll give you a URL to open in your browser — you'll authorize the app, then paste the code back to me. Ready?\",
    \"context\": \"This is a one-time authorization. The refresh token persists — you won't need to repeat this.\"
  }"
```

After user confirms, run the auth script. When it outputs the URL, surface it to the user as another challenge asking for the authorization code.

## Step 3: Connection Code Template

```python
"""
connection_code: Google Workspace
strategy: oauth2
discovered: YYYY-MM-DD
scope: gmail.readonly, gmail.send, calendar, drive.readonly
actions:
  - authenticate() -> credentials
  - gmail_list_inbox(creds, max_results=10) -> list[dict]
  - gmail_send(creds, to, subject, body) -> dict
  - calendar_list_events(creds, days_ahead=7) -> list[dict]
  - drive_list_files(creds, query=None, max_results=10) -> list[dict]
notes: |
  Token auto-refreshes via google-auth library. Token stored at
  ~/workspace/credentials/google_token.json. Re-run auth if token is revoked.
  Scopes are fixed at auth time — adding new scopes requires re-authorization.
"""

import os
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build
import base64
from email.mime.text import MIMEText
from datetime import datetime, timedelta, timezone

TOKEN_PATH = os.path.expanduser("~/workspace/credentials/google_token.json")

SCOPES = [
    "https://www.googleapis.com/auth/gmail.readonly",
    "https://www.googleapis.com/auth/gmail.send",
    "https://www.googleapis.com/auth/calendar",
    "https://www.googleapis.com/auth/drive.readonly",
]


def authenticate():
    """Load and refresh credentials. Raises if token missing or revoked."""
    if not os.path.exists(TOKEN_PATH):
        raise FileNotFoundError(
            f"No token at {TOKEN_PATH}. Run the auth flow first."
        )
    creds = Credentials.from_authorized_user_file(TOKEN_PATH, SCOPES)
    if creds.expired and creds.refresh_token:
        creds.refresh(Request())
        with open(TOKEN_PATH, "w") as f:
            f.write(creds.to_json())
    if not creds.valid:
        raise RuntimeError("Token invalid. Re-authorize via auth flow.")
    return creds


# ---------------------------------------------------------------------------
# Gmail
# ---------------------------------------------------------------------------

def gmail_list_inbox(creds, max_results: int = 10) -> list[dict]:
    """Return list of recent inbox messages with id, subject, from, date, snippet."""
    service = build("gmail", "v1", credentials=creds)
    result = service.users().messages().list(
        userId="me", labelIds=["INBOX"], maxResults=max_results
    ).execute()
    messages = result.get("messages", [])
    out = []
    for m in messages:
        msg = service.users().messages().get(userId="me", id=m["id"], format="metadata",
              metadataHeaders=["Subject", "From", "Date"]).execute()
        headers = {h["name"]: h["value"] for h in msg["payload"].get("headers", [])}
        out.append({
            "id": m["id"],
            "subject": headers.get("Subject", ""),
            "from": headers.get("From", ""),
            "date": headers.get("Date", ""),
            "snippet": msg.get("snippet", ""),
        })
    return out


def gmail_send(creds, to: str, subject: str, body: str) -> dict:
    """Send email. Returns message ID."""
    service = build("gmail", "v1", credentials=creds)
    message = MIMEText(body)
    message["to"] = to
    message["subject"] = subject
    raw = base64.urlsafe_b64encode(message.as_bytes()).decode()
    result = service.users().messages().send(userId="me", body={"raw": raw}).execute()
    return {"id": result["id"]}


def gmail_search(creds, query: str, max_results: int = 10) -> list[dict]:
    """Search Gmail. query uses Gmail search syntax (e.g. 'from:alice subject:meeting')."""
    service = build("gmail", "v1", credentials=creds)
    result = service.users().messages().list(
        userId="me", q=query, maxResults=max_results
    ).execute()
    messages = result.get("messages", [])
    out = []
    for m in messages:
        msg = service.users().messages().get(userId="me", id=m["id"], format="metadata",
              metadataHeaders=["Subject", "From", "Date"]).execute()
        headers = {h["name"]: h["value"] for h in msg["payload"].get("headers", [])}
        out.append({
            "id": m["id"],
            "subject": headers.get("Subject", ""),
            "from": headers.get("From", ""),
            "date": headers.get("Date", ""),
            "snippet": msg.get("snippet", ""),
        })
    return out


# ---------------------------------------------------------------------------
# Calendar
# ---------------------------------------------------------------------------

def calendar_list_events(creds, days_ahead: int = 7) -> list[dict]:
    """Return upcoming calendar events for the next N days."""
    service = build("calendar", "v3", credentials=creds)
    now = datetime.now(timezone.utc)
    end = now + timedelta(days=days_ahead)
    result = service.events().list(
        calendarId="primary",
        timeMin=now.isoformat(),
        timeMax=end.isoformat(),
        maxResults=20,
        singleEvents=True,
        orderBy="startTime",
    ).execute()
    events = result.get("items", [])
    return [
        {
            "id": e["id"],
            "summary": e.get("summary", ""),
            "start": e["start"].get("dateTime", e["start"].get("date", "")),
            "end": e["end"].get("dateTime", e["end"].get("date", "")),
            "location": e.get("location", ""),
            "description": e.get("description", ""),
        }
        for e in events
    ]


def calendar_create_event(creds, summary: str, start_iso: str, end_iso: str,
                          description: str = "", location: str = "") -> dict:
    """Create a calendar event. start/end in ISO 8601 format with timezone."""
    service = build("calendar", "v3", credentials=creds)
    event = {
        "summary": summary,
        "location": location,
        "description": description,
        "start": {"dateTime": start_iso},
        "end": {"dateTime": end_iso},
    }
    result = service.events().insert(calendarId="primary", body=event).execute()
    return {"id": result["id"], "htmlLink": result.get("htmlLink", "")}


# ---------------------------------------------------------------------------
# Drive
# ---------------------------------------------------------------------------

def drive_list_files(creds, query: str = None, max_results: int = 10) -> list[dict]:
    """List Drive files. query uses Drive search syntax (e.g. "name contains 'report'")."""
    service = build("drive", "v3", credentials=creds)
    params = {
        "pageSize": max_results,
        "fields": "files(id, name, mimeType, modifiedTime, size)",
    }
    if query:
        params["q"] = query
    result = service.files().list(**params).execute()
    return result.get("files", [])


def drive_get_file_content(creds, file_id: str) -> str:
    """Download a text/plain or Google Doc as plain text."""
    from googleapiclient.http import MediaIoBaseDownload
    import io
    service = build("drive", "v3", credentials=creds)
    meta = service.files().get(fileId=file_id, fields="mimeType").execute()
    mime = meta["mimeType"]
    if "google-apps.document" in mime:
        result = service.files().export(
            fileId=file_id, mimeType="text/plain"
        ).execute()
        return result.decode("utf-8") if isinstance(result, bytes) else result
    else:
        request = service.files().get_media(fileId=file_id)
        buf = io.BytesIO()
        downloader = MediaIoBaseDownload(buf, request)
        done = False
        while not done:
            _, done = downloader.next_chunk()
        return buf.getvalue().decode("utf-8", errors="replace")


# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    print("Testing Google Workspace connection_code")
    creds = authenticate()
    print("  ✓ authenticated")

    msgs = gmail_list_inbox(creds, max_results=3)
    print(f"  ✓ gmail_list_inbox → {len(msgs)} messages")
    if msgs:
        print(f"    most recent: {msgs[0]['subject'][:60]}")

    events = calendar_list_events(creds, days_ahead=7)
    print(f"  ✓ calendar_list_events → {len(events)} upcoming events")

    files = drive_list_files(creds, max_results=3)
    print(f"  ✓ drive_list_files → {len(files)} files")

    print("All checks passed ✓")
