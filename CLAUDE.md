# Claudblobs

macOS menu bar app that monitors Claude agent sessions and provides deep-linking back to their source (cmux, terminal, or Claude Desktop).

## Build & Run

After every code change, **build and restart** the app to test:

```sh
make restart   # build release, kill running instance, relaunch
```

Other targets:
- `make build` — release build only
- `make bundle` — build + create .app bundle
- `make run` — bundle + launch (first run)
- `make stop` — kill running instance
- `make install` — copy bundle to /Applications

## Testing

Run tests before considering any task complete:

```sh
swift test
```

## Architecture

- **Sources/Lib/Store/AgentStore.swift** — watches `~/.claude/agent-status/*.json` for agent state
- **Sources/Lib/DeepLink/** — routing logic: `DeepLinker` dispatches to `CmuxLinker`, `TerminalLinker`, or Claude Desktop based on process ancestry
- **Sources/Lib/ProcessTree.swift** — shared sysctl-based process tree walker
- **Resources/hooks/** — shell hooks that Claude writes agent status files

## Deep Linking

Link type is determined by process ancestry, not just presence of `cwd`:
1. cmux workspace fields present → cmux socket RPC
2. Agent PID is descendant of Claude Desktop → activate Desktop app
3. Has cwd → walk process tree for terminal GUI ancestor
4. Fallback → activate Claude Desktop
