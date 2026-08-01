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

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            if !tags.isEmpty || isAdding {
                FlowLayout(spacing: DesignTokens.Spacing.sm) {
                    ForEach(CaptureTag.sorted(tags)) { tag in
                        tagChip(tag)
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

    private func tagChip(_ tag: CaptureTag) -> some View {
        HStack(spacing: 4) {
            if tag.kind == .project {
                Image(systemName: "folder.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DesignTokens.Color.textTertiary.swiftUI)
            }
            Text(tag.kind.displayName)
                .foregroundStyle(DesignTokens.Color.textTertiary.swiftUI)
            Text(tag.name)
                .foregroundStyle(DesignTokens.Color.textSecondary.swiftUI)
            Button {
                onRemoveTag(tag)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DesignTokens.Color.textTertiary.swiftUI)
            }
            .buttonStyle(.plain)
            .help(
                tag.kind == .project
                    ? "Remove project and move file back to save folder"
                    : "Remove \(tag.kind.displayName.lowercased()) tag"
            )
        }
        .font(.snipsnap(.caption))
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(DesignTokens.Color.listSelectionFill.swiftUI)
        )
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
        .help("Add tag")
    }

    private var addTagField: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Picker("Kind", selection: $draftKind) {
                ForEach(availableKinds) { kind in
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
            if !availableKinds.contains(draftKind) {
                draftKind = availableKinds.first ?? .custom
            }
        }
    }

    private func commitAdd() {
        let name = CaptureTag.normalizeName(draftName)
        guard !name.isEmpty else { return }
        onAddTag(draftKind, name)
        cancelAdd()
    }

    private func cancelAdd() {
        isAdding = false
        draftName = ""
        addFieldFocused = false
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
