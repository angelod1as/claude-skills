#!/usr/bin/env bash
# Create a new project using the bare + worktrees layout.
#
#   <root>/
#   ├── .bare/      bare repository (all git objects, no working tree)
#   ├── .git        a FILE containing "gitdir: ./.bare"
#   └── wt/
#       ├── .git    a FILE containing "gitdir: ../.bare"  (lets tools detect wt/ as the repo)
#       └── main/   main is a worktree like any other
#
# Usage:
#   bare-new.sh <root> [--branch <name>] [--remote <url>]
#
#   --branch   default branch name (default: main)
#   --remote   clone this remote into .bare instead of creating an empty repo.
#              An empty remote is fine: the script falls back to an empty root commit.

set -euo pipefail

ROOT=""
BRANCH=""          # empty until resolved: an explicit --branch, or the clone's own default
REMOTE=""

need_value() { [ "$#" -ge 2 ] || { echo "missing value for $1" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
  case "$1" in
    --branch) need_value "$@"; BRANCH="$2"; shift 2 ;;
    --remote) need_value "$@"; REMOTE="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) [ -z "$ROOT" ] || { echo "unexpected extra argument: $1" >&2; exit 2; }
       ROOT="$1"; shift ;;
  esac
done

[ -n "$ROOT" ] || { echo "usage: bare-new.sh <root> [--branch <name>] [--remote <url>]" >&2; exit 2; }

# -L as well as -e: a symlink pointing at a path that does not exist yet passes -e,
# and the pointer files below would then be written through it, outside $ROOT.
for entry in .bare .git wt; do
  if [ -e "$ROOT/$entry" ] || [ -L "$ROOT/$entry" ]; then
    echo "refusing to run: $ROOT/$entry already exists" >&2
    exit 1
  fi
done

mkdir -p "$ROOT"
ROOT="$(cd "$ROOT" && pwd)"

if [ -n "$REMOTE" ]; then
  echo "==> cloning $REMOTE into .bare"
  git clone --bare "$REMOTE" "$ROOT/.bare"
  # `git clone --bare` leaves no fetch refspec, so remote-tracking refs never appear.
  git -C "$ROOT/.bare" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
  git -C "$ROOT/.bare" fetch --quiet origin || true
  # The clone's own default branch wins unless --branch was given explicitly.
  if [ -z "$BRANCH" ]; then
    BRANCH="$(git -C "$ROOT/.bare" symbolic-ref --quiet --short HEAD || true)"
    [ -n "$BRANCH" ] || BRANCH="main"
  fi
else
  [ -n "$BRANCH" ] || BRANCH="main"
  echo "==> creating empty bare repository"
  git init --quiet --bare --initial-branch "$BRANCH" "$ROOT/.bare"
fi

printf 'gitdir: ./.bare\n' > "$ROOT/.git"
mkdir -p "$ROOT/wt"
printf 'gitdir: ../.bare\n' > "$ROOT/wt/.git"

# A bare repo with no commits has an unborn HEAD, and `git worktree add` cannot
# check that out. Give it an empty root commit so wt/<branch> can exist.
#
# Only ever do that for a repository with NO branches. Fabricating a commit on a
# repo that already has history would create an unrelated-history branch and an
# empty-looking checkout of the user's own project.
if ! git -C "$ROOT/.bare" rev-parse --verify --quiet "refs/heads/$BRANCH" >/dev/null; then
  if [ -n "$(git -C "$ROOT/.bare" for-each-ref --count=1 refs/heads)" ]; then
    echo "error: branch '$BRANCH' does not exist in this repository." >&2
    echo "available branches:" >&2
    git -C "$ROOT/.bare" for-each-ref --format='  %(refname:short)' refs/heads >&2
    echo "re-run with --branch <one of the above>" >&2
    exit 1
  fi
  echo "==> no refs yet; creating an empty root commit on '$BRANCH'"
  EMPTY_TREE="$(git -C "$ROOT/.bare" hash-object -t tree --stdin </dev/null)"
  COMMIT="$(git -C "$ROOT/.bare" commit-tree "$EMPTY_TREE" -m 'chore: initial commit')"
  git -C "$ROOT/.bare" update-ref "refs/heads/$BRANCH" "$COMMIT"
  git -C "$ROOT/.bare" symbolic-ref HEAD "refs/heads/$BRANCH"
fi

echo "==> adding wt/$BRANCH"
git -C "$ROOT" worktree add "wt/$BRANCH" "$BRANCH"

echo
echo "==> result"
git -C "$ROOT" worktree list
echo
echo "Next:"
echo "  1. work in $ROOT/wt/$BRANCH"
echo "  2. register it in Orca (name, worktree path, visibility, setup hook):"
echo "     scripts/orca-register.sh --root '$ROOT' --name '<Project Name>' --setup '<command>'"
