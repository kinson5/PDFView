import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Record representing a previously opened and read document
public struct RecentDocumentItem: Codable, Identifiable, Equatable, Sendable {
    public var id: String { urlString }
    public let title: String
    public let urlString: String
    public let bookmarkData: Data?
    public var lastOpenedDate: Date
    public var lastPageIndex: Int
    public var totalPages: Int
    public var fileSizeDescription: String?

    public init(
        title: String,
        urlString: String,
        bookmarkData: Data? = nil,
        lastOpenedDate: Date = Date(),
        lastPageIndex: Int = 0,
        totalPages: Int = 0,
        fileSizeDescription: String? = nil
    ) {
        self.title = title
        self.urlString = urlString
        self.bookmarkData = bookmarkData
        self.lastOpenedDate = lastOpenedDate
        self.lastPageIndex = lastPageIndex
        self.totalPages = totalPages
        self.fileSizeDescription = fileSizeDescription
    }
}

/// Thread-safe storage manager for recently viewed documents history
public final class RecentDocumentsStore: @unchecked Sendable {
    public static let shared = RecentDocumentsStore()
    private let defaults = UserDefaults.standard
    private let storageKey = "DuokanPDF_RecentDocuments_List"
    private let maxCount = 5
    private let lock = NSLock()

    private init() {}

    /// Loads the list of recent documents, sorted newest first (max 5)
    public func loadRecents() -> [RecentDocumentItem] {
        lock.lock()
        defer { lock.unlock() }

        var list: [RecentDocumentItem] = []
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([RecentDocumentItem].self, from: data) {
            list = saved
        }

        // Merge with cloud recent documents if available (from another device)
        let cloudKey = "iCloud_RecentDocs"
        if let cloudData = NSUbiquitousKeyValueStore.default.data(forKey: cloudKey),
           let cloudList = try? JSONDecoder().decode([RecentDocumentItem].self, from: cloudData) {
            for cItem in cloudList {
                if let localIdx = list.firstIndex(where: { $0.title == cItem.title }) {
                    if cItem.lastOpenedDate > list[localIdx].lastOpenedDate {
                        list[localIdx].lastPageIndex = cItem.lastPageIndex
                        list[localIdx].totalPages = max(list[localIdx].totalPages, cItem.totalPages)
                        list[localIdx].lastOpenedDate = cItem.lastOpenedDate
                    }
                } else {
                    list.append(cItem)
                }
            }
        }

        let sorted = list.sorted { $0.lastOpenedDate > $1.lastOpenedDate }
        if sorted.count > maxCount {
            return Array(sorted.prefix(maxCount))
        }
        return sorted
    }

    /// Records or updates an opened document in recent history
    public func addOrUpdate(url: URL, title: String, pageIndex: Int, totalPages: Int) {
        lock.lock()
        defer { lock.unlock() }

        var list: [RecentDocumentItem] = []
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([RecentDocumentItem].self, from: data) {
            list = saved
        }

        let canonicalPath = url.standardizedFileURL.path
        let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)

        // Calculate friendly file size
        var sizeDesc: String? = nil
        if let attrs = try? FileManager.default.attributesOfItem(atPath: canonicalPath),
           let byteCount = attrs[.size] as? Int64 {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            sizeDesc = formatter.string(fromByteCount: byteCount)
        }

        let effectiveTitle = title.isEmpty ? url.lastPathComponent : title

        // Remove existing entry for the same file path or title
        list.removeAll { $0.urlString == canonicalPath || $0.title == effectiveTitle }

        let item = RecentDocumentItem(
            title: effectiveTitle,
            urlString: canonicalPath,
            bookmarkData: bookmark,
            lastOpenedDate: Date(),
            lastPageIndex: pageIndex,
            totalPages: totalPages,
            fileSizeDescription: sizeDesc
        )
        list.insert(item, at: 0)

        if list.count > maxCount {
            list = Array(list.prefix(maxCount))
        }

        if let encoded = try? JSONEncoder().encode(list) {
            defaults.set(encoded, forKey: storageKey)
            NSUbiquitousKeyValueStore.default.set(encoded, forKey: "iCloud_RecentDocs")
            NSUbiquitousKeyValueStore.default.synchronize()
        }

        #if os(macOS)
        DispatchQueue.main.async {
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        }
        #endif
    }

    /// Updates reading progress (page index and total pages) for an existing document
    public func updateProgress(title: String, pageIndex: Int, totalPages: Int) {
        lock.lock()
        defer { lock.unlock() }

        guard !title.isEmpty,
              let data = defaults.data(forKey: storageKey),
              var list = try? JSONDecoder().decode([RecentDocumentItem].self, from: data) else {
            return
        }

        if let idx = list.firstIndex(where: { $0.title == title }) {
            list[idx].lastPageIndex = pageIndex
            if totalPages > 0 {
                list[idx].totalPages = totalPages
            }
            list[idx].lastOpenedDate = Date()
            if let encoded = try? JSONEncoder().encode(list) {
                defaults.set(encoded, forKey: storageKey)
                NSUbiquitousKeyValueStore.default.set(encoded, forKey: "iCloud_RecentDocs")
                NSUbiquitousKeyValueStore.default.synchronize()
            }
        }
    }

    /// Removes a specific document from history
    public func remove(urlString: String) {
        lock.lock()
        defer { lock.unlock() }

        guard let data = defaults.data(forKey: storageKey),
              var list = try? JSONDecoder().decode([RecentDocumentItem].self, from: data) else {
            return
        }

        let standardPath = URL(string: urlString)?.path ?? urlString
        list.removeAll {
            $0.urlString == urlString ||
            $0.urlString == standardPath ||
            $0.urlString == URL(fileURLWithPath: urlString).path
        }
        if let encoded = try? JSONEncoder().encode(list) {
            defaults.set(encoded, forKey: storageKey)
        }
    }

    /// Clears all recent documents history
    public func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: storageKey)
    }

    /// Resolves the URL for a recent item, trying bookmark data first, then file path
    public func resolveURL(for item: RecentDocumentItem) -> URL? {
        if let bookmarkData = item.bookmarkData {
            var isStale = false
            if let resolved = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), FileManager.default.fileExists(atPath: resolved.path) {
                return resolved
            }
        }

        let fallbackURL = URL(fileURLWithPath: item.urlString)
        if FileManager.default.fileExists(atPath: fallbackURL.path) {
            return fallbackURL
        }

        // Check if matching book exists in local Documents directory (e.g. imported or copied locally)
        if let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let direct = docsDir.appendingPathComponent(item.title)
            if FileManager.default.fileExists(atPath: direct.path) {
                return direct
            }
            for ext in ["pdf", "jpg", "jpeg", "png", "heic", "webp"] {
                let withExt = docsDir.appendingPathComponent("\(item.title).\(ext)")
                if FileManager.default.fileExists(atPath: withExt.path) {
                    return withExt
                }
            }
            let filenameOnly = URL(fileURLWithPath: item.urlString).lastPathComponent
            let byFilename = docsDir.appendingPathComponent(filenameOnly)
            if FileManager.default.fileExists(atPath: byFilename.path) {
                return byFilename
            }
        }

        return nil
    }
}
