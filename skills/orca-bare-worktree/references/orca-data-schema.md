# The parts of `orca-data.json` this skill touches

Observed against Orca **1.4.199**, `schemaVersion: 1`. `orca-register.py` aborts if
`schemaVersion` differs — if that happens, check the shapes below against the live
file and update the script.

Location:

```
macOS   ~/Library/Application Support/Orca/profiles/<profile>/orca-data.json
Linux   ~/.config/Orca/profiles/<profile>/orca-data.json
```

The default profile is `local-default`.

The app rewrites this file while running. Every edit must happen with Orca quit,
and behind a backup.

## Top-level keys used

| Key | Type | Role |
|---|---|---|
| `schemaVersion` | int | version guard |
| `repos` | list | one entry per repository on one host |
| `projects` | list | a repository identity, shared across hosts |
| `projectHostSetups` | list | the per-host binding, holding a second copy of `hookSettings` |
| `settings.worktreeVisibilityDefaults.external` | string | global default, ships as `"hide"` |

Other keys (`worktreeMeta`, `worktreeIdentityAliases`, `ui`, `workspaceSession`, …)
are written by the app as worktrees are used. Nothing here needs to create them:
Orca fills them in on its own.

## `repos[]`

```jsonc
{
  "id": "<uuid4>",
  "path": "<root>/wt",                       // the folder Orca treats as the repo
  "displayName": "<name>",
  "badgeColor": "#737373",
  "executionHostId": "local",
  "repoIcon": { "type": "emoji", "emoji": "📁" },
  "gitRemoteIdentity": {
    "canonicalKey": "<host>/<owner>/<repo>",
    "remoteName": "origin",
    "remoteUrl": "<url>"
  },
  "upstream": null,
  "addedAt": 0,                              // epoch ms
  "kind": "git",
  "externalWorktreeVisibility": "show",      // else worktrees Orca did not create stay hidden
  "externalWorktreeVisibilityLegacy": false,
  "projectHostSetupMethod": "imported-existing-folder",
  "gitUsername": "<forge account>",          // the forge account, not the commit author name
  "worktreeBasePath": "<root>",              // where new worktrees are created
  "hookSettings": { /* see below */ },
  "agentWorktreeVisibility": "show"
}
```

## `hookSettings`

Present in both `repos[]` and `projectHostSetups[]`, and kept identical in the two.

```jsonc
{
  "mode": "auto",
  "setupRunPolicy": "run-by-default",
  "setupAgentStartupPolicy": "start-immediately",
  "scripts": {
    "setup": "cp ../main/.env .env && CI=true pnpm install",
    "archive": ""
  }
}
```

`scripts.setup` runs with the newly created worktree as its working directory. Since
worktrees are siblings under `<root>/wt`, `../main` is the main worktree.

## `projects[]`

```jsonc
{
  "id": "github:<owner>/<repo>",             // or "local:<name>" with no recognised forge
  "displayName": "<name>",
  "badgeColor": "#737373",
  "repoIcon": { "type": "emoji", "emoji": "📁" },
  "kind": "git",
  "providerIdentity": { "provider": "github", "owner": "<owner>", "repo": "<repo>" },
  "gitRemoteIdentity": { /* same as repos[] */ },
  "sourceRepoIds": ["<repo uuid>"],
  "createdAt": 0,
  "updatedAt": 0
}
```

## `projectHostSetups[]`

Its `id` and `repoId` both equal the `repos[]` entry's `id`.

```jsonc
{
  "id": "<repo uuid>",
  "projectId": "github:<owner>/<repo>",
  "hostId": "local",
  "repoId": "<repo uuid>",
  "path": "<root>/wt",
  "displayName": "<name>",
  "kind": "git",
  "executionHostId": "local",
  "worktreeBasePath": "<root>",
  "hookSettings": { /* identical to the repos[] copy */ },
  "gitUsername": "<forge account>",
  "setupState": "ready",
  "setupMethod": "imported-existing-folder",
  "createdAt": 0,
  "updatedAt": 0
}
```

## Why not the CLI

`orca repo list --json` returns these entries but only reads them. `orca
agent-context --json` lists the full command surface and contains no
`orca settings` / `orca config` equivalent. The CLI also needs the app running —
with the app closed it fails with `runtime_unavailable`. So reads need Orca up,
and writes need it down.

## Worktree placement

`orca worktree create` has no `--path`, and `orca repo add` only takes the
repository root. Worktrees would otherwise land under
`~/orca/workspaces/<displayName>/<name>`, outside the project.

Registering the repository at `<root>/wt` with `worktreeBasePath: <root>` is what
keeps them inside the project, and `externalWorktreeVisibility: "show"` is what
makes Orca display worktrees it did not create — including `wt/main`, made by hand.
