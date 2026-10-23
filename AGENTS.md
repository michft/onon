# AGENTS.md

This file lists the mistakes and confusion points agents tend to hit in this
project. If something in the project surprises you, tell the developer you are
working with and record it in `docs/ISSUES.md`, so later agents avoid the same
problem. Create `docs/ISSUES.md` if it does not exist. Read it before starting.

## Reference

Keep supporting agent documentation under `docs/`, with uppercase filename
stems and the `.md` extension (for example, `docs/WORKTREE.md`). The only
Markdown files at repository root are `AGENTS.md`, `README.md`, and
`CHANGELOG.md`.
Component `README.md` files stay beside their components. Use the same uppercase
filename convention for local handoffs in git-ignored `.plans/`.

- [CONTEXT.md](docs/CONTEXT.md): glossary, product concepts, and design decisions,
  including what the product will do and explicit non-goals. Read before
  changing behavior or terminology; surface conflicts with documented decisions.
- [GLOSSARY.md](docs/GLOSSARY.md): additional map and rendering terms; use
  alongside the product vocabulary in CONTEXT.md.
- [TESTING.md](docs/TESTING.md): how to validate changes, required evidence, and
  what done means, plus commands, physical acceptance checks, and dated results.
  Read before changing code or tests.
- [PLAN.md](docs/PLAN.md): approved MVP scope, delivery phases, and acceptance
  criteria, including the dated implementation status. Keep future proposals
  distinct from completed work.
- [TODO.md](docs/TODO.md): detailed follow-on work and remaining tasks.
- [CHANGELOG.md](CHANGELOG.md): completed changes and release history. Record
  what was done, not future promises.
- [WORKTREE.md](docs/WORKTREE.md): JJ and JJ workspaces. Read before creating
  another checkout, assigning parallel file edits, stacking changes, or sharing
  build, server, simulator, or device resources.
- [API_CONTRACT.md](docs/API_CONTRACT.md): integration boundaries and compatibility
  between clients and server.
- [ARCHITECTURE.md](docs/ARCHITECTURE.md): runtime, data, and dependency boundaries.
- [PRIVACY.md](docs/PRIVACY.md) and [SECURITY.md](docs/SECURITY.md): location-data
  handling, access, trust boundaries, and deployment safeguards.
- [PROTOMAPS_TRIAL.md](docs/PROTOMAPS_TRIAL.md): local map trial setup and limits.
- [0001-USE-POSTGRESQL-FROM-THE-MVP.md](docs/adr/0001-USE-POSTGRESQL-FROM-THE-MVP.md):
  accepted database decision.
- [ISSUES.md](docs/ISSUES.md): local agent discoveries and recurring pitfalls;
  separate from GitHub issues. Read before starting.
- [README.md](README.md): project entrypoint and local quick start.

Component guides: [API](apps/api/README.md), [iOS](apps/ios/README.md),
[web](apps/web/README.md), [infrastructure](infra/README.md),
[map fonts](infra/tileserver/fonts/README.md), and
[map sprites](infra/tileserver/sprites/README.md).

## Working approach

- Treat every user message as an actionable request. Investigate questions,
  implement requested changes, and carry authorized work through validation.
- “Can you…”, “help me…”, and similar wording mean do the work.
- Questions have implied actions. If a question reveals unfinished requested
  work, complete that work within existing authorization before reporting
  the result; do not stop at describing gaps.
- For substantial tasks, list planned actions in a concise plan and proceed.
  Plan approval is not required.
- Use existing context and repository conventions to resolve routine choices.
- Ask only when missing information materially affects correctness, scope,
  product behavior, or authorization. Explain the specific decision needed.
- Ask before starting, stopping or rebuilding the shared local platform,
  contacting an external service, or a first deployment, unless the user
  already authorized that action and target.
- Commit, push and open PRs only when the user asks or the task calls for a PR.
- Continue independent work while awaiting clarification.
- Follow the user's latest corrections and constraints.
- Do not stop after proposing work that you can safely complete.

## Parallel work and agent selection

- Split work into independent tasks and run them in parallel. Keep dependent
  tasks in order. Complete top-level items of a multi-item request in order
  unless blocked, and delegate independent subtasks within each item.
- Use subagents for independent, parallelizable subtasks. Give each a bounded
  brief: goal, files or area, base revision, workspace path, bookmark and
  validation to run.
- Every file-editing task gets its own JJ workspace under `.worktrees/`. Follow
  [WORKTREE.md](docs/WORKTREE.md); use `jj` and JJ workspaces, not `git worktree add`.
  Read-only research and review may share a checkout.
- Never let two agents edit the same checkout. Never touch another agent's
  workspace, server, simulator session or device install.
- Match agent capability to task complexity. Use lower-tier models and lower
  reasoning effort for simple, well-defined work, and stronger agents for work
  requiring deeper reasoning.
- Do not exceed the parent agent's model tier or reasoning effort without
  explicit authorization.
- The parent agent owns shared resources: the local container platform, the
  physical iPhone and simulators. It decides who uses them and in what order.

## Changes and validation

- Inspect relevant code and instructions before editing.
- State intended file edits before making them. Reversible local edits needed
  for the requested work are preapproved.
- Preserve unrelated user changes. A request to modify something authorizes
  changes necessary for that request.
- Keep changes narrow and preserve distinct product concepts. Raw recordings
  are immutable; never weaken the SQLite triggers or the server's raw-data
  rules to make a change easier.
- For behavior changes and bug fixes, add meaningful regression coverage.
  Verify the test fails before the fix where practical.
- Run focused validation after each completed section. Investigate failures;
  ask for advice only when a decision requires user input.
- After tests pass, run builds for the affected platforms. Skip builds for
  documentation-only changes.
- Check for running development servers before launching one. Reuse compatible
  running servers, leave unrelated servers untouched, and stop servers you
  started when finished. Stop them by the PID you captured, never by pattern.
- Report the outcome, validation performed, and unresolved limitations.
- PRs that change layout, UI or product flow should include images or videos.
- Organize PRs around requested merge groups. Stack dependent groups. Do not
  create one PR per finding by default.

## Known pitfalls

- `ls` is aliased to `eza` on this Mac, so `ls -t` and similar flags fail or
  print nothing. Use `/bin/ls` in scripts and command substitutions.
- The iOS app bundles its map from the git-ignored `.local/onon/ios-map`. A
  fresh checkout or workspace builds without it and shows "Offline map
  unavailable". Run `scripts/prepare-ios-map.sh`, or link the main checkout's
  copy as the workspace guide describes.
- The iOS project uses Xcode file-system synchronized groups. New files under
  `apps/ios/Onon` and `apps/ios/OnonTests` are picked up without editing the
  project file.
- `xcodebuild -destination 'platform=iOS Simulator,name=…'` often matches
  nothing. Use `id=<UDID>` from `xcrun simctl list devices available`.
- `xcrun devicectl` install or launch fails with `Locked` or CoreDevice error
  4016 when the iPhone is locked or asleep. Ask the user to unlock it; do not
  retry in a loop.
- The local platform uses fixed container names and ports from
  `infra/config/local.env`. Only one checkout can run it at a time.
- The main checkout is JJ-colocated and the user may use Git branches there.
  Inside `.worktrees/` workspaces use JJ only.

## Agent skills

### Issue tracker

Use GitHub issues in `michft/onon`. Always select the repository explicitly
with `--repo michft/onon` when using `gh issue` or `gh pr`; do not infer it from
another fork or a shared playbook. `docs/ISSUES.md` holds local discoveries and
pitfalls; it does not replace the GitHub issue tracker.

- Search open and closed issues before filing duplicates. Use `--body-file` for
  multiline issues, comments, and PR descriptions.
- Publish issues or comments only when requested as part of the task. A ready
  label does not itself authorize implementation or publication.
- Link an implementation PR to its issue when one exists. Use `Refs` for partial
  work and `Closes` only when the issue's acceptance criteria are complete.
- Keep unrelated or upstream work in its own tracker; changing the destination
  requires an explicit decision.

### Triage labels

Use these canonical states, with exactly one state on each triaged issue:

- `needs-triage`: awaiting maintainer evaluation.
- `needs-info`: waiting for specific evidence from the reporter.
- `ready-for-agent`: accepted, specified work suitable for an assigned agent.
- `ready-for-human`: accepted work needing human judgment or implementation.
- `wontfix`: not accepted; close with the reason.

Each triaged issue also has one category, `bug` or `enhancement`. Remove the
previous state when transitioning. `via-triage` records provenance, not readiness.
If labels are missing or states conflict, report the gap instead of inventing
aliases or silently changing GitHub configuration. A reporter reply to
`needs-info` needs maintainer re-evaluation; it does not launch an agent.
Assign an owner before starting accepted work and track progress through its
assignment and implementation PR, without extra in-progress labels.

### Domain docs

Use [CONTEXT.md](docs/CONTEXT.md) as the glossary and design-decision source,
including explicit non-goals. Read the relevant [API contract](docs/API_CONTRACT.md) when
behavior crosses components. Keep Raw Recordings, Trail Overlays, Waypoints,
and Display Profiles distinct. Surface conflicts before changing the design;
record agreed decisions in context and planned work in [PLAN.md](docs/PLAN.md).
Do not create duplicate glossaries or architecture documents just to satisfy
a skill's default layout.

## Taste

- Complexity belongs at adapter boundaries. Domain logic stays pure where
  practical; UI and orchestration should not duplicate it.
- Keep client mutations behind the owning API client and authorization on the
  server. UI availability is not an authorization check. Extend rejection and
  permission tests when changing a protected operation.
- Server features belong in domain modules or services. A transport handler
  decodes input, calls the owning behavior, and maps results or errors; avoid
  embedding business rules in HTTP routes.
- Reusable UI components own their look. Use existing variants or extend them
  for a reusable concept; keep feature-specific appearance in that feature.
  Layout belongs on the parent rather than in unrelated component overrides.
- Follow existing tracing and logging conventions, keeping useful operation
  names stable. Do not add framework-specific helpers solely to imitate another
  repository.
- Prefer inferred types over redundant annotations. Avoid `any` unless truly
  necessary or explicitly requested.
- Comments explain why: a constraint, external quirk, or invariant the code
  cannot show. Do not narrate steps, restate names, or record change history in
  code comments.
- Respect frame time and battery use. Avoid continuously repainting animations
  or unnecessary map redraws; a stale status or dropped frame is a product bug.
- If a rule conflicts with the task, surface the conflict before bypassing it.
  Follow explicit user decisions and ask when a material decision remains.

## Project records

- Check local `.plans/` for relevant handoffs before starting; read the newest
  first and continue only work within the user's current request. Keep session
  handoffs in this git-ignored folder.
- Record material discoveries in `docs/ISSUES.md`. Keep future work in
  `docs/PLAN.md`; link existing detailed `docs/TODO.md` items rather than
  maintaining duplicate plans.
- Update relevant documentation when behavior or setup changes.
- Add a line to `CHANGELOG.md` under Unreleased for user-visible changes. For
  major features, also update `README.md`.
