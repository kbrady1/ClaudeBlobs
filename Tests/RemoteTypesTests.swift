import Testing
import Foundation
@testable import ClaudeBlobsLib

@Suite("RemoteTypes")
struct RemoteTypesTests {

    @Test func agentSnapshotEncodesToJSON() throws {
        let agent = Agent.fixture(sessionId: "s1", status: .permission, lastToolUse: "Bash: npm deploy")
        let agentSnapshot = AgentSnapshot(agent: agent, appIconPNG: nil)
        let snapshot = RemoteMessage.snapshot(agents: [agentSnapshot])
        let data = try JSONEncoder().encode(snapshot)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["type"] as? String == "snapshot")
        #expect((json["agents"] as? [[String: Any]])?.count == 1)
    }

    @Test func agentSnapshotWithIconEncodesToJSON() throws {
        let agent = Agent.fixture(sessionId: "s1", status: .working)
        let fakeIconData = Data([0x89, 0x50, 0x4E, 0x47]) // PNG magic bytes
        let agentSnapshot = AgentSnapshot(agent: agent, appIconPNG: fakeIconData)
        let snapshot = RemoteMessage.snapshot(agents: [agentSnapshot])
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(RemoteMessage.self, from: data)
        if case .snapshot(let agents) = decoded {
            #expect(agents.count == 1)
            #expect(agents[0].appIconPNG == fakeIconData)
            #expect(agents[0].agent.sessionId == "s1")
        } else {
            Issue.record("Expected snapshot message")
        }
    }

    @Test func agentUpdateEncodesToJSON() throws {
        let agent = Agent.fixture(sessionId: "s1", status: .working)
        let agentSnapshot = AgentSnapshot(agent: agent, appIconPNG: nil)
        let update = RemoteMessage.agentUpdated(agent: agentSnapshot)
        let data = try JSONEncoder().encode(update)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["type"] as? String == "agentUpdated")
    }

    @Test func agentRemovedEncodesToJSON() throws {
        let removed = RemoteMessage.agentRemoved(sessionId: "s1")
        let data = try JSONEncoder().encode(removed)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["type"] as? String == "agentRemoved")
        #expect(json["sessionId"] as? String == "s1")
    }

    @Test func heartbeatEncodesToJSON() throws {
        let hb = RemoteMessage.heartbeat
        let data = try JSONEncoder().encode(hb)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["type"] as? String == "heartbeat")
    }

    @Test func commandRequestDecodesFromJSON() throws {
        let json = """
        {"command": "respond", "sessionId": "s1", "text": "yes please"}
        """.data(using: .utf8)!
        let cmd = try JSONDecoder().decode(CommandRequest.self, from: json)
        #expect(cmd.command == .respond)
        #expect(cmd.sessionId == "s1")
        #expect(cmd.text == "yes please")
    }

    @Test func commandResponseEncodesToJSON() throws {
        let resp = CommandResponse(success: false, error: "Agent not in permission state")
        let data = try JSONEncoder().encode(resp)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["success"] as? Bool == false)
        #expect(json["error"] as? String == "Agent not in permission state")
    }
}
