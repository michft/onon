# AGENTS.md

Read repository-specific guidance in [docs/](docs/) before working. Start with
CONTEXT.md when present, then consult the relevant area and validation guidance.

## Workspace exception

Every file-editing task gets its own JJ workspace under `.worktrees/`. Follow
[WORKTREE.md](docs/WORKTREE.md) before creating checkouts, delegating edits,
stacking changes, or using shared resources. Use `jj` and JJ workspaces, not
`git worktree add`. Read-only work may share a checkout.
