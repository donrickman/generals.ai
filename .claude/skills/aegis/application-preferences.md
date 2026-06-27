---
name: application-preferences
description: Use when connecting to or acting on a service (Aha, Gmail, etc.) — read and maintain the per-app preference file that captures how THIS user uses it, lazy-loaded to keep cost down
---

# Application Preferences — per-app, lazy-loaded, cheap

A living "how THIS user uses <app>" file per application. It makes you better at the user's actual
workflow over time WITHOUT inflating the always-loaded context (every turn re-reads the system
prompt — that cache-read is the enclave's dominant cost, so these must NOT go into CLAUDE.md or the
auto-memory).

## Where it lives
- **One file per app**, per user, on the PVC: `~/.claude/preferences/<app>.md`
  (e.g. `~/.claude/preferences/aha.md`, `~/.claude/preferences/gmail.md`). Create the
  `~/.claude/preferences/` directory if it doesn't exist. These persist across pod restarts and are
  never shared with other users.
- The connection recipe links to it via its `preferences:` header, and the saved-connections list
  surfaces it as "read ~/.claude/preferences/<app>.md first". So you can find it from either.

## How to use it (this is what makes it cheap)
- **Lazy — read on demand only.** When you're about to act on a service (right after you load its
  recipe for reuse), read that one preference file. Do NOT read them otherwise. They are never
  auto-loaded, so they cost zero on every turn you're not touching that app. They can get big; that's
  fine because nothing pays for them until you open the one you need.
- **Update as you learn.** After acting, append/refine what you learned about how the user works:
  common requests, exact phrasing they use, preferred targets, shortcuts, structure quirks, gotchas.
  Keep it terse and current; prune stale lines.
- **Never inline it elsewhere.** Don't copy preference content into CLAUDE.md, the auto-memory, or the
  recipe — those are loaded every turn. Keep only the *link* there.

## Example — `~/.claude/preferences/aha.md`
```
# Aha — how Don uses it
- Top-level "products" are workstreams / clients, NOT his projects.
- His actual projects live UNDER the "Edge Ventures" product. Add features/ideas there.
- ~80% of requests = "add this idea/note/feature to <project>". Prefers terse capture.
- Phrasing: "add a note to X", "add a feature to the <name> project".
```
