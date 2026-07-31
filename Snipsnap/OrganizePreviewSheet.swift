//
//  OrganizePreviewSheet.swift
//  Snipsnap
//

import SwiftUI

struct OrganizePreviewSheet: View {
    @Binding var plan: OrganizePlan
    let isLoading: Bool
    let includeOrganized: Binding<Bool>
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if isLoading {
                loadingState
            } else {
                planContent
            }

            Divider()
            footer
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Organize Captures")
                .font(.snipsnap(.title))
            Text("Review proposed project folders before moving files.")
                .font(.snipsnap(.caption))
                .foregroundStyle(DesignTokens.Color.textSecondary.swiftUI)
            Toggle("Include already organized captures", isOn: includeOrganized)
                .font(.snipsnap(.body))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.Spacing.lg)
    }

    private var loadingState: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ProgressView()
                .controlSize(.regular)
            Text("Classifying captures…")
                .font(.snipsnap(.body))
                .foregroundStyle(DesignTokens.Color.textSecondary.swiftUI)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var planContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                if !plan.groupedByProject.isEmpty {
                    ForEach(plan.groupedByProject, id: \.project) { group in
                        projectSection(project: group.project, items: group.items)
                    }
                }

                if !plan.unmatchedItems.isEmpty {
                    unmatchedSection
                }

                if plan.matchedItems.isEmpty && plan.unmatchedItems.isEmpty {
                    ContentUnavailableView(
                        "Nothing to Organize",
                        systemImage: "folder",
                        description: Text("No captures matched the current scope.")
                    )
                    .padding(.vertical, DesignTokens.Spacing.xl)
                }
            }
            .padding(DesignTokens.Spacing.lg)
        }
    }

    private func projectSection(project: String, items: [OrganizePlanItem]) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Label(project, systemImage: "folder.fill")
                .font(.snipsnap(.bodyEmphasized))

            ForEach(items) { item in
                organizeRow(item)
            }
        }
    }

    private var unmatchedSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("No confident match — staying put")
                .font(.snipsnap(.bodyEmphasized))
                .foregroundStyle(DesignTokens.Color.textSecondary.swiftUI)

            ForEach(plan.unmatchedItems) { item in
                organizeRow(item)
            }
        }
    }

    private func organizeRow(_ item: OrganizePlanItem) -> some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Toggle(
                "",
                isOn: binding(for: item)
            )
            .labelsHidden()
            .disabled(!item.isInteractive)

            Image(nsImage: item.entry.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 36, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.entry.displayName)
                    .font(.snipsnap(.body))
                    .foregroundStyle(item.isInteractive ? .primary : DesignTokens.Color.textSecondary.swiftUI)
                if let project = item.projectName {
                    Text("→ \(project)")
                        .font(.snipsnap(.caption))
                        .foregroundStyle(DesignTokens.Color.textSecondary.swiftUI)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .opacity(item.isInteractive ? 1 : 0.55)
    }

    private func binding(for item: OrganizePlanItem) -> Binding<Bool> {
        Binding(
            get: {
                if let index = plan.matchedItems.firstIndex(where: { $0.id == item.id }) {
                    return plan.matchedItems[index].isChecked
                }
                return false
            },
            set: { newValue in
                guard let index = plan.matchedItems.firstIndex(where: { $0.id == item.id }) else { return }
                plan.matchedItems[index].isChecked = newValue
            }
        )
    }

    private var footer: some View {
        HStack {
            Button("Cancel", action: onCancel)
            Spacer()
            Button("Confirm", action: onConfirm)
                .keyboardShortcut(.defaultAction)
                .disabled(isLoading || !plan.matchedItems.contains(where: \.isChecked))
        }
        .padding(DesignTokens.Spacing.lg)
    }
}
