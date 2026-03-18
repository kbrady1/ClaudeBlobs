# ClaudeBlobs

A macOS menu bar app that monitors your running Claude Code agent sessions and lets you jump back to them with a keystroke.

![macOS](https://img.shields.io/badge/macOS-13%2B-blue)

## What It Does

ClaudeBlobs watches for active Claude Code agent sessions and displays them as animated sprite faces floating at the top of your screen. Each face reflects what the agent is doing — working, waiting for input, or asking for permission — so you can keep tabs on multiple agents at a glance.

![ClaudBlobsDemo](https://github.com/user-attachments/assets/cfd74efd-567f-4617-ad24-3f4d99013d0d)

Click a face or use the keyboard picker to deep-link straight back to the terminal, cmux workspace, or Claude Desktop session that spawned it.

## Features

### Live Agent Monitoring
- Animated sprite faces show agent state: **starting** (happy), **working** (focused), **waiting** (alert), **permission needed** (angry)
- Faces blink, look around, and animate based on state
- Purple badge when a push notification fires
- Accent icons show what the agent is doing (see table below)
- Snooze agents to gray them out; dismiss to remove entirely

### Accent Icons

Each agent sprite shows a small overlay icon indicating what it's currently doing:

#### Working State

| Icon | SF Symbol | When |
|------|-----------|------|
| 🧩 Puzzle piece | `puzzlepiece.fill` | Calling an MCP tool (`mcp__*`) |
| 📋 Checklist | `checklist` | Running tests or verification (test, lint, xcodebuild, etc.) |
| ✏️ Pencil | `pencil` | Writing code (Edit, Write, Bash, NotebookEdit) |
| 🌐 Globe | `globe` | Web search (WebSearch, WebFetch) |
| 🔍 Magnifying glass | `magnifyingglass` | Reading/exploring code (Read, Grep, Glob, LSP, Agent) |
| 💬 Speech bubble | `ellipsis.bubble.fill` | Default — thinking or using other tools |

Priority: testing > MCP > coding > web search > exploring > default.

#### Permission State

| Icon | SF Symbol | When |
|------|-----------|------|
| ✅ Checkmark bubble | `checkmark.bubble.fill` | Plan approval (ExitPlanMode) |
| ❓ Question bubble | `questionmark.bubble.fill` | Asking a question (AskUserQuestion) |

#### Transient (flash for 3 seconds)

| Icon | SF Symbol | When |
|------|-----------|------|
| ✋ Raised hand | `hand.raised.fill` | User interrupted a tool |
| ⚠️ Warning triangle | `exclamationmark.triangle.fill` | Tool error |

#### Other Overlays

| Overlay | When |
|---------|------|
| 🟣 Purple badge (top-right) | Push notification sent |
| 🔥 Fire (above head) | API error or outage |

### Deep Linking
Clicking an agent routes you back to its source automatically:
- **cmux** — sends RPC to select the workspace and surface, then switches to the correct terminal tab
- **Terminal apps** — activates the parent terminal (iTerm2, Kitty, Terminal, Warp, WezTerm, Ghostty, Hyper)
- **Claude Desktop** — activates the desktop app

**Tab-level switching** is supported for **cmux**, **iTerm2**, and **Terminal.app**. When an agent runs in one of these terminals, ClaudeBlobs uses the agent's TTY to find and select the exact tab via AppleScript. Other terminals fall back to activating the app window. On first use, macOS will prompt you to grant ClaudeBlobs Automation permission for the terminal app.

### Keyboard Navigation
- **Ctrl+Option+A** — global hotkey to open the agent picker (customizable)
- **Tab / Shift+Tab / Arrow keys** — cycle through agents
- **Enter** — jump to the selected agent
- **Backspace** — snooze (first press) or dismiss (second press)
- **Escape** — close the picker

### Push Notifications (ntfy.sh)
Optional push notifications via [ntfy.sh](https://ntfy.sh) when agents need attention:
- Configurable delay to avoid noise from brief state changes
- Per-state toggles (permission, waiting, done)
- Separate priority levels for permission requests vs. other states
- Works with self-hosted ntfy servers

## Install

### From Source

Requires Xcode command-line tools (Swift 5.9+).

```sh
git clone https://github.com/yourusername/ClaudeBlobs.git
cd ClaudeBlobs
make install
```

This builds the app, bundles it, and copies it to `/Applications`.

### First Launch

On first launch the app will ask to install hooks into your Claude Code settings (`~/.claude/settings.json`). These hooks write status files to `~/.claude/agent-status/` so the HUD can track agent state.

The app registers itself as a login item so it starts automatically.

## Build Targets

| Command | Description |
|---------|-------------|
| `make build` | Release build only |
| `make bundle` | Build + create .app bundle |
| `make run` | Bundle + launch |
| `make restart` | Build, kill running instance, relaunch |
| `make stop` | Kill running instance |
| `make install` | Copy bundle to /Applications |

## Menu Bar Options

Right-click (or click) the menu bar icon for:

- **Hide/Show Agents** — toggle the floating panel
- **Show All Agents** — include working agents in the collapsed view (off by default, only actionable states shown)
- **Dismiss All Agents** — snooze everything at once
- **Debug Mode** — log to `~/Library/Logs/ClaudeBlobs/debug.log`
- **Push Notifications** — toggle ntfy.sh integration
- **Notification Settings** — configure endpoint, topic, delay, and priorities
- **Change Hotkey** — re-bind the global picker hotkey
- **Reinstall Hooks** — re-install hooks if your Claude Code settings changed
- **Uninstall Hooks & Quit** — clean removal of all hooks and status files

## How It Works

Seven shell hooks are installed into Claude Code's hook system. Each agent lifecycle event (session start, tool use, permission request, prompt submit, stop, session end) writes or updates a JSON status file. The app watches that directory and renders the HUD accordingly.

Deep linking is determined by process ancestry — the app walks the process tree from the agent PID to find whether it belongs to a cmux session, a terminal emulator, or Claude Desktop.

## Requirements

- macOS 13+
- Claude Code CLI
- Accessibility permission (optional, for keyboard picker navigation beyond the global hotkey)

## Uninstall

Use **Uninstall Hooks & Quit** from the menu bar, then delete the app from `/Applications`. Or manually:

```sh
rm -rf /Applications/ClaudeBlobs.app
rm -rf ~/.claude/agent-status
```

Then remove the hook entries from `~/.claude/settings.json`.
