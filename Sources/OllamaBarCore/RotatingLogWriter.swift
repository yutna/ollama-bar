// SPDX-License-Identifier: MIT
//
// Part of OllamaBar — https://github.com/yutna/ollama-bar

import Foundation

/// Appends `ollama serve` output to `server.log`, rotating the file when it
/// grows past the cap — including while the server keeps running.
///
/// The app writes the log itself instead of handing the child a file handle:
/// a running process would keep writing to the rotated inode, so rotation
/// could only ever happen at start and a long session could grow the log
/// without bound.
///
/// The cap is checked after every write, so a single chunk larger than the cap
/// ends up in `server.log.1` whole and the current file can be empty right
/// after a rotation.
final class RotatingLogWriter: @unchecked Sendable {
    /// Default cap for `server.log` (10 MB).
    static let defaultMaxBytes: UInt64 = 10 * 1024 * 1024

    private let path: String
    private let maxBytes: UInt64
    private let lock = NSLock()
    private var handle: FileHandle?
    private var size: UInt64 = 0
    private var isClosed = false

    init(path: String, maxBytes: UInt64 = defaultMaxBytes) {
        self.path = path
        self.maxBytes = maxBytes
    }

    /// Opens the log, moving an oversized file left by a previous session
    /// aside first.
    func open() {
        lock.lock()
        defer { lock.unlock() }
        isClosed = false
        rotateIfOversized()
        handle = Self.openForAppending(path)
        size = Self.fileSize(path)
    }

    /// Appends a chunk and rotates once the cap is crossed.
    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return }
        if handle == nil {
            handle = Self.openForAppending(path)
        }
        do {
            try handle?.write(contentsOf: data)
        } catch {
            return
        }
        size += UInt64(data.count)
        if size > maxBytes {
            rotate()
        }
    }

    /// Stops writing and releases the file handle; later appends are ignored.
    func close() {
        lock.lock()
        defer { lock.unlock() }
        isClosed = true
        try? handle?.close()
        handle = nil
    }

    // MARK: - Rotation

    private func rotate() {
        try? handle?.close()
        handle = nil
        moveAside()
        size = 0
        handle = Self.openForAppending(path)
    }

    private func rotateIfOversized() {
        guard Self.fileSize(path) > maxBytes else { return }
        moveAside()
    }

    /// Moves `server.log` to `server.log.1`, replacing the previous rotation.
    private func moveAside() {
        let rotated = path + ".1"
        try? FileManager.default.removeItem(atPath: rotated)
        try? FileManager.default.moveItem(atPath: path, toPath: rotated)
    }

    // MARK: - Files

    private static func openForAppending(_ path: String) -> FileHandle? {
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true)
        // O_APPEND keeps concurrent writers (several servers share one log)
        // from overwriting each other's offsets.
        let descriptor = Darwin.open(path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard descriptor >= 0 else { return nil }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    private static func fileSize(_ path: String) -> UInt64 {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? UInt64 ?? 0
    }
}
