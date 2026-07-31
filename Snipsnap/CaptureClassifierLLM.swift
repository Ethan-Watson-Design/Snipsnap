//
//  CaptureClassifierLLM.swift
//  Snipsnap
//
//  On-device Foundation Models inference for rename / project / tag suggestions.
//

import AppKit
import Foundation
import FoundationModels

@Generable
private struct LLMRenameAndProjectResult {
    @Guide(description: "Short descriptive filename without extension, suitable for a screenshot or recording")
    var suggestedName: String

    @Guide(description: "Project or folder name to organize this capture under. Empty when unclear.")
    var suggestedProject: String

    @Guide(description: "Optional product flow or screen name (e.g. Checkout, Onboarding, Settings). Empty when unclear.")
    var suggestedFlow: String

    @Guide(description: "Comma-separated UI component tags visible in the capture (e.g. Navigation Bar, Modal, Button). Empty when unclear. Max 6.")
    var suggestedComponents: String

    @Guide(description: "Confidence from 0 to 1")
    var confidence: Double
}

@Generable
private struct LLMProjectResult {
    @Guide(description: "Project or folder name to organize this capture under. Empty when unclear.")
    var suggestedProject: String

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
        ocrText: String
    ) async -> RenameSuggestion? {
        guard isAvailable else { return nil }

        let session = LanguageModelSession(
            instructions: """
            You help organize screenshots and screen recordings on macOS for a design annotation app.
            Suggest:
            1) A concise filename (no extension)
            2) An optional project/folder name (the product or codebase)
            3) An optional flow name (user journey or screen group, e.g. Checkout, Onboarding)
            4) UI component tags visible in the capture (Navigation Bar, Modal, Button, Tab Bar, Form, Card, Sidebar, Toast, etc.)
            Prefer concrete UI/feature names visible in the capture over generic labels.
            Leave fields empty when unclear. Components should be a comma-separated list of at most 6 items.
            """
        )

        do {
            let response = try await session.respond(generating: LLMRenameAndProjectResult.self) {
                promptText(
                    image: image,
                    windowInfo: windowInfo,
                    ocrText: ocrText,
                    mode: .renameAndProject
                )
            }

            let result = response.content
            let project = sanitized(result.suggestedProject)
            let name = sanitized(result.suggestedName)
            let flow = sanitized(result.suggestedFlow)
            let components = parseComponents(result.suggestedComponents)
            guard name != nil || project != nil || flow != nil || !components.isEmpty else { return nil }

            return RenameSuggestion(
                suggestedName: name,
                suggestedProject: project,
                suggestedFlow: flow,
                suggestedComponents: components,
                confidence: min(max(result.confidence, 0), 1)
            )
        } catch {
            return nil
        }
    }

    static func suggestProject(
        image: NSImage,
        windowInfo: WindowSignature?,
        ocrText: String
    ) async -> String? {
        guard isAvailable else { return nil }

        let session = LanguageModelSession(
            instructions: """
            You help sort screenshots and recordings into project folders on macOS.
            Return only a project/folder name when you are reasonably confident.
            """
        )

        do {
            let response = try await session.respond(generating: LLMProjectResult.self) {
                promptText(
                    image: image,
                    windowInfo: windowInfo,
                    ocrText: ocrText,
                    mode: .projectOnly
                )
            }
            return sanitized(response.content.suggestedProject)
        } catch {
            return nil
        }
    }

    // MARK: - Prompt helpers

    private enum PromptMode {
        case renameAndProject
        case projectOnly
    }

    private static func promptText(
        image: NSImage,
        windowInfo: WindowSignature?,
        ocrText: String,
        mode: PromptMode
    ) -> String {
        var lines: [String] = []
        switch mode {
        case .renameAndProject:
            lines.append(
                "A screenshot is attached (described below via OCR). " +
                "Suggest a short descriptive filename, a project folder name, " +
                "an optional flow name, and UI component tags."
            )
        case .projectOnly:
            lines.append(
                "A screenshot is attached (described below via OCR). " +
                "Suggest a project folder name for organizing this capture."
            )
        }

        lines.append("Image size: \(Int(image.size.width))×\(Int(image.size.height)) px")

        if let windowTitle = windowInfo?.windowTitle, !windowTitle.isEmpty {
            lines.append("Window title: \(windowTitle)")
        }
        if let project = windowInfo?.resolvedProjectName, !project.isEmpty {
            lines.append("Resolved project: \(project)")
        }
        if !ocrText.isEmpty {
            lines.append("OCR text from screenshot:\n\(ocrText.prefix(2_000))")
        } else {
            lines.append("OCR text: (none detected)")
        }
        return lines.joined(separator: "\n")
    }

    private static func parseComponents(_ raw: String) -> [String] {
        raw
            .split(separator: ",")
            .compactMap { sanitized(String($0)) }
            .reduce(into: [String]()) { result, name in
                guard !result.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return }
                result.append(name)
            }
            .prefix(6)
            .map { $0 }
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
