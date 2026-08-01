//
//  CaptureLibraryWindow.swift
//  Snipsnap
//

import SwiftUI
import Combine
@preconcurrency import AppKit
import AVKit

enum AppDockPresentation {
    static var isLibraryPresented: Bool {
        guard let window = CaptureLibraryWindow.current else { return false }
        return window.isVisible || window.isMiniaturized
    }

    static func presentLibraryWindow() {
        guard NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
    }

    static func hideFromDockIfNeeded() {
        guard isLibraryPresented == false else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}

final class CaptureLibraryWindow: NSWindow, NSWindowDelegate {
    static var current: CaptureLibraryWindow?

    private nonisolated(unsafe) var historyObserver: NSObjectProtocol?
    fileprivate let sessionState = CaptureLibrarySessionState()
    private var hostingView: NSHostingView<CaptureLibraryView>?

    static func show() {
        DispatchQueue.main.async {
            if current == nil {
                current = CaptureLibraryWindow()
            }
            AppDockPresentation.presentLibraryWindow()
            current?.reloadContent()
            current?.center()
            current?.makeKeyAndOrderFront(nil)
            current?.applyTitlebarFill()
            // Toolbar / titlebar materials finish installing after the first layout pass.
            DispatchQueue.main.async {
                current?.applyTitlebarFill()
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        title = "Snipsnap"
        titleVisibility = .hidden
        toolbarStyle = .unifiedCompact
        // Let window.backgroundColor show through the titlebar + toolbar chrome
        // (SwiftUI .toolbarBackground does not reliably tint AppKit-hosted toolbars).
        styleMask.insert(.fullSizeContentView)
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        backgroundColor = DesignTokens.Color.background.ns
        minSize = NSSize(width: 640, height: 420)
        isReleasedWhenClosed = false
        delegate = self

        historyObserver = NotificationCenter.default.addObserver(
            forName: .captureHistoryDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reloadContent()
            }
        }

        reloadContent()
    }

    deinit {
        if let historyObserver {
            NotificationCenter.default.removeObserver(historyObserver)
        }
    }

    func reloadContent() {
        let view = CaptureLibraryView(
            entries: CaptureHistory.shared.entriesInSaveRoot,
            sessionState: sessionState,
            onOpen: { entry in
                CaptureLibraryWindow.open(entry)
            }
        )
        if let hostingView {
            // Update in place so List scroll position and @State selection survive.
            hostingView.rootView = view
            layoutLibraryContent(hostingView)
            applyTitlebarFill()
            return
        }
        let hostingView = NSHostingView(rootView: view)
        // Avoid List intrinsic height driving window/sidebar sizing.
        hostingView.sizingOptions = []
        self.hostingView = hostingView
        layoutLibraryContent(hostingView)
        applyTitlebarFill()
    }

    private func layoutLibraryContent(_ hostingView: NSView) {
        if let container = contentView as? CaptureLibraryContentContainer {
            container.setHostingView(hostingView)
            return
        }

        let container = CaptureLibraryContentContainer()
        container.wantsLayer = true
        container.layer?.backgroundColor = DesignTokens.Color.background.ns.cgColor
        container.setHostingView(hostingView)
        contentView = container
    }

    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        (contentView as? CaptureLibraryContentContainer)?.layoutHostingView(in: self)
        applyTitlebarFill()
    }

    /// Solid fill behind traffic lights / title / toolbar items; kill vibrancy that stays white.
    fileprivate func applyTitlebarFill() {
        let fill = DesignTokens.Color.background.ns
        backgroundColor = fill
        toolbar?.showsBaselineSeparator = false
        contentView?.wantsLayer = true
        contentView?.layer?.backgroundColor = fill.cgColor

        guard let closeButton = standardWindowButton(.closeButton),
              let titlebar = closeButton.superview else { return }

        // Titlebar view + container + any toolbar chrome often use NSVisualEffectView
        // materials that stay system-white unless removed.
        var roots: [NSView] = [titlebar]
        if let container = titlebar.superview {
            roots.append(container)
        }
        for root in roots {
            hideVisualEffects(in: root, depth: 0)
            root.wantsLayer = true
            root.layer?.backgroundColor = fill.cgColor
        }
    }

    private func hideVisualEffects(in view: NSView, depth: Int) {
        guard depth < 5 else { return }
        if let effect = view as? NSVisualEffectView {
            effect.isHidden = true
            effect.alphaValue = 0
        }
        for subview in view.subviews {
            hideVisualEffects(in: subview, depth: depth + 1)
        }
    }

    static func open(_ entry: CaptureEntry) {
        switch entry.item {
        case .screenshot:
            guard let image = CaptureHistory.shared.fullImage(for: entry.id) else { return }
            AnnotationWindow.show(image: image, fileName: entry.displayName, captureID: entry.id)
        case .recording(let url, let thumbnail):
            VideoAnnotationWindow.show(url: url, thumbnail: thumbnail)
        }
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            AppDockPresentation.hideFromDockIfNeeded()
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        applyTitlebarFill()
    }

    func windowDidResize(_ notification: Notification) {
        applyTitlebarFill()
    }
}

/// Hosts SwiftUI below the titlebar/toolbar when using `fullSizeContentView`.
private final class CaptureLibraryContentContainer: NSView {
    private var hostingView: NSView?

    func setHostingView(_ view: NSView) {
        hostingView?.removeFromSuperview()
        hostingView = view
        addSubview(view)
        needsLayout = true
    }

    func layoutHostingView(in window: NSWindow) {
        guard let hostingView else { return }
        let safeRect = convert(window.contentLayoutRect, from: nil)
        hostingView.frame = safeRect
        hostingView.autoresizingMask = [.width, .height]
    }

    override func layout() {
        super.layout()
        guard let window else { return }
        layoutHostingView(in: window)
    }
}

// MARK: - Row suggestion state

private struct CaptureRowSuggestionState {
    var isLoading = false
    var suggestion: RenameSuggestion?
    var selectedProject: String?
    var selectedFlow: String?
    /// Editable UI-component tags for the active Auto-Tag suggestion (seeded from the model).
    var selectedComponents: [String] = []
    var acceptedSnapshot: CaptureLocationSnapshot?
    var wroteMapping = false
    var windowInfo: WindowSignature?

    var effectiveProject: String? {
        if let selectedProject,
           !selectedProject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return selectedProject
        }
        return suggestion?.suggestedProject
    }

    var effectiveFlow: String? {
        if let selectedFlow,
           !selectedFlow.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return selectedFlow
        }
        return suggestion?.suggestedFlow
    }

    var effectiveComponents: [String] {
        selectedComponents
    }

    var showsProjectPicker: Bool {
        guard suggestion != nil else { return false }
        return suggestion?.hasProject == true || effectiveProject != nil
    }

    var showsFlowPicker: Bool {
        guard suggestion != nil else { return false }
        return suggestion?.hasFlow == true || effectiveFlow != nil
    }

    var showsComponents: Bool {
        guard suggestion != nil else { return false }
        return !selectedComponents.isEmpty || suggestion?.hasComponents == true
    }
}

@MainActor
fileprivate final class CaptureLibrarySessionState: ObservableObject {
    @Published var rowStates: [UUID: CaptureRowSuggestionState] = [:]
}

// MARK: - SwiftUI

private enum CaptureLibraryGroupBy: String, CaseIterable, Identifiable {
    case none
    case project

    var id: String { rawValue }

    var menuLabel: String {
        switch self {
        case .none: return "None"
        case .project: return "Project"
        }
    }
}

private struct CaptureLibraryProjectGroup: Identifiable {
    let name: String
    let entries: [CaptureEntry]

    var id: String { name }
}

private struct CaptureLibraryView: View {
    let entries: [CaptureEntry]
    @ObservedObject var sessionState: CaptureLibrarySessionState
    let onOpen: (CaptureEntry) -> Void

    @AppStorage("captureLibraryGroupBy") private var groupByRaw = CaptureLibraryGroupBy.none.rawValue
    @State private var selection = Set<UUID>()
    @State private var visibleCount = CaptureLibraryView.initialPageSize
    @State private var renameTarget: CaptureEntry?
    @State private var renameDraft = ""
    @State private var createProjectTarget: UUID?
    @State private var createProjectDraft = ""
    @State private var createFlowTarget: UUID?
    @State private var createFlowDraft = ""
    @State private var createComponentTarget: UUID?
    @State private var createComponentDraft = ""
    @State private var replaceComponentTarget: (id: UUID, index: Int)?
    @State private var replaceComponentDraft = ""
    /// Groups start collapsed; membership means the section is expanded.
    @State private var expandedGroupIDs = Set<String>()
    /// Manual double-click detection so rename does not use TapGesture(count: 2),
    /// which can swallow the first click and leave List selection unchanged.
    @State private var lastRowClick: (id: UUID, date: Date)?

    @State private var showOrganizeSheet = false
    @State private var organizePlan = OrganizePlan(matchedItems: [], unmatchedItems: [])
    @State private var organizeLoading = false
    @State private var includeOrganizedCaptures = false
    @State private var organizeTask: Task<Void, Never>?

    private static let initialPageSize = 40
    private static let pageSize = 40

    private var groupBy: CaptureLibraryGroupBy {
        CaptureLibraryGroupBy(rawValue: groupByRaw) ?? .none
    }

    private var visibleEntries: [CaptureEntry] {
        Array(entries.prefix(visibleCount))
    }

    private var projectGroups: [CaptureLibraryProjectGroup] {
        let grouped = Dictionary(grouping: entries) { entry in
            CaptureLibraryProject.currentName(for: entry) ?? "None"
        }
        return grouped.keys
            .sorted { lhs, rhs in
                if lhs == "None" { return false }
                if rhs == "None" { return true }
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
            .map { key in
                CaptureLibraryProjectGroup(name: key, entries: grouped[key] ?? [])
            }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebarColumn
            Rectangle()
                .fill(DesignTokens.Color.border.swiftUI.opacity(0.55))
                .frame(width: 1)
                .frame(maxHeight: .infinity)
            detailColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignTokens.Color.background.swiftUI)
        }
        .background(DesignTokens.Color.background.swiftUI)
        // Prefer a solid toolbar fill; AppKit also strips titlebar vibrancy in applyTitlebarFill().
        .toolbarBackground(DesignTokens.Color.background.swiftUI, for: .windowToolbar)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Snipsnap")
                    .font(.snipsnap(.windowTitle))
                    .foregroundStyle(DesignTokens.Color.textPrimary.swiftUI)
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .primaryAction) {
                Button {
                    requestSuggestions(for: selection)
                } label: {
                    Label("Auto-Rename", systemImage: "sparkles")
                        .font(.snipsnap(.body))
                }
                .controlSize(.small)
                .disabled(selection.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    presentOrganizeSheet()
                } label: {
                    Label("Organize", systemImage: "folder.badge.gearshape")
                        .font(.snipsnap(.body))
                }
                .controlSize(.small)
                .disabled(entries.isEmpty)
            }
        }
        .sheet(isPresented: $showOrganizeSheet) {
            OrganizePreviewSheet(
                plan: $organizePlan,
                isLoading: organizeLoading,
                includeOrganized: $includeOrganizedCaptures,
                onConfirm: confirmOrganize,
                onCancel: {
                    organizeTask?.cancel()
                    showOrganizeSheet = false
                }
            )
        }
        .onChange(of: includeOrganizedCaptures) { _, _ in
            reloadOrganizePlan()
        }
        .alert("New Project", isPresented: createProjectAlertBinding) {
            TextField("Project name", text: $createProjectDraft)
            Button("Cancel", role: .cancel) {
                createProjectTarget = nil
            }
            Button("Create") {
                if let targetID = createProjectTarget,
                   let name = CaptureLibraryOrganizer.sanitizedProjectName(createProjectDraft) {
                    setProject(name, for: targetID)
                }
                createProjectTarget = nil
            }
        }
        .alert("Custom Flow", isPresented: createFlowAlertBinding) {
            TextField("Flow name", text: $createFlowDraft)
            Button("Cancel", role: .cancel) {
                createFlowTarget = nil
            }
            Button("Create") {
                if let targetID = createFlowTarget {
                    let name = CaptureTag.normalizeName(createFlowDraft)
                    if !name.isEmpty {
                        setFlow(name, for: targetID)
                    }
                }
                createFlowTarget = nil
            }
        }
        .alert("Add Component", isPresented: createComponentAlertBinding) {
            TextField("UI component (e.g. Button, Modal)", text: $createComponentDraft)
            Button("Cancel", role: .cancel) {
                createComponentTarget = nil
            }
            Button("Add") {
                if let targetID = createComponentTarget {
                    let name = CaptureTag.normalizeName(createComponentDraft)
                    if !name.isEmpty {
                        addComponent(name, for: targetID)
                    }
                }
                createComponentTarget = nil
            }
        }
        .alert("Edit Component", isPresented: replaceComponentAlertBinding) {
            TextField("UI component", text: $replaceComponentDraft)
            Button("Cancel", role: .cancel) {
                replaceComponentTarget = nil
            }
            Button("Save") {
                if let target = replaceComponentTarget {
                    let name = CaptureTag.normalizeName(replaceComponentDraft)
                    if !name.isEmpty {
                        replaceComponent(at: target.index, with: name, for: target.id)
                    }
                }
                replaceComponentTarget = nil
            }
        }
        .onAppear {
            resetVisibleWindow()
            if selection.isEmpty, let first = entries.first {
                selection = [first.id]
            }
        }
        .onChange(of: groupByRaw) { _, _ in
            expandedGroupIDs = []
        }
        .onChange(of: entries.count) { _, _ in
            selection = selection.filter { id in entries.contains(where: { $0.id == id }) }
            if selection.isEmpty, let first = entries.first {
                selection = [first.id]
            }
            ensureSelectionVisible()
        }
    }

    private var selectedEntry: CaptureEntry? {
        entries.first { selection.contains($0.id) }
    }

    private var selectedEntries: [CaptureEntry] {
        entries.filter { selection.contains($0.id) }
    }

    @ViewBuilder
    private var sidebarColumn: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Captures Yet",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Screenshots and recordings will appear here.")
                )
            } else {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    groupByPicker
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.top, DesignTokens.Spacing.sm)
                        .fixedSize(horizontal: true, vertical: true)

                    GeometryReader { geo in
                        captureList
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DesignTokens.Color.background.swiftUI)
    }

    private var groupByPicker: some View {
        Menu {
            ForEach(CaptureLibraryGroupBy.allCases) { option in
                Button {
                    groupByRaw = option.rawValue
                } label: {
                    if option == groupBy {
                        Label(option.menuLabel, systemImage: "checkmark")
                    } else {
                        Text(option.menuLabel)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("Group by")
                    .foregroundStyle(DesignTokens.Color.textSecondary.swiftUI)
                Text(groupBy.menuLabel)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(DesignTokens.Color.textTertiary.swiftUI)
            }
            .font(.custom(DesignTokens.Typography.postScriptName(for: .medium), size: 14))
            .foregroundStyle(DesignTokens.Color.textPrimary.swiftUI)
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(DesignTokens.Color.listSelectionFill.swiftUI)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .stroke(DesignTokens.Color.border.swiftUI, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .pointerStyle(.link)
        .help("Group captures in the sidebar")
    }

    @ViewBuilder
    private var captureList: some View {
        List(selection: $selection) {
            if groupBy == .project {
                ForEach(projectGroups) { group in
                    projectGroupHeader(for: group)
                        .selectionDisabled()
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(
                            top: DesignTokens.Spacing.xs,
                            leading: 0,
                            bottom: DesignTokens.Spacing.xs,
                            trailing: 0
                        ))

                    if expandedGroupIDs.contains(group.id) {
                        ForEach(group.entries) { entry in
                            captureListRow(for: entry, nested: true)
                        }
                    }
                }
            } else {
                ForEach(visibleEntries) { entry in
                    captureListRow(for: entry)
                        .onAppear {
                            loadMoreIfNeeded(entry)
                        }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .background(DesignTokens.Color.background.swiftUI)
    }

    private func projectGroupHeader(for group: CaptureLibraryProjectGroup) -> some View {
        let isExpanded = expandedGroupIDs.contains(group.id)
        return Button {
            toggleGroupExpanded(group.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DesignTokens.Color.textTertiary.swiftUI)
                    .frame(width: 10, alignment: .center)

                Text(group.name)
                    .font(.snipsnap(.caption))
                    .foregroundStyle(DesignTokens.Color.textSecondary.swiftUI)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
    }

    private func toggleGroupExpanded(_ id: String) {
        if expandedGroupIDs.contains(id) {
            expandedGroupIDs.remove(id)
        } else {
            expandedGroupIDs.insert(id)
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if selection.count >= 2 {
            CaptureMultiSelectPane(
                entries: selectedEntries,
                rowStates: sessionState.rowStates,
                onAutoTag: { requestSuggestions(for: selection) },
                onAcceptSuggestion: { acceptSuggestion(for: $0) },
                onDismissSuggestion: { dismissSuggestion(for: $0) },
                onRevertSuggestion: { revertSuggestion(for: $0) },
                onSelectProject: { setProject($0, for: $1) },
                onCreateProject: { beginCreateProject(for: $0) },
                onSelectFlow: { setFlow($0, for: $1) },
                onCreateFlow: { beginCreateFlow(for: $0) },
                onSelectComponent: { name, index, id in replaceComponent(at: index, with: name, for: id) },
                onRemoveComponent: { index, id in removeComponent(at: index, for: id) },
                onCreateComponent: { beginCreateComponent(for: $0) },
                onEditComponent: { index, id in beginEditComponent(at: index, for: id) },
                onClearProject: { clearSuggestedProject(for: $0) }
            )
        } else if let entry = selectedEntry {
            CapturePreviewPane(
                entry: entry,
                sessionState: sessionState,
                onOpen: onOpen,
                onAutoTag: { requestSuggestion(for: entry) },
                onAcceptSuggestion: { acceptSuggestion(for: entry) },
                onDismissSuggestion: { dismissSuggestion(for: entry) },
                onSelectProject: { setProject($0, for: entry.id) },
                onCreateProject: { beginCreateProject(for: entry.id) },
                onSelectFlow: { setFlow($0, for: entry.id) },
                onCreateFlow: { beginCreateFlow(for: entry.id) },
                onSelectComponent: { name, index in replaceComponent(at: index, with: name, for: entry.id) },
                onRemoveComponent: { index in removeComponent(at: index, for: entry.id) },
                onCreateComponent: { beginCreateComponent(for: entry.id) },
                onEditComponent: { index in beginEditComponent(at: index, for: entry.id) },
                onClearProject: { clearSuggestedProject(for: entry.id) },
                onRemoveTag: { tag in
                    if entry.tags.contains(where: { $0.id == tag.id }) {
                        _ = CaptureHistory.shared.removeTag(id: entry.id, tagID: tag.id)
                    } else if tag.kind == .project {
                        _ = CaptureHistory.shared.clearProjectTag(id: entry.id)
                    }
                },
                onAddTag: { kind, name in
                    _ = CaptureHistory.shared.addTag(id: entry.id, kind: kind, name: name)
                }
            )
        } else {
            ContentUnavailableView(
                "Select a Capture",
                systemImage: "sidebar.left",
                description: Text("Choose a screenshot or recording from the sidebar.")
            )
        }
    }

    @ViewBuilder
    private func captureListRow(for entry: CaptureEntry, nested: Bool = false) -> some View {
        let isRenaming = renameTarget?.id == entry.id
        let row = CaptureSidebarRow(
            entry: entry,
            rowState: sessionState.rowStates[entry.id] ?? CaptureRowSuggestionState(),
            isRenaming: isRenaming,
            renameDraft: $renameDraft,
            onCommitRename: commitRename,
            onCancelRename: cancelRename,
            onRevertSuggestion: { revertSuggestion(for: entry) }
        )

        // Keep the TextField out of a Button while renaming — otherwise macOS
        // shows an empty edit chrome until a second click focuses the field.
        Group {
            if isRenaming {
                row
            } else {
                Button {
                    handleCaptureRowClick(entry)
                } label: {
                    row
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
        }
        .tag(entry.id)
        .listRowBackground(listRowBackground(isSelected: selection.contains(entry.id)))
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(
            top: DesignTokens.Spacing.xs,
            leading: nested ? DesignTokens.Spacing.lg : DesignTokens.Spacing.sm,
            bottom: DesignTokens.Spacing.xs,
            trailing: nested ? DesignTokens.Spacing.md : DesignTokens.Spacing.sm
        ))
        // Custom light selection fill — keep labels dark instead of List's white-on-accent tint.
        .environment(\.backgroundProminence, .standard)
        .foregroundStyle(DesignTokens.Color.textPrimary.swiftUI)
        .contextMenu {
            Button {
                requestSuggestion(for: entry)
            } label: {
                Label("Auto-Rename", systemImage: "sparkles")
            }
            Button {
                showInFinder(entry)
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
            Button {
                beginRename(entry)
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Divider()
            Button("Move to Trash", role: .destructive) {
                moveToTrash(entry)
            }
        }
    }

    private func handleCaptureRowClick(_ entry: CaptureEntry) {
        let now = Date()
        if let last = lastRowClick,
           last.id == entry.id,
           now.timeIntervalSince(last.date) <= NSEvent.doubleClickInterval {
            lastRowClick = nil
            beginRename(entry)
            return
        }
        lastRowClick = (id: entry.id, date: now)

        if NSEvent.modifierFlags.contains(.command) {
            if selection.contains(entry.id) {
                selection.remove(entry.id)
            } else {
                selection.insert(entry.id)
            }
        } else {
            selection = [entry.id]
        }
    }

    private func listRowBackground(isSelected: Bool) -> some View {
        // Same view type always — swapping Clear ↔ Shape on select
        // can nudge List layout/scroll during selection changes.
        Rectangle()
            .fill(DesignTokens.Color.listSelectionFill.swiftUI.opacity(isSelected ? 1 : 0))
    }

    private var createProjectAlertBinding: Binding<Bool> {
        Binding(
            get: { createProjectTarget != nil },
            set: { if !$0 { createProjectTarget = nil } }
        )
    }

    private var createFlowAlertBinding: Binding<Bool> {
        Binding(
            get: { createFlowTarget != nil },
            set: { if !$0 { createFlowTarget = nil } }
        )
    }

    private var createComponentAlertBinding: Binding<Bool> {
        Binding(
            get: { createComponentTarget != nil },
            set: { if !$0 { createComponentTarget = nil } }
        )
    }

    private var replaceComponentAlertBinding: Binding<Bool> {
        Binding(
            get: { replaceComponentTarget != nil },
            set: { if !$0 { replaceComponentTarget = nil } }
        )
    }

    private func resetVisibleWindow() {
        visibleCount = min(Self.initialPageSize, max(entries.count, 0))
        ensureSelectionVisible()
    }

    private func ensureSelectionVisible() {
        guard let farthestIndex = entries.indices.reversed().first(where: { selection.contains(entries[$0].id) }) else {
            visibleCount = min(max(visibleCount, Self.initialPageSize), entries.count)
            return
        }
        let needed = farthestIndex + 1
        if needed > visibleCount {
            visibleCount = min(max(needed, Self.initialPageSize), entries.count)
        } else {
            visibleCount = min(max(visibleCount, Self.initialPageSize), entries.count)
        }
    }

    private func loadMoreIfNeeded(_ entry: CaptureEntry) {
        guard let index = visibleEntries.firstIndex(where: { $0.id == entry.id }) else { return }
        let threshold = max(visibleEntries.count - 8, 0)
        guard index >= threshold else { return }
        guard visibleCount < entries.count else { return }
        visibleCount = min(visibleCount + Self.pageSize, entries.count)
    }

    private func beginCreateProject(for id: UUID) {
        createProjectTarget = id
        createProjectDraft = sessionState.rowStates[id]?.effectiveProject ?? ""
    }

    private func beginCreateFlow(for id: UUID) {
        createFlowTarget = id
        createFlowDraft = sessionState.rowStates[id]?.effectiveFlow ?? ""
    }

    private func beginCreateComponent(for id: UUID) {
        createComponentTarget = id
        createComponentDraft = ""
    }

    private func beginEditComponent(at index: Int, for id: UUID) {
        guard let components = sessionState.rowStates[id]?.selectedComponents,
              components.indices.contains(index) else {
            return
        }
        replaceComponentTarget = (id: id, index: index)
        replaceComponentDraft = components[index]
    }

    private func setProject(_ project: String, for id: UUID) {
        updateRowState(id) { state in
            state.selectedProject = project
        }
    }

    private func clearSuggestedProject(for id: UUID) {
        updateRowState(id) { state in
            state.selectedProject = nil
            guard let suggestion = state.suggestion else { return }
            state.suggestion = RenameSuggestion(
                suggestedName: suggestion.suggestedName,
                suggestedProject: nil,
                suggestedFlow: suggestion.suggestedFlow,
                suggestedComponents: suggestion.suggestedComponents,
                confidence: suggestion.confidence
            )
        }
    }

    private func setFlow(_ flow: String, for id: UUID) {
        updateRowState(id) { state in
            state.selectedFlow = flow
        }
    }

    private func addComponent(_ name: String, for id: UUID) {
        let normalized = CaptureTag.normalizeName(name)
        guard !normalized.isEmpty else { return }
        updateRowState(id) { state in
            guard !state.selectedComponents.contains(where: {
                $0.caseInsensitiveCompare(normalized) == .orderedSame
            }) else { return }
            state.selectedComponents.append(normalized)
        }
    }

    private func replaceComponent(at index: Int, with name: String, for id: UUID) {
        let normalized = CaptureTag.normalizeName(name)
        guard !normalized.isEmpty else { return }
        updateRowState(id) { state in
            guard state.selectedComponents.indices.contains(index) else { return }
            if let existing = state.selectedComponents.firstIndex(where: {
                $0.caseInsensitiveCompare(normalized) == .orderedSame
            }), existing != index {
                return
            }
            state.selectedComponents[index] = normalized
        }
    }

    private func removeComponent(at index: Int, for id: UUID) {
        updateRowState(id) { state in
            guard state.selectedComponents.indices.contains(index) else { return }
            state.selectedComponents.remove(at: index)
        }
    }

    private func beginRename(_ entry: CaptureEntry) {
        selection = [entry.id]
        // Seed the draft before flipping into edit mode so the field never
        // mounts against an empty string.
        renameDraft = entry.displayName
        renameTarget = entry
    }

    private func commitRename() {
        guard let target = renameTarget else { return }
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != target.displayName {
            _ = CaptureHistory.shared.renameCapture(id: target.id, to: trimmed)
        }
        renameTarget = nil
    }

    private func cancelRename() {
        renameTarget = nil
    }

    private func showInFinder(_ entry: CaptureEntry) {
        guard let url = CaptureHistory.shared.fileURL(for: entry.id) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func moveToTrash(_ entry: CaptureEntry) {
        CaptureHistory.shared.remove(id: entry.id)
        sessionState.rowStates.removeValue(forKey: entry.id)
    }

    private func updateRowState(_ id: UUID, _ transform: (inout CaptureRowSuggestionState) -> Void) {
        var state = sessionState.rowStates[id] ?? CaptureRowSuggestionState()
        transform(&state)
        sessionState.rowStates[id] = state
    }

    // MARK: - Inline AI suggestion

    private func requestSuggestions(for ids: Set<UUID>) {
        for entry in entries where ids.contains(entry.id) {
            requestSuggestion(for: entry)
        }
    }

    private func requestSuggestion(for entry: CaptureEntry) {
        guard let image = CaptureClassifier.imageForClassification(from: entry) else { return }

        let windowInfo = AutoOrganizer.windowInfo(for: entry.id)
        updateRowState(entry.id) { state in
            state.isLoading = true
            state.suggestion = nil
            state.selectedProject = nil
            state.selectedFlow = nil
            state.selectedComponents = []
            state.acceptedSnapshot = nil
            state.wroteMapping = false
            state.windowInfo = windowInfo
        }

        Task {
            let request = CaptureSuggestionRequest(entry: entry, image: image, windowInfo: windowInfo)
            let suggestion = await CaptureClassifier.suggestRenameAndProject(for: request)
            await MainActor.run {
                updateRowState(entry.id) { state in
                    state.isLoading = false
                    state.suggestion = suggestion
                    state.selectedProject = suggestion?.suggestedProject
                    state.selectedFlow = suggestion?.suggestedFlow
                    state.selectedComponents = suggestion?.suggestedComponents ?? []
                    state.windowInfo = windowInfo
                }
            }
        }
    }

    private func acceptSuggestion(for entry: CaptureEntry) {
        guard let state = sessionState.rowStates[entry.id],
              let suggestion = state.suggestion,
              let snapshot = CaptureLibraryOrganizer.snapshot(for: entry) else {
            return
        }

        let effectiveSuggestion = RenameSuggestion(
            suggestedName: suggestion.suggestedName,
            suggestedProject: state.effectiveProject,
            suggestedFlow: state.effectiveFlow,
            suggestedComponents: state.effectiveComponents,
            confidence: suggestion.confidence
        )

        _ = CaptureLibraryOrganizer.apply(
            suggestion: effectiveSuggestion,
            to: entry,
            windowInfo: state.windowInfo
        )

        updateRowState(entry.id) { row in
            row.acceptedSnapshot = snapshot
            row.wroteMapping = effectiveSuggestion.hasProject && row.windowInfo != nil
            row.suggestion = nil
            row.selectedProject = nil
            row.selectedFlow = nil
            row.selectedComponents = []
            row.isLoading = false
        }
    }

    private func dismissSuggestion(for entry: CaptureEntry) {
        updateRowState(entry.id) { state in
            state.suggestion = nil
            state.selectedProject = nil
            state.selectedFlow = nil
            state.selectedComponents = []
            state.isLoading = false
        }
    }

    private func revertSuggestion(for entry: CaptureEntry) {
        guard let state = sessionState.rowStates[entry.id],
              let snapshot = state.acceptedSnapshot else {
            return
        }

        CaptureLibraryOrganizer.revert(snapshot: snapshot, captureID: entry.id)
        if state.wroteMapping, let signature = state.windowInfo {
            CaptureDestinationMappingCache.shared.remove(signature: signature)
        }
        sessionState.rowStates.removeValue(forKey: entry.id)
    }

    // MARK: - Batch organize

    private func presentOrganizeSheet() {
        showOrganizeSheet = true
        reloadOrganizePlan()
    }

    private func reloadOrganizePlan() {
        organizeTask?.cancel()
        organizeLoading = true
        let targets = CaptureLibraryOrganizer.targetEntries(
            from: entries,
            includeOrganized: includeOrganizedCaptures
        )

        organizeTask = Task {
            let plan = await CaptureLibraryOrganizer.buildPlan(for: targets)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                organizePlan = plan
                organizeLoading = false
            }
        }
    }

    private func confirmOrganize() {
        guard let result = CaptureLibraryOrganizer.execute(plan: organizePlan) else { return }
        showOrganizeSheet = false

        let message = "Moved \(result.movedCount) files into \(result.projectCount) projects"
        ToastWindow.show(
            message: message,
            associatedCaptureID: nil,
            actionTitle: "Undo",
            hostWindow: CaptureLibraryWindow.current,
            onAction: {
                CaptureLibraryOrganizer.revert(batch: result)
            }
        )
    }
}

/// AppKit-backed rename field so the current name is visible immediately and
/// the field becomes first responder without an extra click.
private struct InlineRenameTextField: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit, onCancel: onCancel)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = RenameNSTextField(string: text)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.snipsnap(.caption)
        field.textColor = DesignTokens.Color.textPrimary.ns
        field.placeholderString = "Name"
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit(_:))
        field.onEscape = { [weak coordinator = context.coordinator] in
            coordinator?.cancel()
        }

        DispatchQueue.main.async {
            guard let window = field.window else { return }
            window.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onCancel = onCancel
        if nsView.stringValue != text, nsView.currentEditor() == nil {
            nsView.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void
        var onCancel: () -> Void
        private var didFinish = false

        init(text: Binding<String>, onSubmit: @escaping () -> Void, onCancel: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
            self.onCancel = onCancel
        }

        @objc func submit(_ sender: NSTextField) {
            finish(commit: true)
        }

        func cancel() {
            finish(commit: false)
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            finish(commit: true)
        }

        private func finish(commit: Bool) {
            guard !didFinish else { return }
            didFinish = true
            if commit {
                onSubmit()
            } else {
                onCancel()
            }
        }
    }
}

private final class RenameNSTextField: NSTextField {
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}

private struct CaptureSidebarRow: View {
    let entry: CaptureEntry
    let rowState: CaptureRowSuggestionState
    let isRenaming: Bool
    @Binding var renameDraft: String
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void
    let onRevertSuggestion: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            filenameLabel
                .frame(maxWidth: .infinity, alignment: .leading)

            trailingMeta
                .layoutPriority(1)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var filenameLabel: some View {
        if isRenaming {
            InlineRenameTextField(
                text: $renameDraft,
                onSubmit: onCommitRename,
                onCancel: onCancelRename
            )
            .font(.snipsnap(.caption))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .stroke(DesignTokens.Color.primary.swiftUI, lineWidth: 1.5)
                    )
            )
        } else {
            Text(entry.displayName)
                .font(.snipsnap(.caption))
                .foregroundStyle(DesignTokens.Color.textPrimary.swiftUI)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private var trailingMeta: some View {
        if rowState.acceptedSnapshot != nil {
            HStack(spacing: 4) {
                Text("Organized")
                    .font(.snipsnap(.caption))
                    .foregroundStyle(DesignTokens.Color.textSecondary.swiftUI)
                Button(action: onRevertSuggestion) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DesignTokens.Color.textSecondary.swiftUI)
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help("Revert rename and move")
            }
        } else {
            Text(entry.createdAt.compactRelativeLabel)
                .font(.snipsnap(.caption))
                .foregroundStyle(DesignTokens.Color.textSecondary.swiftUI)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

private enum CaptureLibraryProject {
    static func currentName(for entry: CaptureEntry) -> String? {
        guard !CaptureHistory.shared.isAtRootCapture(id: entry.id),
              let parent = CaptureHistory.shared.parentDirectoryURL(for: entry.id) else {
            return nil
        }
        return parent.lastPathComponent
    }
}

/// Dropdown chip for editing a suggested project/flow before confirming Auto-Tag.
private struct SuggestionTagMenu: View {
    let kind: CaptureTagKind
    let selected: String
    let options: [String]
    var emphasized: Bool = false
    var onRemove: (() -> Void)? = nil
    let onSelect: (String) -> Void
    let onCreateNew: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            if kind == .project {
                Image(systemName: "folder.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DesignTokens.Color.textTertiary.swiftUI)
            }

            Text(kind.displayName)
                .foregroundStyle(DesignTokens.Color.textTertiary.swiftUI)

            Menu {
                ForEach(options, id: \.self) { name in
                    Button(name) {
                        onSelect(name)
                    }
                }

                if !options.isEmpty {
                    Divider()
                }

                Button("Custom…") {
                    onCreateNew()
                }
            } label: {
                HStack(spacing: 3) {
                    Text(selected)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(DesignTokens.Color.primary.swiftUI.opacity(emphasized ? 0.85 : 0.7))
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .pointerStyle(.link)
            .fixedSize()

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(DesignTokens.Color.textTertiary.swiftUI)
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help(kind == .project ? "Don’t move to a project folder" : "Remove \(kind.displayName.lowercased())")
            }
        }
        .font(.snipsnap(.caption))
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, emphasized ? 5 : 3)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(DesignTokens.Color.listSelectionFill.swiftUI)
                .overlay {
                    if emphasized {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .strokeBorder(DesignTokens.Color.primary.swiftUI.opacity(0.3), lineWidth: 1)
                    }
                }
        )
        .help(
            kind == .project
                ? "Project folder — Confirm moves the file here"
                : "Change \(kind.displayName.lowercased())"
        )
    }
}

/// Editable/removable UI-component chip shown during Auto-Tag review.
private struct SuggestionComponentChip: View {
    let name: String
    let options: [String]
    var emphasized: Bool = true
    let onSelect: (String) -> Void
    let onEditCustom: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(CaptureTagKind.component.displayName)
                .foregroundStyle(DesignTokens.Color.textTertiary.swiftUI)

            Menu {
                ForEach(options, id: \.self) { option in
                    Button(option) {
                        onSelect(option)
                    }
                }

                if !options.isEmpty {
                    Divider()
                }

                Button("Custom…") {
                    onEditCustom()
                }
            } label: {
                HStack(spacing: 3) {
                    Text(name)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(DesignTokens.Color.primary.swiftUI.opacity(emphasized ? 0.85 : 0.7))
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .pointerStyle(.link)
            .fixedSize()

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DesignTokens.Color.textTertiary.swiftUI)
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help("Remove component")
        }
        .font(.snipsnap(.caption))
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, emphasized ? 5 : 3)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(DesignTokens.Color.listSelectionFill.swiftUI)
                .overlay {
                    if emphasized {
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                            .strokeBorder(DesignTokens.Color.primary.swiftUI.opacity(0.3), lineWidth: 1)
                    }
                }
        )
        .help("Change UI component")
    }
}

/// Compact “+ Component” control for Auto-Tag review.
private struct SuggestionAddComponentButton: View {
    let onAdd: () -> Void

    var body: some View {
        Button(action: onAdd) {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                Text("Component")
            }
            .font(.snipsnap(.caption))
            .foregroundStyle(DesignTokens.Color.primary.swiftUI.opacity(0.75))
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .strokeBorder(DesignTokens.Color.primary.swiftUI.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help("Add UI component tag")
    }
}

private struct CaptureMultiSelectPane: View {
    let entries: [CaptureEntry]
    let rowStates: [UUID: CaptureRowSuggestionState]
    let onAutoTag: () -> Void
    let onAcceptSuggestion: (CaptureEntry) -> Void
    let onDismissSuggestion: (CaptureEntry) -> Void
    let onRevertSuggestion: (CaptureEntry) -> Void
    let onSelectProject: (String, UUID) -> Void
    let onCreateProject: (UUID) -> Void
    let onSelectFlow: (String, UUID) -> Void
    let onCreateFlow: (UUID) -> Void
    let onSelectComponent: (String, Int, UUID) -> Void
    let onRemoveComponent: (Int, UUID) -> Void
    let onCreateComponent: (UUID) -> Void
    let onEditComponent: (Int, UUID) -> Void
    let onClearProject: (UUID) -> Void

    private var isAnyLoading: Bool {
        entries.contains { rowStates[$0.id]?.isLoading == true }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(entries) { entry in
                        multiSelectRow(for: entry)
                        if entry.id != entries.last?.id {
                            Divider()
                                .padding(.leading, 64)
                        }
                    }
                }
                .padding(.vertical, DesignTokens.Spacing.sm)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignTokens.Color.background.swiftUI)

            Divider()

            HStack {
                Button {
                    onAutoTag()
                } label: {
                    Label("Auto-Tag", systemImage: "sparkles")
                }
                .buttonStyle(.snipsnap)
                .disabled(entries.isEmpty || isAnyLoading)

                Spacer()

                Text("\(entries.count) selected")
                    .font(.snipsnap(.caption))
                    .foregroundStyle(DesignTokens.Color.textSecondary.swiftUI)
            }
            .padding(DesignTokens.Spacing.lg)
        }
    }

    @ViewBuilder
    private func multiSelectRow(for entry: CaptureEntry) -> some View {
        let rowState = rowStates[entry.id] ?? CaptureRowSuggestionState()

        HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
            Image(nsImage: entry.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 56, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text(displayName(for: entry, rowState: rowState))
                    .font(.snipsnap(.bodyEmphasized))
                    .foregroundStyle(DesignTokens.Color.textPrimary.swiftUI)
                    .lineLimit(1)

                projectAndTags(for: entry, rowState: rowState)

                Text(entry.createdAt.compactRelativeLabel)
                    .font(.snipsnap(.caption))
                    .foregroundStyle(DesignTokens.Color.textTertiary.swiftUI)
            }

            Spacer(minLength: 0)

            trailingActions(for: entry, rowState: rowState)
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
        .contentShape(Rectangle())
    }

    private func displayName(for entry: CaptureEntry, rowState: CaptureRowSuggestionState) -> String {
        if let suggestion = rowState.suggestion,
           suggestion.hasRename,
           let name = suggestion.suggestedName {
            return name
        }
        return entry.displayName
    }

    @ViewBuilder
    private func projectAndTags(for entry: CaptureEntry, rowState: CaptureRowSuggestionState) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                metaChip(
                    label: "Project",
                    value: CaptureLibraryProject.currentName(for: entry) ?? "None"
                )

                if rowState.showsProjectPicker, let project = rowState.effectiveProject {
                    SuggestionTagMenu(
                        kind: .project,
                        selected: project,
                        options: projectOptions(for: rowState),
                        emphasized: false,
                        onRemove: { onClearProject(entry.id) },
                        onSelect: { onSelectProject($0, entry.id) },
                        onCreateNew: { onCreateProject(entry.id) }
                    )
                } else if let project = rowState.effectiveProject {
                    metaChip(label: "Tag", value: project)
                } else if rowState.acceptedSnapshot != nil {
                    metaChip(label: "Tag", value: "Organized")
                }

                if rowState.showsFlowPicker, let flow = rowState.effectiveFlow {
                    SuggestionTagMenu(
                        kind: .flow,
                        selected: flow,
                        options: flowOptions(for: rowState),
                        emphasized: false,
                        onSelect: { onSelectFlow($0, entry.id) },
                        onCreateNew: { onCreateFlow(entry.id) }
                    )
                }
            }

            if rowState.suggestion != nil {
                FlowLayoutCentered(spacing: DesignTokens.Spacing.sm, centered: false) {
                    ForEach(Array(rowState.effectiveComponents.enumerated()), id: \.offset) { index, component in
                        SuggestionComponentChip(
                            name: component,
                            options: componentOptions(for: rowState, excluding: component),
                            emphasized: false,
                            onSelect: { onSelectComponent($0, index, entry.id) },
                            onEditCustom: { onEditComponent(index, entry.id) },
                            onRemove: { onRemoveComponent(index, entry.id) }
                        )
                    }
                    SuggestionAddComponentButton {
                        onCreateComponent(entry.id)
                    }
                }
            }
        }
    }

    private func metaChip(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(DesignTokens.Color.textTertiary.swiftUI)
            Text(value)
                .foregroundStyle(DesignTokens.Color.textSecondary.swiftUI)
        }
        .font(.snipsnap(.caption))
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                .fill(DesignTokens.Color.listSelectionFill.swiftUI)
        )
    }

    private func projectOptions(for rowState: CaptureRowSuggestionState) -> [String] {
        var names = Set(CaptureLibraryOrganizer.existingProjectNames())
        if let effective = rowState.effectiveProject {
            names.insert(effective)
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func flowOptions(for rowState: CaptureRowSuggestionState) -> [String] {
        var names = Set(CaptureLibraryOrganizer.existingTagNames(kind: .flow))
        if let effective = rowState.effectiveFlow {
            names.insert(effective)
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func componentOptions(for rowState: CaptureRowSuggestionState, excluding: String) -> [String] {
        var names = Set(CaptureLibraryOrganizer.existingTagNames(kind: .component))
        names.formUnion(CaptureUIComponentVocabulary.common)
        names.formUnion(rowState.effectiveComponents)
        names = names.filter { $0.caseInsensitiveCompare(excluding) != .orderedSame }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    @ViewBuilder
    private func trailingActions(for entry: CaptureEntry, rowState: CaptureRowSuggestionState) -> some View {
        if rowState.isLoading {
            ProgressView()
                .controlSize(.small)
                .frame(width: 18, height: 18)
        } else if rowState.suggestion != nil {
            HStack(spacing: 6) {
                Button {
                    onAcceptSuggestion(entry)
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .foregroundStyle(DesignTokens.Color.primary.swiftUI.opacity(0.55))
                .help("Accept suggestion")

                Button {
                    onDismissSuggestion(entry)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .foregroundStyle(DesignTokens.Color.primary.swiftUI.opacity(0.55))
                .help("Dismiss suggestion")
            }
        } else if rowState.acceptedSnapshot != nil {
            Button {
                onRevertSuggestion(entry)
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.Color.textSecondary.swiftUI)
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help("Revert rename and move")
        }
    }
}

private struct CapturePreviewPane: View {
    let entry: CaptureEntry
    @ObservedObject var sessionState: CaptureLibrarySessionState
    let onOpen: (CaptureEntry) -> Void
    let onAutoTag: () -> Void
    let onAcceptSuggestion: () -> Void
    let onDismissSuggestion: () -> Void
    let onSelectProject: (String) -> Void
    let onCreateProject: () -> Void
    let onSelectFlow: (String) -> Void
    let onCreateFlow: () -> Void
    let onSelectComponent: (String, Int) -> Void
    let onRemoveComponent: (Int) -> Void
    let onCreateComponent: () -> Void
    let onEditComponent: (Int) -> Void
    let onClearProject: () -> Void
    let onRemoveTag: (CaptureTag) -> Void
    let onAddTag: (CaptureTagKind, String) -> Void

    @State private var fullScreenshot: NSImage?
    @State private var loadTask: Task<Void, Never>?

    private var rowState: CaptureRowSuggestionState {
        sessionState.rowStates[entry.id] ?? CaptureRowSuggestionState()
    }

    private var showsAutoTagOverlay: Bool {
        rowState.isLoading || rowState.suggestion != nil
    }

    private var projectOptions: [String] {
        var names = Set(CaptureLibraryOrganizer.existingProjectNames())
        if let effective = rowState.effectiveProject {
            names.insert(effective)
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var flowOptions: [String] {
        var names = Set(CaptureLibraryOrganizer.existingTagNames(kind: .flow))
        if let effective = rowState.effectiveFlow {
            names.insert(effective)
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func componentOptions(excluding: String) -> [String] {
        var names = Set(CaptureLibraryOrganizer.existingTagNames(kind: .component))
        names.formUnion(CaptureUIComponentVocabulary.common)
        names.formUnion(rowState.effectiveComponents)
        names = names.filter { $0.caseInsensitiveCompare(excluding) != .orderedSame }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        ZStack {
            DesignTokens.Color.background.swiftUI

            VStack(spacing: 0) {
                VStack(spacing: DesignTokens.Spacing.md) {
                    previewContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if !showsAutoTagOverlay {
                        Button {
                            onAutoTag()
                        } label: {
                            Label("Auto-Tag", systemImage: "sparkles")
                        }
                        .buttonStyle(.snipsnap)
                    }

                    CaptureTagBar(
                        tags: displayTags,
                        onRemoveTag: onRemoveTag,
                        onAddTag: onAddTag
                    )
                    .frame(maxWidth: 420)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, DesignTokens.Spacing.xl)
                .padding(.top, DesignTokens.Spacing.lg)
                .padding(.bottom, DesignTokens.Spacing.md)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.displayName)
                            .font(.snipsnap(.bodyEmphasized))
                        Text(entry.createdAt.compactRelativeLabel)
                            .font(.snipsnap(.caption))
                            .foregroundStyle(DesignTokens.Color.textSecondary.swiftUI)
                    }

                    Spacer()

                    Button("Annotate") {
                        onOpen(entry)
                    }
                    .buttonStyle(.snipsnapProminent)
                    .keyboardShortcut(.return, modifiers: [])
                }
                .padding(DesignTokens.Spacing.lg)
                .fixedSize(horizontal: false, vertical: true)
            }

            if showsAutoTagOverlay {
                autoTagOverlay
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showsAutoTagOverlay)
        .animation(.easeInOut(duration: 0.2), value: rowState.isLoading)
        .onAppear {
            loadPreviewIfNeeded()
        }
        .onChange(of: entry.id) { _, _ in
            loadPreviewIfNeeded()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    @ViewBuilder
    private var autoTagOverlay: some View {
        ZStack {
            Color.white.opacity(0.92)

            if rowState.isLoading {
                ProgressView()
                    .controlSize(.large)
            } else if let suggestion = rowState.suggestion {
                VStack(spacing: DesignTokens.Spacing.md) {
                    if suggestion.hasRename, let name = suggestion.suggestedName {
                        VStack(spacing: DesignTokens.Spacing.xs) {
                            Text("Rename")
                                .font(.snipsnap(.caption))
                                .foregroundStyle(DesignTokens.Color.textTertiary.swiftUI)
                            Text(name)
                                .font(.snipsnap(.bodyEmphasized))
                                .foregroundStyle(DesignTokens.Color.textPrimary.swiftUI)
                                .multilineTextAlignment(.center)
                        }
                    }

                    if suggestion.hasTags
                        || rowState.showsProjectPicker
                        || rowState.showsFlowPicker
                        || rowState.showsComponents
                        || suggestion.hasRename {
                        FlowLayoutCentered(spacing: DesignTokens.Spacing.sm) {
                            if rowState.showsProjectPicker, let project = rowState.effectiveProject {
                                SuggestionTagMenu(
                                    kind: .project,
                                    selected: project,
                                    options: projectOptions,
                                    emphasized: true,
                                    onRemove: onClearProject,
                                    onSelect: onSelectProject,
                                    onCreateNew: onCreateProject
                                )
                            }
                            if rowState.showsFlowPicker, let flow = rowState.effectiveFlow {
                                SuggestionTagMenu(
                                    kind: .flow,
                                    selected: flow,
                                    options: flowOptions,
                                    emphasized: true,
                                    onSelect: onSelectFlow,
                                    onCreateNew: onCreateFlow
                                )
                            }
                            ForEach(Array(rowState.effectiveComponents.enumerated()), id: \.offset) { index, component in
                                SuggestionComponentChip(
                                    name: component,
                                    options: componentOptions(excluding: component),
                                    emphasized: true,
                                    onSelect: { onSelectComponent($0, index) },
                                    onEditCustom: { onEditComponent(index) },
                                    onRemove: { onRemoveComponent(index) }
                                )
                            }
                            if rowState.suggestion != nil {
                                SuggestionAddComponentButton(onAdd: onCreateComponent)
                            }
                        }
                        .frame(maxWidth: 360)
                    } else if !suggestion.hasRename {
                        Text("No tags suggested")
                            .font(.snipsnap(.caption))
                            .foregroundStyle(DesignTokens.Color.textSecondary.swiftUI)
                    }

                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Button {
                            onAcceptSuggestion()
                        } label: {
                            Label("Confirm", systemImage: "checkmark")
                        }
                        .buttonStyle(.snipsnapProminent)

                        Button {
                            onDismissSuggestion()
                        } label: {
                            Label("Reject", systemImage: "xmark")
                        }
                        .buttonStyle(.snipsnap)
                    }
                }
                .padding(DesignTokens.Spacing.xl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Prefer persisted tags; always surface the folder-derived project when one is missing.
    private var displayTags: [CaptureTag] {
        var tags = entry.tags
        if !tags.contains(where: { $0.kind == .project }),
           let project = CaptureLibraryProject.currentName(for: entry) {
            // Stable synthetic id so ForEach identity doesn't churn.
            tags.insert(CaptureTag(id: entry.id, kind: .project, name: project), at: 0)
        }
        return CaptureTag.sorted(tags)
    }

    @ViewBuilder
    private var previewContent: some View {
        switch entry.item {
        case .screenshot:
            if let fullScreenshot {
                Image(nsImage: fullScreenshot)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ZStack {
                    Image(nsImage: entry.thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .blur(radius: 2)
                        .opacity(0.55)
                    ProgressView()
                        .controlSize(.regular)
                }
            }

        case .recording(let url, _):
            VideoPreviewRepresentable(url: url)
                .aspectRatio(entry.thumbnail.size.width / max(entry.thumbnail.size.height, 1), contentMode: .fit)
        }
    }

    private func loadPreviewIfNeeded() {
        loadTask?.cancel()
        fullScreenshot = nil

        guard case .screenshot = entry.item else { return }

        let id = entry.id
        loadTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            fullScreenshot = CaptureHistory.shared.fullImage(for: id)
        }
    }
}

/// Centered wrapping layout for suggested tag chips in the overlay.
private struct FlowLayoutCentered: Layout {
    var spacing: CGFloat = 8
    var centered: Bool = true

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        let xOffset = centered ? max(0, (bounds.width - result.size.width) / 2) : 0
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + xOffset + frame.minX, y: bounds.minY + frame.minY),
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

private struct VideoPreviewRepresentable: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = LibraryPreviewPlayerView()
        // Avoid AVKit Tahoe bug: inline glass volume controls have unsatisfiable width constraints.
        view.controlsStyle = .floating
        view.videoGravity = .resizeAspect
        context.coordinator.bind(url: url, to: view)
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        context.coordinator.bind(url: url, to: nsView)
        (nsView as? LibraryPreviewPlayerView)?.applyWindowBackgroundLetterbox()
    }

    final class Coordinator {
        private var currentURL: URL?

        func bind(url: URL, to view: AVPlayerView) {
            guard currentURL != url else { return }
            currentURL = url
            view.player = AVPlayer(url: url)
        }
    }
}

/// AVPlayerView letterboxes with an opaque black fill by default; match the library window instead.
private final class LibraryPreviewPlayerView: AVPlayerView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        videoGravity = .resizeAspect
        applyWindowBackgroundLetterbox()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        applyWindowBackgroundLetterbox()
    }

    func applyWindowBackgroundLetterbox() {
        let fill = DesignTokens.Color.background.ns.cgColor
        layer?.backgroundColor = fill
        applyLetterboxFill(fill, to: layer)
    }

    private func applyLetterboxFill(_ fill: CGColor, to layer: CALayer?) {
        guard let layer else { return }
        if layer is AVPlayerLayer {
            layer.backgroundColor = fill
        }
        layer.sublayers?.forEach { applyLetterboxFill(fill, to: $0) }
    }
}
