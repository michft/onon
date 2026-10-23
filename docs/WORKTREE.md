# Parallel tasks in JJ workspaces

Independent tasks and subagents may run in parallel. Give each task that edits
files its own JJ workspace with Git colocation. Read-only research and review
may share a checkout. Creating local workspaces for an already authorized task
does not need another confirmation. Creating a local workspace does not
authorize pushing, publishing, deploying, or touching another task's workspace.
Preserve unrelated work.

## Location and ownership

- Create workspaces at `<repo>/.worktrees/<task-name>`, for example
  `~/src/onon/.worktrees/waypoint-ui`. `/.worktrees/` is ignored by Git. pnpm
  only runs the packages in `pnpm-workspace.yaml`, and Xcode only syncs folders
  under `apps/ios`, so tools in the main checkout do not pick workspaces up.
- The main checkout is JJ-colocated and the user may use Git branches there.
  Inside `.worktrees/` workspaces, use JJ only.
- Use JJ to create and manage workspaces, changes, and bookmarks. Git colocation
  makes each workspace a linked Git worktree, so Git-based tools work there and
  a detached Git HEAD is normal.
- Do not create a second checkout with `git worktree add`, and do not use
  `git checkout` or `git switch` in a JJ-owned workspace.
- Do not create this project's workspaces under `~/.t3/worktrees` or `/tmp`.
- A new workspace starts from the chosen revision. It does not copy another
  workspace's uncommitted edits or ignored files such as `.local/` and
  `infra/config/local.env`.
- Preserve unrelated edits in the main checkout. Never delete or move another
  agent's active workspace.

## Create a workspace

From the main checkout, inspect the current state and fetch:

```sh
cd ~/src/onon
jj status
jj workspace list
jj git fetch --remote origin
mkdir -p .worktrees
```

When no earlier PR remains unmerged, start from `main`:

```sh
jj workspace add --colocate --name task-a -r main@origin .worktrees/task-a
jj -R .worktrees/task-a bookmark create feat/task-a -r @
```

Use a distinct workspace name, path, and bookmark for each parallel task.
Confirm the base before editing: `jj -R .worktrees/task-a log -r @-`.

## Set up a workspace

Install only what the task needs, from inside the workspace:

- **API or web:** `pnpm install --frozen-lockfile`. Do not symlink
  `node_modules` from another checkout.
- **iOS:** link the main checkout's prepared map so the app bundle has its
  offline map:

  ```sh
  mkdir -p .local/onon
  ln -s ~/src/onon/.local/onon/ios-map .local/onon/ios-map
  ```

  Treat the linked map as read-only. If the task changes map preparation, run
  `scripts/prepare-ios-map.sh` in the workspace instead of linking. If the
  main checkout has no `.local/onon/ios-map` either, run that script there
  first; it needs network access only when its pinned downloads are missing.

## Builds, servers, and shared hardware

- **Xcode builds:** give each workspace its own DerivedData inside the
  workspace, so parallel builds do not overwrite each other:

  ```sh
  xcodebuild -project apps/ios/Onon.xcodeproj -scheme Onon \
    -derivedDataPath .local/DerivedData \
    -destination 'id=<simulator UDID>' test
  ```

- **Simulators:** each agent that runs simulator tests or drives the UI uses a
  different simulator UDID. Agree assignments through the parent agent.
  `xcodebuild test` clones simulators for its own runs, which is safe.
- **Physical iPhone:** only one agent may build onto, install on, or launch the
  app on a device at a time, and an install replaces whatever is on it. The
  parent agent decides the order and tells the user which build is installed.
- **Local platform:** the Apple-container stack (`scripts/start-local.sh`,
  `stop-local.sh`, `bootstrap-local.sh`, `refresh-map.sh`, backup and restore)
  uses fixed container names, ports and the main checkout's data root. It is a
  single shared resource. Never run these scripts from a workspace without the
  parent agent's go-ahead, and never stop a stack you did not start.
- **API and web dev servers** may run per workspace when their ports differ.
  Check for existing servers before launching one; reuse only your own
  compatible server.
  Stop your own by the PID you captured. Never reuse, interrupt, or stop
  another agent's server.
- Supply only the environment files the task's target needs. Never commit
  `infra/config/local.env` or copy its secrets into chat.

## Sequential changes and PR stacking

- Start a sequential or follow-on change from the previous change's latest
  bookmark, including its review fixes. Do not restart from `main` while the
  predecessor is still unmerged.
- Create a new workspace and bookmark on that revision instead of editing the
  previous task's workspace. For example, replace `-r main@origin` above with
  `-r feat/previous-task`.
- Every new PR stacks on the previous unmerged PR. Target its branch as the PR
  base and name that predecessor in the PR body. Coordinate publication order
  even when the implementation tasks ran in parallel.
- Merge stacks bottom-up into `main`. After a predecessor merges, retarget its
  immediate successor to `main` **before** merging the successor. Merging a PR
  into an already merged base branch leaves its changes off `main`. Fetch and
  confirm the merged changes are on `main@origin` before continuing.

## Assign parallel work

- Match agent capability to the task; prefer lower-tier models and effort for
  well-defined work. Do not exceed the parent's model tier or reasoning effort
  without explicit authorization.
- Give each implementation agent a bounded task, its absolute workspace path,
  base revision, bookmark, any simulator or device assignment, and validation
  requirements. Keep dependent tasks in order and run independent ones
  concurrently.
- Bind the agent or thread to that workspace through the orchestration tool's
  workspace selection. A shell `cd` does not change a T3 thread's binding.
  Verify the resolved path before editing.
- For a new T3 thread, use `t3_thread_launch` with
  `workspaceStrategy: {"type": "existing_worktree", "worktreePath": ...}` and
  the prepared absolute path. For a delegated subagent that needs a checkout,
  pass the prepared path in its brief, or use the tool's worktree isolation
  only if it creates the checkout under `.worktrees/`.
- If a delegated agent cannot attach to the prepared workspace, report that
  limitation. Do not substitute an outside checkout or let parallel agents edit
  the same checkout. Read-only subtasks can still proceed.

## Verify and publish

```sh
jj -R .worktrees/task-a status
jj -R .worktrees/task-a workspace list
git -C .worktrees/task-a rev-parse --show-toplevel
```

Run the task's focused checks and relevant builds inside its workspace (see
[TESTING.md](TESTING.md)), review its diff, then advance only its bookmark.
Push only when the user asked for a PR or a push:

```sh
jj -R .worktrees/task-a bookmark set feat/task-a -r @
jj -R .worktrees/task-a git push --remote origin --bookmark feat/task-a
```

Only fast-forward pushes are allowed, and the user merges PRs. Return the
workspace path, bookmark, commit, validation results, and PR URL (if any) to
the parent agent.

## Clean up

When a task's PR has merged, or its bookmark is integrated, and nothing in its
workspace is unpublished:

```sh
jj workspace forget task-a
rm -rf .worktrees/task-a
git worktree prune
```

Remove only workspaces you created. Keep any with unreviewed or unpublished
work.
