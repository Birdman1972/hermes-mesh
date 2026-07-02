#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="${1:-$HOME/hermes-mesh}"
log() { logger -t hermes-mesh-sync "$*"; }

git -C "$REPO_DIR" fetch origin --quiet
if [[ -n "$(git -C "$REPO_DIR" status --porcelain --untracked-files=all)" ]]; then
  log "WARNING: dirty worktree in $REPO_DIR; skipping auto-sync"
  exit 0
fi

read -r ahead behind < <(git -C "$REPO_DIR" rev-list --left-right --count HEAD...origin/main)
if (( ahead == 0 && behind > 0 )); then
  if git -C "$REPO_DIR" pull --ff-only; then log "pulled fast-forward updates in $REPO_DIR"; else log "WARNING: fast-forward pull failed in $REPO_DIR"; fi
elif (( ahead > 0 && behind == 0 )); then
  if git -C "$REPO_DIR" push origin main; then log "pushed local commits from $REPO_DIR"; else log "WARNING: push failed in $REPO_DIR"; fi
elif (( ahead > 0 && behind > 0 )); then
  log "WARNING: branch diverged from origin/main in $REPO_DIR; manual merge required"
fi
