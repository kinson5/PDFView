import Foundation
import Combine

/// Central manager for lightweight multi-device iCloud synchronization:
/// Uses Apple's NSUbiquitousKeyValueStore to sync reading progress, bookmarks, and preferences
/// across devices with zero storage waste, zero cellular upload strain, and instant matching by book title.
@MainActor
public final class iCloudSyncService: ObservableObject {
    public static let shared = iCloudSyncService()

    public static let progressDidChangeExternallyNotification = Notification.Name("PDFview_iCloud_ProgressDidChangeExternally")

    @Published public var isSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isSyncEnabled, forKey: "PDFview_iCloud_ProgressSyncEnabled")
            if isSyncEnabled {
                syncNow()
            }
        }
    }

    @Published public var lastSyncDate: Date? = nil
    @Published public var syncStatusMessage: String = "iCloud 进度同步就绪"
    @Published public var isSyncing: Bool = false

    private let kvStore = NSUbiquitousKeyValueStore.default
    private let prefPrefix = "iCloud_BookPref_"
    private let recentPrefix = "iCloud_RecentDocs"

    private init() {
        let savedSync = UserDefaults.standard.object(forKey: "PDFview_iCloud_ProgressSyncEnabled") as? Bool ?? true
        self.isSyncEnabled = savedSync

        setupExternalNotifications()
        kvStore.synchronize()
    }

    // MARK: - External Notifications

    private func setupExternalNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleExternalChange()
            }
        }
    }

    private func handleExternalChange() {
        lastSyncDate = Date()
        syncStatusMessage = "已同步云端最新进度"
        NotificationCenter.default.post(name: Self.progressDidChangeExternallyNotification, object: nil)
    }

    // MARK: - Progress Synchronization (Key-Value by Title)

    /// Candidates for title matching: with/without file extensions, normalized
    public func candidateKeys(for title: String) -> [String] {
        var keys: [String] = []
        let raw = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return keys }

        keys.append(sanitizeKey(raw))

        let baseName = (raw as NSString).deletingPathExtension
        if !baseName.isEmpty && baseName != raw {
            keys.append(sanitizeKey(baseName))
        }

        let ext = (raw as NSString).pathExtension.lowercased()
        if ext.isEmpty {
            keys.append(sanitizeKey(raw + ".pdf"))
        }

        return keys
    }

    /// Saves book preferences and progress to iCloud NSUbiquitousKeyValueStore
    public func saveBookProgress(for title: String, preference: BookPreference) {
        guard isSyncEnabled, !title.isEmpty else { return }
        guard let data = try? JSONEncoder().encode(preference) else { return }

        // Save under all matching candidate keys so any device opening by title or filename matches
        for key in candidateKeys(for: title) {
            kvStore.set(data, forKey: prefPrefix + key)
        }
        kvStore.synchronize()
        lastSyncDate = Date()
        syncStatusMessage = "进度已同步至云端"
    }

    /// Loads book preferences and progress from iCloud NSUbiquitousKeyValueStore
    public func loadBookProgress(for title: String) -> BookPreference? {
        guard !title.isEmpty else { return nil }
        for key in candidateKeys(for: title) {
            let fullKey = prefPrefix + key
            if let data = kvStore.data(forKey: fullKey),
               let pref = try? JSONDecoder().decode(BookPreference.self, from: data) {
                return pref
            }
        }
        return nil
    }

    /// Syncs recent documents history across devices via iCloud Key-Value store
    public func syncRecentDocuments(_ recents: [RecentDocumentItem]) {
        guard isSyncEnabled else { return }
        if let data = try? JSONEncoder().encode(recents) {
            kvStore.set(data, forKey: recentPrefix)
            kvStore.synchronize()
        }
    }

    /// Retrieves cloud-synced recent documents
    public func loadCloudRecentDocuments() -> [RecentDocumentItem]? {
        guard let data = kvStore.data(forKey: recentPrefix),
              let items = try? JSONDecoder().decode([RecentDocumentItem].self, from: data) else {
            return nil
        }
        return items
    }

    /// Manually triggers iCloud sync
    public func syncNow() {
        isSyncing = true
        kvStore.synchronize()
        lastSyncDate = Date()
        syncStatusMessage = "已同步云端最新进度"
        NotificationCenter.default.post(name: Self.progressDidChangeExternallyNotification, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isSyncing = false
        }
    }

    private func sanitizeKey(_ string: String) -> String {
        return string.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? string
    }
}
