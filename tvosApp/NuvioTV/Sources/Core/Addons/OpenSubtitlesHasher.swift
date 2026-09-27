//
//  OpenSubtitlesHasher.swift
//  NuvioTV
//
//  Computes the 64-bit OpenSubtitles video hash (CRC64-based algorithm using
//  the file size plus the first 64KB and last 64KB 64-bit integers).
//

import Foundation

public enum OpenSubtitlesHasher {
    private static let chunkSize: Int = 65536 // 64 KB

    /// Computes the 16-character hexadecimal OpenSubtitles hash and file size for a local file URL.
    /// Returns nil if the file does not exist, cannot be read, or is smaller than 64KB.
    public static func computeHashAndSize(for fileURL: URL) -> (hash: String, size: Int64)? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }

        do {
            let fileSize = try handle.seekToEnd()
            guard fileSize >= UInt64(chunkSize) else { return nil }

            var hash: UInt64 = fileSize

            // First 64KB
            try handle.seek(toOffset: 0)
            guard let headData = try handle.read(upToCount: chunkSize), headData.count == chunkSize else {
                return nil
            }
            hash = headData.withUnsafeBytes { rawBuffer -> UInt64 in
                let buffer = rawBuffer.bindMemory(to: UInt64.self)
                var current = hash
                for val in buffer {
                    current = current &+ UInt64(littleEndian: val)
                }
                return current
            }

            // Last 64KB
            try handle.seek(toOffset: fileSize - UInt64(chunkSize))
            guard let tailData = try handle.read(upToCount: chunkSize), tailData.count == chunkSize else {
                return nil
            }
            hash = tailData.withUnsafeBytes { rawBuffer -> UInt64 in
                let buffer = rawBuffer.bindMemory(to: UInt64.self)
                var current = hash
                for val in buffer {
                    current = current &+ UInt64(littleEndian: val)
                }
                return current
            }

            return (String(format: "%016llx", hash), Int64(fileSize))
        } catch {
            return nil
        }
    }

    /// Computes the 16-character hexadecimal OpenSubtitles hash for a local file URL.
    /// Returns nil if the file does not exist, cannot be read, or is smaller than 64KB.
    public static func computeHash(for fileURL: URL) -> String? {
        computeHashAndSize(for: fileURL)?.hash
    }
}
