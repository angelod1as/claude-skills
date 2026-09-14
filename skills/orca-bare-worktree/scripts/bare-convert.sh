#!/usr/bin/env bash
# Convert an existing normal repository to the bare + worktrees layout, by COPYING
# its .git directory. The original repository is never modified and stays on disk
# as a safety net.
#
# Usage:
#   bare-convert.sh <old-repo> <new-root>            # audit only, changes nothing
#   bare-convert.sh <old-repo> <new-root> --apply    # perform the conversion
#
# The audit runs in both modes and reports:
#   - local branches whose tip exists on no remote (they would be lost by a
#     `git clone --bare`, which is why this script copies .git instead)
#   - ignored/untracked files each worktree will need copied by hand
#
# `git log @{u}..` is deliberately NOT used to detect unpushed work: it reports
# nothing when a branch has no upstream configured, which looks like "all pushed"
# and is not. `git branch -r --contains <sha>` is the honest check.

set -euo pipefail

OLD=""; NEW=""; APPLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) if [ -z "$OLD" ]; then OLD="$1"; else NEW="$1"; fi; shift ;;
  esac
done

[ -n "$OLD" ] && [ -n "$NEW" ] || { echo "usage: bare-convert.sh <old-repo> <new-root> [--apply]" >&2; exit 2; }
[ -d "$OLD/.git" ] || { echo "not a normal git repository (no .git directory): $OLD" >&2; exit 1; }
OLD="$(cd "$OLD" && pwd)"

# Detached HEAD (mid-rebase, mid-bisect, a checked-out tag) has no symbolic ref.
# Falling back to the literal "main" would misreport, and then fail halfway through
# the conversion on a repo whose default is named something else.
BRANCH="$(git -C "$OLD" symbolic-ref --quiet --short HEAD || true)"
if [ -z "$BRANCH" ]; then
  BRANCH="$(git -C "$OLD" for-each-ref --count=1 --format='%(refname:short)' refs/heads)"
fi
[ -n "$BRANCH" ] || { echo "no local branches in $OLD; nothing to convert" >&2; exit 1; }

echo "=============================================================="
echo " AUDIT — $OLD"
echo "=============================================================="
echo
echo "-- remotes --"
git -C "$OLD" remote -v || true
echo
echo "-- fetch refspec --"
git -C "$OLD" config --get-all remote.origin.fetch || echo "  (none)"
echo
echo "-- existing worktrees --"
git -C "$OLD" worktree list
echo
echo "-- local branches not contained in any remote branch --"
UNPUSHED=0
while IFS= read -r b; do
  sha="$(git -C "$OLD" rev-parse "$b")"
  if [ -z "$(git -C "$OLD" branch -r --contains "$sha" 2>/dev/null)" ]; then
    echo "  LOCAL ONLY: $b  ($sha)"
    UNPUSHED=$((UNPUSHED + 1))
  fi
done < <(git -C "$OLD" for-each-ref --format='%(refname:short)' refs/heads)
[ "$UNPUSHED" -eq 0 ] && echo "  (none — every local branch tip exists on a remote)"
echo
echo "-- ignored files (not versioned; each worktree may need its own copy) --"
git -C "$OLD" status --ignored --porcelain 2>/dev/null | grep '^!!' | sed 's/^!! /  /' || echo "  (none)"
echo
echo "-- stashes --"
git -C "$OLD" stash list || true
echo

if [ "$APPLY" -ne 1 ]; then
  echo "=============================================================="
  echo " AUDIT ONLY. Nothing was changed."
  echo " Review the list above. Anything marked LOCAL ONLY exists on this"
  echo " machine only; decide what to keep before converting."
  echo " Re-run with --apply to convert."
  echo "=============================================================="
  exit 0
fi

for entry in .bare .git wt; do
  if [ -e "$NEW/$entry" ] || [ -L "$NEW/$entry" ]; then
    echo "refusing to run: $NEW/$entry already exists" >&2
    exit 1
  fi
done

mkdir -p "$NEW"
NEW="$(cd "$NEW" && pwd)"

# The closing instructions tell the user to delete $OLD once everything is green.
# If one directory sits inside the other, that deletes the conversion too.
case "$NEW/" in "$OLD"/*) echo "refusing to run: $NEW is inside $OLD" >&2; exit 1 ;; esac
case "$OLD/" in "$NEW"/*) echo "refusing to run: $OLD is inside $NEW" >&2; exit 1 ;; esac

# A copy taken while another process is mid-write can be internally inconsistent.
for lock in index.lock gc.pid; do
  if [ -e "$OLD/.git/$lock" ]; then
    echo "refusing to run: $OLD/.git/$lock exists — another git process is active." >&2
    echo "Close any git client or background gc, then re-run." >&2
    exit 1
  fi
done

echo "==> copying $OLD/.git -> $NEW/.bare (the original is left untouched)"
cp -R "$OLD/.git" "$NEW/.bare"
rm -f "$NEW/.bare/index"
rm -rf "$NEW/.bare/worktrees"
git -C "$NEW/.bare" config core.bare true
printf 'gitdir: ./.bare\n' > "$NEW/.git"
mkdir -p "$NEW/wt"
printf 'gitdir: ../.bare\n' > "$NEW/wt/.git"

echo "==> adding wt/$BRANCH"
git -C "$NEW" worktree add "wt/$BRANCH" "$BRANCH"

echo
echo "=============================================================="
echo " VERIFICATION"
echo "=============================================================="
FAILED=0

echo "-- fsck --"
if git -C "$NEW/.bare" fsck --no-progress; then
  echo "  fsck clean"
else
  echo "  FSCK FAILED"
  FAILED=1
fi
echo
echo "-- ref parity (old vs new; expect no output) --"
if diff <(git -C "$OLD" for-each-ref --format='%(refname) %(objectname)') \
        <(git -C "$NEW/.bare" for-each-ref --format='%(refname) %(objectname)'); then
  echo "  refs identical"
else
  echo "  REF MISMATCH"
  FAILED=1
fi
echo

if [ "$FAILED" -ne 0 ]; then
  echo "=============================================================="
  echo " VERIFICATION FAILED — DO NOT DELETE $OLD"
  echo " The copy at $NEW is not trustworthy. $OLD is still intact and"
  echo " remains the source of truth. Investigate the output above before"
  echo " doing anything else."
  echo "=============================================================="
  exit 1
fi

echo "-- worktrees --"
git -C "$NEW" worktree list
echo
echo "Remaining, by hand:"
echo "  * add a worktree per branch you want live:  git -C '$NEW' worktree add wt/<name> <branch>"
echo "  * copy the ignored files listed in the audit into wt/$BRANCH"
echo "  * install dependencies and run lint / tests / build in wt/$BRANCH"
echo "  * git -C '$NEW' fetch --dry-run"
echo "  * only once all of that is green, delete $OLD"
