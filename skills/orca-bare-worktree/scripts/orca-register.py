#!/usr/bin/env python3
"""Register a bare+worktrees repository in Orca, and set its worktree setup hook.

Orca has no CLI for writing repository settings: `orca repo list --json` reads
them, and there is no `orca settings` / `orca config` command. So this script
edits Orca's own state file.

That file is rewritten by the app while it runs, so this script refuses to touch
it unless Orca is closed, and always writes a timestamped backup first.

What it writes, per repository:

    path                        <root>/wt      (the folder Orca treats as the repo)
    worktreeBasePath            <root>
    externalWorktreeVisibility  "show"         (global default is "hide")
    agentWorktreeVisibility     "show"
    hookSettings.scripts.setup  the command run inside each new worktree

The setup command runs with the new worktree as its working directory, so
`../main` refers to the main worktree. Typical shape:

    cp ../main/.env .env && CI=true <pkg-manager> install

Usage:
    orca-register.py --root <path> [--setup '<command>'] [--name <display name>]
                     [--profile local-default] [--data <orca-data.json>]
                     [--dry-run] [--allow-running]
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
import uuid

TESTED_SCHEMA_VERSION = 1
DEFAULT_PROFILE = "local-default"
BACKUPS_KEPT = 5


def fail(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def data_path(profile, override):
    if override:
        return os.path.abspath(os.path.expanduser(override))
    if sys.platform == "darwin":
        base = os.path.expanduser("~/Library/Application Support/Orca/profiles")
    elif sys.platform.startswith("linux"):
        base = os.path.expanduser("~/.config/Orca/profiles")
    else:
        fail("unsupported platform; pass --data with the path to orca-data.json")
    return os.path.join(base, profile, "orca-data.json")


def orca_is_running():
    """True if the Orca desktop app looks alive, and True whenever that cannot be
    determined. This check is the only thing protecting the state file, so it fails
    CLOSED: an unknown answer must not read as "safe to write". --allow-running is
    the deliberate escape hatch.

    The process pattern is macOS-specific. On any other platform, and if pgrep is
    missing or errors, the answer is "assume running"."""
    if sys.platform != "darwin":
        return True
    try:
        out = subprocess.run(
            ["pgrep", "-f", r"Orca\.app/Contents/MacOS/Orca"],
            capture_output=True, text=True,
        )
    except (FileNotFoundError, OSError):
        return True
    if out.returncode == 0:
        return out.stdout.strip() != ""
    if out.returncode == 1:      # documented pgrep exit code for "no match"
        return False
    return True                  # any other exit code: pgrep itself failed


def git(root, *args):
    r = subprocess.run(["git", "-C", root, *args], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""


def strip_credentials(url):
    """Remove any user:password@ / token@ component. Orca stores this URL in
    plaintext, and every backup then keeps a copy of it forever."""
    return re.sub(r"(//)[^/@]+@", r"\1", url or "")


def parse_remote(url):
    """-> (canonical_key, provider, owner, repo) or (None, None, None, None)."""
    if not url:
        return (None, None, None, None)
    m = re.match(r"^(?:https?://|ssh://)?(?:[^@/]+@)?([^:/]+)[:/](.+?)(?:\.git)?/?$", url)
    if not m:
        return (None, None, None, None)
    host, path = m.group(1), m.group(2)
    parts = path.split("/")
    if len(parts) < 2:
        return (f"{host}/{path}", None, None, None)
    owner, repo = parts[-2], parts[-1]
    provider = {"github.com": "github", "gitlab.com": "gitlab"}.get(host)
    return (f"{host}/{owner}/{repo}", provider, owner, repo)


def hook_settings(setup):
    return {
        "mode": "auto",
        "setupRunPolicy": "run-by-default",
        "setupAgentStartupPolicy": "start-immediately",
        "scripts": {"setup": setup, "archive": ""},
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", required=True, help="repository root (the folder holding .bare and wt)")
    ap.add_argument("--setup", default="", help="command to run in each new worktree")
    ap.add_argument("--name", default=None, help="display name in Orca (default: folder name)")
    ap.add_argument("--profile", default=DEFAULT_PROFILE)
    ap.add_argument("--data", default=None, help="explicit path to orca-data.json")
    ap.add_argument("--dry-run", action="store_true", help="print the change, write nothing")
    ap.add_argument("--allow-running", action="store_true",
                    help="proceed even though Orca appears to be running (it will overwrite you)")
    args = ap.parse_args()

    root = os.path.abspath(os.path.expanduser(args.root))
    wt = os.path.join(root, "wt")

    if not os.path.isdir(os.path.join(root, ".bare")):
        fail(f"{root} has no .bare directory — run bare-new.sh or bare-convert.sh first")
    if not os.path.isdir(wt):
        fail(f"{root} has no wt directory")

    path = data_path(args.profile, args.data)
    if not os.path.isfile(path):
        fail(f"no Orca state file at {path}")

    if orca_is_running() and not args.allow_running:
        fail("Orca appears to be running, or it could not be determined that it is "
             "not (this check only works on macOS). Orca rewrites this file while "
             "open, so the edit would be lost or corrupted. Quit Orca and re-run, "
             "or pass --allow-running once you are certain it is closed.")

    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)

    if data.get("schemaVersion") != TESTED_SCHEMA_VERSION:
        fail(f"orca-data.json schemaVersion is {data.get('schemaVersion')}, this script was "
             f"written against {TESTED_SCHEMA_VERSION}. The layout may have changed; configure "
             f"the repository through the Orca UI instead (see SKILL.md).")

    for key in ("repos", "projects", "projectHostSetups"):
        data.setdefault(key, [])

    display = args.name or os.path.basename(root)
    remote_url = strip_credentials(git(root, "remote", "get-url", "origin"))
    canonical, provider, owner, repo_name = parse_remote(remote_url)
    # Orca stores the forge account name here, not the commit author name.
    username = owner or git(root, "config", "user.name")

    remote_identity = None
    if canonical:
        remote_identity = {"canonicalKey": canonical, "remoteName": "origin",
                           "remoteUrl": remote_url}
    project_id = (f"{provider}:{owner}/{repo_name}" if provider and owner
                  else f"local:{display}")

    # Compare resolved paths: abspath normalizes ".." and trailing slashes but not
    # symlinks, so the same folder reached two ways would otherwise register twice.
    def same_path(a, b):
        return a and os.path.realpath(a) == os.path.realpath(b)

    existing = next((r for r in data["repos"] if same_path(r.get("path"), wt)), None)
    now = int(time.time() * 1000)

    if existing:
        action = "update"
        repo_id = existing["id"]
        existing.update({
            "path": wt,
            "displayName": display,
            "gitRemoteIdentity": remote_identity,
            "gitUsername": username,
            "worktreeBasePath": root,
            "externalWorktreeVisibility": "show",
            "agentWorktreeVisibility": "show",
            "hookSettings": hook_settings(args.setup),
        })
    else:
        action = "create"
        repo_id = str(uuid.uuid4())
        data["repos"].append({
            "id": repo_id,
            "path": wt,
            "displayName": display,
            "badgeColor": "#737373",
            "executionHostId": "local",
            "repoIcon": {"type": "emoji", "emoji": "📁"},
            "gitRemoteIdentity": remote_identity,
            "upstream": None,
            "addedAt": now,
            "kind": "git",
            "externalWorktreeVisibility": "show",
            "externalWorktreeVisibilityLegacy": False,
            "projectHostSetupMethod": "imported-existing-folder",
            "gitUsername": username,
            "worktreeBasePath": root,
            "hookSettings": hook_settings(args.setup),
            "agentWorktreeVisibility": "show",
        })

    # Both branches converge here. A repos[] entry can exist without its project or
    # projectHostSetup — that is the state left by configuring through the Orca UI
    # and then running this script — so create whatever is missing rather than
    # assuming the update path has nothing to add.
    project = next((p for p in data["projects"] if p.get("id") == project_id), None)
    if project is None:
        project = {
            "id": project_id,
            "displayName": display,
            "badgeColor": "#737373",
            "repoIcon": {"type": "emoji", "emoji": "📁"},
            "kind": "git",
            "gitRemoteIdentity": remote_identity,
            "sourceRepoIds": [repo_id],
            "createdAt": now,
            "updatedAt": now,
        }
        if provider and owner:
            project["providerIdentity"] = {"provider": provider, "owner": owner,
                                           "repo": repo_name}
        data["projects"].append(project)
    elif repo_id not in project.get("sourceRepoIds", []):
        project.setdefault("sourceRepoIds", []).append(repo_id)
        project["updatedAt"] = now

    # repos[] and projectHostSetups[] each carry their own copy of hookSettings.
    # Orca keeps the two identical; so must this, or they disagree.
    setup = next((h for h in data["projectHostSetups"]
                  if h.get("repoId") == repo_id or h.get("id") == repo_id), None)
    if setup is None:
        setup = {
            "id": repo_id,
            "repoId": repo_id,
            "hostId": "local",
            "kind": "git",
            "executionHostId": "local",
            "setupState": "ready",
            "setupMethod": "imported-existing-folder",
            "createdAt": now,
        }
        data["projectHostSetups"].append(setup)
    setup.update({
        "projectId": project_id,
        "path": wt,
        "displayName": display,
        "worktreeBasePath": root,
        "hookSettings": hook_settings(args.setup),
        "gitUsername": username,
        "updatedAt": now,
    })

    print(f"{action}: {display}")
    print(f"  repo id                    {repo_id}")
    print(f"  path                       {wt}")
    print(f"  worktreeBasePath           {root}")
    print(f"  externalWorktreeVisibility show")
    print(f"  setup script               {args.setup or '(empty)'}")

    if args.dry_run:
        print("\n--dry-run: nothing written")
        return

    backup = f"{path}.bak-orca-register-{time.strftime('%Y%m%d-%H%M%S')}"
    shutil.copy2(path, backup)

    # Unique tmp name so two runs cannot write the same scratch file, and fsync
    # before the rename so a power loss cannot leave a truncated file at `path`.
    tmp = f"{path}.tmp-orca-register-{os.getpid()}"
    try:
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=2, ensure_ascii=False)
            fh.write("\n")
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise

    # These backups hold the user's whole workspace state; keep the recent few.
    prefix = os.path.basename(path) + ".bak-orca-register-"
    folder = os.path.dirname(path)
    old_backups = sorted(f for f in os.listdir(folder) if f.startswith(prefix))
    for stale in old_backups[:-BACKUPS_KEPT]:
        os.unlink(os.path.join(folder, stale))

    print(f"\nwritten. backup: {backup}")
    print("Start Orca and confirm the repository and its setup hook appear.")


if __name__ == "__main__":
    main()
