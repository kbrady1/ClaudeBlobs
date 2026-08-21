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

- Animated faces show agent state: **starting** (happy), **working** (focused), **waiting** (alert), **permission needed** (angry), **compacting** (purple — context window shrinking), **delegating** (green ring — parent handed off to subagent)
- Faces blink, look around, and animate based on state
- Agents that go idle show X-eyes and eventually desaturate (configurable threshold)
- **Sub-agents** appear as mini blobs alongside their parent; a child's status bubbles up to the parent (e.g., a child needing permission turns the parent red too)
- **Rename** an agent by pressing **R** while it's selected in the picker, or right-click → "Rename"
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
| Clock badge | Loop/cron schedule active |
| Blue spinning ring | Delegating to subagent |

### Keyboard Navigation

- **Ctrl+Option+A** — global hotkey to open the agent picker (customizable)
- **Tab / Shift+Tab / Arrow keys** — cycle through agents
- **Enter** — jump to the selected agent
- **Shift+Enter** — open the permission popover for the selected agent (cmux only)
- **Backspace** — snooze (first press) or dismiss (second press)
- **Escape** — close the picker

### Blob Board

**Ctrl+Option+B** (customizable) opens the Blob Board, a full-size kanban board in its own window. Cards are grouped into columns — Idle, Needs Attention, Working, Monitoring, Snoozed — and sorted by how long each agent has been in that column (oldest at top). Each card shows the agent's latest message and tool call, its location, sub-agents, and tags. Click a card (or press Enter) to deep-link to the agent and close the board.

**Tags.** Tag cards with any of the preset tags (core task, side task, code review, research, eng request, orchestrator) or add your own in *Manage Tags*. Each tag carries a description that explains what it means and how to recognize it. When a new session is first seen, ClaudeBlobs runs a small non-interactive `claude -p --model haiku` call against the session's first prompt and proposes one tag. Inferred tags show as a dashed outline with a `?`; confirmed tags are filled. Open the tag editor (press `T` on the card) and choose the tag to confirm it. The tag filter in the header persists across board openings.

**Modes.** The header's segmented control switches between **Board**, **Conductor**, and **Stats** (**⌘1 / ⌘2 / ⌘3**); the board reopens in the last mode used.

**Conductor.** Ranks every session that is waiting on you (Needs Attention, then Idle) and walks you through them. Each session is scored once by a `claude -p --model sonnet` call from its tags, repo, first prompt, pending tool, last message, and your instructions; the score is cached per input fingerprint, so new or changed sessions cost one call and everything else is re-sorted locally (AI score + a working-hours wait boost − a skip penalty). The top item shows the reasoning and a proposed action: an editable reply or an approval you can send straight into a superset or cmux session (**⌘Return**), or just **Open** / **Skip** / **Snooze**. *Instructions…* lets you rewrite how the Conductor prioritizes; *Re-analyze* re-scores everything.

**Stats.** The Stats mode stacks two sections: *Stats* — a trailing 24h / 7d window (**1 / 2**) with tiles and charts for concurrent sessions over time, sessions started, sessions by tag, and Idle / Needs Attention wait-time spreads (median / p75 / max / mean, counting working hours only: Mon–Fri 09:00–17:00); *History* — 7 / 30 / 90 days (**3 / 4 / 5**) with sessions per day stacked by tag, sessions by tag, top repositories, and a session list. Sessions are recorded to `~/Library/Application Support/ClaudeBlobs/history.json` while the app runs and kept for 90 days.

Board keys: **Arrows / H J K L / Tab** move, **Enter** open, **T** tag editor (**↑↓ / Return** walk and toggle, **1–9** toggle, **C** confirm all inferred, **R** re-infer), **S** snooze, **U** unsnooze, **Backspace** snooze / dismiss, **C** collapse column, **1–9** toggle filter tags, **N** untagged filter, **0** clear filter, **⌘1 / ⌘2 / ⌘3** (or **B / D / Y**) board / conductor / stats, **M** manage tags, **?** help, **Escape** close (from Conductor or Stats: back to Board).

### Deep Linking

Clicking an agent routes you back to its source. The level of support depends on the terminal:

| Terminal | Activate app | Select tab | Select surface | Permission popover | Method |
|----------|:---:|:---:|:---:|:---:|--------|
| **cmux** | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: | JSON-RPC (workspace + surface) |
| **iTerm2** | :white_check_mark: | :white_check_mark: | | | AppleScript (by TTY) |
| **Terminal.app** | :white_check_mark: | :white_check_mark: | | | AppleScript (by TTY) |
| **Ghostty** | :white_check_mark: | :white_check_mark: | | | AppleScript (by working directory) |
| **VS Code** | :white_check_mark: | | | | URL scheme |
| **Cursor** | :white_check_mark: | | | | URL scheme |
| **Kitty** | :white_check_mark: | | | | |
| **WezTerm** | :white_check_mark: | | | | |
| **Warp** | :white_check_mark: | | | | |
| **Hyper** | :white_check_mark: | | | | |
| **Claude Desktop** | :white_check_mark: | | | | |

cmux provides the deepest integration — it can navigate to the exact workspace, tab, and surface (split pane) where the agent is running. With cmux, clicking a permission-state agent opens a popover showing the full tool request and a "Go to Agent" button to jump directly to the permission prompt. Any terminal not listed above still gets app-level activation via process tree detection.

### Loop / Cron Support

Agents that create a loop or cron schedule (via the `/loop` or `/schedule` commands) get a clock badge on their sprite. Loop sessions auto-hide when idle and quiet (done, no errors) and reappear if errors occur. Loop state persists across app restarts.

**Tip:** Loop commands should explicitly ask the user a question or request permission when action is required — this ensures the agent surfaces in the HUD at the right time.

### Sound Effects

ClaudeBlobs can play per-state audio alerts: a sound when an agent starts, waits, requests permission, or finishes. Toggle and configure sounds in **Alert Settings** from the menu bar.

### Customization

All settings are accessible from the menu bar icon:

- **Color Themes** — 7 built-in themes: Traffic Light, Ocean Depths, Sunset Boulevard, Neon Nights, Forest Floor, Candy Apple, Firecracker
- **Push Notifications** — [ntfy.sh](https://ntfy.sh) integration with configurable endpoint, topic, delay, and per-state priorities
- **Sound Effects** — per-state audio alerts, toggleable
- **Idle Threshold** — how long before an idle agent shows X-eyes and desaturates
- **Screen Placement** — show blobs on all displays, primary only, or all except primary
- **Visibility** — hide working agents, hide when collapsed, sort by priority, prominent state change animations
- **App Icons** — show host app icons on agent cards (always, when expanded, or never)

## How It Works

ClaudeBlobs collects agent state from two providers:

- Claude Code shell hooks write JSON status files into `~/.claude/agent-status/`
- The bundled OpenCode plugin writes matching JSON status files into `~/.opencode/agent-status/`

The app watches both directories and renders a single combined HUD.

Deep linking is determined by process ancestry — the app walks the process tree from the agent PID to find whether it belongs to a cmux session, a terminal emulator, an editor, or Claude Desktop.

## Uninstall

Use **Uninstall Hooks & Quit** from the menu bar, then delete the app from `/Applications`. Or manually:

```sh
rm -rf /Applications/ClaudeBlobs.app
rm -rf ~/.claude/agent-status
rm -rf ~/.opencode/agent-status
rm -f ~/.config/opencode/plugins/claudeblobs-opencode.js
```

Then remove the hook entries from `~/.claude/settings.json`.
