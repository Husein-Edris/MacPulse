import Foundation

struct LargeFile: Identifiable, Equatable {
    let path: String
    let sizeBytes: Int64
    var id: String { path }
    var sizeMB: Double { Double(sizeBytes) / 1_048_576 }
    var name: String { (path as NSString).lastPathComponent }
}

/// Pure selection logic: keep files at/above the threshold, biggest first, capped.
enum LargeFileRanker {
    static func top(_ files: [LargeFile], minBytes: Int64, limit: Int) -> [LargeFile] {
        files.filter { $0.sizeBytes >= minBytes }
             .sorted { $0.sizeBytes > $1.sizeBytes }
             .prefix(limit)
             .map { $0 }
    }
}

/// On-demand home-folder walk for big files. Skips ~/Library, hidden dirs, and
/// symlinks to avoid TCC prompts and noise. I/O — not exercised by the unit runner.
enum FileScanner {
    static func scanLargeFiles(minBytes: Int64 = 100 * 1_048_576, limit: Int = 30) -> [LargeFile] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey]
        guard let walker = FileManager.default.enumerator(
            at: home,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var found: [LargeFile] = []
        for case let url as URL in walker {
            if url.lastPathComponent == "Library", url.deletingLastPathComponent() == home {
                walker.skipDescendants()
                continue
            }
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  v.isSymbolicLink != true, v.isRegularFile == true,
                  let size = v.fileSize, Int64(size) >= minBytes
            else { continue }
            found.append(LargeFile(path: url.path, sizeBytes: Int64(size)))
        }
        return LargeFileRanker.top(found, minBytes: minBytes, limit: limit)
    }
}
