# ClaudeBlobs

A macOS menu bar app that monitors your running Claude Code and OpenCode agent sessions and lets you jump back to them with a keystroke.

![macOS](https://img.shields.io/badge/macOS-13%2B-blue)

## What It Does

ClaudeBlobs watches for active Claude Code and OpenCode agent sessions and displays them as animated sprite faces floating at the top of your screen. Each face reflects what the agent is doing — working, waiting for input, or asking for permission — so you can keep tabs on multiple agents at a glance.

![ClaudeBlobsDemo](https://github.com/user-attachments/assets/cfd74efd-567f-4617-ad24-3f4d99013d0d)

Click a face or use the keyboard picker to deep-link straight back to the terminal, cmux workspace, Superset workspace, or Claude Desktop session that spawned it.

For a bigger picture, the **Blob Board** (⌃⌥B) opens a kanban view of every session with tags, stats, and a **Conductor** that ranks what needs your attention next and can reply into sessions for you.

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

**Accessibility** — macOS will prompt for Accessibility permission the first time you use keyboard navigation in the agent picker (Tab, arrow keys, number keys), and again the first time the Conductor answers a multiple-choice question in a Superset session (it focuses the terminal and presses the keys for you; the Superset CLI can only paste text, which the question menu ignores). The global hotkey works without it. Ad-hoc dev builds lose the grant on every rebuild; re-approve the prompt or run `tccutil reset Accessibility com.local.ClaudeBlobs`.

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
- **Override** an agent's state with **E** (Waiting / Starting / Working); the override clears when the agent's real state changes
- **Snooze** agents until their next message (the default), or for 30 min, 1 h, 3 h, tomorrow 8 AM, or next week; a snoozed agent wakes early when its state changes. Dismiss to remove entirely. Every snooze menu — HUD, board card, Conductor — is the same one: **↑ ↓ / J K** move, **Return** picks, **1–6** picks directly, **Escape** closes
- When more than nine agents are open, click the **+n** indicator in the expanded view to reveal the extra rows
- **Use Conductor Order** (*Blob Settings*) sorts the HUD by the Conductor's ranking instead of by status priority. Sessions the Conductor has not ranked (working, starting) keep their usual order behind the ranked ones; sessions the Conductor marked as still running sort last and are dimmed like a snoozed blob, so they stay visible without asking for attention. With no Conductor scores yet, the HUD order is unchanged

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
| Clock badge | Loop / cron schedule, Monitor task, or scheduled wakeup active (click to dismiss) |
| Blue spinning ring | Delegating to subagent |

### Keyboard Navigation

- **Ctrl+Option+A** — global hotkey to open the agent picker (customizable)
- **Tab / Shift+Tab / Arrow keys** — cycle through agents
- **Enter** — jump to the selected agent
- **Shift+Enter** — open the permission popover for the selected agent (cmux only)
- **R** — rename; **E** — override state (then **1 / 2 / 3**)
- **Backspace** — choose a snooze duration (**1–6**); when already snoozed, dismiss
- **Escape** — close the picker

### Blob Board

**Ctrl+Option+B** (change it under *Change Board Hotkey…*) opens the Blob Board, a full-size kanban board in its own window. Cards are grouped into columns — Idle, Needs Attention, Working, Monitoring, Snoozed — and sorted by how long each agent has been in that column (oldest at top). Each card shows the agent's latest message and tool call, its location, sub-agents, and tags. Click a card (or press Enter) to deep-link to the agent and close the board.

**Tags.** Tag cards with any of the preset tags (core task, side task, code review, research, eng request, orchestrator) or add your own in *Manage Tags*. Each tag carries a description that explains what it means and how to recognize it. When a new session is first seen, ClaudeBlobs runs a small non-interactive `claude -p --model haiku` call against the session's first prompt and proposes one tag. Inferred tags show as a dashed outline with a `?`; confirmed tags are filled. Open the tag editor (press `T` on the card) and choose the tag to confirm it. The tag filter in the header persists across board openings.

**Modes.** The header's segmented control switches between **Board**, **Conductor**, and **Stats** (**⌘1 / ⌘2 / ⌘3**); the board reopens in the last mode used.

**Conductor.** Ranks every session that is waiting on you (Needs Attention, then Idle) and walks you through them. Each session is scored once by a `claude -p --model sonnet` call from its tags, repo, first prompt, pending tool, last message, and your instructions; the score is cached per input fingerprint, so new or changed sessions cost one call and everything else is re-sorted locally (AI score + a working-hours wait boost − a skip penalty). The top item shows the session's message (rendered as Markdown), the reasoning, and a proposed action: an editable reply, an approval, or — when the agent asked a multiple-choice question — the enumerated options. Send it straight into a Superset or cmux session with **⌘Return** (Superset option answers are sent as key presses after deep-linking to the terminal; cmux uses its socket), or just **Open** / **Skip** / **Snooze**. *Instructions…* lets you rewrite how the Conductor prioritizes; *Re-analyze* re-scores everything.

**Still running.** A session can read as idle while work is still in flight — a background task, an armed monitor, a long shell command, a pull request waiting on CI. The Conductor marks those *in flight* and keeps them out of the queue; the header shows a **n in flight** pill that puts them back (they sort behind everything else). A session that asks a question, requests permission, hit an error, or was interrupted is never treated as in flight, so anything that needs you still surfaces.

A session must sit in Needs Attention or Idle for 15 seconds before the Conductor admits it, so blobs that flash idle between background turns never show up. Plan approvals are never auto-approved. Conductor keys: **↑ ↓ / J K** walk the queue, **Return** open, **1–9** choose an option, **⌥1–9** choose and send, **⌘Return** send, **S** skip, **Z** snooze (then **↑ ↓ / Return** or **1–6**), **I** instructions, **R** re-analyze. **Escape** ends editing in the reply box; while the box is empty, arrows and Return still control the board.

**Stats.** The Stats mode stacks two sections: *Stats* — a trailing 24h / 7d window (**1 / 2**) with tiles and charts for concurrent sessions over time, sessions started, sessions by tag, and Idle / Needs Attention wait-time spreads (median / p75 / max / mean, counting working hours only: Mon–Fri 09:00–17:00); *History* — 7 / 30 / 90 days (**3 / 4 / 5**) with sessions per day stacked by tag, sessions by tag, top repositories, and a session list. Sessions are recorded to `~/Library/Application Support/ClaudeBlobs/history.json` while the app runs and kept for 90 days.

Board keys: **Arrows / H J K L / Tab** move, **Enter** open, **T** tag editor (**↑↓ / Return** walk and toggle, **1–9** toggle, **C** confirm all inferred, **R** re-infer), **S** snooze, **U** unsnooze, **Backspace** snooze / dismiss, **C** collapse column, **1–9** toggle filter tags, **N** untagged filter, **0** clear filter, **⌘1 / ⌘2 / ⌘3** board / conductor / stats, **M** manage tags, **?** help, **Escape** close (from Conductor or Stats: back to Board). *Close Board After Deep Link* in the menu bar controls whether opening a session also closes the board.

### Deep Linking

Clicking an agent routes you back to its source. The level of support depends on the terminal:

| Terminal | Activate app | Select tab | Select surface | Permission popover | Method |
|----------|:---:|:---:|:---:|:---:|--------|
| **cmux** | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: | JSON-RPC (workspace + surface) |
| **Superset** | :white_check_mark: | :white_check_mark: | :white_check_mark: | | URL scheme (workspace + terminal); Conductor replies via the `superset` CLI |
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

### Loop / Cron / Monitor Support

Agents that create a loop or cron schedule (via the `/loop` or `/schedule` commands), run a `Monitor` task, or schedule a wakeup get a clock badge on their sprite. These sessions auto-hide when idle and quiet (done, no errors), reappear if errors occur, and land in the board's Monitoring column. Loop state persists across app restarts; click the clock badge to dismiss it.

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
- **Board** — *Open Blob Board*, *Close Board After Deep Link*, *Change Board Hotkey…*
- **Appearance** — the HUD and all windows always render in dark mode, regardless of the system setting

## How It Works

ClaudeBlobs collects agent state from two providers:

- Claude Code shell hooks write JSON status files into `~/.claude/agent-status/`
- The bundled OpenCode plugin writes matching JSON status files into `~/.opencode/agent-status/`

The app watches both directories and renders a single combined HUD. Besides status, the hooks record each session's first prompt (`firstPrompt`), any pending multiple-choice question (`pendingQuestions`), and Monitor activity (`monitorActive`).

The board keeps its own state in `~/Library/Application Support/ClaudeBlobs/`: `tags.json` (tags, assignments, filter), `history.json` (90 days of sessions and wait episodes), and `conductor.json` (cached scores and your instructions).

**AI calls.** Two features run `claude -p` under your own Claude Code login: tag inference sends a new session's first prompt to `haiku` once; the Conductor sends a waiting session's tags, repo, first prompt, pending tool, and last message to `sonnet` once per change. Nothing leaves the machine otherwise. Turn them off under *Manage Tags → Auto-infer tags* and *Conductor → Instructions… → Use AI scoring*. `history.json` keeps the first 200 characters of each first prompt for 90 days.

Deep linking is determined by process ancestry — the app walks the process tree from the agent PID to find whether it belongs to a cmux session, a terminal emulator, an editor, or Claude Desktop.

## Uninstall

Use **Uninstall Hooks & Quit** from the menu bar, then delete the app from `/Applications`. Or manually:

```sh
rm -rf /Applications/ClaudeBlobs.app
rm -rf ~/.claude/agent-status
rm -rf ~/.opencode/agent-status
rm -f ~/.config/opencode/plugins/claudeblobs-opencode.js
rm -rf ~/Library/Application\ Support/ClaudeBlobs
```

Then remove the hook entries from `~/.claude/settings.json`.
