//
//  CaptureOrganizer.swift
//  Grabbit
//

import AppKit
import Foundation

struct OrganizeSuggestion: Equatable {
    let windowInfo: WindowSignature
    let destination: CaptureDestination
    let folderAlreadyExists: Bool
}

enum CaptureOrganizer {
    private static var windowInfoByCaptureID: [UUID: WindowSignature] = [:]

    /// Window metadata captured at screenshot time, before Grabbit UI took focus.
    static func registerCaptureContext(captureID: UUID, windowInfo: WindowSignature) {
        windowInfoByCaptureID[captureID] = windowInfo
    }

    static func windowInfo(for captureID: UUID) -> WindowSignature? {
        windowInfoByCaptureID[captureID]
    }

    /// Resolves a project folder suggestion for the annotation save organize panel.
    static func suggestion(for captureID: UUID, image: NSImage) async -> OrganizeSuggestion? {
        guard let windowInfo = windowInfoByCaptureID[captureID] else {
            print("[Grabbit AutoOrganize] No capture context for \(captureID) — was this opened from the library?")
            return nil
        }

        print("[Grabbit AutoOrganize] Save tapped — captureID: \(captureID)")
        print("[Grabbit AutoOrganize] Save root: \(AppSettings.destinationFolderURL.path)")
        await CaptureClassifier.printSaveDiagnostics(image: image, windowInfo: windowInfo)

        let destination = await destinationForSave(windowInfo: windowInfo, image: image)
        guard destination.productFolder != "Not sure yet" else {
            print("[Grabbit AutoOrganize] No confident suggestion — panel hidden")
            return nil
        }

        let exists = folderExists(for: destination)
        print(
            "[Grabbit AutoOrganize] Panel suggestion: \(displayPath(for: destination))" +
            " (project folder \(exists ? "exists" : "will be created"))"
        )

        return OrganizeSuggestion(
            windowInfo: windowInfo,
            destination: destination,
            folderAlreadyExists: exists
        )
    }

    static func displayPath(for destination: CaptureDestination) -> String {
        if let subfolder = destination.subfolder, !subfolder.isEmpty {
            return "\(destination.productFolder) / \(subfolder)"
        }
        return destination.productFolder
    }

    static func folderExists(for destination: CaptureDestination) -> Bool {
        var directory = AppSettings.destinationFolderURL
        directory.appendPathComponent(destination.productFolder, isDirectory: true)
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    @discardableResult
    static func organizeCapture(id: UUID, to destination: CaptureDestination) -> Bool {
        guard let windowInfo = windowInfoByCaptureID[id] else {
            return moveCapture(id: id, to: destination)
        }
        guard moveCapture(id: id, to: destination, signature: windowInfo) else { return false }
        windowInfoByCaptureID[id] = nil
        return true
    }

    /// Runs after capture; proposes a project-based folder and attaches a chip to the toast.
    static func handleSave(captureID: UUID, image: NSImage) {
        guard let windowInfo = windowInfoByCaptureID[captureID] else { return }
        Task {
            let destination = await destinationForSave(windowInfo: windowInfo, image: image)
            presentSuggestion(
                captureID: captureID,
                windowInfo: windowInfo,
                destination: destination
            )
        }
    }

    private static func destinationForSave(
        windowInfo: WindowSignature,
        image: NSImage
    ) async -> CaptureDestination {
        if let cached = CaptureDestinationMappingCache.shared.destination(for: windowInfo) {
            // Ignore obviously bad cached mappings (e.g. ultra-short junk like "b").
            if cached.productFolder.count >= 3 {
                print("[Grabbit AutoOrganize] Winner: mapping cache → \(cached.productFolder)")
                return cached
            } else {
                print("[Grabbit AutoOrganize] Ignoring cached mapping with short name: \"\(cached.productFolder)\"")
            }
        }

        if let project = sanitizedFolderName(windowInfo.resolvedProjectName) {
            print(
                "[Grabbit AutoOrganize] Winner: capture-time resolvedProjectName → \"\(project)\" " +
                "(OCR/classifier skipped — may not match on-screen project text)"
            )
            return CaptureDestination(
                productFolder: project,
                subfolder: nil,
                confidence: 0.8,
                source: .windowMetadata
            )
        }

        if let classified = await CaptureClassifier.classify(image: image, windowInfo: windowInfo) {
            let sub = classified.subfolder.map { " / \($0)" } ?? ""
            print(
                "[Grabbit AutoOrganize] Winner: CaptureClassifier.\(classified.source.rawValue) → " +
                "\"\(classified.productFolder)\(sub)\" (confidence \(classified.confidence))"
            )
            return classified
        }

        print("[Grabbit AutoOrganize] Winner: fallback → \"Not sure yet\"")
        return CaptureDestination(
            productFolder: "Not sure yet",
            subfolder: nil,
            confidence: 0.5,
            source: .windowMetadata
        )
    }

    private static func sanitizedFolderName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let invalid = CharacterSet(charactersIn: ":/\\")
        let cleaned = trimmed
            .components(separatedBy: invalid)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return cleaned.isEmpty ? nil : String(cleaned.prefix(120))
    }

    private static func presentSuggestion(
        captureID: UUID,
        windowInfo: WindowSignature,
        destination: CaptureDestination,
        attempt: Int = 0
    ) {
        DispatchQueue.main.async {
            guard ToastWindow.isCurrentToast(for: captureID),
                  let toast = ToastWindow.currentToast else {
                guard attempt < 20 else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    presentSuggestion(
                        captureID: captureID,
                        windowInfo: windowInfo,
                        destination: destination,
                        attempt: attempt + 1
                    )
                }
                return
            }
            toast.attachFolderSuggestion(destination) {
                // Project is hybrid: approving the folder sets the sole project tag and moves the file.
                if CaptureHistory.shared.setProjectTag(id: captureID, name: destination.productFolder) {
                    CaptureDestinationMappingCache.shared.confirm(
                        signature: windowInfo,
                        destination: destination
                    )
                    windowInfoByCaptureID[captureID] = nil
                }
            }
        }
    }

    @discardableResult
    static func moveCapture(id: UUID, to destination: CaptureDestination) -> Bool {
        moveCapture(id: id, to: destination, signature: nil)
    }

  @discardableResult
    private static func moveCapture(id: UUID, to destination: CaptureDestination, signature: WindowSignature?) -> Bool {
        let directory = destinationDirectoryURL(for: destination)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return false
        }

        guard CaptureHistory.shared.moveCapture(id: id, toDirectory: directory) != nil else {
            return false
        }

        if let signature {
            CaptureDestinationMappingCache.shared.confirm(signature: signature, destination: destination)
        }
        return true
    }

    private static func destinationDirectoryURL(for destination: CaptureDestination) -> URL {
        var directory = AppSettings.destinationFolderURL
        directory.appendPathComponent(destination.productFolder, isDirectory: true)
        if let subfolder = destination.subfolder, !subfolder.isEmpty {
            directory.appendPathComponent(subfolder, isDirectory: true)
        }
        return directory
    }
}
