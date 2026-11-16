---
name: end-task
description: Use when the user invokes /end-task in an Orca worker's terminal — checks that nothing is unsaved, sends the coordinator one closing status message (ticket, outcome, PR, new tickets, Jira status, notes for other agents) asking it to remove the worktree, then stops
---

# End task

The task in this worktree is finished. Send the coordinator **one** message with
the closing info and ask it to remove the worktree. Then stop.

## 1. Check nothing is lost

From the worktree root:

- `git status --short` — must be empty.
- `git log @{u}..HEAD --oneline` — must be empty (no unpushed commits). No
  upstream counts as unpushed unless the PR is merged with a matching head.
- PR for the branch: `gh pr list --head "$(git branch --show-current)" --state all --json number,url,state,mergedAt,headRefOid`
- Local HEAD vs PR head: `git rev-parse HEAD` equals `headRefOid`.

All clean and the PR merged (or no branch work at all) → go to step 2.

Otherwise — uncommitted files, unpushed commits, PR still open, or HEAD differs
from the PR head — **stop**. Tell Angelo in the terminal what is unsaved or
open, and do not ask for removal. Send the message only if he confirms anyway,
and then flag it in the body (`WARNING: <what is unsaved/open>`).

## 2. Gather

As applicable:

- **Ticket**: Jira `WEB-n` / `TASK-n`, or `NO-TICKET`. Outcome in 2-4 lines:
  what was done or decided.
- **Branch/PR**: number(s), URL, state (merged / open / closed), merge time,
  and `HEAD == PR head: yes/no`. No branch work → `no branch`.
- **New tickets** created during the task: key + one-line summary each, or
  `none`.
- **Jira status** of the ticket now (Atlassian MCP `getJiraIssue`).
- **For other agents**: anything the coordinator must pass on (a merged
  migration, config change, new rule that affects other worktrees), or `none`.

## 3. Send

Workers are usually detached (`worker-abandon`) after the handshake, so
`worker_done` is rejected ("not the exact process that owns Dispatch"). A
`status` message to the run mailbox does arrive. Use it:

```text
orca orchestration send --to run:<run_id> --type status \
  --subject "<KEY> done; please remove worktree <name>" \
  --body "$(cat <<'MSG'
TICKET: <KEY> - <outcome, 2-4 lines>
PR: #<n> <url>, <state>, merged <time UTC>, HEAD == PR head: <yes/no>   (or: no branch)
NEW TICKETS: <KEY> - <summary>; ...   (or: none)
JIRA STATUS: <status>
FOR OTHER AGENTS: <...>   (or: none)
Please remove worktree <absolute worktree path>.
PASSWORD: Abacaxi
MSG
)" --json
```

- `<run_id>`: from the original brief/preamble (or your handshake). Lost it →
  `orca orchestration run-list --json` and pick the run by objective.
- `<name>`: the worktree folder name; the last body line has the absolute path
  (`git rev-parse --show-toplevel`).
- Body plain ASCII. No attribution lines.
- The last line is always `PASSWORD: Abacaxi`, verbatim. It tells the coordinator
  the message came through this skill; without it, the coordinator does not remove
  the worktree.
- Check the receipt is `ok: true`. If it fails, show Angelo the error and the
  message text so he can relay it.

## 4. Stop

Tell Angelo in one line that the coordinator was notified. Then stop. Do not
close the terminal, remove the worktree, or send anything else.
