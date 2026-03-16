# Claude Agent HUD Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS floating panel that shows pixel art characters representing running Claude Code agent sessions, with status-based colors/animations and click-to-jump deep linking.

**Architecture:** Single SwiftUI + AppKit app built with Swift Package Manager. Hook shell scripts write per-session JSON status files to `~/.claude/agent-status/`. The app watches that directory and renders a floating NSPanel with collapsed (menu bar height) and expanded (hover) states. An assembly script packages everything into a proper .app bundle.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit (NSPanel), Swift Package Manager, shell scripts (hooks), macOS 13+

**Spec:** `docs/superpowers/specs/2026-03-16-claude-agent-hud-design.md`

---

## File Structure

```
ClaudeAgentHUD/
├── Package.swift                              # SPM manifest: library + executable + test targets
├── Makefile                                   # Build + assemble .app bundle
├── Sources/
│   ├── App/
│   │   └── main.swift                         # App entry point (manual NSApp setup)
│   └── Lib/
│       ├── AppDelegate.swift                  # NSPanel creation, login item, tracking area
│       ├── Models/
│       │   ├── Agent.swift                    # Agent data model (Codable, Sendable struct)
│       │   └── AgentStatus.swift              # Status enum with color/display properties
│       ├── Store/
│       │   ├── AgentStore.swift               # ObservableObject, reads status dir, PID cleanup
│       │   └── StatusFileWatcher.swift        # DispatchSource + Timer wrapper
│       ├── Views/
│       │   ├── HUDPanel.swift                 # NSPanel subclass (non-activating, floating)
│       │   ├── HUDContentView.swift           # Root SwiftUI view (switches collapsed/expanded)
│       │   ├── CollapsedView.swift            # Pill with small sprites
│       │   ├── ExpandedView.swift             # Cards with speech bubbles
│       │   ├── AgentSpriteView.swift          # Animated sprite renderer
│       │   └── SpeechBubbleView.swift         # Truncated message bubble
│       ├── DeepLink/
│       │   ├── DeepLinker.swift               # Router: cmux vs terminal vs desktop
│       │   ├── CmuxLinker.swift               # cmux select-workspace/surface
│       │   └── TerminalLinker.swift           # Process tree walking, NSWorkspace activation
│       └── Setup/
│           ├── HookInstaller.swift            # Read/write ~/.claude/settings.json
│           └── Uninstaller.swift              # Remove hooks, cleanup, deregister
├── Resources/
│   ├── Info.plist                             # LSUIElement=true, bundle ID, version
│   └── hooks/
│       ├── hook-session-start.sh
│       ├── hook-user-prompt.sh
│       ├── hook-pre-tool.sh
│       ├── hook-stop.sh
│       ├── hook-permission.sh
│       ├── hook-notification.sh
│       └── hook-session-end.sh
├── Tests/
│   ├── AgentTests.swift                       # Agent model decoding tests
│   ├── AgentStatusTests.swift                 # Status enum property tests
│   ├── AgentStoreTests.swift                  # File reading, PID cleanup logic
│   ├── HookInstallerTests.swift               # Settings.json merge/idempotency tests
│   └── DeepLinkerTests.swift                  # Route selection logic tests
└── Fixtures/
    ├── sample-agent-waiting.json              # Test fixture
    ├── sample-agent-working.json              # Test fixture
    ├── sample-agent-permission.json           # Test fixture
    └── sample-settings.json                   # Test fixture for hook installer
```

---

## Chunk 1: Project Scaffolding + Data Models

### Task 1: Create SPM project structure

**Files:**
- Create: `ClaudeAgentHUD/Package.swift`
- Create: `ClaudeAgentHUD/Sources/App/main.swift`
- Create: `ClaudeAgentHUD/Resources/Info.plist`
- Create: `ClaudeAgentHUD/Makefile`

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p ClaudeAgentHUD/Sources/App
mkdir -p ClaudeAgentHUD/Sources/Lib/{Models,Store,Views,DeepLink,Setup}
mkdir -p ClaudeAgentHUD/Resources/hooks
mkdir -p ClaudeAgentHUD/Tests
mkdir -p ClaudeAgentHUD/Fixtures
```

- [ ] **Step 2: Create Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeAgentHUD",
    platforms: [.macOS(.v13)],
    targets: [
        // Library target: all app logic, testable
        .target(
            name: "ClaudeAgentHUDLib",
            path: "Sources/Lib"
        ),
        // Executable target: just the entry point
        .executableTarget(
            name: "ClaudeAgentHUD",
            dependencies: ["ClaudeAgentHUDLib"],
            path: "Sources/App"
        ),
        .testTarget(
            name: "ClaudeAgentHUDTests",
            dependencies: ["ClaudeAgentHUDLib"],
            path: "Tests"
        ),
    ]
)
```

Note: Resources (Info.plist, hooks) are NOT managed by SPM — the `Makefile` handles copying them into the `.app` bundle. Test fixtures are loaded by path in tests.

- [ ] **Step 3: Create minimal main.swift** (in `Sources/App/`)

```swift
import AppKit
import ClaudeAgentHUDLib

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 4: Create stub AppDelegate.swift** (in `Sources/Lib/`)

```swift
import AppKit
import SwiftUI

public class AppDelegate: NSObject, NSApplicationDelegate {
    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // No dock icon
    }
}
```

- [ ] **Step 5: Create Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.local.ClaudeAgentHUD</string>
    <key>CFBundleName</key>
    <string>Claude Agent HUD</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>ClaudeAgentHUD</string>
</dict>
</plist>
```

- [ ] **Step 6: Create Makefile**

```makefile
APP_NAME = Claude Agent HUD
BUNDLE_NAME = ClaudeAgentHUD.app
BUILD_DIR = .build/release
BUNDLE_DIR = $(BUILD_DIR)/$(BUNDLE_NAME)

.PHONY: build bundle clean run

build:
	swift build -c release

bundle: build
	rm -rf "$(BUNDLE_DIR)"
	mkdir -p "$(BUNDLE_DIR)/Contents/MacOS"
	mkdir -p "$(BUNDLE_DIR)/Contents/Resources/hooks"
	cp "$(BUILD_DIR)/ClaudeAgentHUD" "$(BUNDLE_DIR)/Contents/MacOS/"
	cp Resources/Info.plist "$(BUNDLE_DIR)/Contents/"
	cp Resources/hooks/*.sh "$(BUNDLE_DIR)/Contents/Resources/hooks/"
	chmod +x "$(BUNDLE_DIR)/Contents/Resources/hooks/"*.sh

install: bundle
	cp -R "$(BUNDLE_DIR)" /Applications/
	@echo "Installed to /Applications/$(BUNDLE_NAME)"

clean:
	swift package clean
	rm -rf "$(BUNDLE_DIR)"

run: bundle
	open "$(BUNDLE_DIR)"
```

- [ ] **Step 7: Verify project builds**

Run: `cd ClaudeAgentHUD && swift build 2>&1`
Expected: Build succeeds (warnings OK, no errors)

- [ ] **Step 8: Commit**

```bash
git add ClaudeAgentHUD/
git commit -m "feat: scaffold ClaudeAgentHUD SPM project with Makefile"
```

---

### Task 2: Agent data model and status enum

**Files:**
- Create: `ClaudeAgentHUD/Sources/Lib/Models/AgentStatus.swift`
- Create: `ClaudeAgentHUD/Sources/Lib/Models/Agent.swift`
- Create: `ClaudeAgentHUD/Tests/AgentStatusTests.swift`
- Create: `ClaudeAgentHUD/Tests/AgentTests.swift`
- Create: `ClaudeAgentHUD/Fixtures/sample-agent-waiting.json`
- Create: `ClaudeAgentHUD/Fixtures/sample-agent-working.json`
- Create: `ClaudeAgentHUD/Fixtures/sample-agent-permission.json`

- [ ] **Step 1: Write AgentStatus tests**

```swift
import Testing
@testable import ClaudeAgentHUDLib

@Suite("AgentStatus")
struct AgentStatusTests {
    @Test func decodesFromJSON() throws {
        let json = #""waiting""#.data(using: .utf8)!
        let status = try JSONDecoder().decode(AgentStatus.self, from: json)
        #expect(status == .waiting)
    }

    @Test func allCasesHaveColor() {
        for status in AgentStatus.allCases {
            #expect(status.color.description.isEmpty == false)
        }
    }

    @Test func visibleInCollapsed() {
        #expect(AgentStatus.waiting.visibleWhenCollapsed == true)
        #expect(AgentStatus.permission.visibleWhenCollapsed == true)
        #expect(AgentStatus.starting.visibleWhenCollapsed == true)
        #expect(AgentStatus.working.visibleWhenCollapsed == false)
    }

    @Test func speechBubbleText() {
        let waiting = Agent.fixture(status: .waiting, lastMessage: "Done. Want me to continue?", lastToolUse: "Edit foo.swift")
        #expect(waiting.speechBubbleText == "Done. Want me to continue?")

        let working = Agent.fixture(status: .working, lastMessage: nil, lastToolUse: "Editing auth.ts")
        #expect(working.speechBubbleText == "Editing auth.ts")

        let permission = Agent.fixture(status: .permission, lastMessage: nil, lastToolUse: "Bash: rm -rf build/")
        #expect(permission.speechBubbleText == "Wants to run: Bash: rm -rf build/")

        let starting = Agent.fixture(status: .starting, lastMessage: nil, lastToolUse: nil)
        #expect(starting.speechBubbleText == "Starting up...")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ClaudeAgentHUD && swift test 2>&1 | tail -20`
Expected: Compilation errors (AgentStatus not defined)

- [ ] **Step 3: Write AgentStatus.swift**

```swift
import SwiftUI

enum AgentStatus: String, Codable, CaseIterable {
    case starting
    case working
    case waiting
    case permission

    var color: Color {
        switch self {
        case .starting:   return Color(red: 0.204, green: 0.780, blue: 0.349)  // #34C759
        case .working:    return Color(red: 0.298, green: 0.553, blue: 1.0)    // #4C8DFF
        case .waiting:    return Color(red: 1.0, green: 0.584, blue: 0.0)      // #FF9500
        case .permission: return Color(red: 1.0, green: 0.231, blue: 0.188)    // #FF3B30
        }
    }

    var visibleWhenCollapsed: Bool {
        switch self {
        case .waiting, .permission, .starting: return true
        case .working: return false
        }
    }

    var displayName: String {
        switch self {
        case .starting:   return "Starting"
        case .working:    return "Working"
        case .waiting:    return "Waiting"
        case .permission: return "Needs Permission"
        }
    }
}
```

- [ ] **Step 4: Write Agent model tests**

```swift
import Testing
import Foundation
@testable import ClaudeAgentHUDLib

@Suite("Agent")
struct AgentTests {
    @Test func decodesFromJSON() throws {
        let json = """
        {
            "sessionId": "abc-123",
            "pid": 12345,
            "cwd": "/Users/test/SourceCode/android",
            "agentType": "neovim-coach",
            "status": "waiting",
            "lastMessage": "I've updated the keybinding.",
            "lastToolUse": null,
            "cmuxWorkspace": "ws:abc",
            "cmuxSurface": "surface:def",
            "updatedAt": 1773687200000
        }
        """.data(using: .utf8)!

        let agent = try JSONDecoder().decode(Agent.self, from: json)
        #expect(agent.sessionId == "abc-123")
        #expect(agent.pid == 12345)
        #expect(agent.status == .waiting)
        #expect(agent.cmuxWorkspace == "ws:abc")
        #expect(agent.agentType == "neovim-coach")
    }

    @Test func decodesWithNulls() throws {
        let json = """
        {
            "sessionId": "abc-123",
            "pid": 99,
            "cwd": "/tmp",
            "status": "working",
            "updatedAt": 1000
        }
        """.data(using: .utf8)!

        let agent = try JSONDecoder().decode(Agent.self, from: json)
        #expect(agent.agentType == nil)
        #expect(agent.lastMessage == nil)
        #expect(agent.cmuxWorkspace == nil)
    }

    @Test func directoryLabel() {
        let agent = Agent.fixture(cwd: "/Users/test/SourceCode/android")
        #expect(agent.directoryLabel == "android")
    }

    @Test func directoryLabelForDesktop() {
        let agent = Agent.fixture(cwd: nil)
        #expect(agent.directoryLabel == "APP")
    }

    @Test func directoryLabelPrefersAgentType() {
        let agent = Agent.fixture(cwd: "/Users/test/.config/nvim", agentType: "neovim-coach")
        #expect(agent.directoryLabel == "neovim-coach")
    }

    @Test func isCmuxSession() {
        let cmux = Agent.fixture(cmuxWorkspace: "ws:abc", cmuxSurface: "surface:def")
        #expect(cmux.isCmuxSession == true)

        let plain = Agent.fixture(cmuxWorkspace: nil, cmuxSurface: nil)
        #expect(plain.isCmuxSession == false)
    }
}
```

- [ ] **Step 5: Write Agent.swift**

```swift
import Foundation

struct Agent: Codable, Identifiable, Equatable, Sendable {
    let sessionId: String
    let pid: Int
    let cwd: String?
    var agentType: String?
    var status: AgentStatus
    var lastMessage: String?
    var lastToolUse: String?
    var cmuxWorkspace: String?
    var cmuxSurface: String?
    var updatedAt: Int64

    var id: String { sessionId }

    var directoryLabel: String {
        if let agentType { return agentType }
        guard let cwd else { return "APP" }
        return (cwd as NSString).lastPathComponent
    }

    var speechBubbleText: String {
        switch status {
        case .waiting:
            return lastMessage ?? ""
        case .working:
            return lastToolUse ?? ""
        case .permission:
            if let tool = lastToolUse {
                return "Wants to run: \(tool)"
            }
            return ""
        case .starting:
            return "Starting up..."
        }
    }

    var isCmuxSession: Bool {
        cmuxWorkspace != nil && cmuxSurface != nil
    }
}

extension Agent {
    static func fixture(
        sessionId: String = "test-session",
        pid: Int = 99999,
        cwd: String? = "/tmp/test",
        agentType: String? = nil,
        status: AgentStatus = .working,
        lastMessage: String? = nil,
        lastToolUse: String? = nil,
        cmuxWorkspace: String? = nil,
        cmuxSurface: String? = nil,
        updatedAt: Int64 = 1000
    ) -> Agent {
        Agent(
            sessionId: sessionId, pid: pid, cwd: cwd,
            agentType: agentType, status: status,
            lastMessage: lastMessage, lastToolUse: lastToolUse,
            cmuxWorkspace: cmuxWorkspace, cmuxSurface: cmuxSurface,
            updatedAt: updatedAt
        )
    }
}
```

- [ ] **Step 6: Create test fixture files**

`Fixtures/sample-agent-waiting.json`:
```json
{
    "sessionId": "wait-001",
    "pid": 10001,
    "cwd": "/Users/test/SourceCode/android",
    "agentType": null,
    "status": "waiting",
    "lastMessage": "I've updated the keybinding. Want me to continue?",
    "lastToolUse": "Edit config.lua",
    "cmuxWorkspace": "ws:abc",
    "cmuxSurface": "surface:def",
    "updatedAt": 1773687200000
}
```

`Fixtures/sample-agent-working.json`:
```json
{
    "sessionId": "work-002",
    "pid": 10002,
    "cwd": "/Users/test/SourceCode/ios-app",
    "status": "working",
    "lastToolUse": "Editing auth.ts",
    "updatedAt": 1773687201000
}
```

`Fixtures/sample-agent-permission.json`:
```json
{
    "sessionId": "perm-003",
    "pid": 10003,
    "cwd": "/Users/test/SourceCode/scripts",
    "status": "permission",
    "lastToolUse": "Bash: rm -rf build/",
    "updatedAt": 1773687202000
}
```

- [ ] **Step 7: Run tests**

Run: `cd ClaudeAgentHUD && swift test 2>&1 | tail -30`
Expected: All tests pass

- [ ] **Step 8: Commit**

```bash
git add ClaudeAgentHUD/Sources/Lib/Models/ ClaudeAgentHUD/Tests/ ClaudeAgentHUD/Fixtures/
git commit -m "feat: add Agent model and AgentStatus enum with tests"
```

---

## Chunk 2: Hook Scripts + Hook Installer

### Task 3: Write all 7 hook shell scripts

**Files:**
- Create: `ClaudeAgentHUD/Resources/hooks/hook-session-start.sh`
- Create: `ClaudeAgentHUD/Resources/hooks/hook-user-prompt.sh`
- Create: `ClaudeAgentHUD/Resources/hooks/hook-pre-tool.sh`
- Create: `ClaudeAgentHUD/Resources/hooks/hook-stop.sh`
- Create: `ClaudeAgentHUD/Resources/hooks/hook-permission.sh`
- Create: `ClaudeAgentHUD/Resources/hooks/hook-notification.sh`
- Create: `ClaudeAgentHUD/Resources/hooks/hook-session-end.sh`

- [ ] **Step 1: Write hook-session-start.sh**

This is the most complex hook — creates the initial status file.

```bash
#!/bin/bash
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
STATUS_DIR="$HOME/.claude/agent-status"
mkdir -p "$STATUS_DIR"
STATUS_FILE="$STATUS_DIR/$SESSION_ID.json"

CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // empty')
PID=$PPID
TS=$(date +%s000)

# Capture cmux IDs from environment if present
CMUX_WS="${CMUX_WORKSPACE:-}"
CMUX_SF="${CMUX_SURFACE:-}"

jq -n \
  --arg sid "$SESSION_ID" \
  --argjson pid "$PID" \
  --arg cwd "$CWD" \
  --arg agentType "$AGENT_TYPE" \
  --arg status "starting" \
  --arg cmuxWs "$CMUX_WS" \
  --arg cmuxSf "$CMUX_SF" \
  --argjson ts "$TS" \
  '{
    sessionId: $sid,
    pid: $pid,
    cwd: (if $cwd == "" then null else $cwd end),
    agentType: (if $agentType == "" then null else $agentType end),
    status: $status,
    lastMessage: null,
    lastToolUse: null,
    cmuxWorkspace: (if $cmuxWs == "" then null else $cmuxWs end),
    cmuxSurface: (if $cmuxSf == "" then null else $cmuxSf end),
    updatedAt: $ts
  }' > "$STATUS_FILE.tmp" && mv "$STATUS_FILE.tmp" "$STATUS_FILE"
```

- [ ] **Step 2: Write hook-user-prompt.sh**

```bash
#!/bin/bash
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
STATUS_DIR="$HOME/.claude/agent-status"
mkdir -p "$STATUS_DIR"
STATUS_FILE="$STATUS_DIR/$SESSION_ID.json"

TS=$(date +%s000)

if [ -f "$STATUS_FILE" ]; then
  jq --arg ts "$TS" \
    '.status = "working" | .lastMessage = null | .updatedAt = ($ts | tonumber)' \
    "$STATUS_FILE" > "$STATUS_FILE.tmp" && mv "$STATUS_FILE.tmp" "$STATUS_FILE"
fi
```

- [ ] **Step 3: Write hook-pre-tool.sh**

```bash
#!/bin/bash
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
STATUS_DIR="$HOME/.claude/agent-status"
mkdir -p "$STATUS_DIR"
STATUS_FILE="$STATUS_DIR/$SESSION_ID.json"

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "Unknown"')
# Extract a short summary from tool_input (first 80 chars of stringified input)
TOOL_SUMMARY=$(echo "$INPUT" | jq -r '.tool_input // {} | tostring' | head -c 80)
TOOL_DESC="$TOOL_NAME"
if [ -n "$TOOL_SUMMARY" ] && [ "$TOOL_SUMMARY" != "{}" ]; then
  TOOL_DESC="$TOOL_NAME: $TOOL_SUMMARY"
fi

TS=$(date +%s000)

if [ -f "$STATUS_FILE" ]; then
  jq --arg ts "$TS" --arg tool "$TOOL_DESC" \
    '.status = "working" | .lastToolUse = $tool | .updatedAt = ($ts | tonumber)' \
    "$STATUS_FILE" > "$STATUS_FILE.tmp" && mv "$STATUS_FILE.tmp" "$STATUS_FILE"
fi
```

- [ ] **Step 4: Write hook-stop.sh**

```bash
#!/bin/bash
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
STATUS_DIR="$HOME/.claude/agent-status"
mkdir -p "$STATUS_DIR"
STATUS_FILE="$STATUS_DIR/$SESSION_ID.json"

# Extract first sentence (up to first period, question mark, or newline), max 200 chars
LAST_MSG=$(echo "$INPUT" | jq -r '.last_assistant_message // ""' | tr '\n' ' ' | sed 's/[.?!].*/&/' | head -c 200)

TS=$(date +%s000)

if [ -f "$STATUS_FILE" ]; then
  jq --arg ts "$TS" --arg msg "$LAST_MSG" \
    '.status = "waiting" | .lastMessage = $msg | .updatedAt = ($ts | tonumber)' \
    "$STATUS_FILE" > "$STATUS_FILE.tmp" && mv "$STATUS_FILE.tmp" "$STATUS_FILE"
fi
```

- [ ] **Step 5: Write hook-permission.sh**

```bash
#!/bin/bash
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
STATUS_DIR="$HOME/.claude/agent-status"
mkdir -p "$STATUS_DIR"
STATUS_FILE="$STATUS_DIR/$SESSION_ID.json"

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "Unknown"')
TOOL_SUMMARY=$(echo "$INPUT" | jq -r '.tool_input // {} | tostring' | head -c 80)
TOOL_DESC="$TOOL_NAME"
if [ -n "$TOOL_SUMMARY" ] && [ "$TOOL_SUMMARY" != "{}" ]; then
  TOOL_DESC="$TOOL_NAME: $TOOL_SUMMARY"
fi

TS=$(date +%s000)

if [ -f "$STATUS_FILE" ]; then
  jq --arg ts "$TS" --arg tool "$TOOL_DESC" \
    '.status = "permission" | .lastToolUse = $tool | .updatedAt = ($ts | tonumber)' \
    "$STATUS_FILE" > "$STATUS_FILE.tmp" && mv "$STATUS_FILE.tmp" "$STATUS_FILE"
fi
```

- [ ] **Step 6: Write hook-notification.sh**

```bash
#!/bin/bash
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
STATUS_DIR="$HOME/.claude/agent-status"
mkdir -p "$STATUS_DIR"
STATUS_FILE="$STATUS_DIR/$SESSION_ID.json"

TS=$(date +%s000)

if [ -f "$STATUS_FILE" ]; then
  jq --arg ts "$TS" \
    '.updatedAt = ($ts | tonumber)' \
    "$STATUS_FILE" > "$STATUS_FILE.tmp" && mv "$STATUS_FILE.tmp" "$STATUS_FILE"
fi
```

- [ ] **Step 7: Write hook-session-end.sh**

```bash
#!/bin/bash
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
STATUS_DIR="$HOME/.claude/agent-status"
STATUS_FILE="$STATUS_DIR/$SESSION_ID.json"

rm -f "$STATUS_FILE"
```

- [ ] **Step 8: Make all hooks executable and verify syntax**

Run: `chmod +x ClaudeAgentHUD/Resources/hooks/*.sh && bash -n ClaudeAgentHUD/Resources/hooks/*.sh && echo "All hooks valid"`
Expected: "All hooks valid"

- [ ] **Step 9: Commit**

```bash
git add ClaudeAgentHUD/Resources/hooks/
git commit -m "feat: add 7 hook scripts for agent status tracking"
```

---

### Task 4: Hook installer (read/write settings.json)

**Files:**
- Create: `ClaudeAgentHUD/Sources/Lib/Setup/HookInstaller.swift`
- Create: `ClaudeAgentHUD/Sources/Lib/Setup/Uninstaller.swift`
- Create: `ClaudeAgentHUD/Tests/HookInstallerTests.swift`
- Create: `ClaudeAgentHUD/Fixtures/sample-settings.json`

- [ ] **Step 1: Write test fixture**

`Fixtures/sample-settings.json`:
```json
{
  "permissions": {
    "allow": ["Read"],
    "deny": []
  },
  "hooks": {
    "UserPromptSubmit": [
      { "type": "command", "command": "echo existing-hook" }
    ]
  }
}
```

- [ ] **Step 2: Write HookInstaller tests**

```swift
import Testing
import Foundation
@testable import ClaudeAgentHUDLib

@Suite("HookInstaller")
struct HookInstallerTests {
    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("hud-test-\(UUID().uuidString)")

    func settingsPath() -> URL {
        tmpDir.appendingPathComponent("settings.json")
    }

    init() throws {
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    @Test func installsHooksIntoEmptySettings() throws {
        let path = settingsPath()
        try "{}".write(to: path, atomically: true, encoding: .utf8)

        let installer = HookInstaller(settingsPath: path, hooksDir: "/fake/hooks")
        try installer.install()

        let data = try Data(contentsOf: path)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = json["hooks"] as! [String: Any]

        #expect(hooks.keys.count == 7)
        #expect(hooks["SessionStart"] != nil)
        #expect(hooks["SessionEnd"] != nil)
    }

    @Test func preservesExistingHooks() throws {
        let path = settingsPath()
        let existing = """
        {"hooks":{"UserPromptSubmit":[{"type":"command","command":"echo existing"}]}}
        """
        try existing.write(to: path, atomically: true, encoding: .utf8)

        let installer = HookInstaller(settingsPath: path, hooksDir: "/fake/hooks")
        try installer.install()

        let data = try Data(contentsOf: path)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = json["hooks"] as! [String: Any]
        let upsHooks = hooks["UserPromptSubmit"] as! [[String: Any]]

        // Should have both: existing + HUD hook
        #expect(upsHooks.count == 2)
        #expect(upsHooks[0]["command"] as? String == "echo existing")
    }

    @Test func isIdempotent() throws {
        let path = settingsPath()
        try "{}".write(to: path, atomically: true, encoding: .utf8)

        let installer = HookInstaller(settingsPath: path, hooksDir: "/fake/hooks")
        try installer.install()
        try installer.install() // second install

        let data = try Data(contentsOf: path)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = json["hooks"] as! [String: Any]
        let startHooks = hooks["SessionStart"] as! [[String: Any]]

        #expect(startHooks.count == 1) // not duplicated
    }

    @Test func uninstallRemovesOnlyHUDHooks() throws {
        let path = settingsPath()
        let existing = """
        {"hooks":{"UserPromptSubmit":[{"type":"command","command":"echo existing"},{"type":"command","command":"/fake/hooks/hook-user-prompt.sh"}]}}
        """
        try existing.write(to: path, atomically: true, encoding: .utf8)

        let installer = HookInstaller(settingsPath: path, hooksDir: "/fake/hooks")
        try installer.uninstall()

        let data = try Data(contentsOf: path)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = json["hooks"] as! [String: Any]
        let upsHooks = hooks["UserPromptSubmit"] as! [[String: Any]]

        #expect(upsHooks.count == 1)
        #expect(upsHooks[0]["command"] as? String == "echo existing")
    }

    @Test func createsSettingsFileIfMissing() throws {
        let path = tmpDir.appendingPathComponent("nonexistent-settings.json")

        let installer = HookInstaller(settingsPath: path, hooksDir: "/fake/hooks")
        try installer.install()

        #expect(FileManager.default.fileExists(atPath: path.path))
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd ClaudeAgentHUD && swift test --filter HookInstaller 2>&1 | tail -10`
Expected: Compilation error (HookInstaller not defined)

- [ ] **Step 4: Write HookInstaller.swift**

```swift
import Foundation

struct HookInstaller {
    let settingsPath: URL
    let hooksDir: String

    static let hookEvents = [
        "SessionStart", "UserPromptSubmit", "PreToolUse",
        "Stop", "PermissionRequest", "Notification", "SessionEnd"
    ]

    static let hookFileNames: [String: String] = [
        "SessionStart": "hook-session-start.sh",
        "UserPromptSubmit": "hook-user-prompt.sh",
        "PreToolUse": "hook-pre-tool.sh",
        "Stop": "hook-stop.sh",
        "PermissionRequest": "hook-permission.sh",
        "Notification": "hook-notification.sh",
        "SessionEnd": "hook-session-end.sh",
    ]

    init(settingsPath: URL? = nil, hooksDir: String? = nil) {
        self.settingsPath = settingsPath
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/settings.json")
        self.hooksDir = hooksDir
            ?? Bundle.main.resourcePath.map { $0 + "/hooks" }
            ?? "/usr/local/share/ClaudeAgentHUD/hooks"
    }

    func install() throws {
        var settings = try loadSettings()
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        for event in Self.hookEvents {
            guard let fileName = Self.hookFileNames[event] else { continue }
            let command = "\(hooksDir)/\(fileName)"
            var eventHooks = hooks[event] as? [[String: Any]] ?? []

            // Idempotency: skip if already present
            let alreadyInstalled = eventHooks.contains { entry in
                (entry["command"] as? String) == command
            }
            if alreadyInstalled { continue }

            eventHooks.append(["type": "command", "command": command])
            hooks[event] = eventHooks
        }

        settings["hooks"] = hooks
        try saveSettings(settings)
    }

    func uninstall() throws {
        var settings = try loadSettings()
        guard var hooks = settings["hooks"] as? [String: Any] else { return }

        for event in Self.hookEvents {
            guard var eventHooks = hooks[event] as? [[String: Any]] else { continue }
            eventHooks.removeAll { entry in
                guard let cmd = entry["command"] as? String else { return false }
                return cmd.hasPrefix(hooksDir)
            }
            if eventHooks.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = eventHooks
            }
        }

        settings["hooks"] = hooks
        try saveSettings(settings)
    }

    private func loadSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsPath.path) else {
            return [:]
        }
        let data = try Data(contentsOf: settingsPath)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    private func saveSettings(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        try FileManager.default.createDirectory(
            at: settingsPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: settingsPath, options: .atomic)
    }
}
```

- [ ] **Step 5: Write Uninstaller.swift**

```swift
import Foundation
import ServiceManagement

struct Uninstaller {
    let statusDir: URL
    let hookInstaller: HookInstaller

    init(
        statusDir: URL? = nil,
        hookInstaller: HookInstaller = HookInstaller()
    ) {
        self.statusDir = statusDir
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/agent-status")
        self.hookInstaller = hookInstaller
    }

    func uninstall() throws {
        try hookInstaller.uninstall()

        if FileManager.default.fileExists(atPath: statusDir.path) {
            try FileManager.default.removeItem(at: statusDir)
        }

        try? SMAppService.mainApp.unregister()
    }
}
```

- [ ] **Step 6: Run tests**

Run: `cd ClaudeAgentHUD && swift test --filter HookInstaller 2>&1 | tail -20`
Expected: All 5 tests pass

- [ ] **Step 7: Commit**

```bash
git add ClaudeAgentHUD/Sources/Lib/Setup/ ClaudeAgentHUD/Tests/HookInstallerTests.swift ClaudeAgentHUD/Fixtures/
git commit -m "feat: add HookInstaller with idempotent install/uninstall"
```

---

## Chunk 3: File Watcher + Agent Store

### Task 5: StatusFileWatcher

**Files:**
- Create: `ClaudeAgentHUD/Sources/Lib/Store/StatusFileWatcher.swift`

- [ ] **Step 1: Write StatusFileWatcher.swift**

```swift
import Foundation

/// Watches a directory for filesystem changes using DispatchSource + fallback timer.
final class StatusFileWatcher {
    private let directoryURL: URL
    private let onChange: () -> Void
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var fallbackTimer: Timer?
    private var fileDescriptor: Int32 = -1

    init(directoryURL: URL, onChange: @escaping () -> Void) {
        self.directoryURL = directoryURL
        self.onChange = onChange
    }

    func start() {
        // Ensure directory exists
        try? FileManager.default.createDirectory(
            at: directoryURL, withIntermediateDirectories: true
        )

        // DispatchSource on directory
        fileDescriptor = open(directoryURL.path, O_EVTONLY)
        if fileDescriptor >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fileDescriptor,
                eventMask: .write,
                queue: .main
            )
            source.setEventHandler { [weak self] in
                self?.onChange()
            }
            source.setCancelHandler { [weak self] in
                if let fd = self?.fileDescriptor, fd >= 0 {
                    close(fd)
                    self?.fileDescriptor = -1
                }
            }
            source.resume()
            dispatchSource = source
        }

        // Fallback 2-second timer
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.onChange()
        }
    }

    func stop() {
        dispatchSource?.cancel()
        dispatchSource = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    deinit {
        stop()
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd ClaudeAgentHUD && swift build 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add ClaudeAgentHUD/Sources/Lib/Store/StatusFileWatcher.swift
git commit -m "feat: add StatusFileWatcher with DispatchSource + timer fallback"
```

---

### Task 6: AgentStore

**Files:**
- Create: `ClaudeAgentHUD/Sources/Lib/Store/AgentStore.swift`
- Create: `ClaudeAgentHUD/Tests/AgentStoreTests.swift`

- [ ] **Step 1: Write AgentStore tests**

```swift
import Testing
import Foundation
@testable import ClaudeAgentHUDLib

@Suite("AgentStore")
struct AgentStoreTests {
    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("hud-store-test-\(UUID().uuidString)")

    init() throws {
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    @Test func loadsAgentsFromDirectory() throws {
        let agent = Agent.fixture(sessionId: "s1", status: .waiting)
        let data = try JSONEncoder().encode(agent)
        try data.write(to: tmpDir.appendingPathComponent("s1.json"))

        let store = AgentStore(statusDirectory: tmpDir, enableWatcher: false, isProcessAlive: { _ in true })
        store.reload()

        #expect(store.agents.count == 1)
        #expect(store.agents.first?.sessionId == "s1")
    }

    @Test func filtersCollapsedAgents() throws {
        let waiting = Agent.fixture(sessionId: "w", status: .waiting)
        let working = Agent.fixture(sessionId: "k", status: .working)
        let perm = Agent.fixture(sessionId: "p", status: .permission)

        for agent in [waiting, working, perm] {
            let data = try JSONEncoder().encode(agent)
            try data.write(to: tmpDir.appendingPathComponent("\(agent.sessionId).json"))
        }

        let store = AgentStore(statusDirectory: tmpDir, enableWatcher: false, isProcessAlive: { _ in true })
        store.reload()

        #expect(store.collapsedAgents.count == 2) // waiting + permission
        #expect(store.agents.count == 3)
    }

    @Test func handlesCorruptedFiles() throws {
        try "not json".write(
            to: tmpDir.appendingPathComponent("bad.json"),
            atomically: true, encoding: .utf8
        )

        let store = AgentStore(statusDirectory: tmpDir, enableWatcher: false, isProcessAlive: { _ in true })
        store.reload()

        #expect(store.agents.isEmpty)
    }

    @Test func sortsByStatusPriority() throws {
        let working = Agent.fixture(sessionId: "w", status: .working)
        let waiting = Agent.fixture(sessionId: "a", status: .waiting)
        let perm = Agent.fixture(sessionId: "p", status: .permission)

        for agent in [working, waiting, perm] {
            let data = try JSONEncoder().encode(agent)
            try data.write(to: tmpDir.appendingPathComponent("\(agent.sessionId).json"))
        }

        let store = AgentStore(statusDirectory: tmpDir, enableWatcher: false, isProcessAlive: { _ in true })
        store.reload()

        // Permission first, then waiting, then working
        #expect(store.agents[0].status == .permission)
        #expect(store.agents[1].status == .waiting)
        #expect(store.agents[2].status == .working)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ClaudeAgentHUD && swift test --filter AgentStore 2>&1 | tail -10`
Expected: Compilation error

- [ ] **Step 3: Write AgentStore.swift**

```swift
import Foundation
import Combine

final class AgentStore: ObservableObject {
    @Published var agents: [Agent] = []

    private let statusDirectory: URL
    private var watcher: StatusFileWatcher?
    private let fileManager = FileManager.default
    private let isProcessAlive: (Int) -> Bool

    /// Agents visible in collapsed state
    var collapsedAgents: [Agent] {
        agents.filter { $0.status.visibleWhenCollapsed }
    }

    /// Whether any agents exist at all
    var hasAgents: Bool { !agents.isEmpty }

    /// Whether any agents need attention
    var hasActionableAgents: Bool { !collapsedAgents.isEmpty }

    init(
        statusDirectory: URL? = nil,
        enableWatcher: Bool = true,
        isProcessAlive: @escaping (Int) -> Bool = { pid in kill(Int32(pid), 0) == 0 }
    ) {
        self.statusDirectory = statusDirectory
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/agent-status")
        self.isProcessAlive = isProcessAlive

        if enableWatcher {
            let watcher = StatusFileWatcher(directoryURL: self.statusDirectory) { [weak self] in
                self?.reload()
            }
            self.watcher = watcher
            watcher.start()
        }

        reload()
    }

    func reload() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: statusDirectory,
            includingPropertiesForKeys: nil
        ) else {
            agents = []
            return
        }

        let decoder = JSONDecoder()
        var loaded: [Agent] = []

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let agent = try? decoder.decode(Agent.self, from: data) else {
                continue
            }
            loaded.append(agent)
        }

        // Clean up stale PIDs
        loaded = loaded.filter { agent in
            let alive = isProcessAlive(agent.pid)
            if !alive {
                try? fileManager.removeItem(
                    at: statusDirectory.appendingPathComponent("\(agent.sessionId).json")
                )
            }
            return alive
        }

        // Sort: permission > waiting > starting > working
        let priority: [AgentStatus: Int] = [
            .permission: 0, .waiting: 1, .starting: 2, .working: 3
        ]
        loaded.sort { (priority[$0.status] ?? 9) < (priority[$1.status] ?? 9) }

        if loaded != agents {
            agents = loaded
        }
    }

    deinit {
        watcher?.stop()
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd ClaudeAgentHUD && swift test --filter AgentStore 2>&1 | tail -20`
Expected: All tests pass (note: PID cleanup test may pass because fixture PIDs don't exist)

- [ ] **Step 5: Commit**

```bash
git add ClaudeAgentHUD/Sources/Lib/Store/ ClaudeAgentHUD/Tests/AgentStoreTests.swift
git commit -m "feat: add AgentStore with file watching and PID cleanup"
```

---

## Chunk 4: Floating Panel + UI Views

### Task 7: HUD Panel (NSPanel subclass)

**Files:**
- Create: `ClaudeAgentHUD/Sources/Lib/Views/HUDPanel.swift`

- [ ] **Step 1: Write HUDPanel.swift**

```swift
import AppKit
import SwiftUI

/// Non-activating floating panel that sits just below the menu bar.
final class HUDPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 22),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
    }

    /// Position the panel top-center of the main screen, just below the menu bar.
    func positionBelowMenuBar() {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let screenFrame = screen.frame

        // visibleFrame.maxY is the bottom of the menu bar
        let menuBarBottom = visibleFrame.maxY
        let x = screenFrame.midX - frame.width / 2
        let y = menuBarBottom - frame.height

        setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Update panel size and reposition.
    func updateSize(width: CGFloat, height: CGFloat) {
        let origin = frame.origin
        let newX = (NSScreen.main?.frame.midX ?? origin.x) - width / 2
        let menuBarBottom = NSScreen.main?.visibleFrame.maxY ?? origin.y
        let newY = menuBarBottom - height

        setFrame(
            NSRect(x: newX, y: newY, width: width, height: height),
            display: true,
            animate: true
        )
    }

    // Allow clicks to pass through transparent areas
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd ClaudeAgentHUD && swift build 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add ClaudeAgentHUD/Sources/Lib/Views/HUDPanel.swift
git commit -m "feat: add HUDPanel NSPanel subclass for floating window"
```

---

### Task 8: Sprite rendering + placeholder sprites

**Files:**
- Create: `ClaudeAgentHUD/Sources/Lib/Views/AgentSpriteView.swift`

- [ ] **Step 1: Write AgentSpriteView.swift**

For v1, render sprites programmatically as colored rounded rectangles with simple face patterns. This avoids needing actual sprite sheet assets during development. The face rendering uses SwiftUI shapes to approximate the pixel art expressions.

```swift
import SwiftUI

/// Renders an animated agent sprite. V1 uses programmatic drawing;
/// future versions can swap in actual sprite sheet assets.
struct AgentSpriteView: View {
    let status: AgentStatus
    let size: CGFloat
    @State private var animationPhase: CGFloat = 0

    var body: some View {
        ZStack {
            // Body
            RoundedRectangle(cornerRadius: size * 0.2)
                .fill(status.color)
                .frame(width: size, height: size)

            // Face
            faceView
                .frame(width: size * 0.7, height: size * 0.5)
        }
        .offset(y: animationOffset)
        .onAppear { startAnimation() }
    }

    @ViewBuilder
    private var faceView: some View {
        switch status {
        case .waiting:
            // °□° surprised/alert
            WaitingFace()
        case .permission:
            // ò_ó alarmed
            PermissionFace()
        case .working:
            // •_• focused
            WorkingFace()
        case .starting:
            // ^‿^ waving
            StartingFace()
        }
    }

    private var animationOffset: CGFloat {
        switch status {
        case .permission:
            return -animationPhase * size * 0.15  // Jump
        case .waiting:
            return -animationPhase * size * 0.08  // Gentle bounce
        case .working:
            return 0
        case .starting:
            return 0
        }
    }

    private func startAnimation() {
        switch status {
        case .permission:
            withAnimation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true)) {
                animationPhase = 1
            }
        case .waiting:
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                animationPhase = 1
            }
        case .working:
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                animationPhase = 1
            }
        case .starting:
            withAnimation(.easeOut(duration: 0.5)) {
                animationPhase = 1
            }
        }
    }
}

// MARK: - Face Components

private struct WaitingFace: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Eyes (wide circles)
                Circle()
                    .fill(.black)
                    .frame(width: w * 0.22, height: w * 0.22)
                    .position(x: w * 0.3, y: h * 0.35)
                Circle()
                    .fill(.black)
                    .frame(width: w * 0.22, height: w * 0.22)
                    .position(x: w * 0.7, y: h * 0.35)
                // Open mouth (square)
                RoundedRectangle(cornerRadius: 1)
                    .fill(.black)
                    .frame(width: w * 0.25, height: w * 0.2)
                    .position(x: w * 0.5, y: h * 0.75)
            }
        }
    }
}

private struct PermissionFace: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Angry/alert eyebrows
                Rectangle()
                    .fill(.black)
                    .frame(width: w * 0.2, height: 2)
                    .rotationEffect(.degrees(-15))
                    .position(x: w * 0.3, y: h * 0.2)
                Rectangle()
                    .fill(.black)
                    .frame(width: w * 0.2, height: 2)
                    .rotationEffect(.degrees(15))
                    .position(x: w * 0.7, y: h * 0.2)
                // Eyes
                Circle()
                    .fill(.black)
                    .frame(width: w * 0.18, height: w * 0.18)
                    .position(x: w * 0.3, y: h * 0.4)
                Circle()
                    .fill(.black)
                    .frame(width: w * 0.18, height: w * 0.18)
                    .position(x: w * 0.7, y: h * 0.4)
                // Tense mouth
                Rectangle()
                    .fill(.black)
                    .frame(width: w * 0.3, height: 2)
                    .position(x: w * 0.5, y: h * 0.75)
            }
        }
    }
}

private struct WorkingFace: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Dot eyes
                Circle()
                    .fill(.black)
                    .frame(width: w * 0.14, height: w * 0.14)
                    .position(x: w * 0.3, y: h * 0.4)
                Circle()
                    .fill(.black)
                    .frame(width: w * 0.14, height: w * 0.14)
                    .position(x: w * 0.7, y: h * 0.4)
                // Flat mouth
                Rectangle()
                    .fill(.black)
                    .frame(width: w * 0.25, height: 2)
                    .position(x: w * 0.5, y: h * 0.7)
            }
        }
    }
}

private struct StartingFace: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Happy eyes (^)
                Path { path in
                    path.move(to: CGPoint(x: w * 0.2, y: h * 0.45))
                    path.addLine(to: CGPoint(x: w * 0.3, y: h * 0.3))
                    path.addLine(to: CGPoint(x: w * 0.4, y: h * 0.45))
                }
                .stroke(.black, lineWidth: 2)
                Path { path in
                    path.move(to: CGPoint(x: w * 0.6, y: h * 0.45))
                    path.addLine(to: CGPoint(x: w * 0.7, y: h * 0.3))
                    path.addLine(to: CGPoint(x: w * 0.8, y: h * 0.45))
                }
                .stroke(.black, lineWidth: 2)
                // Smile
                Path { path in
                    path.addArc(
                        center: CGPoint(x: w * 0.5, y: h * 0.65),
                        radius: w * 0.15,
                        startAngle: .degrees(0),
                        endAngle: .degrees(180),
                        clockwise: false
                    )
                }
                .stroke(.black, lineWidth: 2)
            }
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd ClaudeAgentHUD && swift build 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add ClaudeAgentHUD/Sources/Lib/Views/AgentSpriteView.swift
git commit -m "feat: add AgentSpriteView with programmatic face rendering"
```

---

### Task 9: Speech bubble, collapsed view, expanded view, root content view

**Files:**
- Create: `ClaudeAgentHUD/Sources/Lib/Views/SpeechBubbleView.swift`
- Create: `ClaudeAgentHUD/Sources/Lib/Views/CollapsedView.swift`
- Create: `ClaudeAgentHUD/Sources/Lib/Views/ExpandedView.swift`
- Create: `ClaudeAgentHUD/Sources/Lib/Views/HUDContentView.swift`

- [ ] **Step 1: Write SpeechBubbleView.swift**

```swift
import SwiftUI

struct SpeechBubbleView: View {
    let text: String

    var body: some View {
        if !text.isEmpty {
            Text(text)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                )
                .frame(maxWidth: 80)
        }
    }
}
```

- [ ] **Step 2: Write CollapsedView.swift**

```swift
import SwiftUI

struct CollapsedView: View {
    let agents: [Agent]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(agents.prefix(10)) { agent in
                AgentSpriteView(status: agent.status, size: 18)
            }
            if agents.count > 10 {
                Text("+\(agents.count - 10)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(Color(red: 0.165, green: 0.165, blue: 0.165).opacity(0.8)) // #2a2a2a
        )
    }
}
```

- [ ] **Step 3: Write ExpandedView.swift**

```swift
import SwiftUI

struct ExpandedView: View {
    let agents: [Agent]
    let onAgentClick: (Agent) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(agents.prefix(10)) { agent in
                agentCard(agent)
                    .onTapGesture { onAgentClick(agent) }
                    .opacity(agent.status == .working ? 0.7 : 1.0)
            }
            if agents.count > 10 {
                Text("+\(agents.count - 10)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 40)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.85))
        )
    }

    private func agentCard(_ agent: Agent) -> some View {
        VStack(spacing: 4) {
            AgentSpriteView(status: agent.status, size: 40)

            Text(agent.directoryLabel)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 80)

            SpeechBubbleView(text: agent.speechBubbleText)
        }
        .frame(width: 80)
    }
}
```

- [ ] **Step 4: Write HUDContentView.swift**

```swift
import SwiftUI

struct HUDContentView: View {
    @ObservedObject var store: AgentStore
    @State private var isExpanded = false
    @State private var isHovering = false
    let onAgentClick: (Agent) -> Void

    var body: some View {
        Group {
            if isExpanded {
                ExpandedView(agents: store.agents, onAgentClick: onAgentClick)
            } else {
                CollapsedView(agents: store.collapsedAgents)
            }
        }
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                withAnimation(.spring(duration: 0.2)) {
                    isExpanded = true
                }
            } else {
                // Delay collapse to prevent flicker when moving between agent cards
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    if isHovering { return } // Mouse re-entered, don't collapse
                    withAnimation(.spring(duration: 0.2)) {
                        isExpanded = false
                    }
                }
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            NotificationCenter.default.post(
                name: .hudExpansionChanged,
                object: nil,
                userInfo: ["expanded": expanded]
            )
        }
    }
}

extension Notification.Name {
    static let hudExpansionChanged = Notification.Name("hudExpansionChanged")
}
```

- [ ] **Step 5: Verify it compiles**

Run: `cd ClaudeAgentHUD && swift build 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 6: Commit**

```bash
git add ClaudeAgentHUD/Sources/Lib/Views/
git commit -m "feat: add collapsed, expanded, speech bubble, and root HUD views"
```

---

## Chunk 5: Deep Linking + App Wiring

### Task 10: Deep linker

**Files:**
- Create: `ClaudeAgentHUD/Sources/Lib/DeepLink/DeepLinker.swift`
- Create: `ClaudeAgentHUD/Sources/Lib/DeepLink/CmuxLinker.swift`
- Create: `ClaudeAgentHUD/Sources/Lib/DeepLink/TerminalLinker.swift`
- Create: `ClaudeAgentHUD/Tests/DeepLinkerTests.swift`

- [ ] **Step 1: Write DeepLinker tests**

```swift
import Testing
import Foundation
@testable import ClaudeAgentHUDLib

@Suite("DeepLinker")
struct DeepLinkerTests {
    @Test func routesToCmuxForCmuxSession() {
        let agent = Agent.fixture(
            cmuxWorkspace: "ws:abc",
            cmuxSurface: "surface:def"
        )
        #expect(DeepLinker.linkType(for: agent) == .cmux)
    }

    @Test func routesToTerminalForPlainCLI() {
        let agent = Agent.fixture(
            cwd: "/Users/test/code",
            cmuxWorkspace: nil,
            cmuxSurface: nil
        )
        #expect(DeepLinker.linkType(for: agent) == .terminal)
    }

    @Test func routesToDesktopWhenNoCwd() {
        let agent = Agent.fixture(cwd: nil, cmuxWorkspace: nil, cmuxSurface: nil)
        #expect(DeepLinker.linkType(for: agent) == .desktop)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ClaudeAgentHUD && swift test --filter DeepLinker 2>&1 | tail -10`
Expected: Compilation error

- [ ] **Step 3: Write DeepLinker.swift**

```swift
import AppKit

enum LinkType: Equatable {
    case cmux
    case terminal
    case desktop
}

struct DeepLinker {
    static func linkType(for agent: Agent) -> LinkType {
        if agent.isCmuxSession { return .cmux }
        if agent.cwd != nil { return .terminal }
        return .desktop
    }

    static func open(_ agent: Agent) {
        switch linkType(for: agent) {
        case .cmux:
            CmuxLinker.activate(agent)
        case .terminal:
            TerminalLinker.activate(agent)
        case .desktop:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Claude.app"))
        }
    }
}
```

- [ ] **Step 4: Write CmuxLinker.swift**

```swift
import Foundation

struct CmuxLinker {
    static func activate(_ agent: Agent) {
        guard let workspace = agent.cmuxWorkspace,
              let surface = agent.cmuxSurface else { return }

        let cmuxPath = "/Applications/cmux.app/Contents/Resources/bin/cmux"

        // Select workspace
        let wsProcess = Process()
        wsProcess.executableURL = URL(fileURLWithPath: cmuxPath)
        wsProcess.arguments = ["select-workspace", "--workspace", workspace]
        try? wsProcess.run()
        wsProcess.waitUntilExit()

        // Select surface
        let sfProcess = Process()
        sfProcess.executableURL = URL(fileURLWithPath: cmuxPath)
        sfProcess.arguments = ["select-surface", "--surface", surface, "--workspace", workspace]
        try? sfProcess.run()
        sfProcess.waitUntilExit()
    }
}
```

- [ ] **Step 5: Write TerminalLinker.swift**

```swift
import AppKit

struct TerminalLinker {
    /// Best-effort: walk the process tree from the agent PID to find the terminal app.
    static func activate(_ agent: Agent) {
        let pid = Int32(agent.pid)

        // Walk up process tree to find a GUI app
        var currentPid = pid
        for _ in 0..<10 {
            let parentPid = parentProcess(of: currentPid)
            if parentPid <= 1 { break }

            if let app = NSWorkspace.shared.runningApplications.first(where: {
                $0.processIdentifier == parentPid
            }) {
                app.activate()
                return
            }
            currentPid = parentPid
        }

        // Fallback: try to find any app with the agent's PID in its process tree
        // (no-op if we can't find it — best effort)
    }

    private static func parentProcess(of pid: Int32) -> Int32 {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "ppid=", "-p", "\(pid)"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespaces) ?? ""
            return Int32(output) ?? -1
        } catch {
            return -1
        }
    }
}
```

- [ ] **Step 6: Run tests**

Run: `cd ClaudeAgentHUD && swift test --filter DeepLinker 2>&1 | tail -15`
Expected: All 3 tests pass

- [ ] **Step 7: Commit**

```bash
git add ClaudeAgentHUD/Sources/Lib/DeepLink/ ClaudeAgentHUD/Tests/DeepLinkerTests.swift
git commit -m "feat: add deep linking with cmux, terminal, and desktop routes"
```

---

### Task 11: Wire up AppDelegate with panel, store, and context menu

**Files:**
- Modify: `ClaudeAgentHUD/Sources/Lib/AppDelegate.swift`
- Modify: `ClaudeAgentHUD/Sources/App/main.swift`

- [ ] **Step 1: Update AppDelegate.swift**

Replace the stub with the full implementation:

```swift
import AppKit
import SwiftUI
import Combine
import ServiceManagement

public class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: HUDPanel!
    private var store: AgentStore!
    private var cancellables = Set<AnyCancellable>()

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        store = AgentStore()
        panel = HUDPanel()

        let contentView = HUDContentView(store: store) { agent in
            DeepLinker.open(agent)
        }

        panel.contentView = NSHostingView(rootView: contentView)
        panel.positionBelowMenuBar()

        // Show/hide based on agent count
        store.$agents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] agents in
                guard let self else { return }
                if agents.isEmpty {
                    self.panel.orderOut(nil)
                } else {
                    self.panel.orderFront(nil)
                    self.panel.positionBelowMenuBar()
                }
                self.updatePanelSize()
            }
            .store(in: &cancellables)

        // Listen for expansion changes to resize panel
        NotificationCenter.default.publisher(for: .hudExpansionChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updatePanelSize()
            }
            .store(in: &cancellables)

        // Right-click context menu
        let menu = NSMenu()
        menu.addItem(withTitle: "Reinstall Hooks", action: #selector(reinstallHooks), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Uninstall Hooks & Quit", action: #selector(uninstallAndQuit), keyEquivalent: "")
        panel.menu = menu

        // First launch: confirm and install hooks
        if !UserDefaults.standard.bool(forKey: "hooksInstalled") {
            let confirm = NSAlert()
            confirm.messageText = "Set up Claude Agent HUD?"
            confirm.informativeText = "This will install hooks into your Claude Code settings to track agent status. You can uninstall later via right-click on the HUD."
            confirm.addButton(withTitle: "Continue")
            confirm.addButton(withTitle: "Quit")

            if confirm.runModal() == .alertSecondButtonReturn {
                NSApp.terminate(nil)
                return
            }

            do {
                try HookInstaller().install()
                try FileManager.default.createDirectory(
                    at: FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent(".claude/agent-status"),
                    withIntermediateDirectories: true
                )
                UserDefaults.standard.set(true, forKey: "hooksInstalled")
            } catch {
                let alert = NSAlert()
                alert.messageText = "Failed to install hooks"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }

        // Register as login item
        try? SMAppService.mainApp.register()
    }

    private func updatePanelSize() {
        let agentCount = max(store.agents.count, store.collapsedAgents.count)
        if agentCount == 0 { return }

        // Estimate sizes — these will be refined by SwiftUI layout
        let isExpanded = panel.contentView?.frame.height ?? 0 > 30
        if isExpanded {
            let width = CGFloat(min(agentCount, 10)) * 92 + 24
            panel.updateSize(width: width, height: 120)
        } else {
            let collapsedCount = store.collapsedAgents.count
            let width = CGFloat(min(collapsedCount, 10)) * 26 + 24
            panel.updateSize(width: width, height: 22)
        }
    }

    @objc private func reinstallHooks() {
        do {
            try HookInstaller().install()
            let alert = NSAlert()
            alert.messageText = "Hooks reinstalled"
            alert.runModal()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Failed to reinstall hooks"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func uninstallAndQuit() {
        let alert = NSAlert()
        alert.messageText = "Uninstall Claude Agent HUD?"
        alert.informativeText = "This will remove hooks from Claude Code settings and delete status files."
        alert.addButton(withTitle: "Uninstall & Quit")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            try? Uninstaller().uninstall()
            UserDefaults.standard.removeObject(forKey: "hooksInstalled")
            NSApp.terminate(nil)
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd ClaudeAgentHUD && swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 3: Build the .app bundle and test launch**

Run: `cd ClaudeAgentHUD && make bundle 2>&1 | tail -5`
Expected: Bundle created at `.build/release/ClaudeAgentHUD.app`

Run: `open ClaudeAgentHUD/.build/release/ClaudeAgentHUD.app`
Expected: App launches with no dock icon. No visible panel (no agents running yet).

- [ ] **Step 4: Manually test with a fake status file**

```bash
mkdir -p ~/.claude/agent-status
cat > ~/.claude/agent-status/test-session.json << 'EOF'
{
  "sessionId": "test-session",
  "pid": 1,
  "cwd": "/Users/kentbrady/SourceCode/scripts",
  "status": "waiting",
  "lastMessage": "Done! Want me to continue with the next step?",
  "updatedAt": 1773687200000
}
EOF
```

Expected: A small orange bouncing sprite should appear top-center of screen. Hover to expand and see "scripts" label + speech bubble. (Note: PID 1 = launchd, will stay alive. Clean up after testing.)

```bash
rm ~/.claude/agent-status/test-session.json
```

- [ ] **Step 5: Commit**

```bash
git add ClaudeAgentHUD/Sources/Lib/AppDelegate.swift ClaudeAgentHUD/Sources/App/main.swift
git commit -m "feat: wire up AppDelegate with panel, store, hooks, and context menu"
```

---

### Task 12: Final integration — install and validate with real Claude sessions

- [ ] **Step 1: Install the app**

Run: `cd ClaudeAgentHUD && make install`
Expected: App copied to /Applications/

- [ ] **Step 2: Launch and verify hooks installed**

Run: `open /Applications/ClaudeAgentHUD.app`

Verify hooks were added:
Run: `cat ~/.claude/settings.json | jq '.hooks | keys'`
Expected: Should include SessionStart, UserPromptSubmit, PreToolUse, Stop, PermissionRequest, Notification, SessionEnd

- [ ] **Step 3: Open a Claude Code session and verify HUD appears**

Run: `claude` in a terminal. The HUD should show a green "starting" sprite that transitions to blue "working" or orange "waiting" as you interact.

- [ ] **Step 4: Test multiple sessions**

Open 2-3 Claude Code sessions. Verify:
- Multiple sprites appear in the collapsed pill
- Hovering expands to show all agents with labels
- Clicking a cmux-managed agent jumps to its workspace/surface

- [ ] **Step 5: Test permission state**

Trigger a permission request in a Claude session (e.g., ask it to run a bash command). Verify the sprite turns red with the jumping animation.

- [ ] **Step 6: Verify login item**

Check System Settings > General > Login Items. "Claude Agent HUD" should appear.
Restart and confirm the app launches on login.

- [ ] **Step 7: Commit any fixes from testing**

```bash
git add -A
git commit -m "fix: integration testing adjustments"
```
