import Foundation
import Darwin

public final class ScanCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    public init() {}
    public func cancel() { lock.lock(); flag = true; lock.unlock() }
    public var isCanceled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}

public enum FileScanner {
    private enum Work { case visit(URL, NodeID?); case close(NodeID) }
    private static let keys: Set<URLResourceKey> = [
        .isPackageKey, .isAliasFileKey, .isHiddenKey, .isUbiquitousItemKey,
        .totalFileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey
    ]
    private static let packageExtensions: Set<String> = [
        "app", "bundle", "framework", "plugin", "photoslibrary", "photolibrary",
        "musiclibrary", "imovielibrary", "fcpbundle", "band", "logicx", "vmwarevm", "pvm", "sparsebundle"
    ]
    public static func identity(at url: URL) -> FileIdentity? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return FileIdentity(device: Int64(info.st_dev), inode: UInt64(info.st_ino))
    }

    /// Blocking worker. Call off the main thread. Reads metadata only; never opens file contents.
    public static func scan(root: URL, cancellation: ScanCancellation,
                            deliver: (ScanBatch) -> Void) -> ScanResult {
        let start = Date(), fm = FileManager()
        let rootDevice = identity(at: root)?.device
        var stack: [Work] = [.visit(root, nil)]
        var nextID = 0, events: [ScanEvent] = [], lastDelivery = Date(), currentPath = root.path
        var hardLinks: [FileIdentity: NodeID] = [:]
        func flush(force: Bool = false) {
            if !events.isEmpty && (force || events.count >= 2000 || Date().timeIntervalSince(lastDelivery) >= 0.25) {
                deliver(ScanBatch(events: events, currentPath: currentPath))
                events.removeAll(keepingCapacity: true); lastDelivery = Date()
            }
        }
        while !stack.isEmpty && !cancellation.isCanceled {
            let work = stack.removeLast()
            switch work {
            case .close(let id): events.append(.closed(id))
            case .visit(let url, let parent):
                autoreleasepool {
                    currentPath = url.path
                    let id = nextID; nextID += 1
                    var node = DiskNode(id: id, parent: parent, name: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent, kind: .other)
                    var info = stat()
                    guard lstat(url.path, &info) == 0 else {
                        node.issue = String(cString: strerror(errno)); node.issueCount = 1
                        node.unknownLogical = 1; node.unknownAllocated = 1
                        events.append(.discovered(node)); return
                    }
                    let identity = FileIdentity(device: Int64(info.st_dev), inode: UInt64(info.st_ino))
                    node.identity = identity
                    let fileType = info.st_mode & S_IFMT
                    // Never resolve links, including links to directories or other volumes.
                    if fileType == S_IFLNK {
                        node.kind = .symbolicLink
                        node.hidden = node.name.hasPrefix(".")
                        events.append(.discovered(node)); return
                    }
                    let values = try? url.resourceValues(forKeys: keys)
                    node.hidden = values?.isHidden ?? node.name.hasPrefix(".")
                    node.cloud = values?.isUbiquitousItem ?? false
                    node.modified = values?.contentModificationDate ?? Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec))
                    if fileType == S_IFDIR {
                        node.kind = (values?.isPackage == true || packageExtensions.contains(url.pathExtension.lowercased())) ? .package : .folder
                        if parent != nil && identity.device != rootDevice {
                            node.issue = "Another mounted volume. Scan this location separately."
                            node.issueCount = 1
                            events.append(.discovered(node)); return
                        }
                        node.pendingDirectories = 1
                        events.append(.discovered(node))
                        do {
                            let children = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys), options: [])
                                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                            stack.append(.close(id))
                            for child in children.reversed() { stack.append(.visit(child, id)) }
                        } catch {
                            events.append(.problem(id, error.localizedDescription))
                            events.append(.closed(id))
                        }
                    } else if fileType == S_IFREG {
                        node.kind = values?.isAliasFile == true ? .alias : .file
                        node.logicalBytes = Int64(values?.totalFileSize ?? Int(info.st_size))
                        if let allocation = values?.totalFileAllocatedSize {
                            node.reportedAllocated = Int64(allocation)
                            node.allocatedBytes = Int64(allocation)
                        } else { node.unknownAllocated = 1 }
                        if info.st_nlink > 1 {
                            if let first = hardLinks[identity] {
                                node.sharedWith = first; node.allocatedBytes = 0; node.unknownAllocated = 0
                            } else { hardLinks[identity] = id }
                        }
                        events.append(.discovered(node))
                    } else {
                        // Sockets/devices are never opened; their content is outside file accounting.
                        events.append(.discovered(node))
                    }
                }
            }
            flush()
        }
        flush(force: true)
        return ScanResult(canceled: cancellation.isCanceled, elapsed: Date().timeIntervalSince(start), itemCount: nextID)
    }
}
