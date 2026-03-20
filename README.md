# ClaudeBlobs

A macOS menu bar app that monitors your running Claude Code and OpenCode agent sessions and lets you jump back to them with a keystroke.

![macOS](https://img.shields.io/badge/macOS-13%2B-blue)

## What It Does

ClaudeBlobs watches for active Claude Code and OpenCode agent sessions and displays them as animated sprite faces floating at the top of your screen. Each face reflects what the agent is doing — working, waiting for input, or asking for permission — so you can keep tabs on multiple agents at a glance.

![ClaudBlobsDemo](https://github.com/user-attachments/assets/cfd74efd-567f-4617-ad24-3f4d99013d0d)

Click a face or use the keyboard picker to deep-link straight back to the terminal, cmux workspace, or Claude Desktop session that spawned it.

## Install

Requires macOS 13+ and either Claude Code, OpenCode, or both.

### Homebrew

```sh
brew install kbrady1/tap/claude-blobs
```

### Download

Grab the latest DMG from [Releases](https://github.com/kbrady1/ClaudeBlobs/releases), open it, and drag ClaudeBlobs to `/Applications`.

### Build from Source

Requires Xcode command-line tools (Swift 5.9+).

```sh
git clone https://github.com/kbrady1/ClaudeBlobs.git
cd ClaudeBlobs
make install
```

## Setup

On first launch the app will ask to install hooks into your Claude Code settings (`~/.claude/settings.json`) and install the bundled OpenCode plugin into `~/.config/opencode/plugins/`. These integrations write status files so the HUD can track agent state. The app registers itself as a login item so it starts automatically.

**Accessibility** — macOS will prompt for Accessibility permission the first time you use keyboard navigation in the agent picker (Tab, arrow keys, number keys). The global hotkey works without it.

**Automation** — The first time you click an agent running in **iTerm2**, **Terminal.app**, or **Ghostty**, macOS will prompt to grant ClaudeBlobs Automation permission for that terminal. This enables tab-level switching via AppleScript.

**cmux** — For deep linking to cmux workspaces, go to cmux Settings and switch **Socket Control Mode** to **Automation**. Without this, ClaudeBlobs will fall back to activating the cmux window without navigating to the specific workspace.

**Push notifications** — Enable **Push Notifications** from the menu bar, then open **Notification Settings** to configure your [ntfy.sh](https://ntfy.sh) topic, endpoint, delay, and priority levels. See [ntfy.sh](https://ntfy.sh) for setup and optional self-hosting.

## Usage

### Agent Sprites

- Animated faces show agent state: **starting** (happy), **working** (focused), **waiting** (alert), **permission needed** (angry)
- Faces blink, look around, and animate based on state
- Snooze agents to gray them out; dismiss to remove entirely

Each sprite shows a small overlay icon indicating what the agent is doing:

| Icon | When |
|------|------|
| Puzzle piece | Calling an MCP tool |
| Checklist | Running tests or verification |
| Pencil | Writing code |
| Globe | Web search |
| Magnifying glass | Reading/exploring code |
| Speech bubble | Default — thinking or using other tools |
| Checkmark bubble | Waiting for plan approval |
| Question bubble | Asking a question |
| Raised hand | User interrupted (flashes 3s) |
| Warning triangle | Tool error (flashes 3s) |
| Purple badge | Push notification sent |
| Fire | API error or outage |

### Keyboard Navigation

- **Ctrl+Option+A** — global hotkey to open the agent picker (customizable)
- **Tab / Shift+Tab / Arrow keys** — cycle through agents
- **Enter** — jump to the selected agent
- **Backspace** — snooze (first press) or dismiss (second press)
- **Escape** — close the picker

### Deep Linking

Clicking an agent routes you back to its source. The level of support depends on the terminal:

| Terminal | Activate app | Select tab | Select surface | Method |
|----------|:---:|:---:|:---:|--------|
| **cmux** | :white_check_mark: | :white_check_mark: | :white_check_mark: | JSON-RPC (workspace + surface) |
| **iTerm2** | :white_check_mark: | :white_check_mark: | | AppleScript (by TTY) |
| **Terminal.app** | :white_check_mark: | :white_check_mark: | | AppleScript (by TTY) |
| **Ghostty** | :white_check_mark: | :white_check_mark: | | AppleScript (by working directory) |
| **VS Code** | :white_check_mark: | | | URL scheme |
| **Cursor** | :white_check_mark: | | | URL scheme |
| **Kitty** | :white_check_mark: | | | |
| **WezTerm** | :white_check_mark: | | | |
| **Warp** | :white_check_mark: | | | |
| **Hyper** | :white_check_mark: | | | |
| **Claude Desktop** | :white_check_mark: | | | |

cmux provides the deepest integration — it can navigate to the exact workspace, tab, and surface (split pane) where the agent is running. Any terminal not listed above still gets app-level activation via process tree detection.

### Menu Bar

Right-click (or click) the menu bar icon for:

- **Hide/Show Agents** — toggle the floating panel
- **Show All Agents** — include working agents in the collapsed view
- **Dismiss All Agents** — snooze everything at once
- **Debug Mode** — log to `~/Library/Logs/ClaudeBlobs/debug.log`
- **Push Notifications** — toggle ntfy.sh integration
- **Notification Settings** — configure endpoint, topic, delay, and priorities
- **Change Hotkey** — re-bind the global picker hotkey
- **Reinstall Claude Code Hooks** — re-install hooks if your Claude Code settings changed
- **Reinstall OpenCode Plugin** — copy the latest ClaudeBlobs plugin into `~/.config/opencode/plugins/`
- **Uninstall Hooks & Quit** — clean removal of all hooks and status files

## How It Works

ClaudeBlobs collects agent state from two providers:

- Claude Code shell hooks write JSON status files into `~/.claude/agent-status/`
- The bundled OpenCode plugin writes matching JSON status files into `~/.opencode/agent-status/`

The app watches both directories and renders a single combined HUD.

Deep linking is determined by process ancestry — the app walks the process tree from the agent PID to find whether it belongs to a cmux session, a terminal emulator, an editor, or Claude Desktop.

## Development

| Command | Description |
|---------|-------------|
| `make build` | Release build only |
| `make bundle` | Build + create .app bundle |
| `make run` | Bundle + launch |
| `make restart` | Build, kill running instance, relaunch |
| `make stop` | Kill running instance |
| `make install` | Copy bundle to /Applications |

## Uninstall

Use **Uninstall Hooks & Quit** from the menu bar, then delete the app from `/Applications`. Or manually:

```sh
rm -rf /Applications/ClaudeBlobs.app
rm -rf ~/.claude/agent-status
rm -rf ~/.opencode/agent-status
rm -f ~/.config/opencode/plugins/claudeblobs-opencode.js
```

Then remove the hook entries from `~/.claude/settings.json`.
