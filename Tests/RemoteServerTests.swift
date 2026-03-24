// Tests/RemoteServerTests.swift
import Testing
import Foundation
@testable import ClaudeBlobsLib

@Suite("RemoteServer Integration")
struct RemoteServerIntegrationTests {

    @Test func serverStartsAndStops() async {
        let store = AgentStore(
            statusSources: [],
            enableWatcher: false,
            isProcessAlive: { _ in false }
        )
        let port = UInt16.random(in: 49152...65535)
        let pairing = PairingManager(keychainPrefix: "test-\(UUID().uuidString)", enableTLS: false)
        let server = RemoteServer(agentStore: store, port: port, pairingManager: pairing)
        server.start()
        // Server starts asynchronously — give it a moment
        try? await Task.sleep(for: .milliseconds(100))
        server.stop()
        // After stop, isRunning should be false
        #expect(server.isRunning == false)
    }

    @Test func routerValidatesCommandStates() {
        let permAgent = Agent.fixture(sessionId: "s1", status: .permission, cmuxSurface: "surface:1")
        #expect(RemoteRouter.validateCommand(.approve, agent: permAgent) == nil)
        #expect(RemoteRouter.validateCommand(.deny, agent: permAgent) == nil)

        let waitAgent = Agent.fixture(sessionId: "s2", status: .waiting, cmuxSurface: "surface:2")
        #expect(RemoteRouter.validateCommand(.respond, agent: waitAgent) == nil)
        #expect(RemoteRouter.validateCommand(.approve, agent: waitAgent) != nil)

        let workAgent = Agent.fixture(sessionId: "s3", status: .working, cmuxSurface: "surface:3")
        #expect(RemoteRouter.validateCommand(.interrupt, agent: workAgent) == nil)
        #expect(RemoteRouter.validateCommand(.approve, agent: workAgent) != nil)
    }

    @Test func commandExecutorRejectsNonCmuxAgent() async throws {
        let agent = Agent.fixture(sessionId: "s1", status: .permission)
        let result = try await CommandExecutor.execute(command: .approve, agent: agent, text: nil)
        #expect(result.success == false)
        #expect(result.error?.contains("cmux") == true)
    }

    @Test func commandExecutorRejectsWrongState() async throws {
        let agent = Agent.fixture(sessionId: "s1", status: .working, cmuxSurface: "surface:1")
        let result = try await CommandExecutor.execute(command: .approve, agent: agent, text: nil)
        #expect(result.success == false)
    }
}
