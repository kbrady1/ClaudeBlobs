import Foundation

struct CmuxLinker {
    static func activate(_ agent: Agent) {
        guard let workspace = agent.cmuxWorkspace,
              let surface = agent.cmuxSurface else { return }

        let cmuxPath = "/Applications/cmux.app/Contents/Resources/bin/cmux"

        let wsProcess = Process()
        wsProcess.executableURL = URL(fileURLWithPath: cmuxPath)
        wsProcess.arguments = ["select-workspace", "--workspace", workspace]
        try? wsProcess.run()
        wsProcess.waitUntilExit()

        let sfProcess = Process()
        sfProcess.executableURL = URL(fileURLWithPath: cmuxPath)
        sfProcess.arguments = ["select-surface", "--surface", surface, "--workspace", workspace]
        try? sfProcess.run()
        sfProcess.waitUntilExit()
    }
}
