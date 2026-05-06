#!/usr/bin/env bash
# Commits and pushes generated Promises to the root of the generated-promises branch.
# Keeps main free of CI bot commits; Flux watches generated-promises for Promises.
# Skips the commit if nothing changed. Tagged [skip ci] to avoid re-triggering.
set -euo pipefail

BRANCH="generated-promises"

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

# Snapshot contents of platform-api/ without the directory prefix, then remove
# it so the untracked files don't block the branch switch
tar czf /tmp/platform-api.tar.gz -C platform-api .
rm -rf platform-api/

# Set up the generated-promises branch
git fetch origin "${BRANCH}" 2>/dev/null || true

if git rev-parse --verify "origin/${BRANCH}" &>/dev/null; then
  git checkout -B "${BRANCH}" "origin/${BRANCH}"
else
  # First run — create an orphan branch with no shared history with main
  git checkout --orphan "${BRANCH}"
fi

# Wipe existing content and restore fresh from the snapshot
git rm -rf . --quiet 2>/dev/null || true
tar xzf /tmp/platform-api.tar.gz

git add .
git diff --staged --quiet || (
  git commit -m "chore: regenerate promises from terraform modules [skip ci]" &&
  git push origin "${BRANCH}"
)
