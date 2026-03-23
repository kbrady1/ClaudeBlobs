import Testing
@testable import ClaudeBlobsLib

@Suite("RemoteRouter")
struct RemoteRouterTests {

    @Test func validateAuthRejectsInvalidToken() {
        let result = RemoteRouter.validateAuth(
            header: "Bearer wrong-token",
            validTokens: ["correct-token"]
        )
        #expect(result == false)
    }

    @Test func validateAuthAcceptsValidToken() {
        let result = RemoteRouter.validateAuth(
            header: "Bearer correct-token",
            validTokens: ["correct-token"]
        )
        #expect(result == true)
    }

    @Test func validateAuthRejectsMissingBearer() {
        let result = RemoteRouter.validateAuth(
            header: "correct-token",
            validTokens: ["correct-token"]
        )
        #expect(result == false)
    }

    @Test func validateCommandRejectsNonCmuxAgent() {
        let agent = Agent.fixture(sessionId: "s1", status: .permission)
        let result = RemoteRouter.validateCommand(.approve, agent: agent)
        #expect(result != nil)
        #expect(result!.contains("cmux"))
    }

    @Test func validateCommandRejectsApproveOnWorkingAgent() {
        let agent = Agent.fixture(sessionId: "s1", status: .working, cmuxSurface: "surface:1")
        let result = RemoteRouter.validateCommand(.approve, agent: agent)
        #expect(result != nil)
    }

    @Test func validateCommandAllowsApproveOnPermissionAgent() {
        let agent = Agent.fixture(sessionId: "s1", status: .permission, cmuxSurface: "surface:1")
        let result = RemoteRouter.validateCommand(.approve, agent: agent)
        #expect(result == nil)
    }

    @Test func validateCommandAllowsInterruptOnAnyState() {
        let agent = Agent.fixture(sessionId: "s1", status: .working, cmuxSurface: "surface:1")
        let result = RemoteRouter.validateCommand(.interrupt, agent: agent)
        #expect(result == nil)
    }
}
