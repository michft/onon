# Local agent pitfalls

## Merging into an already merged PR branch

PR #1 merged `protomaps-trial` into `main` before PR #2 merged the native map
into `protomaps-trial`. GitHub marked both PRs merged, but the native map was
still absent from `main`. A merged PR label alone is not integration evidence.

Merge dependent PRs bottom-up and retarget each successor to `main` after its
predecessor merges. Fetch and inspect the actual `main@origin` tree before
declaring the stack integrated. Publish missing changes against current `main`
rather than merging again into the old feature branch.

## Case-only Markdown renames on macOS

When integrating the uppercase ADR filename with JJ on this Mac, `jj new`
reported a skipped working-copy update and left the renamed file missing.
The isolated workspace still contained the correct uppercase file.

After a case-only rename, check `jj status`, the on-disk filename case, and
inbound links in the destination checkout. If JJ skipped the rename, confirm
there are no unrelated edits to that file, then restore only the exact affected
path from the validated revision. Do not use a repository-wide restore.
