# claude-skills

Skills for [Claude Code](https://claude.com/claude-code). One folder per skill
under `skills/`.

| Skill | What it does |
|---|---|
| [`orca-bare-worktree`](skills/orca-bare-worktree) | Set a repository up in the bare + worktrees layout (`.bare/` plus `wt/<branch>/`), and register it in the [Orca](https://orca.computer) desktop app with a setup hook that prepares every new worktree. Covers new projects and converting existing repositories, with a pre-conversion audit for work that exists only on the local machine. |

## Install

Claude Code picks up anything in `~/.claude/skills/`. Clone once, then symlink —
so `git pull` updates the skill in place.

```bash
git clone https://github.com/angelod1as/claude-skills.git ~/src/claude-skills
mkdir -p ~/.claude/skills
ln -s ~/src/claude-skills/skills/orca-bare-worktree ~/.claude/skills/orca-bare-worktree
```

All of them at once:

```bash
for s in ~/src/claude-skills/skills/*/; do
  ln -sfn "$s" ~/.claude/skills/"$(basename "$s")"
done
```

Restart the session and run `/skills` to confirm. Project-scoped installs, updating
and uninstalling: [INSTALL.md](INSTALL.md).

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
