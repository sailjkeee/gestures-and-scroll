import Foundation

struct DrawingApplication: Codable, Equatable {
    let url: URL
    let bundleIdentifier: String
    let name: String

    init?(url: URL) {
        let url = url.standardizedFileURL
        guard let bundle = Self.applicationBundle(at: url),
              let identifier = bundle.bundleIdentifier, !identifier.isEmpty else { return nil }
        self.url = url
        self.bundleIdentifier = identifier
        self.name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
    }

    func resolvedURL(findApplication: (String) -> URL?) -> URL? {
        if Self.applicationBundle(at: url)?.bundleIdentifier == bundleIdentifier {
            return url
        }
        guard let registered = findApplication(bundleIdentifier),
              Self.applicationBundle(at: registered)?.bundleIdentifier == bundleIdentifier else { return nil }
        return registered
    }

    private static func applicationBundle(at url: URL) -> Bundle? {
        guard url.isFileURL, url.pathExtension.lowercased() == "app",
              FileManager.default.fileExists(atPath: url.path),
              let bundle = Bundle(url: url), bundle.executableURL != nil else { return nil }
        return bundle
    }
}

struct DrawingAssignment: Equatable {
    var action: GestureAction
    var application: DrawingApplication?

    var isConfigured: Bool {
        action != .openApplication || application != nil
    }
}
