//
//  CaptureTagBar.swift
//  Snipsnap
//
//  Shared tag chips + add-tag control for Capture Library preview.
//

import SwiftUI

struct CaptureTagBar: View {
    let tags: [CaptureTag]
    let onRemoveTag: (CaptureTag) -> Void
    let onAddTag: (CaptureTagKind, String) -> Void
    /// Replaces an existing project/flow tag with a new name (move/upsert).
    var onReplaceTag: ((CaptureTag, String) -> Void)? = nil

    @State private var isAdding = false
    @State private var draftKind: CaptureTagKind = .custom
    @State private var draftName = ""
    @FocusState private var addFieldFocused: Bool

    /// Project is singular (the folder). Omit it from the add picker when one already exists.
    private var availableKinds: [CaptureTagKind] {
        if tags.contains(where: { $0.kind == .project }) {
            return CaptureTagKind.allCases.filter { $0 != .project }
        }
        return Array(CaptureTagKind.allCases)
    }

    private var projectOptions: [String] {
        CaptureLibraryOrganizer.existingProjectNames()
    }

    private var flowOptions: [String] {
        var names = Set(CaptureLibraryOrganizer.existingTagNames(kind: .flow))
        for tag in tags where tag.kind == .flow {
            names.insert(tag.name)
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            if !tags.isEmpty || isAdding {
                FlowLayout(spacing: DesignTokens.Spacing.sm) {
                    ForEach(CaptureTag.sorted(tags)) { tag in
                        tagView(tag)
                    }

                    if isAdding {
                        addTagField
                    } else {
                        addButton
                    }
                }
            } else {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text("No tags")
                        .font(.snipsnap(.caption))
                        .foregroundStyle(DesignTokens.Color.textTertiary.swiftUI)
                    addButton
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private func tagView(_ tag: CaptureTag) -> some View {
        switch tag.kind {
        case .project, .flow:
            TagKindDropdown(
                kind: tag.kind,
                selected: tag.name,
                options: tag.kind == .project ? projectOptions : flowOptions,
                onRemove: { onRemoveTag(tag) },
                onSelect: { name in
                    if name.caseInsensitiveCompare(tag.name) == .orderedSame { return }
                    if let onReplaceTag {
                        onReplaceTag(tag, name)
                    } else {
                        onRemoveTag(tag)
                        onAddTag(tag.kind, name)
                    }
                },
                onCreateNew: { beginCustom(kind: tag.kind) }
            )
        case .custom:
            tagChip(tag)
        }
    }

    private func tagChip(_ tag: CaptureTag) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(tag.kind.displayName)
                    .foregroundStyle(DesignTokens.Color.textTertiary.swiftUI)
                Text(tag.name)
                    .foregroundStyle(DesignTokens.Color.textSecondary.swiftUI)
            }
            .padding(.leading, DesignTokens.Spacing.sm)
            .padding(.trailing, 6)
            .padding(.vertical, 3)

            Rectangle()
                .fill(DesignTokens.Color.border.swiftUI)
                .frame(width: 1)
                .padding(.vertical, 1)

            Button {
                onRemoveTag(tag)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DesignTokens.Color.textTertiary.swiftUI)
                    .frame(width: 24, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help("Remove \(tag.kind.displayName.lowercased()) tag")
        }
        .font(.snipsnap(.caption))
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(DesignTokens.Color.listSelectionFill.swiftUI)
        }
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .strokeBorder(DesignTokens.Color.border.swiftUI, lineWidth: 1)
        }
        .fixedSize()
    }

    private var addButton: some View {
        Button {
            isAdding = true
            draftKind = availableKinds.contains(.custom) ? .custom : (availableKinds.first ?? .custom)
            draftName = ""
            DispatchQueue.main.async {
                addFieldFocused = true
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DesignTokens.Color.textSecondary.swiftUI)
                .frame(width: 22, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                        .fill(DesignTokens.Color.listSelectionFill.swiftUI)
                )
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help("Add tag")
    }

    private var addTagField: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Picker("Kind", selection: $draftKind) {
                ForEach(kindsForAddField) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()

            TextField(draftKind == .project ? "Project folder" : "Tag name", text: $draftName)
                .textFieldStyle(.plain)
                .font(.snipsnap(.caption))
                .frame(minWidth: 100, maxWidth: 180)
                .focused($addFieldFocused)
                .onSubmit(commitAdd)

            Button(draftKind == .project ? "Move" : "Add") {
                commitAdd()
            }
            .buttonStyle(.snipsnapCompact)
            .disabled(CaptureTag.normalizeName(draftName).isEmpty)
            .help(
                draftKind == .project
                    ? "Set project and move this capture into that folder"
                    : "Add tag"
            )

            Button {
                cancelAdd()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .foregroundStyle(DesignTokens.Color.textTertiary.swiftUI)
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(DesignTokens.Color.listSelectionFill.swiftUI)
        )
        .onExitCommand {
            cancelAdd()
        }
        .onChange(of: availableKinds.map(\.rawValue).joined(separator: ",")) { _, _ in
            if !kindsForAddField.contains(draftKind) {
                draftKind = kindsForAddField.first ?? .custom
            }
        }
    }

    /// When Custom… opens from an existing project dropdown, keep project in the picker.
    private var kindsForAddField: [CaptureTagKind] {
        if draftKind == .project || !tags.contains(where: { $0.kind == .project }) {
            return Array(CaptureTagKind.allCases)
        }
        return availableKinds
    }

    private func beginCustom(kind: CaptureTagKind) {
        isAdding = true
        draftKind = kind
        draftName = ""
        DispatchQueue.main.async {
            addFieldFocused = true
        }
    }

    private func commitAdd() {
        let name = CaptureTag.normalizeName(draftName)
        guard !name.isEmpty else { return }
        if draftKind == .project || draftKind == .flow,
           let existing = tags.first(where: { $0.kind == draftKind }) {
            if let onReplaceTag {
                onReplaceTag(existing, name)
            } else {
                onRemoveTag(existing)
                onAddTag(draftKind, name)
            }
        } else {
            onAddTag(draftKind, name)
        }
        cancelAdd()
    }

    private func cancelAdd() {
        isAdding = false
        draftName = ""
        addFieldFocused = false
    }
}

/// Bordered project/flow control: editable name field + trailing options menu.
/// Select-only soft control — same chrome as `TagKindDropdown`, without a text field.
struct SoftControlDropdown<MenuContent: View>: View {
    var leadingLabel: String? = nil
    let title: String
    var help: String? = nil
    var primaryForeground: Color = DesignTokens.Color.textPrimary.swiftUI
    var secondaryForeground: Color = DesignTokens.Color.textSecondary.swiftUI
    @ViewBuilder var menuContent: () -> MenuContent

    @State private var isHovered = false
    @State private var isPresented = false

    var body: some View {
        SoftDropdownAnchor(isPresented: $isPresented) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    if let leadingLabel {
                        Text(leadingLabel)
                            .foregroundStyle(secondaryForeground)
                    }
                    Text(title)
                        .foregroundStyle(primaryForeground)
                }
                .font(.snipsnap(.caption))
                .padding(.leading, 10)
                .padding(.trailing, 8)
                .padding(.vertical, 4)

                SoftControlDropdownChrome.divider()

                SoftControlDropdownChrome.chevron(height: 22, color: secondaryForeground)
            }
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                    .fill(
                        isHovered || isPresented
                            ? DesignTokens.Color.softControlFillHovered.swiftUI
                            : DesignTokens.Color.softControlFill.swiftUI
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                    .strokeBorder(DesignTokens.Color.softControlBorder.swiftUI, lineWidth: 1)
            }
        } menuContent: {
            menuContent()
        }
        .fixedSize()
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .pointerStyle(.link)
        .modifier(OptionalHelpModifier(help: help))
    }
}

private struct OptionalHelpModifier: ViewModifier {
    let help: String?

    func body(content: Content) -> some View {
        if let help, !help.isEmpty {
            content.help(help)
        } else {
            content
        }
    }
}

enum SoftControlDropdownChrome {
    @ViewBuilder
    static func divider(color: Color = DesignTokens.Color.softControlBorder.swiftUI) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: 1)
            .padding(.vertical, 1)
    }

    static func chevron(
        height: CGFloat,
        color: Color = DesignTokens.Color.textSecondary.swiftUI
    ) -> some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 28, height: height)
            .contentShape(Rectangle())
    }
}

/// Auto-Tag rename suggestion: "Suggesting" label outside neutral soft-control name field.
struct SuggestedNameField: View {
    let name: String
    let onCommit: (String) -> Void

    @State private var draft = ""
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Suggesting")
                .font(.snipsnap(.caption))
                .foregroundStyle(DesignTokens.Color.textSecondary.swiftUI)
                .fixedSize()

            TextField("Name", text: $draft)
                .textFieldStyle(.plain)
                .font(.snipsnap(.caption))
                .foregroundStyle(DesignTokens.Color.textPrimary.swiftUI)
                .frame(minWidth: 64, maxWidth: 220, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.leading, 10)
                .padding(.trailing, 10)
                .padding(.vertical, 4)
                .background {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                        .fill(
                            isHovered || isFocused
                                ? DesignTokens.Color.softControlFillHovered.swiftUI
                                : DesignTokens.Color.softControlFill.swiftUI
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                        .strokeBorder(
                            isFocused
                                ? DesignTokens.Color.primary.swiftUI.opacity(0.45)
                                : DesignTokens.Color.softControlBorder.swiftUI,
                            lineWidth: 1
                        )
                }
                .contentShape(Rectangle())
                .onTapGesture { isFocused = true }
                .focused($isFocused)
                .onSubmit(commitDraft)
                .onExitCommand {
                    syncDraft()
                    isFocused = false
                }
                .onHover { isHovered = $0 }
                .help("Edit suggested name")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: syncDraft)
        .onChange(of: name) { _, _ in
            guard !isFocused else { return }
            syncDraft()
        }
        .onChange(of: isFocused) { _, focused in
            if focused {
                draft = name
            } else {
                commitDraft()
            }
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private func syncDraft() {
        draft = name
    }

    private func commitDraft() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            syncDraft()
            return
        }
        if trimmed.caseInsensitiveCompare(name) == .orderedSame {
            syncDraft()
            return
        }
        draft = trimmed
        onCommit(trimmed)
    }
}

struct TagKindDropdown: View {
    let kind: CaptureTagKind
    let selected: String
    let options: [String]
    var emphasized: Bool = false
    /// When true, keeps the same chrome but disables editing and the menu.
    var isReadOnly: Bool = false
    var onRemove: (() -> Void)? = nil
    let onSelect: (String) -> Void
    let onCreateNew: () -> Void

    @State private var draft = ""
    @State private var isHovered = false
    @State private var isMenuPresented = false
    @FocusState private var isFocused: Bool

    private var borderColor: Color {
        emphasized
            ? DesignTokens.Color.primary.swiftUI.opacity(0.35)
            : DesignTokens.Color.softControlBorder.swiftUI
    }

    private var labelForeground: Color {
        isReadOnly
            ? DesignTokens.Color.textSecondary.swiftUI
            : DesignTokens.Color.textPrimary.swiftUI
    }

    private var isEmptySelection: Bool {
        selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selected.caseInsensitiveCompare("None") == .orderedSame
    }

    private var placeholder: String {
        kind == .project ? "Project" : kind.displayName
    }

    private var kindSymbol: String {
        kind == .project ? "folder" : "arrow.triangle.branch"
    }

    private var menuChevron: some View {
        SoftControlDropdownChrome.chevron(height: emphasized ? 24 : 22)
    }

    var body: some View {
        HStack(spacing: 0) {
            fieldContent

            SoftControlDropdownChrome.divider(color: borderColor)

            if isReadOnly {
                menuChevron
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            } else {
                SoftDropdownAnchor(isPresented: $isMenuPresented) {
                    menuChevron
                } menuContent: {
                    ForEach(options, id: \.self) { name in
                        SoftDropdownRow(
                            title: name,
                            systemImage: kindSymbol,
                            isSelected: name.caseInsensitiveCompare(selected) == .orderedSame
                        ) {
                            applySelection(name)
                        }
                    }

                    if !options.isEmpty {
                        SoftDropdownDivider()
                    }

                    if onRemove != nil, !isEmptySelection {
                        SoftDropdownRow(title: "None", systemImage: "circle.slash") {
                            onRemove?()
                        }
                    }

                    SoftDropdownRow(title: "Custom…", systemImage: "plus") {
                        onCreateNew()
                    }
                }
                .pointerStyle(.link)
                .help(
                    kind == .project
                        ? "Choose project folder"
                        : "Choose \(kind.displayName.lowercased())"
                )
            }
        }
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .fill(
                    !isReadOnly && (isHovered || isFocused)
                        ? DesignTokens.Color.softControlFillHovered.swiftUI
                        : DesignTokens.Color.softControlFill.swiftUI
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .strokeBorder(
                    isFocused
                        ? DesignTokens.Color.primary.swiftUI.opacity(0.45)
                        : borderColor,
                    lineWidth: 1
                )
        }
        .fixedSize()
        .onAppear(perform: syncDraftFromSelected)
        .onChange(of: selected) { _, _ in
            guard !isFocused else { return }
            syncDraftFromSelected()
        }
        .onChange(of: isFocused) { _, focused in
            if focused {
                draft = isEmptySelection ? "" : selected
            } else {
                commitDraft()
            }
        }
        .onChange(of: isReadOnly) { _, readOnly in
            if readOnly {
                isFocused = false
                syncDraftFromSelected()
            }
        }
        .onHover { hovering in
            guard !isReadOnly else { return }
            isHovered = hovering
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityAddTraits(isReadOnly ? .isStaticText : [])
    }

    @ViewBuilder
    private var fieldContent: some View {
        HStack(spacing: 6) {
            Image(systemName: kind == .project ? "folder.fill" : "arrow.triangle.branch")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(labelForeground)

            TextField(placeholder, text: $draft)
                .textFieldStyle(.plain)
                .font(.snipsnap(.caption))
                .foregroundStyle(labelForeground)
                .frame(minWidth: 48, maxWidth: 160, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
                .focused($isFocused)
                .onSubmit(commitDraft)
                .onExitCommand {
                    syncDraftFromSelected()
                    isFocused = false
                }
        }
        .font(.snipsnap(.caption))
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, emphasized ? 5 : 4)
        .contentShape(Rectangle())
        .allowsHitTesting(!isReadOnly)
    }

    private func syncDraftFromSelected() {
        draft = isEmptySelection ? "" : selected
    }

    private func commitDraft() {
        guard !isReadOnly else {
            syncDraftFromSelected()
            return
        }

        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty || trimmed.caseInsensitiveCompare("None") == .orderedSame {
            if let onRemove, !isEmptySelection {
                onRemove()
            } else {
                syncDraftFromSelected()
            }
            return
        }

        if !isEmptySelection, trimmed.caseInsensitiveCompare(selected) == .orderedSame {
            syncDraftFromSelected()
            return
        }

        applySelection(trimmed)
    }

    private func applySelection(_ name: String) {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        draft = normalized
        onSelect(normalized)
    }
}

/// Simple wrapping layout for tag chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalWidth = max(totalWidth, x - spacing)
        }

        return (CGSize(width: totalWidth, height: y + rowHeight), frames)
    }
}
