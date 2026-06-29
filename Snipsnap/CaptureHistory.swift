//
//  CaptureHistory.swift
//  Snipsnap
//

import AppKit
import AVFoundation

enum CaptureNaming {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return formatter
    }()

    static func baseName(at date: Date = Date()) -> String {
        "Snipsnap \(formatter.string(from: date))"
    }

    static func recordingFilename(at date: Date = Date()) -> String {
        "\(baseName(at: date)).mp4"
    }

    static func screenshotFilename(at date: Date = Date()) -> String {
        "\(baseName(at: date)).png"
    }

    static func uniqueURL(in directory: URL, preferredFilename: String) -> URL {
        let fileManager = FileManager.default
        var candidate = directory.appendingPathComponent(preferredFilename)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let ext = candidate.pathExtension
        let stem = candidate.deletingPathExtension().lastPathComponent
        var counter = 2
        while true {
            candidate = directory.appendingPathComponent("\(stem) (\(counter)).\(ext)")
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }
}

enum CaptureItem {
    case screenshot(NSImage)
    case recording(url: URL, thumbnail: NSImage)

    var thumbnail: NSImage {
        switch self {
        case .screenshot(let img): return img
        case .recording(_, let thumb): return thumb
        }
    }

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    var kindLabel: String {
        isRecording ? "Recording" : "Screenshot"
    }
}

struct CaptureEntry: Identifiable {
    let id: UUID
    let createdAt: Date
    let item: CaptureItem

    var thumbnail: NSImage { item.thumbnail }
    var isRecording: Bool { item.isRecording }
    var kindLabel: String { item.kindLabel }

    var displayName: String {
        switch item {
        case .screenshot:
            return CaptureNaming.baseName(at: createdAt)
        case .recording(let url, _):
            return url.deletingPathExtension().lastPathComponent
        }
    }

    var menuTitle: String {
        "\(displayName) · \(createdAt.compactRelativeLabel)"
    }
}

extension Date {
    var compactRelativeLabel: String {
        let seconds = Date().timeIntervalSince(self)
        guard seconds >= 0 else {
            return formatted(date: .abbreviated, time: .omitted)
        }

        if seconds < 60 { return "just now" }

        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)min ago" }

        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }

        let days = hours / 24
        if days < 7 { return "\(days)d ago" }

        let weeks = days / 7
        if weeks < 5 { return "\(weeks)w ago" }

        let calendar = Calendar.current
        if calendar.isDate(self, equalTo: Date(), toGranularity: .year) {
            return formatted(.dateTime.month(.abbreviated).day())
        }
        return formatted(.dateTime.month(.abbreviated).day().year())
    }
}

extension Notification.Name {
    static let captureHistoryDidChange = Notification.Name("CaptureHistoryDidChange")
}

final class CaptureHistory {
    static let shared = CaptureHistory()

    static let maxMenuItems = 3
    private static let maxStored = 200

    private struct StoredCapture: Codable {
        enum Kind: String, Codable {
            case screenshot
            case recording
        }

        let id: UUID
        let createdAt: Date
        let kind: Kind
        let path: String
        let thumbnailPath: String?
    }

    private let storageDirectory: URL
    private let manifestURL: URL
    private var storedCaptures: [StoredCapture] = []

    private(set) var entries: [CaptureEntry] = []

    var recents: [CaptureItem] { entries.map(\.item) }
    var menuEntries: [CaptureEntry] { Array(entries.prefix(Self.maxMenuItems)) }

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storageDirectory = appSupport.appendingPathComponent("Snipsnap/recents", isDirectory: true)
        manifestURL = storageDirectory.appendingPathComponent("manifest.json")
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        loadFromDisk()
    }

    func add(_ item: CaptureItem) {
        let entry = CaptureEntry(id: UUID(), createdAt: Date(), item: item)

        switch item {
        case .screenshot(let image):
            guard let path = saveScreenshot(image, at: entry.createdAt) else { return }
            storedCaptures.insert(
                StoredCapture(id: entry.id, createdAt: entry.createdAt, kind: .screenshot, path: path.path, thumbnailPath: nil),
                at: 0
            )

        case .recording(let url, let thumbnail):
            let thumbPath = saveThumbnail(thumbnail)
            storedCaptures.insert(
                StoredCapture(
                    id: entry.id,
                    createdAt: entry.createdAt,
                    kind: .recording,
                    path: url.path,
                    thumbnailPath: thumbPath?.path
                ),
                at: 0
            )
        }

        entries.insert(entry, at: 0)
        trimAndPersist()
        NotificationCenter.default.post(name: .captureHistoryDidChange, object: self)
    }

    func entry(at index: Int) -> CaptureEntry? {
        guard entries.indices.contains(index) else { return nil }
        return entries[index]
    }

    func fileURL(for id: UUID) -> URL? {
        guard let stored = storedCaptures.first(where: { $0.id == id }) else { return nil }
        let url = URL(fileURLWithPath: stored.path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    func remove(id: UUID) {
        guard let index = storedCaptures.firstIndex(where: { $0.id == id }) else { return }
        let stored = storedCaptures[index]
        trashStoredFiles(for: stored)

        storedCaptures.remove(at: index)
        entries.removeAll { $0.id == id }
        persist()
        NotificationCenter.default.post(name: .captureHistoryDidChange, object: self)
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: manifestURL) else { return }

        if let stored = try? JSONDecoder().decode([StoredCapture].self, from: data) {
            rebuildEntries(from: stored)
            return
        }

        // Migrate legacy manifest without id/createdAt.
        struct LegacyStoredCapture: Codable {
            enum Kind: String, Codable { case screenshot, recording }
            let kind: Kind
            let path: String
            let thumbnailPath: String?
        }

        guard let legacy = try? JSONDecoder().decode([LegacyStoredCapture].self, from: data) else { return }

        var migrated: [StoredCapture] = []
        for (index, entry) in legacy.enumerated() {
            migrated.append(
                StoredCapture(
                    id: UUID(),
                    createdAt: Date().addingTimeInterval(-Double(index) * 60),
                    kind: StoredCapture.Kind(rawValue: entry.kind.rawValue) ?? .screenshot,
                    path: entry.path,
                    thumbnailPath: entry.thumbnailPath
                )
            )
        }
        rebuildEntries(from: migrated)
        persist()
    }

    private func rebuildEntries(from stored: [StoredCapture]) {
        var loadedEntries: [CaptureEntry] = []
        var validStored: [StoredCapture] = []

        for entry in stored {
            guard let item = captureItem(from: entry) else { continue }
            loadedEntries.append(CaptureEntry(id: entry.id, createdAt: entry.createdAt, item: item))
            validStored.append(entry)
        }

        entries = loadedEntries
        storedCaptures = validStored

        if validStored.count != stored.count {
            persist()
        }
    }

    private func captureItem(from entry: StoredCapture) -> CaptureItem? {
        let fileManager = FileManager.default

        switch entry.kind {
        case .screenshot:
            let url = URL(fileURLWithPath: entry.path)
            guard fileManager.fileExists(atPath: url.path),
                  let image = NSImage(contentsOf: url) else {
                return nil
            }
            return .screenshot(image)

        case .recording:
            let url = URL(fileURLWithPath: entry.path)
            guard fileManager.fileExists(atPath: url.path) else { return nil }

            if let thumbPath = entry.thumbnailPath,
               fileManager.fileExists(atPath: thumbPath),
               let thumb = NSImage(contentsOf: URL(fileURLWithPath: thumbPath)) {
                return .recording(url: url, thumbnail: thumb)
            }

            guard let thumb = recordingThumbnail(for: url) else { return nil }
            return .recording(url: url, thumbnail: thumb)
        }
    }

    private func trimAndPersist() {
        if entries.count > Self.maxStored {
            let evicted = storedCaptures.suffix(from: Self.maxStored)
            for entry in evicted {
                cleanupStoredFiles(for: entry)
            }
            entries = Array(entries.prefix(Self.maxStored))
            storedCaptures = Array(storedCaptures.prefix(Self.maxStored))
        }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(storedCaptures) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    private func cleanupStoredFiles(for entry: StoredCapture) {
        let fileManager = FileManager.default

        switch entry.kind {
        case .screenshot:
            try? fileManager.removeItem(atPath: entry.path)
        case .recording:
            if let thumbPath = entry.thumbnailPath {
                try? fileManager.removeItem(atPath: thumbPath)
            }
        }
    }

    private func trashStoredFiles(for entry: StoredCapture) {
        let fileManager = FileManager.default
        let url = URL(fileURLWithPath: entry.path)
        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.trashItem(at: url, resultingItemURL: nil)
        }
        if let thumbPath = entry.thumbnailPath {
            let thumbURL = URL(fileURLWithPath: thumbPath)
            if fileManager.fileExists(atPath: thumbURL.path) {
                try? fileManager.trashItem(at: thumbURL, resultingItemURL: nil)
            }
        }
    }

    // MARK: - File helpers

    private func saveScreenshot(_ image: NSImage, at date: Date) -> URL? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        let url = CaptureNaming.uniqueURL(
            in: storageDirectory,
            preferredFilename: CaptureNaming.screenshotFilename(at: date)
        )
        do {
            try png.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func saveThumbnail(_ image: NSImage) -> URL? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        let url = storageDirectory.appendingPathComponent("thumb-\(UUID().uuidString).png")
        do {
            try png.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func recordingThumbnail(for url: URL) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        let semaphore = DispatchSemaphore(value: 0)
        let thumbnailResult = ThumbnailResult()
        generator.generateCGImageAsynchronously(for: .zero) { cgImage, _, _ in
            if let cgImage {
                thumbnailResult.image = NSImage(cgImage: cgImage, size: .zero)
            }
            semaphore.signal()
        }
        semaphore.wait()
        return thumbnailResult.image
    }
}

private final class ThumbnailResult: @unchecked Sendable {
    var image: NSImage?
}
