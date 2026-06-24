import Foundation

/// A path that may be rooted in either the app's sandbox container or a
/// security-scoped bookmark obtained from the Files app via UIDocumentPicker.
public enum VirtualRoot: Equatable {
    case container       // NSFileManager.default.url(for: .documentDirectory, ...)
    case bookmark(BookmarkID)
}

public typealias BookmarkID = String

/// The virtual file system the shell operates on. It resolves every path
/// against a current working directory expressed as a logical absolute path
/// (e.g. "/Projects/Termious/README.md") and maps it to a concrete `URL`
/// inside either the app container or a granted bookmark.
public final class VirtualFileSystem {
    var rootKind: VirtualRoot = .container
    var cwd: String = "/"
    var bookmarks: [BookmarkID: Data] = [:]
    private var resolvedRoots: [BookmarkID: URL] = [:]

    public init() {
        loadBookmarks()
        if let id = bookmarks.keys.sorted().first {
            rootKind = .bookmark(id)
            cwd = "/"
        } else {
            rootKind = .container
            cwd = "/"
        }
    }

    // MARK: - Bookmarks / Files app grants

    func addBookmark(for url: URL) -> BookmarkID? {
        do {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            let data = try url.bookmarkData(options: [],
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil)
            let id = url.lastPathComponent.isEmpty ? "root" : url.lastPathComponent
            bookmarks[id] = data
            resolvedRoots[id] = url
            saveBookmarks()
            return id
        } catch {
            return nil
        }
    }

    func resolveBookmark(_ id: BookmarkID) -> URL? {
        if let cached = resolvedRoots[id] { return cached }
        guard let data = bookmarks[id] else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        if stale {
            if let renewed = try? url.bookmarkData(options: [],
                                                    includingResourceValuesForKeys: nil,
                                                    relativeTo: nil) {
                bookmarks[id] = renewed
                saveBookmarks()
            }
        }
        resolvedRoots[id] = url
        return url
    }

    func removeBookmark(_ id: BookmarkID) {
        bookmarks.removeValue(forKey: id)
        resolvedRoots.removeValue(forKey: id)
        saveBookmarks()
        if case .bookmark(let current) = rootKind, current == id {
            rootKind = .container
            cwd = "/"
        }
    }

    private let bookmarksKey = "Termious.bookmarks.v1"

    private func saveBookmarks() {
        UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
    }

    private func loadBookmarks() {
        if let stored = UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] {
            bookmarks = stored
        }
    }

    // MARK: - Root URL

    var rootURL: URL {
        switch rootKind {
        case .container:
            return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
        case .bookmark(let id):
            if let url = resolveBookmark(id) { return url }
            rootKind = .container
            return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
        }
    }

    // MARK: - Path resolution

    /// Resolves a logical path (absolute or relative to `cwd`) to a concrete
    /// file URL. Returns nil if the path tries to escape above the root.
    func resolve(_ logicalPath: String) -> URL? {
        let absolute: String
        if logicalPath.hasPrefix("/") {
            absolute = logicalPath
        } else if logicalPath == "~" || logicalPath.hasPrefix("~/") {
            let rest = logicalPath.dropFirst()
            if rest == "~" { absolute = "/" }
            else { absolute = "/" + String(rest.dropFirst()) }
        } else {
            absolute = join(cwd, logicalPath)
        }

        let normalized = normalize(absolute)
        guard normalized.hasPrefix("/") else { return nil }

        return rootURL.appendingPathComponent(String(normalized.dropFirst()))
    }

    /// Logical absolute path of a resolved URL, expressed relative to root.
    func logicalPath(of url: URL) -> String {
        let root = rootURL.standardizedFileURL.path
        let target = url.standardizedFileURL.path
        guard target.hasPrefix(root) else { return "/" }
        let rel = String(target.dropFirst(root.count))
        return rel.isEmpty ? "/" : (rel.hasPrefix("/") ? rel : "/" + rel)
    }

    func changeDirectory(to path: String) -> ShellResult {
        guard let url = resolve(path) else {
            return .failure("cd: no such directory: \(path)")
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
              isDir.boolValue else {
            return .failure("cd: not a directory: \(path)")
        }
        cwd = logicalPath(of: url)
        if cwd.isEmpty { cwd = "/" }
        return .success("")
    }

    // MARK: - Path helpers

    private func join(_ a: String, _ b: String) -> String {
        if a == "/" { return "/" + b }
        return a + "/" + b
    }

    /// Removes "." and ".." segments and prevents escaping above "/".
    private func normalize(_ path: String) -> String {
        let isAbs = path.hasPrefix("/")
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        var stack: [String] = []
        for part in parts {
            if part == "." { continue }
            if part == ".." {
                if !stack.isEmpty { stack.removeLast() }
            } else {
                stack.append(String(part))
            }
        }
        let joined = stack.joined(separator: "/")
        if isAbs { return "/" + joined }
        return joined.isEmpty ? "/" : joined
    }

    /// Starts security-scoped access on the current root if applicable.
    /// Always pair with `stopRootAccess()`.
    func startRootAccess() -> Bool {
        switch rootKind {
        case .container:
            return true
        case .bookmark(let id):
            if let url = resolveBookmark(id) {
                return url.startAccessingSecurityScopedResource()
            }
            return false
        }
    }

    func stopRootAccess() {
        switch rootKind {
        case .container:
            break
        case .bookmark(let id):
            if let url = resolvedRoots[id] {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }
}

public enum ShellResult {
    case success(String)
    case failure(String)

    var output: String {
        switch self {
        case .success(let s): return s
        case .failure(let s): return s
        }
    }

    var isError: Bool {
        if case .failure = self { return true }
        return false
    }
}