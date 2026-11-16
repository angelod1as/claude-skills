---
name: comment
description: Use when the user invokes /comment to process the Claude bot's comments on a pull request — runs at least 3 autonomous rounds of read comments, apply the valid ones, delete the processed Claude comments, commit and push, wait for the bot's next review; then gives one final summary
---

# Comment

Process the Claude bot's review comments on a pull request in a loop: read them, apply
what is valid, reject what is not, remove the Claude comments that were processed, commit
and push, wait for the bot to review the new push, and go again. No permission is asked
between rounds; one summary comes at the end.

Human comments are **read and evaluated** but are **never deleted**.

## Determining the PR

- If the user passes a PR number as argument (e.g. `/comment 123`), use it directly. A
  second number sets the round count: `/comment 123 5` runs 5 rounds. Default: 3.
- Otherwise: `gh pr view --json number --jq .number` from the current directory. This works
  in regular branches and worktrees, since git context is per-directory.
- Owner/repo: `gh repo view --json nameWithOwner --jq .nameWithOwner`

## Round number

One invocation runs rounds 1..n (n = 3 unless the user set it). Rounds keep counting
across invocations on the same PR in the current conversation: if an earlier `/comment`
on this PR ended at Round 3, this one starts at Round 4. A different PR starts its own
count at Round 1.

Write the round in three places:

- Start of each round: `**Round N** — PR #<number>`
- End of each round: one progress line, e.g.
  `Round N: applied 2 (abc1234), rejected 1, deleted 3 — waiting for review`
- The final summary heading: `**/comment summary — PR #<number>, rounds X–Y**`

If the conversation was compacted and the earlier rounds are no longer visible, do not
restart at 1. Give your best count and say it is estimated, e.g.
`**Round 4 (estimated — earlier rounds were summarized)**`.

## Comments to read

"Comment" is not only the inline code-view comment. Fetch all three kinds:

- **Issue comments** — the PR conversation body:
  `gh api repos/{owner}/{repo}/issues/{pr}/comments --paginate`
- **Review comments** — inline, on a diff line:
  `gh api repos/{owner}/{repo}/pulls/{pr}/comments --paginate`
- **Reviews** — the top-level review body:
  `gh api repos/{owner}/{repo}/pulls/{pr}/reviews --paginate`

Merge all three into one list and sort by `created_at` (reviews use `submitted_at`).

- **First round of the invocation** → take the **last 3** overall.
- **Later rounds** → take every comment created after the previous round's push time (all
  three kinds, any author).

## Steps

1. Resolve the PR number, the round count n and the starting round (see Round number).
2. Run each round:
   1. Fetch the three comment kinds and select per Comments to read.
   2. For each comment, evaluate whether the suggestion is valid and beneficial.
      - **Valid** → apply the change. Do not ask.
      - **Invalid** → note why (wrong assumption, would break something, already
        handled, out of scope for this PR, etc.).
      - **Unclear** (genuinely ambiguous intent) → skip it: do not apply, do not delete,
        leave it on the PR, and list it in the final summary. Do not stop the loop to ask.
   3. Delete each processed comment **authored by Claude**, applied or rejected — not the
      skipped unclear ones:
      - Issue comment: `gh api -X DELETE repos/{owner}/{repo}/issues/comments/{id}`
      - Review comment: `gh api -X DELETE repos/{owner}/{repo}/pulls/comments/{id}`
      - Review: `gh api -X DELETE repos/{owner}/{repo}/pulls/{pr}/reviews/{id}`
   4. If anything was applied: run the repo's lint and the tests related to the change, as
      the repo's CLAUDE.md prescribes, fix what breaks, then commit with a Conventional
      Commits message and push. Never bypass hooks (`--no-verify` is forbidden). Record the
      SHA and the push time (`date -u +%Y-%m-%dT%H:%M:%SZ`).
   5. Print the one-line progress note (see Round number).
   6. If rounds remain, wait for the next review (see Waiting for the review), then start
      the next round.
3. Give the final summary (see Final summary).

## Waiting for the review

The review is a workflow run on `pull_request` `synchronize`, so every push triggers it.
In the reference repo it is `.github/workflows/claude-code-review.yml`: types `[opened,
synchronize]`, `concurrency: cancel-in-progress` per PR, `timeout-minutes: 20`, median
run ~3.5 min, slowest ~15 min. It posts its review with `gh pr comment`, so it lands as an
**issue comment**. Look in the PR's repo for the equivalent workflow first; adapt if it
differs.

1. Find the run for the pushed SHA (it can take ~30 s to appear):
   `gh run list --commit <sha> --workflow <review-workflow> --json databaseId,status`
2. Block on it: `gh run watch <id> --exit-status` (run it with a long tool timeout, or in
   the background and get notified when it exits).
3. Then fetch the three comment kinds and keep Claude-authored ones created after the push
   time. The run can end green without posting; poll a few more times before concluding
   there is no review.
4. Overall timeout: **20 minutes** from the push. On timeout, end the loop and report it.

Do not write foreground `sleep` loops if the harness blocks them. Prefer the blocking
`gh run watch`; for any polling use the harness's background or monitor tooling.

## Early exit

Stop before n rounds, and say why in the summary, when:

- A round finds no new Claude comment, or the new review has nothing actionable (it
  approves, says "no findings", or everything in it is rejected).
- Nothing was applied in a round, so there is no push to review.
- Lint, tests or CI break in a way you cannot fix.
- The review wait times out.

## Final summary

Once, after the last round, headed `**/comment summary — PR #<number>, rounds X–Y**`. Per
round: what was applied (with commit SHAs), what was rejected and why, what was deleted.
Then: unclear comments left on the PR, everything else still on the PR, and why the loop
ended (n rounds done or which early exit).

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
- Apply valid fixes and delete processed Claude comments without asking.
- Only delete a Claude comment you actually processed in this round. Older Claude comments
  outside the round's selection stay put.
- No Claude/AI attribution in commits: no `Co-Authored-By`, no session links.
- Human comments are never deleted, even after their suggestion is applied. The author
  closes them.
