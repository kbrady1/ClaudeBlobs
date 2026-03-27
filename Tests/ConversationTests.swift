import Testing
import Foundation
@testable import ClaudeBlobsLib

// MARK: - Fixtures (matching real Claude Code JSON from hook logs)

private let parentSessionId = "17f26610-ff40-490a-9fce-2950f896cda6"
private let subagentA = "a79f32e43eea4c9b2"
private let subagentB = "b88g43f54ffb5d0c3"
private let subagentC = "c99h54g65ggc6e1d4"

private let cmuxEnv: [String: String] = [
    "CMUX_WORKSPACE_ID": "EDD18C14-7FBB-49ED-B274-5C5DE7886C97",
    "CMUX_SURFACE_ID": "ED335DAC-5B3A-43D6-92B6-2B42C727D829",
    "CMUX_SOCKET_PATH": "/tmp/cmux.sock",
]

private func sessionStart(
    sessionId: String = parentSessionId,
    cwd: String = "/tmp/test"
) -> ConversationStep {
    ConversationStep("hook-session-start.sh", input: [
        "session_id": sessionId,
        "cwd": cwd,
        "hook_event_name": "SessionStart",
        "source": "startup",
        "model": "claude-opus-4-6[1m]",
    ], environment: cmuxEnv)
}

private func userPrompt(
    sessionId: String = parentSessionId,
    prompt: String = "Hello"
) -> ConversationStep {
    ConversationStep("hook-user-prompt.sh", input: [
        "session_id": sessionId,
        "cwd": "/tmp/test",
        "permission_mode": "default",
        "hook_event_name": "UserPromptSubmit",
        "prompt": prompt,
    ])
}

private func preToolUse(
    sessionId: String = parentSessionId,
    agentId: String? = nil,
    agentType: String? = nil,
    toolName: String = "Bash",
    toolInput: [String: Any] = ["command": "echo hello"]
) -> ConversationStep {
    var input: [String: Any] = [
        "session_id": sessionId,
        "cwd": "/tmp/test",
        "permission_mode": "default",
        "hook_event_name": "PreToolUse",
        "tool_name": toolName,
        "tool_input": toolInput,
        "tool_use_id": "toolu_\(UUID().uuidString.prefix(20))",
    ]
    if let agentId { input["agent_id"] = agentId }
    if let agentType { input["agent_type"] = agentType }
    return ConversationStep("hook-pre-tool.sh", input: input)
}

private func postToolUse(
    sessionId: String = parentSessionId,
    agentId: String? = nil,
    agentType: String? = nil,
    toolName: String = "Bash",
    toolInput: [String: Any]? = nil
) -> ConversationStep {
    var input: [String: Any] = [
        "session_id": sessionId,
        "cwd": "/tmp/test",
        "permission_mode": "default",
        "hook_event_name": "PostToolUse",
        "tool_name": toolName,
        "tool_input": toolInput ?? ["command": "echo hello"],
        "tool_response": ["stdout": "hello", "stderr": "", "interrupted": false],
        "tool_use_id": "toolu_\(UUID().uuidString.prefix(20))",
    ]
    if let agentId { input["agent_id"] = agentId }
    if let agentType { input["agent_type"] = agentType }
    return ConversationStep("hook-post-tool.sh", input: input)
}

private func permissionRequest(
    sessionId: String = parentSessionId,
    agentId: String? = nil,
    agentType: String? = nil,
    toolName: String = "Bash",
    toolInput: [String: Any] = ["command": "rm -rf /tmp/stuff"]
) -> ConversationStep {
    var input: [String: Any] = [
        "session_id": sessionId,
        "cwd": "/tmp/test",
        "permission_mode": "default",
        "hook_event_name": "PermissionRequest",
        "tool_name": toolName,
        "tool_input": toolInput,
    ]
    if let agentId { input["agent_id"] = agentId }
    if let agentType { input["agent_type"] = agentType }
    return ConversationStep("hook-permission.sh", input: input)
}

private func subagentStart(
    sessionId: String = parentSessionId,
    agentId: String,
    agentType: String = "Explore"
) -> ConversationStep {
    ConversationStep("hook-subagent-start.sh", input: [
        "session_id": sessionId,
        "agent_id": agentId,
        "agent_type": agentType,
        "hook_event_name": "SubagentStart",
    ])
}

private func subagentStop(
    sessionId: String = parentSessionId,
    agentId: String,
    agentType: String = "Explore"
) -> ConversationStep {
    ConversationStep("hook-subagent-stop.sh", input: [
        "session_id": sessionId,
        "agent_id": agentId,
        "agent_type": agentType,
        "hook_event_name": "SubagentStop",
        "stop_hook_active": false,
    ])
}

private func stop(
    sessionId: String = parentSessionId,
    message: String = "I've finished the task."
) -> ConversationStep {
    ConversationStep("hook-stop.sh", input: [
        "session_id": sessionId,
        "cwd": "/tmp/test",
        "permission_mode": "default",
        "hook_event_name": "Stop",
        "stop_hook_active": false,
        "last_assistant_message": message,
    ])
}

private func sessionEnd(
    sessionId: String = parentSessionId
) -> ConversationStep {
    ConversationStep("hook-session-end.sh", input: [
        "session_id": sessionId,
        "hook_event_name": "SessionEnd",
    ])
}

// MARK: - Tests

@Suite("Conversation E2E")
struct ConversationTests {

    @Test("basic session lifecycle: starting → working → waiting → deleted")
    func basicSessionLifecycle() throws {
        let c = try ConversationTestHelper()

        try c.replayWithCheckpoints([
            sessionStart(),
            userPrompt(),
            preToolUse(toolName: "Read", toolInput: ["file_path": "/tmp/foo.swift"]),
            postToolUse(toolName: "Read"),
            stop(message: "I've finished the task."),
            sessionEnd(),
        ], checkpoints: [
            0: [StatusAssertion(parentSessionId, status: "starting")],
            1: [StatusAssertion(parentSessionId, status: "working")],
            2: [StatusAssertion(parentSessionId, status: "working", lastToolUse: "Read")],
            3: [StatusAssertion(parentSessionId, status: "working")],
            4: [StatusAssertion(parentSessionId, status: "waiting", waitReason: "done")],
            5: [StatusAssertion(parentSessionId, exists: false)],
        ])
    }

    @Test("subagent start creates its own status file with parentSessionId")
    func subagentCreatesOwnFile() throws {
        let c = try ConversationTestHelper()

        try c.replay([
            sessionStart(),
            userPrompt(),
            subagentStart(agentId: subagentA, agentType: "Explore"),
        ])

        // Parent file exists
        let parent = try c.readStatus(parentSessionId)
        #expect(parent != nil)
        #expect(parent?["status"] as? String == "working")

        // Subagent file exists with correct fields
        let sub = try c.readStatus(subagentA)
        #expect(sub != nil)
        #expect(sub?["status"] as? String == "starting")
        #expect(sub?["parentSessionId"] as? String == parentSessionId)
        #expect(sub?["pid"] as? Int == 0)
        #expect(sub?["agentType"] as? String == "Explore")
    }

    @Test("subagent tool use updates subagent file, not parent")
    func subagentToolUpdatesSubagentFile() throws {
        let c = try ConversationTestHelper()

        try c.replay([
            sessionStart(),
            userPrompt(),
            preToolUse(toolName: "Skill", toolInput: ["skill": "brainstorming"]),
            subagentStart(agentId: subagentA, agentType: "Explore"),
        ])

        // Capture parent state before subagent tool use
        let parentBefore = try c.readStatus(parentSessionId)
        let parentToolBefore = parentBefore?["lastToolUse"] as? String

        // Subagent uses a tool
        try c.replay([
            preToolUse(agentId: subagentA, agentType: "Explore",
                       toolName: "Bash", toolInput: ["command": "find . -name '*.swift'"]),
        ])

        // Parent's lastToolUse should be unchanged
        let parentAfter = try c.readStatus(parentSessionId)
        #expect(parentAfter?["lastToolUse"] as? String == parentToolBefore)

        // Subagent's file should be updated
        let sub = try c.readStatus(subagentA)
        #expect(sub?["status"] as? String == "working")
        #expect((sub?["lastToolUse"] as? String)?.hasPrefix("Bash") == true)
    }

    @Test("subagent permission does not overwrite parent status")
    func subagentPermissionDoesNotAffectParent() throws {
        let c = try ConversationTestHelper()

        try c.replay([
            sessionStart(),
            userPrompt(),
            subagentStart(agentId: subagentA, agentType: "Explore"),
            subagentStart(agentId: subagentB, agentType: "Plan"),
        ])

        // Subagent A asks for permission
        try c.replay([
            permissionRequest(agentId: subagentA, agentType: "Explore",
                              toolName: "Bash", toolInput: ["command": "rm -rf /tmp"]),
        ])

        // Subagent B continues working
        try c.replay([
            preToolUse(agentId: subagentB, agentType: "Plan",
                       toolName: "Read", toolInput: ["file_path": "/tmp/foo"]),
        ])

        // Parent should still be working (not permission!)
        let parent = try c.readStatus(parentSessionId)
        #expect(parent?["status"] as? String == "working")

        // Subagent A should be in permission state
        let subA = try c.readStatus(subagentA)
        #expect(subA?["status"] as? String == "permission")
        #expect((subA?["lastToolUse"] as? String)?.hasPrefix("Bash") == true)

        // Subagent B should be working
        let subB = try c.readStatus(subagentB)
        #expect(subB?["status"] as? String == "working")
        #expect((subB?["lastToolUse"] as? String)?.hasPrefix("Read") == true)
    }

    @Test("AgentStore builds correct parent-child relationships")
    func parentEffectiveStatusReflectsChildren() throws {
        let c = try ConversationTestHelper()

        try c.replay([
            sessionStart(),
            userPrompt(),
            subagentStart(agentId: subagentA, agentType: "Explore"),
            subagentStart(agentId: subagentB, agentType: "Plan"),
            // Subagent A asks for permission
            permissionRequest(agentId: subagentA, agentType: "Explore",
                              toolName: "Bash", toolInput: ["command": "rm stuff"]),
            // Subagent B is working
            preToolUse(agentId: subagentB, agentType: "Plan",
                       toolName: "Read", toolInput: ["file_path": "/tmp/foo"]),
        ])

        let store = c.loadStore()

        // Should have 3 agents: parent + 2 subagents
        #expect(store.agents.count == 3)

        // Top-level agents should only include the parent
        let topLevel = store.topLevelAgents
        #expect(topLevel.count == 1)
        #expect(topLevel[0].sessionId == parentSessionId)

        // Children should be correctly mapped
        let parentId = "claude-code:\(parentSessionId)"
        let kids = store.children(of: parentId)
        #expect(kids.count == 2)

        // Verify child statuses
        let childStatuses = Set(kids.map(\.status))
        #expect(childStatuses.contains(.permission))
        #expect(childStatuses.contains(.working))
    }

    @Test("subagent stop deletes subagent file, parent unaffected")
    func subagentStopCleansUpFile() throws {
        let c = try ConversationTestHelper()

        try c.replay([
            sessionStart(),
            userPrompt(),
            subagentStart(agentId: subagentA, agentType: "Explore"),
            preToolUse(agentId: subagentA, agentType: "Explore",
                       toolName: "Bash", toolInput: ["command": "ls"]),
        ])

        #expect(c.statusFileExists(subagentA))

        try c.replay([
            subagentStop(agentId: subagentA),
        ])

        // Subagent file should be deleted
        #expect(!c.statusFileExists(subagentA))
        // Parent should still exist
        #expect(c.statusFileExists(parentSessionId))
        let parent = try c.readStatus(parentSessionId)
        #expect(parent?["status"] as? String == "working")
    }

    @Test("multiple subagents create separate files with correct parent mapping")
    func multipleSubagentsParallelWork() throws {
        let c = try ConversationTestHelper()

        try c.replay([
            sessionStart(),
            userPrompt(),
            subagentStart(agentId: subagentA, agentType: "Explore"),
            subagentStart(agentId: subagentB, agentType: "Plan"),
            subagentStart(agentId: subagentC, agentType: "general-purpose"),
            // Each subagent does different work
            preToolUse(agentId: subagentA, agentType: "Explore",
                       toolName: "Grep", toolInput: ["pattern": "TODO"]),
            preToolUse(agentId: subagentB, agentType: "Plan",
                       toolName: "Read", toolInput: ["file_path": "/tmp/plan.md"]),
            preToolUse(agentId: subagentC, agentType: "general-purpose",
                       toolName: "Bash", toolInput: ["command": "make test"]),
        ])

        // 4 status files should exist
        let statuses = try c.allStatuses()
        #expect(statuses.count == 4)

        // All subagents should link to parent
        for id in [subagentA, subagentB, subagentC] {
            let sub = try c.readStatus(id)
            #expect(sub?["parentSessionId"] as? String == parentSessionId)
        }

        // AgentStore should have correct parent-child mapping
        let store = c.loadStore()
        #expect(store.topLevelAgents.count == 1)
        let parentId = "claude-code:\(parentSessionId)"
        #expect(store.children(of: parentId).count == 3)
    }

    @Test("permission race condition: subagent A permission stays while B works")
    func permissionRaceCondition() throws {
        let c = try ConversationTestHelper()

        // Set up: parent working, two subagents
        try c.replay([
            sessionStart(),
            userPrompt(),
            subagentStart(agentId: subagentA, agentType: "Explore"),
            subagentStart(agentId: subagentB, agentType: "Plan"),
        ])

        // Subagent A asks for permission
        try c.replay([
            permissionRequest(agentId: subagentA, agentType: "Explore",
                              toolName: "Bash", toolInput: ["command": "rm -rf build/"]),
        ])
        let subAPermission = try c.readStatus(subagentA)
        #expect(subAPermission?["status"] as? String == "permission")

        // Subagent B fires multiple tool calls — should NOT affect A's permission
        try c.replay([
            preToolUse(agentId: subagentB, agentType: "Plan",
                       toolName: "Read", toolInput: ["file_path": "/tmp/a.swift"]),
            postToolUse(agentId: subagentB, agentType: "Plan", toolName: "Read"),
            preToolUse(agentId: subagentB, agentType: "Plan",
                       toolName: "Grep", toolInput: ["pattern": "class Foo"]),
        ])

        // A should STILL be in permission state
        let subAStill = try c.readStatus(subagentA)
        #expect(subAStill?["status"] as? String == "permission")

        // B should be working
        let subBWorking = try c.readStatus(subagentB)
        #expect(subBWorking?["status"] as? String == "working")

        // Parent should be working (not affected by either subagent)
        let parent = try c.readStatus(parentSessionId)
        #expect(parent?["status"] as? String == "working")

        // Now A's permission is granted — PostToolUse with matching tool key clears it.
        // (PreToolUse fires before PermissionRequest, so PostToolUse is the grant signal.)
        try c.replay([
            postToolUse(agentId: subagentA, agentType: "Explore",
                        toolName: "Bash", toolInput: ["command": "rm -rf build/"]),
        ])

        // A should now be working
        let subAResume = try c.readStatus(subagentA)
        #expect(subAResume?["status"] as? String == "working")
    }
}
