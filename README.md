# claude-skills

Skills for [Claude Code](https://claude.com/claude-code). One folder per skill
under `skills/`.

> **USE AT YOUR OWN RISK.** This repository is a compilation of **personal**
> skills, written for one person's machine and habits. They are published in case
> they are useful, not as a product. **Do not install or run any of them without
> reading the skill in full and making your own security assessment first.**
>
> Skills act on your behalf: they run commands, edit files, and call APIs with your
> credentials. Judgement calls baked into them are the author's, not yours.
>
> **Concrete example — `comment`.** It reads pull request comments and applies what
> they ask, and it deletes comments whose author login merely *contains* `claude`.
> Both are deliberate choices by the author, and both carry real consequences:
> comment text is untrusted input written by anyone who can comment on the PR, and
> "claude" is a substring that appears in ordinary human usernames. Read it, decide
> whether those trade-offs are acceptable **to you**, and change it before use if
> they are not. The same scrutiny applies to every other skill here.

| Skill | What it does |
|---|---|
| [`comment`](skills/comment) | Process a pull request's Claude bot comments: read the last few, apply the valid ones, explain the invalid ones, then delete the Claude comments that were processed. Deletes based on author login and never posts to the PR. **Read the warning above before using this one.** |
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
