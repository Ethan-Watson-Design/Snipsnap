//
//  CaptureClassifierLLM.swift
//  Grabbit
//
//  On-device Foundation Models inference for rename / project / tag suggestions.
//

import AppKit
import Foundation
import FoundationModels

@Generable
private struct LLMRenameAndProjectResult {
    @Guide(description: """
        Short descriptive filename without extension. Prefer the active workspace, \
        site, product, or browser/app tab name from the top chrome — not page titles \
        (Design, Parts, Settings), breadcrumbs, or selected tree/list items. Expand \
        compound product names into readable Title Case \
        (e.g. Handwerkercenter → Handwerk Center).
        """)
    var suggestedName: String

    @Guide(description: """
        Project or folder name for organizing this capture. Prefer matching an \
        existing project name when one fits. Use the product, codebase, client, or \
        brand identity — NOT in-app breadcrumbs, page paths \
        (e.g. Extension to North-West › High Performance), or view titles. \
        Empty when unclear.
        """)
    var suggestedProject: String

    @Guide(description: "Optional product flow or screen name (e.g. Checkout, Onboarding, Settings). Empty when unclear.")
    var suggestedFlow: String

    @Guide(description: "Confidence from 0 to 1")
    var confidence: Double
}

enum CaptureClassifierLLM {
    static var isAvailable: Bool {
        switch SystemLanguageModel.default.availability {
        case .available:
            return true
        case .unavailable:
            return false
        }
    }

    static func suggestRenameAndProject(
        image: NSImage,
        windowInfo: WindowSignature?,
        ocrText: String,
        existingProjects: [String] = []
    ) async -> RenameSuggestion? {
        guard isAvailable else { return nil }

        let session = LanguageModelSession(
            instructions: """
            You help organize screenshots and screen recordings on macOS for a design annotation app.
            Read UI chrome carefully, in top-to-bottom order:
            1) Filename — active tab / workspace / product name in the top bar. \
            Expand glued compound words into Title Case. Do not use page headings, \
            breadcrumbs, sidebar labels, or selected list rows as the filename.
            2) Project — the product, brand, client, or codebase this capture belongs to. \
            Prefer an existing project name when one clearly matches. Do not use \
            breadcrumbs or in-page navigation paths as the project.
            3) Flow — optional screen or journey label (Parts, Design, Checkout). Empty when unclear.
            Leave fields empty when unclear. Do not invent UI component tags.
            """
        )

        do {
            let response = try await session.respond(generating: LLMRenameAndProjectResult.self) {
                promptText(
                    image: image,
                    windowInfo: windowInfo,
                    ocrText: ocrText,
                    existingProjects: existingProjects
                )
            }

            let result = response.content
            let project = sanitized(result.suggestedProject)
            let name = sanitized(result.suggestedName)
            let flow = sanitized(result.suggestedFlow)
            guard name != nil || project != nil || flow != nil else { return nil }

            return RenameSuggestion(
                suggestedName: name,
                suggestedProject: project,
                suggestedFlow: flow,
                confidence: min(max(result.confidence, 0), 1)
            )
        } catch {
            return nil
        }
    }

    // MARK: - Prompt helpers

    private static func promptText(
        image: NSImage,
        windowInfo: WindowSignature?,
        ocrText: String,
        existingProjects: [String]
    ) -> String {
        var lines: [String] = [
            "OCR from the screenshot is listed top→bottom (UI chrome first). " +
            "Suggest a short descriptive filename, a project folder name, " +
            "and an optional flow name.",
            "Image size: \(Int(image.size.width))×\(Int(image.size.height)) px"
        ]

        if let windowTitle = windowInfo?.windowTitle, !windowTitle.isEmpty {
            lines.append("Window title: \(windowTitle)")
        }
        if let project = windowInfo?.resolvedProjectName, !project.isEmpty {
            lines.append("Resolved project signal: \(project)")
        }
        if let app = windowInfo?.dominantAppName ?? windowInfo?.bundleID, !app.isEmpty {
            lines.append("Captured app: \(app)")
        }
        if !existingProjects.isEmpty {
            lines.append(
                "Existing project folders (prefer matching one when appropriate): " +
                existingProjects.prefix(40).joined(separator: ", ")
            )
        }
        if !ocrText.isEmpty {
            lines.append("OCR text (top → bottom):\n\(ocrText.prefix(2_500))")
        } else {
            lines.append("OCR text: (none detected)")
        }
        return lines.joined(separator: "\n")
    }

    private static func sanitized(_ raw: String?) -> String? {
        guard let raw else { return nil }
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
}
