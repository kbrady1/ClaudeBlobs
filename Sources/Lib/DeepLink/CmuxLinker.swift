import AppKit
import Foundation

struct CmuxLinker {
    private static let defaultSocketPath = "/tmp/cmux.sock"

    static func activate(_ agent: Agent) {
        guard let workspace = agent.cmuxWorkspace else {
            DebugLog.shared.log("CmuxLinker: no workspace ID, falling back to app activation")
            activateHost(agent)
            return
        }

        let socketPath = agent.cmuxSocketPath ?? defaultSocketPath

        // Try to select workspace via JSON-RPC
        DebugLog.shared.log("CmuxLinker: selecting workspace \(workspace) via socket \(socketPath)")
        let wsResult = sendRPC(
            socketPath: socketPath,
            method: "workspace.select",
            params: ["workspace_id": workspace]
        )
        DebugLog.shared.log("  workspace.select result: \(wsResult ?? "nil")")

        // If socket access denied, fall back to just activating the app
        if let result = wsResult, result.contains("Access denied") {
            DebugLog.shared.log("  socket access denied — activate host app only. Set CMUX_SOCKET_MODE=allowAll for full deep-linking.")
            activateHost(agent)
            return
        }

        // Focus surface if available
        if let surface = agent.cmuxSurface {
            DebugLog.shared.log("CmuxLinker: focusing surface \(surface)")
            let sfResult = sendRPC(
                socketPath: socketPath,
                method: "surface.focus",
                params: ["surface_id": surface]
            )
            DebugLog.shared.log("  surface.focus result: \(sfResult ?? "nil")")
        }

        activateHost(agent)
    }

    private static func activateHost(_ agent: Agent) {
        // Try the standalone cmux app first
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.cmuxterm.app"
        }) {
            app.unhide()
            app.activate()
            DebugLog.shared.log("  activated cmux app via NSWorkspace")
            return
        }

        // cmux is running inside another terminal — use TTY-based tab selection
        DebugLog.shared.log("  cmux app not found, using TabSelector for host terminal")
        TabSelector.activateTab(for: agent)
    }

    private static func validateSocketPath(_ path: String) -> Bool {
        // Only allow paths that look like legitimate cmux sockets
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let parent = (path as NSString).deletingLastPathComponent
        guard fm.fileExists(atPath: parent, isDirectory: &isDir), isDir.boolValue else {
            DebugLog.shared.log("  socket parent directory does not exist: \(parent)")
            return false
        }

        // Verify the socket file is owned by the current user
        if fm.fileExists(atPath: path) {
            if let attrs = try? fm.attributesOfItem(atPath: path),
               let ownerID = attrs[.ownerAccountID] as? NSNumber {
                let currentUID = getuid()
                if ownerID.uint32Value != currentUID {
                    DebugLog.shared.log("  socket owned by uid \(ownerID), expected \(currentUID)")
                    return false
                }
            }
        }

        return true
    }

    private static func sendRPC(socketPath: String, method: String, params: [String: String]) -> String? {
        guard validateSocketPath(socketPath) else {
            DebugLog.shared.log("  rejected socket path: \(socketPath)")
            return nil
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            DebugLog.shared.log("  socket() failed: \(errno)")
            return nil
        }
        defer { close(fd) }

        // Set a 5-second timeout on read/write to prevent hanging on unresponsive sockets
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(104)) { dest in
                for (i, byte) in pathBytes.enumerated() where i < 104 {
                    dest[i] = byte
                }
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard connectResult == 0 else {
            DebugLog.shared.log("  connect() failed: \(errno) (\(String(cString: strerror(errno))))")
            return nil
        }

        let paramsJSON = params.map { "\"\($0.key)\":\"\($0.value)\"" }.joined(separator: ",")
        let request = "{\"id\":\"hud\",\"method\":\"\(method)\",\"params\":{\(paramsJSON)}}\n"

        guard let data = request.data(using: .utf8) else { return nil }

        let written = data.withUnsafeBytes { buf in
            write(fd, buf.baseAddress!, buf.count)
        }
        DebugLog.shared.log("  sent \(written) bytes: \(request.trimmingCharacters(in: .newlines))")

        var responseData = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(fd, &buffer, buffer.count)
        if bytesRead > 0 {
            responseData.append(contentsOf: buffer[0..<bytesRead])
        }

        return String(data: responseData, encoding: .utf8)
    }
}
