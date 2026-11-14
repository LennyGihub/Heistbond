#!/bin/bash
# Save the game's code to GitHub: export Studio scripts -> game/, rebuild the
# graphify map (offline), commit both to the `main` branch and push.
# Works from any session branch: it commits through a temporary worktree of main.
#
#   tools/save_game.sh "game: coin pickups + shop UI"     # export + push
#   tools/save_game.sh "msg" --no-push                     # dry run (commit locally only)
#   EXPORT_ARGS='--studio "Text opti"' tools/save_game.sh "msg"
set -euo pipefail
MSG="${1:-game: update scripts from Studio}"
PUSH=1; [ "${2:-}" = "--no-push" ] && PUSH=0
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

eval python3 tools/export_studio.py ${EXPORT_ARGS:-}

git fetch -q origin main
WT="$(mktemp -d)"
trap 'git -C "$ROOT" worktree remove --force "$WT" >/dev/null 2>&1 || true' EXIT
git worktree add -q --detach "$WT" origin/main

sync_dir() {  # copy $1 from the session checkout into main's worktree (mirror)
  rm -rf "$WT/$1"
  if [ -d "$ROOT/$1" ]; then cp -r "$ROOT/$1" "$WT/$1"; fi
  rm -rf "$WT/$1/cache"
}
sync_dir game
sync_dir graphify-out

cd "$WT"
for d in game graphify-out; do
  if [ -e "$d" ] || git ls-files --error-unmatch "$d" >/dev/null 2>&1; then git add -A -f "$d"; fi
done
if git diff --cached --quiet; then
  echo "No script changes since the last save."
  exit 0
fi
git commit -q -m "$MSG"
echo "Committed to main: $(git log -1 --format='%h %s')"
[ "$PUSH" = 1 ] || { echo "(dry run: not pushed)"; exit 0; }

for i in 1 2 3 4; do
  if git push -q origin HEAD:main; then echo "Pushed to main."; exit 0; fi
  sleep $((2 ** i))
  git fetch -q origin main && git rebase -q origin/main   # someone else saved meanwhile
done
echo "Push to main failed after retries." >&2
exit 1
