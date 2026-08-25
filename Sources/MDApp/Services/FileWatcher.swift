import Foundation

/// Watches a single file for external modification.
///
/// Watching the file descriptor alone is not enough: almost every editor saves
/// atomically, replacing the inode. The old descriptor then reports `.delete`
/// and goes silent on a file that still exists. So the parent directory is
/// watched too, and a delete/rename triggers a re-arm against the new inode.
final class FileWatcher {
    private var fileSource: DispatchSourceFileSystemObject?
    private var dirSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var dirDescriptor: Int32 = -1
    private let queue = DispatchQueue(label: "com.hmuyal.mdapp.filewatcher")

    private(set) var url: URL
    private let onChange: (URL) -> Void
    private var debounce: DispatchWorkItem?

    init(url: URL, onChange: @escaping (URL) -> Void) {
        self.url = url
        self.onChange = onChange
        start()
    }

    deinit { stop() }

    private func start() {
        watchFile()
        watchDirectory()
    }

    private func watchFile() {
        fileSource?.cancel()
        fileSource = nil
        if fileDescriptor >= 0 { close(fileDescriptor); fileDescriptor = -1 }

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename, .attrib],
            queue: queue)

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.rename) {
                // Atomic save: re-arm against the replacement inode.
                self.queue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.watchFile()
                    self?.notify()
                }
            } else {
                self.notify()
            }
        }
        source.setCancelHandler { [weak self] in
            guard let self, self.fileDescriptor >= 0 else { return }
            close(self.fileDescriptor)
            self.fileDescriptor = -1
        }
        source.resume()
        fileSource = source
    }

    private func watchDirectory() {
        let dir = url.deletingLastPathComponent()
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        dirDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write], queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            // A write in the directory may be the atomic replacement landing.
            if self.fileDescriptor < 0, FileManager.default.fileExists(atPath: self.url.path) {
                self.watchFile()
                self.notify()
            }
        }
        source.setCancelHandler { [weak self] in
            guard let self, self.dirDescriptor >= 0 else { return }
            close(self.dirDescriptor)
            self.dirDescriptor = -1
        }
        source.resume()
        dirSource = source
    }

    /// Coalesces the burst of events a single save produces.
    private func notify() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async { self.onChange(self.url) }
        }
        debounce = work
        queue.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    func stop() {
        debounce?.cancel()
        fileSource?.cancel(); fileSource = nil
        dirSource?.cancel();  dirSource = nil
    }
}
