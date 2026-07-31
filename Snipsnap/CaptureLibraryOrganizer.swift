//
//  CaptureLibraryOrganizer.swift
//  Snipsnap
//

import Foundation

struct CaptureLocationSnapshot: Equatable {
    let name: String
    let directoryURL: URL
}

struct OrganizePlanItem: Identifiable {
    let id: UUID
    let entry: CaptureEntry
    let destination: CaptureDestination?
    let windowInfo: WindowSignature?
    var isChecked: Bool
    var isInteractive: Bool

    var projectName: String? {
        destination?.productFolder
    }
}

struct OrganizePlan: Equatable {
    var matchedItems: [OrganizePlanItem]
    var unmatchedItems: [OrganizePlanItem]

    static func == (lhs: OrganizePlan, rhs: OrganizePlan) -> Bool {
        lhs.matchedItems.map(\.id) == rhs.matchedItems.map(\.id)
            && lhs.unmatchedItems.map(\.id) == rhs.unmatchedItems.map(\.id)
    }

    var groupedByProject: [(project: String, items: [OrganizePlanItem])] {
        let grouped = Dictionary(grouping: matchedItems) { $0.projectName ?? "Unknown" }
        return grouped.keys.sorted().map { key in
            (project: key, items: grouped[key] ?? [])
        }
    }
}

struct OrganizeBatchMove: Equatable {
    let captureID: UUID
    let snapshot: CaptureLocationSnapshot
    let windowInfo: WindowSignature?
    let wroteMapping: Bool
    let destination: CaptureDestination
}

struct OrganizeBatchResult: Equatable {
    let moves: [OrganizeBatchMove]
    let projectCount: Int

    var movedCount: Int { moves.count }
}

enum CaptureLibraryOrganizer {
    static func existingProjectNames() -> [String] {
        let root = AppSettings.destinationFolderURL
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            .map(\.lastPathComponent)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func sanitizedProjectName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let invalid = CharacterSet(charactersIn: ":/\\")
        let cleaned = trimmed
            .components(separatedBy: invalid)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "-")

        guard !cleaned.isEmpty else { return nil }
        return String(cleaned.prefix(120))
    }

    static func rootLevelEntries(from entries: [CaptureEntry]) -> [CaptureEntry] {
        entries.filter { CaptureHistory.shared.isAtRootCapture(id: $0.id) }
    }

    static func targetEntries(from entries: [CaptureEntry], includeOrganized: Bool) -> [CaptureEntry] {
        includeOrganized ? entries : rootLevelEntries(from: entries)
    }

    static func buildPlan(for entries: [CaptureEntry]) async -> OrganizePlan {
        var matched: [OrganizePlanItem] = []
        var unmatched: [OrganizePlanItem] = []

        for entry in entries {
            guard let image = CaptureClassifier.imageForClassification(from: entry) else {
                unmatched.append(
                    OrganizePlanItem(
                        id: entry.id,
                        entry: entry,
                        destination: nil,
                        windowInfo: AutoOrganizer.windowInfo(for: entry.id),
                        isChecked: false,
                        isInteractive: false
                    )
                )
                continue
            }

            let windowInfo = AutoOrganizer.windowInfo(for: entry.id)
            let destination = await CaptureClassifier.classifyForOrganize(
                image: image,
                windowInfo: windowInfo
            )

            if let destination {
                matched.append(
                    OrganizePlanItem(
                        id: entry.id,
                        entry: entry,
                        destination: destination,
                        windowInfo: windowInfo,
                        isChecked: true,
                        isInteractive: true
                    )
                )
            } else {
                unmatched.append(
                    OrganizePlanItem(
                        id: entry.id,
                        entry: entry,
                        destination: nil,
                        windowInfo: windowInfo,
                        isChecked: false,
                        isInteractive: false
                    )
                )
            }
        }

        return OrganizePlan(matchedItems: matched, unmatchedItems: unmatched)
    }

    static func execute(plan: OrganizePlan) -> OrganizeBatchResult? {
        let selected = plan.matchedItems.filter(\.isChecked)
        guard !selected.isEmpty else { return nil }

        var moves: [OrganizeBatchMove] = []
        var projects = Set<String>()

        for item in selected {
            guard let destination = item.destination,
                  let snapshot = snapshot(for: item.entry) else {
                continue
            }

            let wroteMapping = item.windowInfo != nil
            guard CaptureHistory.shared.setProjectTag(id: item.id, name: destination.productFolder) else {
                continue
            }
            if let windowInfo = item.windowInfo {
                CaptureDestinationMappingCache.shared.confirm(signature: windowInfo, destination: destination)
            }

            moves.append(
                OrganizeBatchMove(
                    captureID: item.id,
                    snapshot: snapshot,
                    windowInfo: item.windowInfo,
                    wroteMapping: wroteMapping,
                    destination: destination
                )
            )
            projects.insert(destination.productFolder)
        }

        guard !moves.isEmpty else { return nil }
        return OrganizeBatchResult(moves: moves, projectCount: projects.count)
    }

    static func revert(batch: OrganizeBatchResult) {
        for move in batch.moves.reversed() {
            revert(snapshot: move.snapshot, captureID: move.captureID)
            if move.wroteMapping, let signature = move.windowInfo {
                CaptureDestinationMappingCache.shared.remove(signature: signature)
            }
        }
    }

    @discardableResult
    static func apply(
        suggestion: RenameSuggestion,
        to entry: CaptureEntry,
        windowInfo: WindowSignature?
    ) -> CaptureLocationSnapshot? {
        guard let snapshot = snapshot(for: entry) else { return nil }

        if suggestion.hasRename, let name = suggestion.suggestedName {
            _ = CaptureHistory.shared.renameCapture(id: entry.id, to: name)
        }

        if suggestion.hasProject, let project = suggestion.suggestedProject {
            _ = CaptureHistory.shared.setProjectTag(id: entry.id, name: project)
            if let windowInfo {
                let destination = CaptureDestination(
                    productFolder: project,
                    subfolder: nil,
                    confidence: suggestion.confidence,
                    source: .localLLM
                )
                CaptureDestinationMappingCache.shared.confirm(signature: windowInfo, destination: destination)
            }
        }

        if let flow = suggestion.suggestedFlow, !flow.isEmpty {
            _ = CaptureHistory.shared.addTag(id: entry.id, kind: .flow, name: flow)
        }
        for component in suggestion.suggestedComponents {
            _ = CaptureHistory.shared.addTag(id: entry.id, kind: .component, name: component)
        }

        return snapshot
    }

    static func revert(snapshot: CaptureLocationSnapshot, captureID: UUID) {
        _ = CaptureHistory.shared.renameCapture(id: captureID, to: snapshot.name)
        _ = CaptureHistory.shared.moveCapture(id: captureID, toDirectory: snapshot.directoryURL)
        CaptureHistory.shared.syncProjectTagFromFolder(id: captureID)
    }

    static func snapshot(for entry: CaptureEntry) -> CaptureLocationSnapshot? {
        guard let fileURL = CaptureHistory.shared.fileURL(for: entry.id) else { return nil }
        return CaptureLocationSnapshot(
            name: entry.displayName,
            directoryURL: fileURL.deletingLastPathComponent()
        )
    }
}
