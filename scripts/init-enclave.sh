#!/usr/bin/env bash
# init-enclave.sh — First-boot initialization for an Aegis Enclave pod
#
# Called by the Enclave container entrypoint before launching Claude Code.
# Idempotent: safe to run on every pod start; skips if already initialized.
#
# Required env vars (set by enclave_provisioner.py):
#   HOME            — /data/users/<user_id>  (PVC mount point)
#   ENCLAVE_USER_ID — UUID of the user
#   ENCLAVE_API_KEY — per-Enclave API key
#   AEGIS_API_URL   — backend API base URL
#
# After this script exits, the entrypoint launches:
#   claude --dangerously-skip-permissions [task from /prompt]

set -euo pipefail

SCAFFOLD_REPO="git@github.com:donrickman/generals.ai.git"
INIT_MARKER="$HOME/.aegis_initialized"
WORKSPACE="$HOME/workspace"
CREDS_DIR="$WORKSPACE/credentials"
BROWSER_PROFILE_DIR="$WORKSPACE/browser-profile"

log() { echo "[init-enclave] $*"; }
err() { echo "[init-enclave] ERROR: $*" >&2; exit 1; }

# Validate required env vars
[[ -z "${HOME:-}" ]]            && err "HOME not set — pod spec missing HOME env var"
[[ -z "${ENCLAVE_USER_ID:-}" ]] && err "ENCLAVE_USER_ID not set"
[[ "$HOME" == "/root" ]]        && err "HOME is /root (ephemeral). Set HOME=/data/users/\$ENCLAVE_USER_ID in pod spec."
[[ "$HOME" != /data/* ]]        && err "HOME=$HOME is not on the PVC. Expected /data/users/<uuid>."

log "Starting enclave init for user $ENCLAVE_USER_ID"
log "HOME=$HOME"

# ── Already initialized ────────────────────────────────────────────────────
if [[ -f "$INIT_MARKER" ]]; then
    log "Already initialized (found $INIT_MARKER) — skipping scaffold clone"
    # Still ensure workspace subdirs exist (in case PVC was partially wiped)
    mkdir -p "$WORKSPACE/connection_code" "$BROWSER_PROFILE_DIR" "$CREDS_DIR" "$WORKSPACE/downloads"
    log "Init complete (resumed)"
    exit 0
fi

# ── First boot ─────────────────────────────────────────────────────────────
log "First boot — setting up scaffold"

# Ensure HOME exists on PVC
mkdir -p "$HOME"

# Clone scaffold into HOME, then detach remote
# Each user's PVC becomes their own independent copy
log "Cloning scaffold from $SCAFFOLD_REPO"
git clone "$SCAFFOLD_REPO" "$HOME" --depth=1 --quiet || err "Failed to clone scaffold repo"

# Detach from remote — this user's copy is now independent
rm -rf "$HOME/.git"
log "Detached scaffold from remote — user copy is now independent"

# Initialize workspace as its own git repo for connection_code tracking
git -C "$HOME" init --quiet
git -C "$WORKSPACE" init --quiet 2>/dev/null || true

# Create required workspace subdirectories
mkdir -p \
    "$WORKSPACE/connection_code" \
    "$BROWSER_PROFILE_DIR" \
    "$CREDS_DIR" \
    "$WORKSPACE/downloads" \
    "$HOME/.claude/memory"

# Set safe permissions on credentials dir
chmod 700 "$CREDS_DIR"

# Write memory primer so Claude Code starts with user context
cat > "$HOME/.claude/memory/enclave-identity.md" << EOF
---
name: enclave-identity
description: This Enclave's identity and Aegis connection
metadata:
  type: project
---

This Claude Code instance is an Aegis Enclave agent.

- User ID: $ENCLAVE_USER_ID
- Aegis API: $AEGIS_API_URL
- Home (PVC): $HOME
- Workspace: $WORKSPACE
- Connection code artifacts: $WORKSPACE/connection_code/
- Browser profile: $BROWSER_PROFILE_DIR/
- Credentials: $CREDS_DIR/

All outbound communication goes to POST \$AEGIS_API_URL/api/v1/session/agent_response.
Never go silent. Push progress, challenges, and results via the report-progress skill.
EOF

log "Workspace initialized:"
log "  connection_code/ → $WORKSPACE/connection_code"
log "  browser-profile/ → $BROWSER_PROFILE_DIR"
log "  credentials/     → $CREDS_DIR"

# Mark initialized — prevents re-clone on subsequent pod starts
touch "$INIT_MARKER"
log "Marked as initialized ($INIT_MARKER)"

log "Init complete — ready for Claude Code"
