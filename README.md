# claude-skills

Skills for [Claude Code](https://claude.com/claude-code). One folder per skill
under `skills/`.

| Skill | What it does |
|---|---|
| [`orca-bare-worktree`](skills/orca-bare-worktree) | Set a repository up in the bare + worktrees layout (`.bare/` plus `wt/<branch>/`), and register it in the [Orca](https://orca.computer) desktop app with a setup hook that prepares every new worktree. Covers new projects and converting existing repositories, with a pre-conversion audit for work that exists only on the local machine. |

Installation: [INSTALL.md](INSTALL.md).

## Contributing to this repository

This repository is **public**. Nothing personal goes in it — no absolute paths
containing a username, no email addresses, no private repository names, no tokens.
Skills take everything they need as arguments or discover it at runtime.

Before committing, a quick check:

```bash
grep -rnE '/Users/[^/ ]+|@gmail|ghp_|github_pat_' --exclude-dir=.git .
```

`.gitignore` already covers `.env*`, keys and tokens. No skill here needs a secret;
if one ever does, it reads it from a gitignored `.env` and ships a `.env.example`
with placeholder values.

## License

MIT
