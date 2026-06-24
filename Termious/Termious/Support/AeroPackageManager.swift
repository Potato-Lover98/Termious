import Foundation
import Compression

/// A package installed by Aero, tracked in the manifest.
public struct AeroPackage: Codable, Equatable {
    public var name: String
    public var repo: String        // "owner/repo"
    public var ref: String         // branch/tag/commit
    public var installedAt: Date
    public var localPath: String   // logical path within the aero store
    public var commitSha: String?
    public var description: String?
}

public final class AeroPackageManager {
    public static let shared = AeroPackageManager()

    private(set) var installed: [AeroPackage] = []
    private let lock = NSLock()
    private let manifestName = "aero_manifest.json"
    private let session: URLSession

    public init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 120
        cfg.httpAdditionalHeaders = ["User-Agent": "Termious-Aero/1.0"]
        self.session = URLSession(configuration: cfg)
        loadManifest()
    }

    // MARK: - Store location

    /// The directory under the current root where aero installs packages.
    public func storeRoot(in fs: VirtualFileSystem) -> URL {
        let started = fs.startRootAccess()
        defer { if started { fs.stopRootAccess() } }
        let root = fs.rootURL
        let aeroDir = root.appendingPathComponent(".aero")
        try? FileManager.default.createDirectory(at: aeroDir, withIntermediateDirectories: true)
        return aeroDir
    }

    public func packageURL(_ name: String, in fs: VirtualFileSystem) -> URL {
        storeRoot(in: fs).appendingPathComponent(name)
    }

    // MARK: - Install

    /// Installs a package from GitHub by downloading a zipball of the repo.
    /// - Parameters:
    ///   - repo: "owner/repo" (required) — e.g. "torvalds/linux"
    ///   - ref: optional branch/tag/commit (defaults to HEAD/master)
    ///   - name: local package name (defaults to repo's last component)
    ///   - progress: called with progress messages
    public func install(repo: String, ref: String?, name: String?,
                        fs: VirtualFileSystem,
                        progress: (String) -> Void,
                        completion: @escaping (Result<AeroPackage, Error>) -> Void) {
        let cleanRepo = repo.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let pkgName = name ?? cleanRepo.split(separator: "/").last.map(String.init) ?? cleanRepo
        let refToUse = ref ?? "HEAD"

        progress("Resolving \(cleanRepo) at \(refToUse)...")

        // Step 1: get repo info to resolve the default branch + description
        fetchRepoInfo(repo: cleanRepo) { [weak self] infoResult in
            guard let self = self else { return }
            switch infoResult {
            case .failure(let err):
                completion(.failure(err))
                return
            case .success(let info):
                let actualRef = (ref ?? info.defaultBranch) ?? "HEAD"
                let desc = info.description

                // Step 2: download the zipball
                let zipURLStr = "https://codeload.github.com/\(cleanRepo)/zip/refs/heads/\(actualRef)"
                progress("Downloading \(zipURLStr)...")
                self.downloadZip(urlString: zipURLStr) { dlResult in
                    switch dlResult {
                    case .failure(let err):
                        completion(.failure(err))
                    case .success(let zipData):
                        // Step 3: extract into the store
                        progress("Extracting \(pkgName)...")
                        do {
                            let pkg = try self.extractAndStore(
                                zipData: zipData, name: pkgName, repo: cleanRepo,
                                ref: actualRef, description: desc, fs: fs)
                            progress("Installed \(pkgName) -> /aero/\(pkgName)")
                            completion(.success(pkg))
                        } catch {
                            completion(.failure(error))
                        }
                    }
                }
            }
        }
    }

    /// Fetches repository metadata from the GitHub REST API.
    private func fetchRepoInfo(repo: String,
                               completion: @escaping (Result<(defaultBranch: String?, description: String?), Error>) -> Void) {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)") else {
            completion(.failure(AeroError.invalidRepo))
            return
        }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Termious-Aero/1.0", forHTTPHeaderField: "User-Agent")

        let task = session.dataTask(with: req) { data, response, error in
            if let error = error {
                completion(.failure(error)); return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(AeroError.invalidResponse)); return
            }
            if let msg = json["message"] as? String, msg.contains("Not Found") {
                completion(.failure(AeroError.repoNotFound(repo))); return
            }
            let branch = json["default_branch"] as? String
            let desc = json["description"] as? String
            completion(.success((branch, desc)))
        }
        task.resume()
    }

    /// Downloads a zipball and returns the raw data.
    private func downloadZip(urlString: String,
                             completion: @escaping (Result<Data, Error>) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(.failure(AeroError.invalidURL)); return
        }
        let task = session.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(.failure(error)); return
            }
            guard let data = data, !data.isEmpty else {
                completion(.failure(AeroError.downloadFailed)); return
            }
            completion(.success(data))
        }
        task.resume()
    }

    /// Extracts the zip data into the aero store directory.
    private func extractAndStore(zipData: Data, name: String, repo: String,
                                 ref: String, description: String?,
                                 fs: VirtualFileSystem) throws -> AeroPackage {
        let started = fs.startRootAccess()
        defer { if started { fs.stopRootAccess() } }

        let pkgDir = packageURL(name, in: fs)
        let fm = FileManager.default

        // Remove old install if present
        if fm.fileExists(atPath: pkgDir.path) {
            try? fm.removeItem(at: pkgDir)
        }
        try fm.createDirectory(at: pkgDir, withIntermediateDirectories: true)

        // Write zip to temp, then extract
        let tempZip = pkgDir.appendingPathComponent("__download.zip")
        try zipData.write(to: tempZip)

        try extractZip(at: tempZip, to: pkgDir)
        try? fm.removeItem(at: tempZip)

        // GitHub zipballs contain a single top-level dir like "repo-<sha>/".
        // Flatten it: move contents up one level.
        flattenTopLevel(dir: pkgDir)

        let pkg = AeroPackage(
            name: name, repo: repo, ref: ref,
            installedAt: Date(), localPath: "/.aero/\(name)",
            commitSha: nil, description: description)

        addInstalled(pkg)
        return pkg
    }

    /// A minimal zip extractor that handles STORED (0) and DEFLATE (8) entries.
    private func extractZip(at zipURL: URL, to destDir: URL) throws {
        let fm = FileManager.default
        let data = try Data(contentsOf: zipURL)
        let bytes = [UInt8](data)

        // Find End of Central Directory record
        guard let eocdOffset = findEOCD(in: bytes) else {
            throw AeroError.invalidZip
        }
        let centralDirOffset = readUInt32LE(bytes, at: eocdOffset + 16)
        let centralDirSize = readUInt32LE(bytes, at: eocdOffset + 12)
        let entryCount = readUInt16LE(bytes, at: eocdOffset + 10)

        var offset = Int(centralDirOffset)
        let endOffset = Int(centralDirOffset) + Int(centralDirSize)

        for _ in 0..<entryCount {
            guard offset + 46 <= endOffset else { break }
            guard readUInt32LE(bytes, at: offset) == 0x02014b50 else { break }

            let compressMethod = readUInt16LE(bytes, at: offset + 10)
            let compressedSize = Int(readUInt32LE(bytes, at: offset + 20))
            let uncompressedSize = Int(readUInt32LE(bytes, at: offset + 24))
            let fileNameLength = Int(readUInt16LE(bytes, at: offset + 28))
            let extraFieldLength = Int(readUInt16LE(bytes, at: offset + 30))
            let commentLength = Int(readUInt16LE(bytes, at: offset + 32))
            let localHeaderOffset = Int(readUInt32LE(bytes, at: offset + 42))

            let nameStart = offset + 46
            let nameEnd = nameStart + fileNameLength
            guard nameEnd <= bytes.count else { break }
            let fileName = String(bytes: bytes[nameStart..<nameEnd], encoding: .utf8) ?? ""

            // Move to next central dir entry
            offset = nameEnd + extraFieldLength + commentLength

            guard !fileName.isEmpty else { continue }

            // Read local file header
            guard localHeaderOffset + 30 <= bytes.count,
                  readUInt32LE(bytes, at: localHeaderOffset) == 0x04034b50 else { continue }
            let localNameLen = Int(readUInt16LE(bytes, at: localHeaderOffset + 26))
            let localExtraLen = Int(readUInt16LE(bytes, at: localHeaderOffset + 28))
            let dataStart = localHeaderOffset + 30 + localNameLen + localExtraLen
            guard dataStart + compressedSize <= bytes.count else { continue }

            let entryData = Data(bytes[dataStart..<(dataStart + compressedSize)])
            let outURL = destDir.appendingPathComponent(fileName)

            if fileName.hasSuffix("/") {
                try? fm.createDirectory(at: outURL, withIntermediateDirectories: true)
                continue
            }

            try? fm.createDirectory(at: outURL.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)

            let finalData: Data
            if compressMethod == 0 {
                finalData = entryData
            } else if compressMethod == 8 {
                finalData = try inflateDEFLATE(entryData, expectedSize: uncompressedSize)
            } else {
                continue // unsupported
            }
            try finalData.write(to: outURL)
        }
    }

    /// Walks the package dir; if it contains exactly one subdirectory whose
    /// name starts with the repo name, moves its contents up and removes it.
    private func flattenTopLevel(dir: URL) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dir.path),
              entries.count == 1 else { return }
        let single = dir.appendingPathComponent(entries[0])
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: single.path, isDirectory: &isDir), isDir.boolValue else { return }
        if let inner = try? fm.contentsOfDirectory(atPath: single.path) {
            for item in inner {
                let src = single.appendingPathComponent(item)
                let dst = dir.appendingPathComponent(item)
                try? fm.moveItem(at: src, to: dst)
            }
            try? fm.removeItem(at: single)
        }
    }

    // MARK: - Search

    public func search(query: String,
                       completion: @escaping (Result<[(repo: String, desc: String, stars: Int)], Error>) -> Void) {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://api.github.com/search/repositories?q=\(encoded)&sort=stars&per_page=20") else {
            completion(.failure(AeroError.invalidQuery)); return
        }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Termious-Aero/1.0", forHTTPHeaderField: "User-Agent")

        let task = session.dataTask(with: req) { data, _, error in
            if let error = error {
                completion(.failure(error)); return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else {
                completion(.failure(AeroError.invalidResponse)); return
            }
            let results = items.compactMap { item -> (repo: String, desc: String, stars: Int)? in
                guard let fullName = item["full_name"] as? String else { return nil }
                let desc = (item["description"] as? String) ?? ""
                let stars = (item["stargazers_count"] as? Int) ?? 0
                return (fullName, desc, stars)
            }
            completion(.success(results))
        }
        task.resume()
    }

    // MARK: - List / Delete / Info

    public func listInstalled() -> [AeroPackage] {
        lock.lock(); defer { lock.unlock() }
        return installed.sorted { $0.name < $1.name }
    }

    public func uninstall(name: String, fs: VirtualFileSystem) -> Bool {
        let started = fs.startRootAccess()
        defer { if started { fs.stopRootAccess() } }
        let pkgDir = packageURL(name, in: fs)
        if FileManager.default.fileExists(atPath: pkgDir.path) {
            try? FileManager.default.removeItem(at: pkgDir)
        }
        lock.lock()
        let before = installed.count
        installed.removeAll { $0.name == name }
        let removed = installed.count < before
        saveManifest()
        lock.unlock()
        return removed
    }

    public func packageInfo(name: String) -> AeroPackage? {
        lock.lock(); defer { lock.unlock() }
        return installed.first { $0.name == name }
    }

    // MARK: - Manifest

    private func addInstalled(_ pkg: AeroPackage) {
        lock.lock()
        installed.removeAll { $0.name == pkg.name }
        installed.append(pkg)
        saveManifest()
        lock.unlock()
    }

    private var manifestURL: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent(manifestName)
    }

    private func saveManifest() {
        guard let data = try? JSONEncoder().encode(installed) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    private func loadManifest() {
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode([AeroPackage].self, from: data)
        else { return }
        installed = decoded
    }

    // MARK: - Low-level zip helpers

    private func findEOCD(in bytes: [UInt8]) -> Int? {
        let minSize = 22
        guard bytes.count >= minSize else { return nil }
        let maxScan = min(65557, bytes.count)
        let start = bytes.count - maxScan
        for i in stride(from: bytes.count - minSize, through: max(0, start), by: -1) {
            if readUInt32LE(bytes, at: i) == 0x06054b50 {
                return i
            }
        }
        return nil
    }

    private func readUInt16LE(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        guard offset + 2 <= bytes.count else { return 0 }
        return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private func readUInt32LE(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        guard offset + 4 <= bytes.count else { return 0 }
        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    /// Minimal DEFLATE decompressor using zlib via the Compression framework.
    private func inflateDEFLATE(_ data: Data, expectedSize: Int) throws -> Data {
        let bufSize = max(expectedSize, data.count * 8)
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buffer.deallocate() }

        let result = data.withUnsafeBytes { (srcPtr: UnsafeRawBufferPointer) -> Int in
            guard let base = srcPtr.baseAddress else { return 0 }
            let src = base.assumingMemoryBound(to: UInt8.self)
            return compression_decode_buffer(buffer, bufSize,
                                             src, data.count, nil, COMPRESSION_ZLIB)
        }
        if result == 0 {
            throw AeroError.decompressionFailed
        }
        return Data(bytes: buffer, count: result)
    }
}

public enum AeroError: Error, CustomStringConvertible {
    case invalidRepo
    case invalidURL
    case invalidQuery
    case invalidResponse
    case downloadFailed
    case repoNotFound(String)
    case invalidZip
    case decompressionFailed
    case packageNotFound(String)

    public var description: String {
        switch self {
        case .invalidRepo: return "invalid repository specified"
        case .invalidURL: return "invalid URL"
        case .invalidQuery: return "invalid search query"
        case .invalidResponse: return "invalid API response"
        case .downloadFailed: return "download failed"
        case .repoNotFound(let r): return "repository '\(r)' not found"
        case .invalidZip: return "invalid zip file"
        case .decompressionFailed: return "failed to decompress zip entry"
        case .packageNotFound(let n): return "package '\(n)' not found"
        }
    }
}