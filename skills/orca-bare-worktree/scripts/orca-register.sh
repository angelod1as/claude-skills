#!/usr/bin/env bash
# Register <root>/wt in Orca and configure it for the bare + worktrees layout,
# through Orca's own runtime (the app must be running — no need to quit it).
#
#   orca-register.sh --root <root> --name "<Display Name>" --setup '<command>' [--dry-run]
#
# `orca repo add` registers the folder but leaves displayName as the folder name
# ("wt") and sets no worktreeBasePath, hooks or agent visibility. The CLI has no
# command for those, so this calls the runtime's `repo.update` RPC with the CLI's
# own client. Orca persists the change to `repos` and `projectHostSetups` itself.
# Idempotent: running it again updates the same repo.
set -euo pipefail

root="" name="" setup="" dry_run=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root="$2"; shift 2 ;;
    --name) name="$2"; shift 2 ;;
    --setup) setup="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
if [ -z "$root" ] || [ -z "$name" ] || [ -z "$setup" ]; then
  echo "usage: $0 --root <root> --name <display name> --setup '<command>' [--dry-run]" >&2
  exit 2
fi

root="$(cd "$root" && pwd -P)"
wt="$root/wt"
if [ ! -f "$wt/.git" ] || [ ! -d "$root/.bare" ]; then
  echo "error: $root is not a bare + worktrees layout (need .bare/ and wt/.git file)" >&2
  exit 1
fi

orca_bin="$(command -v orca)" || { echo "error: orca CLI not on PATH" >&2; exit 1; }
orca_bin="$(readlink -f "$orca_bin")"
contents="${orca_bin%/Resources/bin/orca}"
electron="$contents/MacOS/Orca"
cli_dir="$contents/Resources/app.asar.unpacked/out/cli"
if [ ! -x "$electron" ] || [ ! -f "$cli_dir/runtime-client.js" ]; then
  echo "error: could not locate Orca.app internals from $orca_bin" >&2
  exit 1
fi

updates="$(ROOT="$root" NAME="$name" SETUP="$setup" python3 -c '
import json, os
print(json.dumps({
    "displayName": os.environ["NAME"],
    "worktreeBasePath": os.environ["ROOT"],
    "externalWorktreeVisibility": "show",
    "agentWorktreeVisibility": "show",
    "hookSettings": {
        "mode": "auto",
        "setupRunPolicy": "run-by-default",
        "setupAgentStartupPolicy": "start-immediately",
        "scripts": {"setup": os.environ["SETUP"], "archive": ""},
    },
}, indent=1))')"

if [ "$dry_run" -eq 1 ]; then
  echo "would register: $wt"
  echo "would apply repo.update:"
  echo "$updates"
  exit 0
fi

if ! orca status 2>/dev/null | grep -q '^runtimeReachable: true'; then
  echo "==> starting Orca"
  orca open >/dev/null
fi

json_field() { python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["result"]["repo"]["id"] if d.get("ok") else "")'; }

repo_id="$(orca repo show --repo "path:$wt" --json 2>/dev/null | json_field || true)"
if [ -z "$repo_id" ]; then
  echo "==> adding $wt"
  repo_id="$(orca repo add --path "$wt" --json | json_field)"
fi
[ -n "$repo_id" ] || { echo "error: could not register $wt" >&2; exit 1; }

echo "==> updating repo $repo_id"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/update.mjs" <<'EOF'
const { RuntimeClient } = await import(process.env.ORCA_CLI_DIR + '/runtime-client.js');
const client = new RuntimeClient(undefined, undefined, null, null);
const res = await client.call('repo.update', {
  repo: process.env.REPO_SELECTOR,
  updates: JSON.parse(process.env.REPO_UPDATES),
});
if (!res.ok) { console.error(JSON.stringify(res, null, 1)); process.exit(1); }
EOF
ORCA_CLI_DIR="$cli_dir" REPO_SELECTOR="id:$repo_id" REPO_UPDATES="$updates" \
  ELECTRON_RUN_AS_NODE=1 "$electron" "$tmp/update.mjs"

echo "==> result"
orca repo show --repo "id:$repo_id" --json | python3 -c '
import json, sys
r = json.load(sys.stdin)["result"]["repo"]
for k in ("displayName", "path", "worktreeBasePath",
          "externalWorktreeVisibility", "agentWorktreeVisibility"):
    print(f"{k:28} {r.get(k)}")
setup = r.get("hookSettings", {}).get("scripts", {}).get("setup")
print("setup".ljust(28), setup)'
