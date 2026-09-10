# Co-op Foundation 0.1 workflow

This copy is the working base for version 0.1. The original desktop folder remains unchanged.

## Save a version

From this folder, review the changed files, run the relevant Godot or server checks, then commit:

```powershell
git status
git add .
git commit -m "Describe the change"
git tag -a v0.1-<milestone> -m "Milestone description"
```

Each commit is a rollback point. Before a large experiment, create a branch:

```powershell
git switch -c feature/<short-name>
```

Return to the last saved baseline with `git log --oneline` and `git switch <branch>`; do not delete files to undo work.

## Checks

The Godot project is under `game`. Use Godot headless checks when available, and run the matching scripts in `game/tests` or `server/test` for gameplay/network changes. Keep test output in `work/` and commit source changes only.

## Working with Codex

Ask Codex to inspect, edit, and verify a focused change in this folder. Codex will show the files changed and the checks run. You remain the final playtest: launch the Godot editor or exported build and report what you see so the next iteration can target the real behavior.
