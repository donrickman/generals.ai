---
name: auth-strategies
description: Use during connection discovery when deciding how to authenticate to a service — how to gauge the smartest approach up front from what you already know, what tools you have, and when to ask the user for something.
---

# Auth strategy: gauge the right way in, then adapt as you learn

This is about judgment, not a procedure. There are no thresholds here and no "if you see X, do Y"
table — the range of services and defenses you'll meet is open-ended, so no fixed script survives
contact. Use what you know and what the service shows you.

## Size it up first — don't just start clicking
Before you touch the service, judge the smartest way in, from what you already know about it plus a
quick look at its docs:
- **You already know a lot.** You know which services are ordinary consumer logins, which publish a
  real developer API, and which are notoriously hard or anti-automation. Let that steer your opening
  move — pick the approach most likely to work up front instead of defaulting to one and discovering
  the target is hard by failing.
- **Has it been solved?** Check `~/workspace/connection_code/` first — reuse beats rediscovery.
- **Is there a cleaner path than the browser?** An official API, a ready MCP server, or a maintained
  library is cheaper and more durable — worth it when one genuinely exists for *this* account and the
  task wants server-side scale (searching a big mailbox, say). For a plain personal-account login
  there usually isn't one; that's a browser login, so start there.

## What you have to work with
- **Two browsers, both baked in**, driven via the Playwright MCP tools (never Playwright-in-Bash):
  `mcp__playwright__browser_*` (headless — lighter, cheaper) and `mcp__playwright_headed__browser_*`
  (headed, real display — "looks real" to a target). Headed exists for logins a headless browser
  can't clear; reaching for it is an ordinary judgment call, not a failure or a last resort. The two
  keep separate profiles, so log in again when you switch, and record which one worked in the saved
  recipe so reuse takes the same path.
- **API key / OAuth2 / basic auth** for services that genuinely expose a developer API worth using.

## Read what the service tells you, and adapt
The response is the signal. A dashboard means you're in. A login form means log in. A CAPTCHA, an
"is this you / this browser may not be secure" screen, or a login that only fails automated is the
service telling you a plain automated browser won't do — so meet it with a more convincing one, or a
different path, per your read. Trust your judgment over any sequence.

## Ask the user only for what only they can provide
Raise a challenge (`mcp__aegis__raise_challenge`) — and wait — for the things that are genuinely
theirs: their credentials, an MFA code, or approval for a consequential action (sending, buying,
posting publicly). Don't stop for anything you can settle yourself (which header to try, which path
to take, a rate-limit backoff, a missing package). Never print JSON to ask — use the tool.

## When it works
Persist the artifact (see `aegis:write-connection-code`) with the credentials and the browser mode
that worked, run its self-test end-to-end, then report via `mcp__aegis__report_result`. And once
you're authenticated, think about next time — if a durable path (an API key you can now set up) is
cleaner, offer it.

## The browser login, concretely
```
mcp__playwright__browser_navigate(url="https://example.com")
mcp__playwright__browser_snapshot()        # already at a dashboard? you're logged in — go extract
# login form? read the field refs from the snapshot, then:
mcp__playwright__browser_type(element="email field", ref="<ref>", text=email)
mcp__playwright__browser_type(element="password field", ref="<ref>", text=password)
mcp__playwright__browser_click(element="submit button", ref="<ref>")
mcp__playwright__browser_snapshot()        # confirm you reached the dashboard
```
Many SPAs load data from internal JSON endpoints — worth checking network requests before scraping the DOM.
