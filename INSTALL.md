# Installing

Claude Code discovers skills in `~/.claude/skills/`. Anything in there — a real
directory or a symlink — is picked up at session start.

Clone this repository once, then symlink the skills you want. Symlinks mean
`git pull` updates them in place, with no copying.

## Clone

```bash
git clone https://github.com/<owner>/claude-skills.git ~/src/claude-skills
```

Any location works; `~/src/claude-skills` is used below.

## Link a skill

```bash
mkdir -p ~/.claude/skills
ln -s ~/src/claude-skills/skills/orca-bare-worktree ~/.claude/skills/orca-bare-worktree
```

All of them at once:

```bash
mkdir -p ~/.claude/skills
for s in ~/src/claude-skills/skills/*/; do
  ln -sfn "$s" ~/.claude/skills/"$(basename "$s")"
done
```

Make the scripts executable if your clone lost the bit:

```bash
chmod +x ~/src/claude-skills/skills/*/scripts/*
```

## Project-scoped instead

To install for one project only, link into that project's `.claude/skills/`:

```bash
mkdir -p <project>/.claude/skills
ln -s ~/src/claude-skills/skills/orca-bare-worktree <project>/.claude/skills/orca-bare-worktree
```

## Verify

Start a new Claude Code session and run `/skills`. The skill should be listed. If
it is not:

- confirm `~/.claude/skills/<name>/SKILL.md` resolves (`ls -L`)
- confirm the frontmatter has both `name:` and `description:`
- restart the session — skills are read at startup

## Update

```bash
git -C ~/src/claude-skills pull
```

Symlinked skills need nothing further. Restart the session to pick up changes.

## Uninstall

```bash
rm ~/.claude/skills/orca-bare-worktree
```

That removes the symlink only. Delete the clone separately if you want it gone.

## Running the scripts without the skill

The scripts under `skills/orca-bare-worktree/scripts/` are plain bash and Python 3
with no dependencies, and run standalone:

```bash
~/src/claude-skills/skills/orca-bare-worktree/scripts/bare-new.sh --help
~/src/claude-skills/skills/orca-bare-worktree/scripts/bare-convert.sh --help
~/src/claude-skills/skills/orca-bare-worktree/scripts/orca-register.py --help
```
