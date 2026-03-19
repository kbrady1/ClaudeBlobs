import Testing
import Foundation

@Suite("HookScripts")
struct HookScriptTests {

    // MARK: - hook-stop.sh — wait-reason classification

    @Suite("hook-stop: done cases")
    struct StopDone {
        @Test("done — completion phrases", arguments: [
            "Done! I've applied all the changes.",
            "Finished updating the config files.",
            "All set! The tests are passing.",
            "Everything's ready for deployment.",
            "Changes applied to all three files.",
            "I've updated the README with the new instructions.",
            "",
        ])
        func doneMessages(message: String) throws {
            let h = try HookTestHelper()
            let r = try h.runHook("hook-stop.sh", input: ["last_assistant_message": message])
            #expect(r.status?["waitReason"] as? String == "done")
            #expect(r.status?["status"] as? String == "waiting")
        }

        @Test("done — completion in head overrides trailing question")
        func doneOverridesQuestion() throws {
            let h = try HookTestHelper()
            let msg = "Done with the refactor.\n\nShall I do anything else?"
            let r = try h.runHook("hook-stop.sh", input: ["last_assistant_message": msg])
            #expect(r.status?["waitReason"] as? String == "done")
        }

        @Test("done — question beyond tail's 500 chars")
        func questionBeyondTail() throws {
            let h = try HookTestHelper()
            let msg = "Should I proceed?\n" + String(repeating: "x", count: 600)
            let r = try h.runHook("hook-stop.sh", input: ["last_assistant_message": msg])
            #expect(r.status?["waitReason"] as? String == "done")
        }

        @Test("done — completion phrase on line 3, outside head")
        func completionOutsideHead() throws {
            let h = try HookTestHelper()
            let msg = "Line1\nLine2\nCompleted the task."
            let r = try h.runHook("hook-stop.sh", input: ["last_assistant_message": msg])
            #expect(r.status?["waitReason"] as? String == "done")
        }
    }

    @Suite("hook-stop: question — trailing ?")
    struct StopQuestionMark {
        @Test("question — trailing question mark", arguments: [
            "Should I fix the tests?",
            "Should I fix them?**",
            "Want me to update `config.json`?",
            "Should I proceed?  \n",
        ])
        func trailingQuestionMark(message: String) throws {
            let h = try HookTestHelper()
            let r = try h.runHook("hook-stop.sh", input: ["last_assistant_message": message])
            #expect(r.status?["waitReason"] as? String == "question")
            #expect(r.status?["status"] as? String == "waiting")
        }
    }

    @Suite("hook-stop: question — conversational phrases")
    struct StopQuestionPhrase {
        @Test("question — conversational phrases", arguments: [
            "I can add error handling. Shall I proceed.",
            "There are two options. Should I go with A.",
            "Would you like me to implement it.",
            "Sound good.",
            "Let me know which you prefer.",
            "What do you think.",
            "Next question: what version should we use.",
        ])
        func conversationalPhrases(message: String) throws {
            let h = try HookTestHelper()
            let r = try h.runHook("hook-stop.sh", input: ["last_assistant_message": message])
            #expect(r.status?["waitReason"] as? String == "question")
        }
    }

    @Suite("hook-stop: first-sentence extraction")
    struct StopFirstSentence {
        @Test("extracts first sentence before period")
        func firstSentence() throws {
            let h = try HookTestHelper()
            let r = try h.runHook("hook-stop.sh", input: ["last_assistant_message": "I fixed the bug. Here are the details."])
            #expect(r.status?["lastMessage"] as? String == "I fixed the bug")
        }

        @Test("truncates long message to 200 chars")
        func truncatesLong() throws {
            let h = try HookTestHelper()
            let longMsg = String(repeating: "a", count: 250)
            let r = try h.runHook("hook-stop.sh", input: ["last_assistant_message": longMsg])
            let msg = r.status?["lastMessage"] as? String ?? ""
            #expect(msg.count <= 200)
        }
    }

    @Suite("hook-stop: metadata")
    struct StopMetadata {
        @Test("sets status to waiting and updatedAt is recent")
        func statusAndTimestamp() throws {
            let h = try HookTestHelper()
            let before = Date().timeIntervalSince1970 * 1000
            let r = try h.runHook("hook-stop.sh", input: ["last_assistant_message": "Done."])
            let ts = r.status?["updatedAt"] as? Double ?? 0
            #expect(r.status?["status"] as? String == "waiting")
            #expect(ts >= before - 2000)
        }
    }

    // MARK: - hook-session-start.sh

    @Suite("hook-session-start")
    struct SessionStart {
        @Test("creates status file with correct fields")
        func createsStatusFile() throws {
            let h = try HookTestHelper()
            let r = try h.runHook("hook-session-start.sh", input: [
                "cwd": "/tmp/project",
                "agent_type": "code",
            ])
            #expect(r.status?["sessionId"] as? String == "test-session")
            #expect(r.status?["cwd"] as? String == "/tmp/project")
            #expect(r.status?["agentType"] as? String == "code")
            #expect(r.status?["status"] as? String == "starting")
            let pid = r.status?["pid"] as? Int ?? 0
            #expect(pid > 0)
        }

        @Test("null cwd and agentType when omitted")
        func nullOptionalFields() throws {
            let h = try HookTestHelper()
            let r = try h.runHook("hook-session-start.sh", input: [:])
            #expect(r.status?["cwd"] is NSNull)
            #expect(r.status?["agentType"] is NSNull)
        }

        @Test("cmux fields populated from env vars")
        func cmuxFieldsFromEnv() throws {
            let h = try HookTestHelper()
            let r = try h.runHook("hook-session-start.sh", input: [:], environment: [
                "CMUX_WORKSPACE_ID": "ws-123",
                "CMUX_SURFACE_ID": "sf-456",
                "CMUX_SOCKET_PATH": "/tmp/cmux.sock",
            ])
            #expect(r.status?["cmuxWorkspace"] as? String == "ws-123")
            #expect(r.status?["cmuxSurface"] as? String == "sf-456")
            #expect(r.status?["cmuxSocketPath"] as? String == "/tmp/cmux.sock")
        }

        @Test("cmux fields null when env vars unset")
        func cmuxFieldsNull() throws {
            let h = try HookTestHelper()
            let r = try h.runHook("hook-session-start.sh", input: [:])
            #expect(r.status?["cmuxWorkspace"] is NSNull)
            #expect(r.status?["cmuxSurface"] is NSNull)
            #expect(r.status?["cmuxSocketPath"] is NSNull)
        }
    }

    // MARK: - hook-pre-tool.sh

    @Suite("hook-pre-tool")
    struct PreTool {
        @Test("records lastToolUse with tool name and input")
        func toolNameAndInput() throws {
            let h = try HookTestHelper()
            let r = try h.runHook("hook-pre-tool.sh", input: [
                "tool_name": "Read",
                "tool_input": "some file content",
            ], existingStatus: makeWorkingStatus())
            #expect(r.status?["lastToolUse"] as? String == "Read: some file content")
            #expect(r.status?["status"] as? String == "working")
            #expect(r.status?["waitReason"] is NSNull)
        }

        @Test("truncates input at 80 chars")
        func truncatesInput() throws {
            let h = try HookTestHelper()
            let longInput = String(repeating: "z", count: 120)
            let r = try h.runHook("hook-pre-tool.sh", input: [
                "tool_name": "Write",
                "tool_input": longInput,
            ], existingStatus: makeWorkingStatus())
            let toolUse = r.status?["lastToolUse"] as? String ?? ""
            // "Write: " is 7 chars, input truncated to 80
            #expect(toolUse.count <= 87)
        }

        @Test("empty input omits colon")
        func emptyInputOmitsColon() throws {
            let h = try HookTestHelper()
            let r = try h.runHook("hook-pre-tool.sh", input: [
                "tool_name": "Bash",
            ], existingStatus: makeWorkingStatus())
            #expect(r.status?["lastToolUse"] as? String == "Bash")
        }
    }

    // MARK: - hook-permission.sh

    @Suite("hook-permission")
    struct Permission {
        @Test("sets status to permission and records lastToolUse")
        func setsPermission() throws {
            let h = try HookTestHelper()
            let r = try h.runHook("hook-permission.sh", input: [
                "tool_name": "Bash",
                "tool_input": "rm -rf /",
            ], existingStatus: makeWorkingStatus())
            #expect(r.status?["status"] as? String == "permission")
            #expect((r.status?["lastToolUse"] as? String)?.hasPrefix("Bash: ") == true)
        }
    }

    // MARK: - hook-post-tool-failure.sh

    @Suite("hook-post-tool-failure")
    struct PostToolFailure {
        @Test("interrupt sets toolFailure to interrupt")
        func interrupt() throws {
            let h = try HookTestHelper()
            let r = try h.runHook("hook-post-tool-failure.sh", input: [
                "is_interrupt": true,
            ], existingStatus: makeWorkingStatus())
            #expect(r.status?["toolFailure"] as? String == "interrupt")
        }

        @Test("non-interrupt sets toolFailure to error")
        func error() throws {
            let h = try HookTestHelper()
            let r = try h.runHook("hook-post-tool-failure.sh", input: [
                "is_interrupt": false,
            ], existingStatus: makeWorkingStatus())
            #expect(r.status?["toolFailure"] as? String == "error")
        }
    }

    // MARK: - hook-subagent-start.sh

    @Suite("hook-subagent-start")
    struct SubagentStart {
        @Test("creates subagent file with parentSessionId and pid 0")
        func createsSubagentFile() throws {
            let h = try HookTestHelper()
            let r = try h.runSubagentHook("hook-subagent-start.sh",
                sessionId: "parent-sess",
                subagentId: "sub-123",
                input: ["cwd": "/tmp", "subagent_type": "task"])
            #expect(r.status?["parentSessionId"] as? String == "parent-sess")
            #expect(r.status?["pid"] as? Int == 0)
            #expect(r.status?["status"] as? String == "starting")
            #expect(r.status?["sessionId"] as? String == "sub-123")
        }

        @Test("exits silently when subagent_id is empty")
        func exitsSilently() throws {
            let h = try HookTestHelper()
            let r = try h.runSubagentHook("hook-subagent-start.sh",
                sessionId: "parent-sess",
                subagentId: "",
                input: ["subagent_id": ""])
            #expect(r.exitCode == 0)
            // No file should be created for empty subagent_id — check the specific empty-named file
            let emptyFile = h.statusDir.appendingPathComponent(".json")
            #expect(!FileManager.default.fileExists(atPath: emptyFile.path))
        }
    }

    // MARK: - hook-subagent-stop.sh / hook-session-end.sh

    @Suite("hook-subagent-stop")
    struct SubagentStop {
        @Test("deletes the subagent status file")
        func deletesFile() throws {
            let h = try HookTestHelper()
            // Create the file first
            try h.runSubagentHook("hook-subagent-start.sh",
                sessionId: "parent", subagentId: "sub-del")
            // Now stop it
            let r = try h.runSubagentHook("hook-subagent-stop.sh",
                sessionId: "parent", subagentId: "sub-del")
            #expect(r.exitCode == 0)
            #expect(!r.statusFileExists)
        }
    }

    @Suite("hook-session-end")
    struct SessionEnd {
        @Test("deletes the status file")
        func deletesFile() throws {
            let h = try HookTestHelper()
            try h.runHook("hook-session-start.sh", input: [:])
            let r = try h.runHook("hook-session-end.sh", input: [:])
            #expect(r.exitCode == 0)
            #expect(!r.statusFileExists)
        }
    }

    // MARK: - hook-notification.sh

    @Suite("hook-notification")
    struct Notification {
        @Test("does NOT overwrite permission status")
        func preservesPermission() throws {
            let h = try HookTestHelper()
            let existing = makeStatus(status: "permission")
            let r = try h.runHook("hook-notification.sh", input: [:], existingStatus: existing)
            #expect(r.status?["status"] as? String == "permission")
        }

        @Test("does NOT overwrite waiting status")
        func preservesWaiting() throws {
            let h = try HookTestHelper()
            let existing = makeStatus(status: "waiting")
            let r = try h.runHook("hook-notification.sh", input: [:], existingStatus: existing)
            #expect(r.status?["status"] as? String == "waiting")
        }

        @Test("overwrites starting status")
        func overwritesStarting() throws {
            let h = try HookTestHelper()
            let existing = makeStatus(status: "starting")
            let r = try h.runHook("hook-notification.sh", input: [:], existingStatus: existing)
            #expect(r.status?["status"] as? String == "working")
        }

        @Test("overwrites working status")
        func overwritesWorking() throws {
            let h = try HookTestHelper()
            let existing = makeStatus(status: "working")
            let r = try h.runHook("hook-notification.sh", input: [:], existingStatus: existing)
            #expect(r.status?["status"] as? String == "working")
        }
    }

    // MARK: - hook-user-prompt.sh

    @Suite("hook-user-prompt")
    struct UserPrompt {
        @Test("sets working and clears lastMessage, waitReason, toolFailure")
        func clearsFields() throws {
            let h = try HookTestHelper()
            let existing: [String: Any] = [
                "sessionId": "test-session",
                "pid": 99999,
                "status": "waiting",
                "lastMessage": "old message",
                "waitReason": "question",
                "toolFailure": "error",
                "lastToolUse": NSNull(),
                "cwd": NSNull(),
                "agentType": NSNull(),
                "tty": NSNull(),
                "cmuxWorkspace": NSNull(),
                "cmuxSurface": NSNull(),
                "cmuxSocketPath": NSNull(),
                "createdAt": 1000000,
                "updatedAt": 1000000,
            ]
            let r = try h.runHook("hook-user-prompt.sh", input: [:], existingStatus: existing)
            #expect(r.status?["status"] as? String == "working")
            #expect(r.status?["lastMessage"] is NSNull)
            #expect(r.status?["waitReason"] is NSNull)
            #expect(r.status?["toolFailure"] is NSNull)
        }
    }

    // MARK: - Simple transitions

    @Suite("hook-post-tool")
    struct PostTool {
        @Test("sets working and clears waitReason")
        func setsWorking() throws {
            let h = try HookTestHelper()
            let r = try h.runHook("hook-post-tool.sh", input: [:], existingStatus: makeWorkingStatus())
            #expect(r.status?["status"] as? String == "working")
            #expect(r.status?["waitReason"] is NSNull)
        }
    }

    @Suite("hook-pre-compact")
    struct PreCompact {
        @Test("sets status to compacting")
        func setsCompacting() throws {
            let h = try HookTestHelper()
            let r = try h.runHook("hook-pre-compact.sh", input: [:], existingStatus: makeWorkingStatus())
            #expect(r.status?["status"] as? String == "compacting")
        }
    }

    @Suite("hook-post-compact")
    struct PostCompact {
        @Test("sets working and clears waitReason")
        func setsWorking() throws {
            let h = try HookTestHelper()
            let existing = makeStatus(status: "compacting")
            let r = try h.runHook("hook-post-compact.sh", input: [:], existingStatus: existing)
            #expect(r.status?["status"] as? String == "working")
            #expect(r.status?["waitReason"] is NSNull)
        }
    }

    @Suite("hook-task-completed")
    struct TaskCompleted {
        @Test("sets taskCompletedAt timestamp")
        func setsTimestamp() throws {
            let h = try HookTestHelper()
            let before = Date().timeIntervalSince1970 * 1000
            let r = try h.runHook("hook-task-completed.sh", input: [:], existingStatus: makeWorkingStatus())
            let ts = r.status?["taskCompletedAt"] as? Double ?? 0
            #expect(ts >= before - 2000)
        }
    }
}

// MARK: - Helpers

private func makeWorkingStatus(sessionId: String = "test-session") -> [String: Any] {
    [
        "sessionId": sessionId,
        "pid": 99999,
        "status": "working",
        "lastMessage": NSNull(),
        "lastToolUse": NSNull(),
        "waitReason": NSNull(),
        "cwd": NSNull(),
        "agentType": NSNull(),
        "tty": NSNull(),
        "cmuxWorkspace": NSNull(),
        "cmuxSurface": NSNull(),
        "cmuxSocketPath": NSNull(),
        "createdAt": 1000000,
        "updatedAt": 1000000,
    ]
}

private func makeStatus(status: String, sessionId: String = "test-session") -> [String: Any] {
    var s = makeWorkingStatus(sessionId: sessionId)
    s["status"] = status
    return s
}
