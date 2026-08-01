//
//  CaptureTags.swift
//  Snipsnap
//
//  Typed tags for Capture Library organization. Project is hybrid: a tag and a folder.
//

import Foundation

enum CaptureTagKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case project
    case flow
    case component
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .project: return "Project"
        case .flow: return "Flow"
        case .component: return "Component"
        case .custom: return "Custom"
        }
    }

    /// Sort order in the tag bar: Project → Flow → Component → Custom.
    var sortOrder: Int {
        switch self {
        case .project: return 0
        case .flow: return 1
        case .component: return 2
        case .custom: return 3
        }
    }
}

struct CaptureTag: Identifiable, Codable, Hashable {
    var id: UUID
    var kind: CaptureTagKind
    var name: String

    init(id: UUID = UUID(), kind: CaptureTagKind, name: String) {
        self.id = id
        self.kind = kind
        self.name = CaptureTag.normalizeName(name)
    }

    static func normalizeName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let collapsed = trimmed
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(collapsed.prefix(80))
    }

    static func sorted(_ tags: [CaptureTag]) -> [CaptureTag] {
        tags.sorted { lhs, rhs in
            if lhs.kind.sortOrder != rhs.kind.sortOrder {
                return lhs.kind.sortOrder < rhs.kind.sortOrder
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

/// Common UI-component labels for Auto-Tag suggestions and editing menus.
enum CaptureUIComponentVocabulary {
    static let common: Set<String> = [
        "Button",
        "Icon Button",
        "Text Field",
        "Search",
        "Tab",
        "Tab Bar",
        "Navigation Bar",
        "Sidebar",
        "Modal",
        "Dialog",
        "Sheet",
        "Drawer",
        "Dropdown",
        "Select",
        "Checkbox",
        "Radio",
        "Toggle",
        "Switch",
        "Slider",
        "Data Grid",
        "Table",
        "List",
        "Card",
        "Avatar",
        "Badge",
        "Chip",
        "Toast",
        "Alert",
        "Banner",
        "Tooltip",
        "Popover",
        "Pagination",
        "Breadcrumb",
        "Progress",
        "Spinner",
        "Chart",
        "Calendar",
        "Date Picker",
        "Accordion",
        "Menu",
        "Toolbar",
        "Form",
        "Segmented Control",
        "Empty State",
    ]
}
