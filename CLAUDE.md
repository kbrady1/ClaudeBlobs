# ClaudeBlobs

macOS menu bar app that monitors Claude agent sessions and provides deep-linking back to their source (cmux, terminal, or Claude Desktop).

## Build & Run

After every code change, **build and restart** the app to test:

```sh
make restart-dev   # build release, kill running instance, relaunch
```

Other targets:
- `make build` — release build only
- `make bundle` — build + create .app bundle
- `make run` — bundle + launch (first run)
- `make stop` — kill running instance
- `make install` — copy bundle to /Applications

When working with superpowers, do not commit those files to the github repo. They are .gitignored

## Testing

Run all tests (unit + E2E conversation tests) before considering any task complete:

```sh
make test     # runs swift test
```

## Architecture

- **Sources/Lib/Store/AgentStore.swift** — watches `~/.claude/agent-status/*.json` for agent state
- **Sources/Lib/DeepLink/** — routing logic: `DeepLinker` dispatches to `CmuxLinker`, `TerminalLinker`, or Claude Desktop based on process ancestry
- **Sources/Lib/ProcessTree.swift** — shared sysctl-based process tree walker
- **Resources/hooks/** — shell hooks that Claude writes agent status files
- **Sources/Lib/Models/BoardModel.swift** — pure column classification and sorting for the kanban board
- **Sources/Lib/Views/Board/** — board window, view model (keyboard handling), cards, tag editor, tag manager, Conductor / Stats / History modes
- **Sources/Lib/Store/TagStore.swift** — tag definitions, per-session assignments (confirmed vs inferred), persisted filter; file at `~/Library/Application Support/ClaudeBlobs/tags.json`
- **Sources/Lib/Store/SessionHistoryStore.swift** — session history (90-day retention, Idle/Needs Attention dwell episodes), `HistoryStats` and `BoardStats` aggregation; file at `~/Library/Application Support/ClaudeBlobs/history.json`
- **Sources/Lib/Conductor/** — `ConductorStore` (AI-ranked queue of sessions waiting on the user; one score per input fingerprint, persisted to `conductor.json`), `SessionMessenger` (reply/approve via `superset terminals send` or cmux)
- **Sources/Lib/Models/WorkingHours.swift** — working-hours (Mon–Fri 09:00–17:00) wait-time math used by stats and the Conductor
- **Sources/Lib/RepoInfo.swift** — repo name + branch from `.git` (worktree-aware, no git binary)
- **Sources/Lib/Tagging/TagInference.swift** — one-shot `claude -p --model haiku` tag inference from a session's first prompt (`firstPrompt` in the status file, transcript fallback)

## Deep Linking

Link type is determined by process ancestry, not just presence of `cwd`:
1. cmux workspace fields present → cmux socket RPC
2. Agent PID is descendant of Claude Desktop → activate Desktop app
3. Has cwd → walk process tree for terminal GUI ancestor
4. Fallback → activate Claude Desktop
