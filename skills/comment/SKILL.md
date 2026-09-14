---
name: comment
description: Use when the user invokes /comment to process the Claude bot's comments on a pull request — reads the last 3 comments of every kind, applies the valid ones, explains the invalid ones, then deletes the processed Claude comments from the PR
disable-model-invocation: true
---

# Comment

Process the Claude bot's review comments on a pull request: read them, apply what is
valid, explain what is not, then remove the Claude comments that were processed.

Human comments are **read and evaluated** but are **never deleted**.

## Determining the PR

- If the user passes a PR number as argument (e.g. `/comment 123`), use it directly.
- Otherwise: `gh pr view --json number --jq .number` from the current directory. This works
  in regular branches and worktrees, since git context is per-directory.
- Owner/repo: `gh repo view --json nameWithOwner --jq .nameWithOwner`

## Comments to read

"Comment" is not only the inline code-view comment. Fetch all three kinds:

- **Issue comments** — the PR conversation body:
  `gh api repos/{owner}/{repo}/issues/{pr}/comments --paginate`
- **Review comments** — inline, on a diff line:
  `gh api repos/{owner}/{repo}/pulls/{pr}/comments --paginate`
- **Reviews** — the top-level review body:
  `gh api repos/{owner}/{repo}/pulls/{pr}/reviews --paginate`

Merge all three into one list, sort by `created_at`, and take the **last 3** overall.

## Steps

1. Resolve the PR number.
2. Fetch the three comment kinds above and take the last 3 by creation time.
3. For each comment, evaluate whether the suggestion is valid and beneficial.
   - **Valid** → apply the change.
   - **Invalid** → state clearly why (wrong assumption, would break something, already
     handled, out of scope for this PR, etc.).
   - **Unclear** → ask the user. Do not guess, and do not apply a change whose intent or
     relevance you are not sure of.
4. Delete each processed comment **authored by Claude**, whether it was applied or rejected:
   - Issue comment: `gh api -X DELETE repos/{owner}/{repo}/issues/comments/{id}`
   - Review comment: `gh api -X DELETE repos/{owner}/{repo}/pulls/comments/{id}`
   - Review: `gh api -X DELETE repos/{owner}/{repo}/pulls/{pr}/reviews/{id}`
5. Report a summary: what was applied, what was rejected and why, what was deleted, and
   what was left on the PR.

## Whose comments get deleted

Check the `user.login` field. Delete only:

- `claude-code[bot]`, or any login containing `claude`
- `github-actions[bot]` **only if** the comment body mentions `Claude`/`claude`

Never delete anything else — not human users, not other bots, not other workflows.
Be conservative: when unsure who authored a comment, leave it.

A rejected Claude comment is still deleted; the reason for the rejection lives in the
summary you give the user, not on the PR.

## Rules

- **Never post a comment of our own.** Do not reply on the PR, do not leave a note
  explaining what was applied or rejected, do not open a new thread. The best outcome of
  this process is: the change is made and the originating Claude comment is gone. The
  summary goes to the user in the terminal, never onto the PR.
- Do **not** switch to plan mode — you may be running alongside sub-agents.
- Ask permission before applying a fix, and before deleting.
- Only delete a Claude comment you actually processed in this round. Older Claude comments
  outside the last 3 stay put.
- Human comments are never deleted, even after their suggestion is applied. The author
  closes them.
