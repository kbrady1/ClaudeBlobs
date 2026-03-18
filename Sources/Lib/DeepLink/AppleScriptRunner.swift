import Foundation

enum AppleScriptRunner {
    private static let ttyPathPattern = try! NSRegularExpression(pattern: #"^/dev/ttys\d{1,4}$"#)

    static func isValidTTYPath(_ path: String) -> Bool {
        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        return ttyPathPattern.firstMatch(in: path, range: range) != nil
    }

    static func run(_ source: String) async -> Bool {
        DebugLog.shared.log("AppleScriptRunner: executing script:\n\(source)")
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                guard let script = NSAppleScript(source: source) else {
                    DebugLog.shared.log("AppleScriptRunner: failed to create NSAppleScript")
                    continuation.resume(returning: false)
                    return
                }
                let result = script.executeAndReturnError(&error)
                if let error {
                    DebugLog.shared.log("AppleScriptRunner error: \(error)")
                    continuation.resume(returning: false)
                } else {
                    DebugLog.shared.log("AppleScriptRunner: success, result=\(result.stringValue ?? "(no string)")")
                    continuation.resume(returning: true)
                }
            }
        }
    }
}
