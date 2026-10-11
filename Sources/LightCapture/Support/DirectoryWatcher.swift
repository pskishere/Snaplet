import Foundation
import Darwin

final class DirectoryWatcher {
    private let source: DispatchSourceFileSystemObject
    init?(url: URL, changed: @escaping () -> Void) {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .global(qos: .utility))
        source.setEventHandler(handler: changed)
        source.setCancelHandler { close(descriptor) }
        source.resume()
    }
    deinit { source.cancel() }
}
