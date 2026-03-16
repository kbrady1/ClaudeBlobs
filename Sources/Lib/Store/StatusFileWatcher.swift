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
        try? FileManager.default.createDirectory(
            at: directoryURL, withIntermediateDirectories: true
        )

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

    deinit { stop() }
}
