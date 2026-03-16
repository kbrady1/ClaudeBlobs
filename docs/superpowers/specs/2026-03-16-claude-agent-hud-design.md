# Claude Agent HUD — Design Spec

A macOS menu-bar-height floating panel that shows the status of all running Claude Code agents as pixel art characters.

## Goals

- At-a-glance visibility into which agents need attention vs which are working
- Minimal footprint (menu bar height when collapsed)
- Click-to-jump deep linking into agent sessions
- Fun, personality-driven pixel art characters

## Non-Goals (v1)

- Working expression cycling per tool type (v2)
- Claude Desktop app deep-linking into specific conversations
- Transcript browsing or full message history
- Controlling agents (stopping, sending input) from the HUD

## Requirements

- macOS 13+ (Ventura) — required for `SMAppService` login item API
- No third-party dependencies (pure SwiftUI + AppKit)

---

## Architecture

Single SwiftUI application. No separate daemon or background service.

```
┌─────────────────────────────────────────────────────┐
│                    Claude Agent HUD                  │
│                   (SwiftUI macOS app)                │
│                                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────┐ │
│  │ StatusFile   │  │ AgentStore   │  │ FloatingUI  │ │
│  │ Watcher      │──│ (ObsObj)     │──│ (NSPanel)   │ │
│  │              │  │              │  │             │ │
│  │ DispatchSrc  │  │ [Agent]      │  │ Collapsed/  │ │
│  │ + 2s timer   │  │ PID cleanup  │  │ Expanded    │ │
│  └──────────────┘  └──────────────┘  └────────────┘ │
│                                                      │
│  ┌──────────────┐  ┌──────────────┐                  │
│  │ DeepLinker   │  │ HookInstaller│                  │
│  │ cmux / NSApp │  │ First-launch │                  │
│  └──────────────┘  └──────────────┘                  │
└─────────────────────────────────────────────────────┘

        reads from
            │
┌───────────┴───────────┐
│ ~/.claude/agent-status │
│  ├── <session-id>.json │
│  ├── <session-id>.json │
│  └── ...               │
└────────────────────────┘
        written by
            │
┌───────────┴───────────┐
│  Claude Code Hooks     │
│  (shell scripts in     │
│   app bundle)          │
└────────────────────────┘
```

---

## Data Layer

### Status Directory

`~/.claude/agent-status/` — one JSON file per active session.

### Status File Format

`~/.claude/agent-status/<session-id>.json`:

```json
{
  "sessionId": "ddb8ef84-ee6e-4e9c-9a1a-0d9e46a423fe",
  "pid": 11324,
  "cwd": "/Users/kentbrady/SourceCode/android",
  "agentType": "neovim-coach",
  "status": "waiting",
  "lastMessage": "I've updated the keybinding. Want me to...",
  "lastToolUse": null,
  "cmuxWorkspace": "ws:abc123",
  "cmuxSurface": "surface:def456",
  "updatedAt": 1773687200000
}
```

Fields:
- `sessionId` — UUID from Claude Code session
- `pid` — OS process ID
- `cwd` — working directory (used as label; last path component displayed)
- `agentType` — from `--agent` flag if present, null otherwise
- `status` — one of: `starting`, `working`, `waiting`, `permission`, enum
- `lastMessage` — first sentence of last assistant response (set on `Stop`)
- `lastToolUse` — last tool name + short summary (set on `PreToolUse`)
- `cmuxWorkspace` — cmux workspace ID if in cmux session, null otherwise
- `cmuxSurface` — cmux surface ID if in cmux session, null otherwise
- `updatedAt` — millisecond timestamp of last update

### Hook → Status Mapping

| Hook Event | Writes `status` | Additional Fields |
|---|---|---|
| `SessionStart` | `"starting"` | cwd, agentType, pid, cmux IDs (from env) |
| `UserPromptSubmit` | `"working"` | clears lastMessage |
| `PreToolUse` | `"working"` | lastToolUse = tool name + input summary |
| `Stop` | `"waiting"` | lastMessage = first sentence of last_assistant_message |
| `PermissionRequest` | `"permission"` | lastToolUse = tool requesting permission |
| `Notification` | no change | updates `updatedAt` only (notification does not imply waiting) |
| `SessionEnd` | deletes file | removes `<session-id>.json` |

### Hook Input Schema

Claude Code passes JSON to hook scripts via stdin. Relevant fields per event:

| Hook Event | Key Input Fields |
|---|---|
| `SessionStart` | `session_id`, `cwd`, `agent_type` |
| `UserPromptSubmit` | `session_id`, `cwd` |
| `PreToolUse` | `session_id`, `tool_name`, `tool_input` |
| `Stop` | `session_id`, `last_assistant_message`, `stop_hook_active` |
| `PermissionRequest` | `session_id`, `tool_name`, `tool_input` |
| `Notification` | `session_id`, `message` |
| `SessionEnd` | `session_id` |

PID is not provided in hook input. Each hook derives it from `$PPID` (the Claude Code process that spawned the hook script).

Environment variables available to all hooks:
- `CMUX_WORKSPACE`, `CMUX_SURFACE` — present if the session runs inside cmux
- `CLAUDE_CODE_ENTRYPOINT` — `cli` for CLI sessions

### Hook Scripts

Bundled inside the .app as shell scripts. Each hook:
1. Receives hook data via stdin (JSON)
2. Ensures status directory exists (`mkdir -p`)
3. Reads/writes `~/.claude/agent-status/<session-id>.json`
4. Extracts session ID from the hook input's `session_id` field

All hook scripts begin with this common preamble:
```bash
#!/bin/bash
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
STATUS_DIR="$HOME/.claude/agent-status"
mkdir -p "$STATUS_DIR"
STATUS_FILE="$STATUS_DIR/$SESSION_ID.json"
```

Example hook script (`hook-stop.sh`):
```bash
#!/bin/bash
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
STATUS_DIR="$HOME/.claude/agent-status"
mkdir -p "$STATUS_DIR"
STATUS_FILE="$STATUS_DIR/$SESSION_ID.json"

# Extract first sentence of last assistant message
LAST_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // ""' | head -c 200 | sed 's/\..*/\./')

if [ -f "$STATUS_FILE" ]; then
  jq --arg status "waiting" \
     --arg msg "$LAST_MSG" \
     --arg ts "$(date +%s000)" \
     '.status = $status | .lastMessage = $msg | .updatedAt = ($ts | tonumber)' \
     "$STATUS_FILE" > "$STATUS_FILE.tmp" && mv "$STATUS_FILE.tmp" "$STATUS_FILE"
fi
```

### File Watching

The app watches `~/.claude/agent-status/` using:
- `DispatchSource.makeFileSystemObjectSource` on the directory for immediate change detection
- Fallback 2-second `Timer` to catch any missed events
- On each change: re-read all JSON files, diff against current state, update `AgentStore`
- Stale file cleanup: cross-reference each file's PID against `kill(pid, 0)` — if the process doesn't exist, delete the status file

---

## UI Layer

### Window

- `NSPanel` subclass with:
  - `.nonactivatingPanel` style mask (doesn't steal focus)
  - `level = .statusBar` (above normal windows, below menu bar extras)
  - `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]` (visible on all desktops)
  - No title bar, transparent background
  - `isMovableByWindowBackground = false`
- Positioned: horizontally centered on main screen, top edge directly below the menu bar (y = screen visible frame maxY). On notched MacBooks, offset left or right if the centered position would overlap the notch area.
- Hides when no agents are running
- Right-click on the panel shows a context menu (settings, reinstall hooks, uninstall & quit)

### Collapsed State (default)

- Height: 22px (menu bar height)
- Pill-shaped rounded rectangle with semi-transparent dark background (`#2a2a2a` at ~80% opacity)
- Shows agents with status `waiting`, `permission`, or `starting`
- Each agent: 18x18px pixel art sprite
- Agents spaced 8px apart horizontally
- Sprites animate: bounce for waiting, jump + wave for permission

### Expanded State (on hover)

- Triggered by `NSTrackingArea` mouse enter on the panel
- Smooth spring animation (~0.2s) expanding height to ~120px
- Shows ALL agents (waiting, permission, AND working)
- Each agent card: ~80px wide
  - 40x40px pixel art sprite (scaled up from sprite sheet)
  - Subtitle: last path component of cwd (or "APP" for desktop app sessions, or agent type if named)
  - Speech bubble content by status:
    - **waiting**: last assistant message (first sentence)
    - **working**: last tool activity (tool name + summary)
    - **permission**: tool requesting permission (e.g., "Wants to run: rm -rf build/")
    - **starting**: empty or "Starting up..."
  - Text truncated with ellipsis
- Working agents rendered at reduced opacity (0.7) to draw attention to waiting/permission agents
- Mouse exit triggers collapse after 0.2s delay (prevents flicker when moving between agent cards)
- Maximum 10 agents visible; if more, show a "+N" overflow indicator

### Status Colors & Expressions

| Status | Color | Sprite Expression | Animation |
|---|---|---|---|
| **Permission** | Red `#FF3B30` | `ò_ó` alarmed/urgent | Jumping + hand waving, most animated |
| **Waiting** | Orange `#FF9500` | `°□°` surprised/alert | Gentle bounce |
| **Working** | Blue `#4C8DFF` | `•_•` focused | Subtle typing motion |
| **Starting** | Green `#34C759` | `^‿^` waving | Fade in, brief transition state |

Note: expressions above are conceptual descriptions for the pixel art sprites, not literal text rendering.

### Pixel Art Sprites

- Base sprite: 16x16 pixel grid, rendered at 18px (collapsed) and 40px (expanded) with nearest-neighbor scaling
- Each status has a sprite sheet with 2-4 animation frames
- Character design: simple humanoid or blob shape with Claude-inspired color palette
- Sprites stored as asset catalogs in the app bundle
- Animation frames played at ~4fps for a retro feel

---

## Deep Linking

### Click Handling

Clicking an agent sprite triggers deep linking based on session type:

### cmux Sessions (primary path)

If `cmuxWorkspace` and `cmuxSurface` are set in the status file:

```bash
cmux select-workspace --workspace <workspace-id>
cmux select-surface --surface <surface-id> --workspace <workspace-id>
```

Detection: `SessionStart` hook checks for `CMUX_WORKSPACE` and `CMUX_SURFACE` environment variables.

### Non-cmux CLI Sessions

1. Look up PID's parent terminal process via `ps -o ppid= -p <pid>`
2. Walk up the process tree to find the terminal app (Terminal.app, iTerm, etc.)
3. Find the terminal app via `NSWorkspace.shared.runningApplications` filtered by PID, then call `activate()` on it
4. Fallback: if process tree walking fails (e.g., tmux, SSH), do nothing — this is best-effort for non-cmux sessions

### Claude Desktop App

If cwd is not set or agent is identified as desktop:
- `NSWorkspace.shared.open(URL(string: "file:///Applications/Claude.app")!)`
- No deep-link into specific conversation (not supported by desktop app)

---

## Installation & First Launch

### App Setup

1. App runs as LSUIElement (no dock icon) — set via `Info.plist` `LSUIElement = true`
2. On first launch, show a brief setup dialog:
   - "Claude Agent HUD will install hooks into your Claude Code settings to track agent status. Continue?"
3. Register as login item: `SMAppService.mainApp.register()`
4. Create `~/.claude/agent-status/` directory

### Hook Installation

Read `~/.claude/settings.json`, merge hook entries for each event:

```json
{
  "hooks": {
    "SessionStart": [{ "type": "command", "command": "/path/to/HUD.app/Contents/Resources/hooks/hook-session-start.sh" }],
    "UserPromptSubmit": [{ "type": "command", "command": "/path/to/HUD.app/Contents/Resources/hooks/hook-user-prompt.sh" }],
    "PreToolUse": [{ "type": "command", "command": "/path/to/HUD.app/Contents/Resources/hooks/hook-pre-tool.sh" }],
    "Stop": [{ "type": "command", "command": "/path/to/HUD.app/Contents/Resources/hooks/hook-stop.sh" }],
    "PermissionRequest": [{ "type": "command", "command": "/path/to/HUD.app/Contents/Resources/hooks/hook-permission.sh" }],
    "Notification": [{ "type": "command", "command": "/path/to/HUD.app/Contents/Resources/hooks/hook-notification.sh" }],
    "SessionEnd": [{ "type": "command", "command": "/path/to/HUD.app/Contents/Resources/hooks/hook-session-end.sh" }]
  }
}
```

Hooks are appended to existing arrays (not replacing). The installer preserves all existing hook configurations. The installer is idempotent: it checks for existing entries matching the HUD's hook paths before appending, preventing duplicates on re-launch or re-install.

### Uninstallation

Menu bar context menu includes "Uninstall Hooks & Quit" which:
1. Removes HUD hook entries from `~/.claude/settings.json`
2. Removes `~/.claude/agent-status/` directory
3. Deregisters login item
4. Quits

---

## Project Structure

```
ClaudeAgentHUD/
├── ClaudeAgentHUD.xcodeproj
├── Sources/
│   ├── App/
│   │   ├── ClaudeAgentHUDApp.swift          # App entry, menu bar setup
│   │   └── AppDelegate.swift                 # NSPanel creation, login item
│   ├── Models/
│   │   ├── Agent.swift                       # Agent data model
│   │   └── AgentStatus.swift                 # Status enum
│   ├── Store/
│   │   ├── AgentStore.swift                  # ObservableObject, file watching
│   │   └── StatusFileWatcher.swift           # DispatchSource wrapper
│   ├── Views/
│   │   ├── HUDPanel.swift                    # NSPanel subclass
│   │   ├── CollapsedView.swift               # Pill with small sprites
│   │   ├── ExpandedView.swift                # Full cards with speech bubbles
│   │   ├── AgentSpriteView.swift             # Pixel art sprite renderer
│   │   └── SpeechBubbleView.swift            # Truncated message bubble
│   ├── DeepLink/
│   │   ├── DeepLinker.swift                  # Router for click actions
│   │   ├── CmuxLinker.swift                  # cmux workspace/surface jumping
│   │   └── TerminalLinker.swift              # Non-cmux terminal activation
│   └── Setup/
│       ├── HookInstaller.swift               # Merges hooks into settings.json
│       └── FirstLaunchView.swift             # Setup confirmation dialog
├── Resources/
│   ├── Assets.xcassets/
│   │   ├── Sprites/                          # Pixel art sprite sheets
│   │   │   ├── waiting/                      # Orange surprised frames
│   │   │   ├── permission/                   # Red alarmed frames
│   │   │   ├── working/                      # Blue focused frames
│   │   │   └── starting/                     # Green waving frames
│   │   └── AppIcon.iconset/
│   └── hooks/
│       ├── hook-session-start.sh
│       ├── hook-user-prompt.sh
│       ├── hook-pre-tool.sh
│       ├── hook-stop.sh
│       ├── hook-permission.sh
│       ├── hook-notification.sh
│       └── hook-session-end.sh
└── Info.plist                                # LSUIElement = true
```

---

## Edge Cases

- **Crashed session**: PID no longer running but status file exists → cleaned up by 2-second timer PID check
- **Multiple displays**: panel always on main screen (screen with menu bar)
- **No agents running**: panel hides entirely, no empty pill
- **Settings.json doesn't exist**: create it with just the hooks section
- **Hook script fails**: agent still works, just no status update — HUD shows stale data until PID cleanup
- **App moved/renamed**: hooks reference absolute path in .app bundle — re-run hook install from menu if app is moved
- **Rapid status transitions**: file writes are atomic (write tmp + rename), reads tolerate partial/missing files gracefully
