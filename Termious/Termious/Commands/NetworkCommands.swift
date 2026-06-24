import Foundation
import Compression

// MARK: - Data little-endian append helpers

private extension Data {
    mutating func append(uint16 value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }
    mutating func append(uint32 value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}

/// `wget` - download a file from a URL.
/// Usage: wget [-O output] <url>
struct WgetCommand: BuiltinCommand {
    let name = "wget"
    let summary = "Download a file from the web"
    let usage = "wget [-O output] <url>"
    var operands: [Operand] {[
        Operand(name: "url", description: "URL to download from", required: true, type: .string),
        Operand(name: "output", description: "Output filename (with -O)", required: false, type: .file),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var outputPath: String? = nil
        var urlStr: String? = nil
        var i = 0
        while i < arguments.count {
            let a = arguments[i]
            if a == "-O" && i + 1 < arguments.count {
                outputPath = arguments[i + 1]; i += 2
            } else if !a.hasPrefix("-") {
                urlStr = a; i += 1
            } else { i += 1 }
        }
        guard let urlStr = urlStr, let url = URL(string: urlStr) else {
            context.stderr("wget: missing or invalid URL\n")
            return 1
        }
        let name = outputPath ?? url.lastPathComponent
        guard let dest = context.fs.resolve(name) else {
            context.stderr("wget: cannot resolve destination '\(name)'\n")
            return 1
        }
        context.stdout("Downloading \(urlStr)...\n")
        let group = DispatchGroup()
        var exitCode: Int32 = 0
        group.enter()
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                context.stderr("wget: \(error.localizedDescription)\n")
                exitCode = 1
            } else if let data = data {
                let started = context.fs.startRootAccess()
                do { try data.write(to: dest) }
                catch {
                    context.stderr("wget: \(error.localizedDescription)\n")
                    exitCode = 1
                }
                if started { context.fs.stopRootAccess() }
                if exitCode == 0 {
                    let kb = Double(data.count) / 1024.0
                    context.stdout(String(format: "Saved to %@ (%.1f KB)\n", name, kb))
                }
            }
            group.leave()
        }
        task.resume()
        group.wait()
        return exitCode
    }
}

/// `curl` - fetch a URL and print to stdout (or save with -o).
/// Usage: curl [-o file] <url>
struct CurlCommand: BuiltinCommand {
    let name = "curl"
    let summary = "Fetch a URL and print contents"
    let usage = "curl [-o file] <url>"
    var operands: [Operand] {[
        Operand(name: "url", description: "URL to fetch", required: true, type: .string),
        Operand(name: "file", description: "Output file (with -o)", required: false, type: .file),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var outputFile: String? = nil
        var urlStr: String? = nil
        var showHeaders = false
        var i = 0
        while i < arguments.count {
            let a = arguments[i]
            if a == "-o" && i + 1 < arguments.count {
                outputFile = arguments[i + 1]; i += 2
            } else if a == "-i" { showHeaders = true; i += 1 }
            else if !a.hasPrefix("-") { urlStr = a; i += 1 }
            else { i += 1 }
        }
        guard let urlStr = urlStr, let url = URL(string: urlStr) else {
            context.stderr("curl: missing or invalid URL\n")
            return 1
        }
        let group = DispatchGroup()
        var exitCode: Int32 = 0
        group.enter()
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                context.stderr("curl: \(error.localizedDescription)\n")
                exitCode = 1
            } else if let data = data {
                if showHeaders, let resp = response as? HTTPURLResponse {
                    context.stdout("HTTP \(resp.statusCode)\n")
                    for (k, v) in resp.allHeaderFields {
                        context.stdout("\(k): \(v)\n")
                    }
                    context.stdout("\n")
                }
                if let outputFile = outputFile {
                    if let dest = context.fs.resolve(outputFile) {
                        let started = context.fs.startRootAccess()
                        try? data.write(to: dest)
                        if started { context.fs.stopRootAccess() }
                    }
                } else {
                    if let str = String(data: data, encoding: .utf8) {
                        context.stdout(str)
                        if !str.hasSuffix("\n") { context.stdout("\n") }
                    } else {
                        context.stdout("[\(data.count) bytes of binary data]\n")
                    }
                }
            }
            group.leave()
        }
        task.resume()
        group.wait()
        return exitCode
    }
}

/// `zip` - create a simple zip archive (STORED only, no compression).
/// Usage: zip <archive.zip> <file...>
struct ZipCommand: BuiltinCommand {
    let name = "zip"
    let summary = "Create a zip archive"
    let usage = "zip <archive.zip> <file...>"
    var operands: [Operand] {[
        Operand(name: "archive", description: "Output zip filename", required: true, type: .file),
        Operand(name: "file", description: "File(s) to add to archive", required: true, type: .file),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard arguments.count >= 2 else {
            context.stderr("zip: missing operand\nusage: \(usage)\n")
            return 1
        }
        let archiveName = arguments[0]
        let files = Array(arguments.dropFirst())
        guard let archiveURL = context.fs.resolve(archiveName) else {
            context.stderr("zip: cannot create '\(archiveName)'\n")
            return 1
        }
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        let fm = FileManager.default
        var entries: [(name: String, data: Data)] = []
        for file in files {
            guard let url = context.fs.resolve(file) else { continue }
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
                if let data = try? Data(contentsOf: url) {
                    entries.append((file, data))
                }
            }
        }
        if entries.isEmpty {
            context.stderr("zip: nothing to archive\n")
            return 1
        }
        let zipData = buildZip(entries: entries)
        do { try zipData.write(to: archiveURL) }
        catch {
            context.stderr("zip: \(error.localizedDescription)\n")
            return 1
        }
        context.stdout("  adding: \(files.joined(separator: " "))\n")
        context.stdout("Created \(archiveName) (\(entries.count) entries, \(zipData.count) bytes)\n")
        return 0
    }

    private func buildZip(entries: [(name: String, data: Data)]) -> Data {
        var zip = Data()
        var centralDir = Data()
        var offset: UInt32 = 0

        for entry in entries {
            let nameBytes = Array(entry.name.utf8)
            let nameData = Data(nameBytes)
            let crc = crc32(entry.data)
            let compressed = entry.data // STORED, no compression

            // Local file header
            var local = Data()
            local.append(uint32: 0x04034b50)        // signature
            local.append(uint16: 20)                // version needed
            local.append(uint16: 0)                 // flags
            local.append(uint16: 0)                 // compression (0=stored)
            local.append(uint16: 0)                 // mod time
            local.append(uint16: 0)                 // mod date
            local.append(uint32: crc)               // crc32
            local.append(uint32: UInt32(compressed.count)) // compressed size
            local.append(uint32: UInt32(compressed.count)) // uncompressed size
            local.append(uint16: UInt16(nameBytes.count))  // name length
            local.append(uint16: 0)                 // extra length
            local.append(nameData)
            local.append(compressed)

            // Central dir entry
            var central = Data()
            central.append(uint32: 0x02014b50)      // signature
            central.append(uint16: 20)              // version made by
            central.append(uint16: 20)              // version needed
            central.append(uint16: 0)               // flags
            central.append(uint16: 0)               // compression
            central.append(uint16: 0)               // mod time
            central.append(uint16: 0)               // mod date
            central.append(uint32: crc)
            central.append(uint32: UInt32(compressed.count))
            central.append(uint32: UInt32(compressed.count))
            central.append(uint16: UInt16(nameBytes.count))
            central.append(uint16: 0)               // extra length
            central.append(uint16: 0)               // comment length
            central.append(uint16: 0)               // disk number
            central.append(uint16: 0)               // internal attrs
            central.append(uint32: 0)               // external attrs
            central.append(uint32: offset)          // local header offset
            central.append(nameData)

            zip.append(local)
            centralDir.append(central)
            offset += UInt32(local.count)
        }

        let cdOffset = offset
        let cdSize = UInt32(centralDir.count)
        zip.append(centralDir)

        // End of central dir
        var eocd = Data()
        eocd.append(uint32: 0x06054b50)
        eocd.append(uint16: 0)                    // disk number
        eocd.append(uint16: 0)                    // disk with cd
        eocd.append(uint16: UInt16(entries.count)) // entries on this disk
        eocd.append(uint16: UInt16(entries.count)) // total entries
        eocd.append(uint32: cdSize)
        eocd.append(uint32: cdOffset)
        eocd.append(uint16: 0)                    // comment length
        zip.append(eocd)
        return zip
    }

    private func crc32(_ data: Data) -> UInt32 {
        var table: [UInt32] = []
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 {
                if c & 1 != 0 { c = 0xEDB88320 ^ (c >> 1) }
                else { c >>= 1 }
            }
            table.append(c)
        }
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

/// `unzip` - list or extract a zip archive.
/// Usage: unzip [-l] <archive.zip> [-d dest]
struct UnzipCommand: BuiltinCommand {
    let name = "unzip"
    let summary = "Extract or list a zip archive"
    let usage = "unzip [-l] <archive.zip> [-d dest]"
    var operands: [Operand] {[
        Operand(name: "archive", description: "Zip file to extract or list", required: true, type: .file),
        Operand(name: "dest", description: "Destination directory (with -d)", required: false, type: .directory),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var listOnly = false
        var archivePath: String? = nil
        var destDir: String? = nil
        var i = 0
        while i < arguments.count {
            let a = arguments[i]
            if a == "-l" { listOnly = true; i += 1 }
            else if a == "-d" && i + 1 < arguments.count { destDir = arguments[i + 1]; i += 2 }
            else if !a.hasPrefix("-") { archivePath = a; i += 1 }
            else { i += 1 }
        }
        guard let archivePath = archivePath,
              let archiveURL = context.fs.resolve(archivePath),
              let data = try? Data(contentsOf: archiveURL) else {
            context.stderr("unzip: cannot open archive\n")
            return 1
        }
        let entries = listZipEntries(data)
        if entries.isEmpty {
            context.stderr("unzip: no entries found (invalid zip?)\n")
            return 1
        }
        if listOnly {
            context.stdout("  Length      Date    Time    Name\n")
            context.stdout("---------  ---------- -----   ----\n")
            var total = 0
            for e in entries {
                context.stdout(String(format: "%9d  ---------- -----   %@\n", e.size, e.name))
                total += e.size
            }
            context.stdout("---------                     -------\n")
            context.stdout(String(format: "%9d                     %d files\n", total, entries.count))
            return 0
        }
        // Extract
        let dest = destDir ?? "."
        guard let destURL = context.fs.resolve(dest) else {
            context.stderr("unzip: cannot resolve destination\n")
            return 1
        }
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        let fm = FileManager.default
        try? fm.createDirectory(at: destURL, withIntermediateDirectories: true)
        for e in entries {
            let outURL = destURL.appendingPathComponent(e.name)
            if e.name.hasSuffix("/") {
                try? fm.createDirectory(at: outURL, withIntermediateDirectories: true)
                continue
            }
            try? fm.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? e.data.write(to: outURL)
            context.stdout("  extracting: \(e.name)\n")
        }
        context.stdout("Done: \(entries.count) entries extracted to \(dest)\n")
        return 0
    }

    private struct ZipEntry { var name: String; var size: Int; var data: Data }

    private func listZipEntries(_ data: Data) -> [ZipEntry] {
        let bytes = [UInt8](data)
        guard let eocdOffset = findEOCD(in: bytes) else { return [] }
        let cdOffset = Int(readUInt32LE(bytes, at: eocdOffset + 16))
        let cdSize = Int(readUInt32LE(bytes, at: eocdOffset + 12))
        let count = Int(readUInt16LE(bytes, at: eocdOffset + 10))
        var entries: [ZipEntry] = []
        var offset = cdOffset
        let end = cdOffset + cdSize
        for _ in 0..<count {
            guard offset + 46 <= end, readUInt32LE(bytes, at: offset) == 0x02014b50 else { break }
            let method = readUInt16LE(bytes, at: offset + 10)
            let compSize = Int(readUInt32LE(bytes, at: offset + 20))
            let uncompSize = Int(readUInt32LE(bytes, at: offset + 24))
            let nameLen = Int(readUInt16LE(bytes, at: offset + 28))
            let extraLen = Int(readUInt16LE(bytes, at: offset + 30))
            let commentLen = Int(readUInt16LE(bytes, at: offset + 32))
            let localOff = Int(readUInt32LE(bytes, at: offset + 42))
            let nameStart = offset + 46
            let name = String(bytes: bytes[nameStart..<(nameStart + nameLen)], encoding: .utf8) ?? ""
            offset = nameStart + nameLen + extraLen + commentLen

            guard localOff + 30 <= bytes.count,
                  readUInt32LE(bytes, at: localOff) == 0x04034b50 else { continue }
            let localNameLen = Int(readUInt16LE(bytes, at: localOff + 26))
            let localExtraLen = Int(readUInt16LE(bytes, at: localOff + 28))
            let dataStart = localOff + 30 + localNameLen + localExtraLen
            guard dataStart + compSize <= bytes.count else { continue }
            let entryData: Data
            if method == 0 {
                entryData = Data(bytes[dataStart..<(dataStart + compSize)])
            } else if method == 8 {
                entryData = (try? inflate(Data(bytes[dataStart..<(dataStart + compSize)]), expected: uncompSize)) ?? Data()
            } else {
                entryData = Data()
            }
            entries.append(ZipEntry(name: name, size: uncompSize, data: entryData))
        }
        return entries
    }

    private func findEOCD(in bytes: [UInt8]) -> Int? {
        guard bytes.count >= 22 else { return nil }
        for i in stride(from: bytes.count - 22, through: max(0, bytes.count - 65557), by: -1) {
            if readUInt32LE(bytes, at: i) == 0x06054b50 { return i }
        }
        return nil
    }

    private func readUInt16LE(_ b: [UInt8], at o: Int) -> UInt16 {
        guard o + 2 <= b.count else { return 0 }
        return UInt16(b[o]) | (UInt16(b[o + 1]) << 8)
    }
    private func readUInt32LE(_ b: [UInt8], at o: Int) -> UInt32 {
        guard o + 4 <= b.count else { return 0 }
        return UInt32(b[o]) | (UInt32(b[o + 1]) << 8) | (UInt32(b[o + 2]) << 16) | (UInt32(b[o + 3]) << 24)
    }
    private func inflate(_ data: Data, expected: Int) throws -> Data {
        let bufSize = max(expected * 2, data.count * 8)
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buffer.deallocate() }
        let result = data.withUnsafeBytes { src -> Int in
            guard let base = src.baseAddress else { return 0 }
            return compression_decode_buffer(buffer, bufSize,
                                             base.assumingMemoryBound(to: UInt8.self), data.count, nil, COMPRESSION_ZLIB)
        }
        if result == 0 { throw NSError(domain: "unzip", code: 1) }
        return Data(bytes: buffer, count: result)
    }
}

/// `tar` - create or list a simple tar archive.
/// Usage: tar -cf <archive.tar> <file...> | tar -tf <archive.tar> | tar -xf <archive.tar>
struct TarCommand: BuiltinCommand {
    let name = "tar"
    let summary = "Create or extract a tar archive"
    let usage = "tar -cf archive.tar files... | tar -tf archive.tar | tar -xf archive.tar"
    var operands: [Operand] {[
        Operand(name: "archive", description: "Tar file to create/list/extract", required: true, type: .file),
        Operand(name: "file", description: "File(s) to add (with -c)", required: false, type: .file),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var mode: String? = nil
        var archive: String? = nil
        var files: [String] = []
        for a in arguments {
            if a.hasPrefix("-") && a.count == 3 {
                mode = String(a.dropFirst())
            } else if a.hasPrefix("-") && a.count == 2 {
                mode = String(a.dropFirst())
            } else if archive == nil {
                archive = a
            } else {
                files.append(a)
            }
        }
        guard let mode = mode, let archive = archive else {
            context.stderr("tar: missing mode or archive\nusage: \(usage)\n")
            return 1
        }
        if mode.contains("c") { return create(archive, files, context: context) }
        if mode.contains("t") { return list(archive, context: context) }
        if mode.contains("x") { return extract(archive, context: context) }
        context.stderr("tar: unknown mode\n")
        return 1
    }

    private func create(_ archive: String, _ files: [String], context: CommandContext) -> Int32 {
        guard let archiveURL = context.fs.resolve(archive) else { return 1 }
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        var tar = Data()
        for file in files {
            guard let url = context.fs.resolve(file) else { continue }
            if let data = try? Data(contentsOf: url) {
                tar.append(buildEntry(name: file, data: data))
            }
        }
        tar.append(Data(repeating: 0, count: 1024))
        try? tar.write(to: archiveURL)
        context.stdout("Created \(archive) (\(files.count) files, \(tar.count) bytes)\n")
        return 0
    }

    private func list(_ archive: String, context: CommandContext) -> Int32 {
        guard let url = context.fs.resolve(archive),
              let data = try? Data(contentsOf: url) else { return 1 }
        var offset = 0
        while offset + 512 <= data.count {
            let nameData = data.subdata(in: offset..<(offset + 100))
            let name = String(data: nameData, encoding: .utf8)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0")) ?? ""
            if name.isEmpty { break }
            let sizeStr = String(data: data.subdata(in: (offset + 124)..<(offset + 136)),
                                 encoding: .ascii)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")) ?? "0"
            let size = Int(sizeStr, radix: 8) ?? 0
            context.stdout("\(name)\n")
            offset += 512 + ((size + 511) / 512) * 512
        }
        return 0
    }

    private func extract(_ archive: String, context: CommandContext) -> Int32 {
        guard let url = context.fs.resolve(archive),
              let data = try? Data(contentsOf: url) else { return 1 }
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        var offset = 0
        var count = 0
        while offset + 512 <= data.count {
            let nameData = data.subdata(in: offset..<(offset + 100))
            let name = String(data: nameData, encoding: .utf8)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0")) ?? ""
            if name.isEmpty { break }
            let sizeStr = String(data: data.subdata(in: (offset + 124)..<(offset + 136)),
                                 encoding: .ascii)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")) ?? "0"
            let size = Int(sizeStr, radix: 8) ?? 0
            let dataEnd = offset + 512 + size
            guard dataEnd <= data.count else { break }
            let fileData = data.subdata(in: (offset + 512)..<dataEnd)
            let outURL = context.fs.resolve(name)
            if let out = outURL {
                try? FileManager.default.createDirectory(
                    at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fileData.write(to: out)
                context.stdout("  extracting: \(name)\n")
                count += 1
            }
            offset += 512 + ((size + 511) / 512) * 512
        }
        context.stdout("Extracted \(count) files\n")
        return 0
    }

    private func buildEntry(name: String, data: Data) -> Data {
        var entry = Data(repeating: 0, count: 512)
        let nameBytes = Array(name.utf8.prefix(100))
        for (i, b) in nameBytes.enumerated() { entry[i] = b }
        // mode: "644 \0"
        setOctal(&entry, offset: 100, value: 0o644, length: 8)
        // uid/gid: 0
        setOctal(&entry, offset: 108, value: 0, length: 8)
        setOctal(&entry, offset: 116, value: 0, length: 8)
        // size
        setOctal(&entry, offset: 124, value: data.count, length: 12)
        // mtime
        setOctal(&entry, offset: 136, value: Int(Date().timeIntervalSince1970), length: 12)
        // checksum placeholder
        for i in 148..<156 { entry[i] = 0x20 }
        // typeflag: '0' = file
        entry[156] = 0x30
        // compute checksum
        var sum = 0
        for byte in entry { sum += Int(byte) }
        setOctal(&entry, offset: 148, value: sum, length: 7)
        entry[155] = 0x20
        entry.append(data)
        let pad = (512 - (data.count % 512)) % 512
        if pad > 0 { entry.append(Data(repeating: 0, count: pad)) }
        return entry
    }

    private func setOctal(_ data: inout Data, offset: Int, value: Int, length: Int) {
        let str = String(format: "%0\(length - 1)o", value) + "\0"
        let bytes = Array(str.utf8)
        for (i, b) in bytes.enumerated() {
            if offset + i < data.count { data[offset + i] = b }
        }
    }
}