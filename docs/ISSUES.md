# Local agent pitfalls

## Merging into an already merged PR branch

PR #1 merged `protomaps-trial` into `main` before PR #2 merged the native map
into `protomaps-trial`. GitHub marked both PRs merged, but the native map was
still absent from `main`. A merged PR label alone is not integration evidence.

Merge dependent PRs bottom-up and retarget each successor to `main` after its
predecessor merges. Fetch and inspect the actual `main@origin` tree before
declaring the stack integrated. Publish missing changes against current `main`
rather than merging again into the old feature branch.

PR #4 repeated this pattern on 23 October 2026: it merged into
`recorder-map-checks` after #3 had merged into `main`. The docs follow-up
therefore carries the approved documentation into actual `main` history.

PR #6 likewise merged into the already-merged `plan-offline-followup` branch.
The Melbourne follow-up includes its reviewed HTTP renderer when targeting main.

## Case-only Markdown renames on macOS

When integrating the uppercase ADR filename with JJ on this Mac, `jj new`
reported a skipped working-copy update and left the renamed file missing.
The isolated workspace still contained the correct uppercase file.

After a case-only rename, check `jj status`, the on-disk filename case, and
inbound links in the destination checkout. If JJ skipped the rename, confirm
there are no unrelated edits to that file, then restore only the exact affected
path from the validated revision. Do not use a repository-wide restore.

## Environment and iOS pitfalls

- `ls` is aliased to `eza` on this Mac, so `ls -t` and similar flags fail or
  print nothing. Use `/bin/ls` in scripts and command substitutions.
- The iOS project uses Xcode file-system synchronized groups. New files under
  `apps/ios/Onon` and `apps/ios/OnonTests` are picked up without editing the
  project file.
- `xcrun devicectl` install or launch fails with `Locked` or CoreDevice error
  4016 when the iPhone is locked or asleep. Ask the user to unlock it; do not
  retry in a loop.
- A fresh checkout without the ignored iOS map shows "Offline map
  unavailable". Follow the existing workspace map setup; the map is not copied
  automatically into a new checkout.
