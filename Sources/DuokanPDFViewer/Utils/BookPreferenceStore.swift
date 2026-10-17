import Foundation

public struct BookPreference: Codable, Equatable, Sendable {
    public var layoutProfile: LayoutProfile
    public var textScale: CGFloat
    public var sliceSpacing: CGFloat
    public var readingTheme: String
    public var lastPageIndex: Int
    public var inkLevel: InkLevel?
    public var enablePageEnhancement: Bool?
    public var scanEnhanceMode: ScanEnhanceMode?
    public var autoPerspectiveCorrection: Bool?
    public var autoDeskew: Bool?
    public var autoCropBlackBorders: Bool?
    public var autoRemoveStaplesAndPunchHoles: Bool?
    public var backgroundBleachLevel: BleachLevel?
    public var pageSharpening: Double?
    public var originalViewEnhanced: Bool?
    public var textRenderMode: TextReflowRenderMode?
    public var pageRotations: [Int: Int]?
    public var documentRotation: Int?
    public var manualPageQuads: [Int: ManualCropQuad]?

    public init(
        layoutProfile: LayoutProfile = .book,
        textScale: CGFloat = 1.0,
        sliceSpacing: CGFloat = 8.0,
        readingTheme: String = ReadingTheme.white.rawValue,
        lastPageIndex: Int = 0,
        inkLevel: InkLevel? = .enhanced,
        enablePageEnhancement: Bool? = true,
        scanEnhanceMode: ScanEnhanceMode? = .cleanBW,
        autoPerspectiveCorrection: Bool? = true,
        autoDeskew: Bool? = true,
        autoCropBlackBorders: Bool? = true,
        autoRemoveStaplesAndPunchHoles: Bool? = true,
        backgroundBleachLevel: BleachLevel? = .strong,
        pageSharpening: Double? = 0.8,
        originalViewEnhanced: Bool? = false,
        textRenderMode: TextReflowRenderMode? = .imageSlices,
        pageRotations: [Int: Int]? = nil,
        documentRotation: Int? = nil,
        manualPageQuads: [Int: ManualCropQuad]? = nil
    ) {
        self.layoutProfile = layoutProfile
        self.textScale = textScale
        self.sliceSpacing = sliceSpacing
        self.readingTheme = readingTheme
        self.lastPageIndex = lastPageIndex
        self.inkLevel = inkLevel
        self.enablePageEnhancement = enablePageEnhancement
        self.scanEnhanceMode = scanEnhanceMode
        self.autoPerspectiveCorrection = autoPerspectiveCorrection
        self.autoDeskew = autoDeskew
        self.autoCropBlackBorders = autoCropBlackBorders
        self.autoRemoveStaplesAndPunchHoles = autoRemoveStaplesAndPunchHoles
        self.backgroundBleachLevel = backgroundBleachLevel
        self.pageSharpening = pageSharpening
        self.originalViewEnhanced = originalViewEnhanced
        self.textRenderMode = textRenderMode
        self.pageRotations = pageRotations
        self.documentRotation = documentRotation
        self.manualPageQuads = manualPageQuads
    }
}

public final class BookPreferenceStore: @unchecked Sendable {
    public static let shared = BookPreferenceStore()
    private let defaults = UserDefaults.standard
    private let prefix = "DuokanPDF_BookPref_"

    private init() {}

    public func candidateKeys(for identifier: String) -> [String] {
        var keys: [String] = []
        let raw = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
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

    public func save(for identifier: String, preference: BookPreference) {
        guard !identifier.isEmpty else { return }
        if let data = try? JSONEncoder().encode(preference) {
            for key in candidateKeys(for: identifier) {
                defaults.set(data, forKey: prefix + key)
            }
        }
        // Sync to iCloud NSUbiquitousKeyValueStore
        Task { @MainActor in
            iCloudSyncService.shared.saveBookProgress(for: identifier, preference: preference)
        }
    }

    public func load(for identifier: String) -> BookPreference? {
        guard !identifier.isEmpty else { return nil }

        // 1. Try local storage first across all candidate keys
        for key in candidateKeys(for: identifier) {
            let fullKey = prefix + key
            if let data = defaults.data(forKey: fullKey),
               let pref = try? JSONDecoder().decode(BookPreference.self, from: data) {
                return pref
            }
        }

        // 2. Try iCloud NSUbiquitousKeyValueStore fallback (for documents opened on another device)
        for key in candidateKeys(for: identifier) {
            let cloudKey = "iCloud_BookPref_" + key
            if let data = NSUbiquitousKeyValueStore.default.data(forKey: cloudKey),
               let pref = try? JSONDecoder().decode(BookPreference.self, from: data) {
                // Cache into local defaults for offline access
                defaults.set(data, forKey: prefix + key)
                return pref
            }
        }

        return nil
    }

    private func sanitizeKey(_ string: String) -> String {
        return string.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? string
    }
}
