#!/usr/bin/env bash
set -euo pipefail
REPO="/Users/jingchunwong/vocabularyLib"
cd "$REPO"
# Only commit if there are changes
if ! git diff-index --quiet HEAD --; then
  git add -A
  MSG="auto commit $(date '+%Y-%m-%d %H:%M:%S')"
  git commit -m "$MSG"
  git push origin HEAD
  echo "$MSG pushed"
else
  echo "No changes at $(date '+%Y-%m-%d %H:%M:%S')"
fi
