import Foundation

/// Per-file metadata store for virtual ownership (owner, group, permissions)
/// and any other metadata Termious tracks. Stored as JSON in the app's
/// Application Support directory, keyed by logical path relative to the
/// current root.
public struct VirtualFileAttributes: Codable, Equatable {
    public var owner: String
    public var group: String
    public var permissions: String   // e.g. "755" (rwxr-xr-x)

    public init(owner: String = "mobile", group: String = "staff",
                permissions: String = "644") {
        self.owner = owner
        self.group = group
        self.permissions = permissions
    }
}

public final class FileMetadataStore {
    public static let shared = FileMetadataStore()

    private var attributes: [String: VirtualFileAttributes] = [:]
    private let lock = NSLock()
    private let filename = "file_metadata.json"

    public init() {
        load()
    }

    public func get(_ logicalPath: String) -> VirtualFileAttributes {
        lock.lock(); defer { lock.unlock() }
        return attributes[normalize(logicalPath)] ?? VirtualFileAttributes()
    }

    public func set(_ logicalPath: String, attrs: VirtualFileAttributes) {
        lock.lock(); defer { lock.unlock() }
        attributes[normalize(logicalPath)] = attrs
        save()
    }

    public func update(_ logicalPath: String, owner: String? = nil,
                       group: String? = nil, permissions: String? = nil) {
        lock.lock(); defer { lock.unlock() }
        let key = normalize(logicalPath)
        var current = attributes[key] ?? VirtualFileAttributes()
        if let o = owner { current.owner = o }
        if let g = group { current.group = g }
        if let p = permissions { current.permissions = p }
        attributes[key] = current
        save()
    }

    public func remove(_ logicalPath: String) {
        lock.lock(); defer { lock.unlock() }
        attributes.removeValue(forKey: normalize(logicalPath))
        save()
    }

    private func normalize(_ path: String) -> String {
        var p = path
        if p.hasPrefix("/") { p.removeFirst() }
        return p
    }

    // MARK: - Persistence

    private var storeURL: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent(filename)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(attributes) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([String: VirtualFileAttributes].self, from: data)
        else { return }
        attributes = decoded
    }
}