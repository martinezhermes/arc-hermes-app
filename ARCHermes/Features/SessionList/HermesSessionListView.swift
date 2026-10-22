import SwiftUI

/// A Hermes server's Sessions list (#1046): the server, its saved connection, and the Profile the
/// list opens on, searching `query` when a chat's `/resume` opened it (#1053). The home's list
/// (#709) opens on no Profile, which takes the server's pick or the host's `current`.
struct HermesSessionListEntry: Hashable, Identifiable {
    let id = UUID()
    let server: URL
    let connection: BotConnection
    let profile: String?
    var query = ""

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Native Agent sessions with shared paging, mutations and offline cache. At home the list is
/// ARC's sidebar beside the selected chat or tool. /sessions can still push a standalone list.
/// The list socket pauses when its sidebar is hidden; the selected chat owns its own stream.
struct HermesSessionListView: View {

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @AppStorage(SessionRowDisplaySettings.showMessageCountKey) private var showsMessageCount = true
    @AppStorage(SessionRowDisplaySettings.showWorkspaceKey) private var showsWorkspace = true
    @AppStorage(SessionSidebarDisclosureSettings.scheduledSessionsAreExpandedKey)
    private var scheduledSessionsAreExpanded = SessionSidebarDisclosureSettings.defaultScheduledSessionsAreExpanded
    @AppStorage(AppHaptics.isEnabledKey) private var isHapticsEnabled = true
    @AppStorage(SessionSidebarDisclosureSettings.projectsAreExpandedKey)
    private var projectsAreExpanded = SessionSidebarDisclosureSettings.defaultProjectsAreExpanded
    @AppStorage(SectionVisibilitySettings.tasksKey) private var showsTasks = true
    @AppStorage(SectionVisibilitySettings.kanbanKey) private var showsKanban = true
    @AppStorage(SectionVisibilitySettings.skillsKey) private var showsSkills = true
    @AppStorage(SectionVisibilitySettings.memoryKey) private var showsMemory = true
    @AppStorage(SectionVisibilitySettings.insightsKey) private var showsInsights = true
    private let entry: HermesSessionListEntry
    private let home: HermesHome?
    /// The session a link named, held by `ContentView` until this list looks it up.
    @Binding private var pendingLink: HermesSessionDestination?
    /// The new session a Shortcut asked for, held by `ContentView` until this list can open it.
    @Binding private var pendingNewChat: HermesNewChatDestination?
    /// The share `ContentView` reserved, and how this list tells it the share is moving, let go
    /// (opened, or discarded after it failed), kept queued or cut short.
    private let pendingShare: SharedImportReservation?
    private let claimShare: (SharedImportReservation) -> Bool
    private let didRouteShare: (SharedImportReservation) -> Void
    private let didDeclineShare: (SharedImportReservation) -> Void
    private let didAbandonShare: (SharedImportReservation) -> Void
    /// Moving `pendingShare` into its new session's draft; leaving cancels it.
    @State private var shareTransfer: Task<Void, Never>?
    /// A share whose move failed, still claimed, until the user discards it or the alert closes (#1196).
    @State private var failedShare: HermesShareFailure?
    @State private var viewModel: SessionListViewModel
    @State private var covers = HermesSessionListCovers()
    private var navigation: HermesHomeNavigation {
        get { covers.navigation }
        nonmutating set { covers.navigation = newValue }
    }
    @State private var actionToast = ActionToastState()
    /// The project lane the list shows; nil shows every session.
    @State private var selectedProjectID: String?
    @State private var searchText: String
    /// Search expands the sidebar's glass field without replacing the list.
    @State private var isSearchExpanded = false
    @State private var isShowingProfileFilter = false
    @FocusState private var isSearchFieldFocused: Bool
    /// The list a chat's `/sessions` pushed.
    init(entry: HermesSessionListEntry) {
        self.init(entry: entry, model: Self.model(for: entry), home: nil)
    }

    /// The Sessions side of the Hermes home, on a `model` the home keeps across its switch, so a
    /// switch back shows the last rows at once (#709), and opening the session `pendingLink` names,
    /// the new session `pendingNewChat` asks for and `pendingShare`.
    init(entry: HermesSessionListEntry, model: SessionListViewModel, home: HermesHome?,
         pendingLink: Binding<HermesSessionDestination?> = .constant(nil),
         pendingNewChat: Binding<HermesNewChatDestination?> = .constant(nil),
         pendingShare: SharedImportReservation? = nil,
         claimShare: @escaping (SharedImportReservation) -> Bool = { _ in false },
         didRouteShare: @escaping (SharedImportReservation) -> Void = { _ in },
         didDeclineShare: @escaping (SharedImportReservation) -> Void = { _ in },
         didAbandonShare: @escaping (SharedImportReservation) -> Void = { _ in }) {
        _searchText = State(initialValue: entry.query)
        self.entry = entry
        self.home = home
        _pendingLink = pendingLink
        _pendingNewChat = pendingNewChat
        self.pendingShare = pendingShare
        self.claimShare = claimShare
        self.didRouteShare = didRouteShare
        self.didDeclineShare = didDeclineShare
        self.didAbandonShare = didAbandonShare
        _viewModel = State(initialValue: model)
    }

    /// The list's view model, reading `entry`'s server through its saved connection.
    static func model(for entry: HermesSessionListEntry) -> SessionListViewModel {
        let server = entry.server
        return SessionListViewModel(server: server, hermes: HermesSessionListSource(
            connection: entry.connection, profile: entry.profile, makeWire: { BotClient(saved: $0, server: server) }
        ))
    }

    private var list: some View {
        let groups = viewModel.scheduledSessionGroups(searchText: searchText, selectedProjectID: selectedProjectID)
        return List {
            if home != nil { MoveToHermesBanner(serverID: entry.server.absoluteString) }
            if viewModel.showsOfflineCache {
                OfflineCacheBanner()
                    .padding(.top, 16)
                    .sessionsScreenListRow()
            }
            SessionSidebarUtilityRows(
                viewModel: viewModel, topPadding: 10, automatedVisibility: .showAll, sectionVisibility: sectionVisibility,
                profilesAreExpanded: .constant(false), projectsAreExpanded: $projectsAreExpanded,
                selectedProjectID: $selectedProjectID, projectPendingDeletion: $covers.deletingProject,
                projectPendingRename: $covers.renamingProject, openDestination: open, switchActiveProfile: { _ in },
                presentProjectCreation: { covers.creatingProject = HermesProjectCreation(folder: "") }
            )
            if groups.showsDisclosure(isSearchActive: isSearching) {
                ScheduledSessionsDisclosure(
                    viewModel: viewModel, searchText: searchText, sessions: groups.scheduled,
                    totalCount: groups.totalScheduledCount, isSearchActive: isSearching,
                    showsMessageCount: showsMessageCount, showsWorkspace: showsWorkspace,
                    selectedSessionID: selectedSessionID,
                    userIsExpanded: $scheduledSessionsAreExpanded, actions: actions,
                    viewAll: {
                        covers.showingScheduled = true
                    }
                )
            }
            SessionListRowsSection(
                viewModel: viewModel,
                searchText: searchText,
                sessions: groups.ordinary,
                emptyTitle: emptyTitle,
                emptyDescription: isSearching ? String(localized: "Try another search or project filter.") : nil,
                isSearchActive: false,
                showsMessageCount: showsMessageCount,
                showsWorkspace: showsWorkspace,
                selectedSessionID: selectedSessionID,
                actions: actions,
                suppressEmptyState: !groups.scheduled.isEmpty
            )
            // A search reads the host's whole list, so it pages nothing in.
            if showsLoadMore && !isSearching { loadMoreRow }
            // The cache holds no archived rows to show, and the Archived screen lists one Profile.
            if !viewModel.isViewingCachedData && !viewModel.hermesShowsAllProfiles { archivedRow }
        }
        .listStyle(.plain)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .environment(\.defaultMinListRowHeight, 0)
        .modifier(chrome)
    }

    var body: some View {
        surface
        .animation(SessionListMotion.disclosureAnimation(reduceMotion: reduceMotion), value: projectsAreExpanded)
        .animation(SessionListMotion.disclosureAnimation(reduceMotion: reduceMotion), value: scheduledSessionsAreExpanded)
        .overlay(alignment: .bottom) {
            ActionToastView(state: actionToast)
                .frame(maxWidth: 420)
                .padding(.horizontal, 24)
                .padding(.bottom, 22)
        }
        .refreshable { await viewModel.refreshHermes(modelContext: modelContext) }
        // Debounced inside; a new query or Profile cancels the search in flight.
        .task(id: SearchScope(profile: profile, showsAll: viewModel.hermesShowsAllProfiles, text: searchText, showingScheduled: covers.showingScheduled)) {
            guard !covers.showingScheduled else { return }
            await viewModel.searchSessions(query: searchText)
        }
        .onChange(of: SearchScope(profile: profile, showsAll: viewModel.hermesShowsAllProfiles, text: searchText, showingScheduled: false)) {
            if covers.showingScheduled { navigation.showSessions() }
        }
        .sheet(item: $covers.renaming, onDismiss: { viewModel.clearRenameError() }) { session in
            SessionRenameSheet(initialTitle: SessionRowView.displayTitle(for: session), isSaving: viewModel.isRenamingSession,
                               errorMessage: viewModel.renameErrorMessage) {
                covers.renaming = nil
            } onSave: { title in
                Task { if await rename(session, to: title) { covers.renaming = nil } }
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $covers.exported) { item in
            SessionExportShareSheet(fileURL: item.fileURL)
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
                // Each export has its own temp directory (`SessionListViewModel.export`).
                .onDisappear { try? FileManager.default.removeItem(at: item.fileURL.deletingLastPathComponent()) }
        }
        .sheet(item: $covers.creatingProject, onDismiss: {
            viewModel.clearProjectSheetError()
            covers.moving = covers.movingAfterCreation
            covers.movingAfterCreation = nil
        }) { creation in
            ProjectCreationSheet(
                existingProjectCount: viewModel.projects.count, isSaving: viewModel.isCreatingProject,
                folder: ProjectFolderField(initialPath: creation.folder) { await viewModel.completeHermesFolder($0) },
                errorMessage: viewModel.projectSheetErrorMessage
            ) {
                covers.creatingProject = nil
            } onSave: { name, color, folder in
                Task {
                    guard let saved = await viewModel.createHermesProject(named: name, color: color, folder: folder ?? "") else { return }
                    covers.movingAfterCreation = creation.move(intoProjectNamed: name, savedOn: saved, isBusy: creation.session
                        .map { viewModel.attentionState(for: $0) != nil } ?? false)
                    covers.creatingProject = nil
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $covers.renamingProject, onDismiss: { viewModel.clearProjectSheetError() }) { project in
            ProjectRenameSheet(project: project, isSaving: viewModel.isRenamingProject,
                               errorMessage: viewModel.projectSheetErrorMessage) {
                covers.renamingProject = nil
            } onSave: { name, color in
                Task { if await viewModel.rename(project, named: name, color: color) { covers.renamingProject = nil } }
            }
            .presentationDetents([.medium])
        }
        .alert(Text(verbatim: covers.moving?.title ?? ""), isPresented: Binding(get: { covers.moving != nil }, set: { if !$0 { covers.moving = nil } }),
               presenting: covers.moving) { move in
            Button("Cancel", role: .cancel) {}
            Button("Move") { Task { await self.move(move) } }
        } message: { move in
            Text(verbatim: move.message)
        }
        // Discard is the only action: kept, the same files would fail the same way. The share stays
        // claimed meanwhile; the alert closing any other way (a Cancel iOS adds, Escape, leaving)
        // queues it again instead.
        .alert("Couldn’t Add Shared Files",
               isPresented: Binding(get: { failedShare != nil }, set: { if !$0 { queueFailedShareAgain() } }),
               presenting: failedShare) { failure in
            Button("Discard Share", role: .destructive) {
                failedShare = nil
                didRouteShare(failure.share)
            }
        } message: { failure in
            Text(verbatim: failure.reason + "\n\n"
                 + String(localized: "Nothing was added. Discard deletes this saved share from ARC Hermes."))
        }
        .modifier(SessionActionConfirmations(
            viewModel: viewModel, sessionPendingDeletion: $covers.deleting, projectPendingDeletion: $covers.deletingProject,
            deleteSession: { session in Task { await delete(session) } },
            deleteProject: { project in Task { _ = await viewModel.delete(project) } }
        ))
        .task { await viewModel.openHermes(modelContext: modelContext) }
        // A link arriving while a chat, screen or sheet covers the rows pops and closes them, so
        // what it opens or says shows here.
        .onChange(of: pendingLink, initial: true) { acceptPendingLink(pendingLink) }
        .task(id: pendingLink) { await openPendingLink() }
        // A Shortcut's new session and a share bring the rows forward at once, and open once the
        // list has read the host live, whichever Profile the request names. A share reserved while
        // another moves into its draft opens once that move ends.
        .onChange(of: NewChatReadiness(request: pendingNewChat, share: pendingShare?.reservationID, profile: profile,
                                       isLive: viewModel.isHermesLive, isTransferringShare: shareTransfer != nil),
                  initial: true) {
            openPendingNewChat()
            openPendingShare()
        }
        .onDisappear {
            shareTransfer?.cancel()
            shareTransfer = nil
            queueFailedShareAgain()
            actionToast.dismiss()
            if home == nil { covers.listDisappeared(viewModel) }
            else { viewModel.closeHermes() }
        }
        // A lane the host no longer lists (deleted here or on Desktop, or another Profile's) clears.
        .onChange(of: viewModel.projects) {
            if let selectedProjectID, !viewModel.projects.contains(where: { $0.projectId == selectedProjectID }) {
                self.selectedProjectID = nil
            }
        }
        .onChange(of: navigation.destination) { old, new in
            if let newChat = new?.chat, newChat.id != old?.chat?.id { SessionOpenSignpost.begin(sessionID: newChat.id.uuidString) }
            if case .session(_, let key)? = old?.chat?.target, new?.chat?.id != old?.chat?.id {
                viewModel.noteHermesReturn(from: key)
            }
        }
        .onChange(of: navigation.isSidebarPresented) {
            guard home != nil else { return }
            if navigation.isSidebarPresented { Task { await viewModel.openHermes(modelContext: modelContext) } }
            else {
                isShowingProfileFilter = false
                if !covers.showingScheduled { viewModel.pauseHermes() }
            }
        }
        .onChange(of: home?.pendingBotDestination.wrappedValue, initial: true) {
            guard let destination = home?.pendingBotDestination.wrappedValue,
                  destination.server == entry.server, destination.connectionID == entry.connection.id else { return }
            navigation.select(.bots)
        }
        .onChange(of: viewModel.sessions.count, initial: true) { LaunchSignpost.end(rows: viewModel.sessions.count) }
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .background: viewModel.closeHermes()
            // Control Center and banners (`.inactive`) keep the socket; only a closed list reopens.
            case .active where (home != nil ? navigation.isSidebarPresented : navigation.destination == nil) && !viewModel.isHermesConnected:
                Task { await viewModel.openHermes(modelContext: modelContext) }
            default: break
            }
        }
    }

    private var selectedSessionID: String? { covers.selectedSessionID }

    @ViewBuilder private var surface: some View {
        if let home {
            HermesHomeShell(navigation: $covers.navigation) {
                sidebar(home)
            } detail: {
                if let destination = navigation.destination {
                    detail(destination)
                } else {
                    ContentUnavailableView {
                        Label("Sessions", systemImage: "bubble.left.and.bubble.right")
                    } actions: { newSessionButton }
                }
            }
        } else {
            list.modifier(chrome)
                .navigationDestination(item: $covers.navigation.destination) { detail($0) }
        }
    }

    private func sidebar(_ home: HermesHome) -> some View {
        list
            .safeAreaBar(edge: .top, spacing: 0) {
                SessionListTopChrome(
                    headerLogoColor: HeaderLogoColor.color(for: home.colorHex), headerLogoText: home.logoText,
                    searchText: $searchText, searchChromeIsExpanded: $isSearchExpanded,
                    searchFieldIsFocused: $isSearchFieldFocused,
                    showsSearchClearButton: SessionListSearchChrome.showsClearButton(isExpanded: isSearchExpanded, query: searchText),
                    reduceMotion: reduceMotion, onOpenSearch: openSearch, onCloseSearch: closeSearch,
                    onSearchFocusChange: { _ in }
                )
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 12) {
                    newSessionButton
                        .buttonStyle(SessionsChromeCircleButtonStyle())
                    Spacer(minLength: 0)
                    profileFilter
                    Button(action: home.openSettings) {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(SessionsChromeCircleButtonStyle())
                    .accessibilityLabel("Settings")
                    .accessibilityHint("Opens Settings. Long press to switch servers.")
                    .contextMenu {
                        AvatarServerSwitcherMenu(model: home.servers, switchToServer: home.switchToServer,
                                                 addServer: home.addServer, manageServers: home.manageServers)
                    }
                }
                .tint(HeaderLogoColor.color(for: home.colorHex))
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
            }
    }

    @ViewBuilder private func detail(_ destination: HermesHomeDestination) -> some View {
        switch destination {
        case .chat(let chat):
            ChatView(hermesSession: covers.building(chat), onReplace: { navigation.select(.chat($0)) }, onOpenSessions: { opened in
                navigation.showSessions()
                if let listed = opened.profile, listed != profile || viewModel.hermesShowsAllProfiles {
                    Task { await viewModel.selectHermesProfile(listed) }
                }
                searchText = opened.query
                if !opened.query.isEmpty && home != nil { isSearchExpanded = true }
            }, onIdentified: { navigation.identify($0, chatID: chat.id) }, onChatReplaced: {
                guard navigation.destination?.chat?.id == chat.id else { return }
                navigation.showSessions()
            }, onDraftKeyChange: { covers.identifyChat(chat.id, draftKey: $0) })
            .id(chat.id)
        case .scheduled:
            scheduledSessions
        case .bots:
            BotsInboxView(server: entry.server, pendingDestination: home?.pendingBotDestination ?? .constant(nil),
                          onConnectionChanged: home?.connectionChanged ?? {})
        case .archived(let profile):
            ArchivedSessionsView(server: entry.server, hermes: .saved(entry.connection, server: entry.server, profile: profile))
        case .tasks(let entry):
            TasksView(server: entry.server, onAPIError: { _ in }, client: entry.client, newTaskProfile: entry.newTaskProfile)
                .id(entry.id)
        case .skills(let entry):
            SkillsView(client: entry.client, profile: entry.client.profile, onAPIError: { _ in }).id(entry.id)
        case .memory(let entry):
            MemoryView(server: entry.server, client: entry.client, profile: entry.client.profile, onAPIError: { _ in }).id(entry.id)
        case .insights(let entry):
            InsightsView(client: entry.client, profile: entry.client.profile, onAPIError: { _ in }).id(entry.id)
        case .kanban:
            KanbanView(server: entry.server, hermes: HermesConnections.shared.connection(for: entry.connection, server: entry.server))
        }
    }

    /// View all of the Profile's scheduled sessions, pushed on a phone and the detail beside the rows.
    private var scheduledSessions: some View {
        ScheduledSessionsView(viewModel: viewModel, showsCronSessions: true,
                              showsMessageCount: showsMessageCount, showsWorkspace: showsWorkspace,
                              selectedSessionID: nil, actions: actions, actionToast: actionToast)
            .onDisappear { covers.scheduledDisappeared(viewModel) }
    }

    /// The listed Profile, and the one New Session opens in; nil until a home list without a
    /// pick has asked the host.
    private var profile: String? { viewModel.hermesProfile ?? entry.profile }

    /// The home's Tasks, Kanban, Skills, Memory and Usage rows, as Settings shows them (#709), and
    /// the project lanes of the one listed Profile. A search drops the links but keeps the lanes,
    /// so the lane it searches in stays in view and can change.
    private var sectionVisibility: SidebarSectionVisibility {
        let isHome = home != nil && !isSearchExpanded
        return SidebarSectionVisibility(
            bots: isHome, tasks: isHome && showsTasks, kanban: isHome && showsKanban, skills: isHome && showsSkills,
            memory: isHome && showsMemory, insights: isHome && showsInsights, activeProfile: false,
            projects: !viewModel.hermesShowsAllProfiles
        )
    }

    /// Pushes a home row's screen: Tasks, Skills, Memory and Usage on the listed Profile (the one
    /// New Session opens in, on a list of every Profile), Kanban for the whole host.
    private func open(_ destination: SessionListUtilityDestination) {
        let server = entry.server, connection = entry.connection
        if destination == .kanban { navigation.select(.kanban); return }
        if destination == .bots { navigation.select(.bots); return }
        guard let profile else { return }
        switch destination {
        case .tasks:
            navigation.select(.tasks(HermesTasksEntry(server: server, client: HermesCronClient(saved: connection, server: server), newTaskProfile: profile)))
        case .skills:
            navigation.select(.skills(HermesSkillsEntry(client: HermesSkillsClient(saved: connection, server: server, profile: profile))))
        case .memory:
            navigation.select(.memory(HermesMemoryEntry(server: server, client: HermesMemoryClient(saved: connection, server: server, profile: profile))))
        case .insights:
            navigation.select(.insights(HermesInsightsEntry(client: HermesInsightsClient(saved: connection, server: server, profile: profile))))
        default:
            break
        }
    }

    /// The home's chrome, or the pushed list's own title and toolbar.
    private var chrome: some ViewModifier {
        HermesSessionListChrome(searchText: $searchText, profileMenu: { profileMenu }, newSession: { newSessionButton })
    }

    private func openSearch() {
        withAnimation(SessionListMotion.searchChromeAnimation(reduceMotion: reduceMotion)) { isSearchExpanded = true }
        isSearchFieldFocused = true
    }

    private func closeSearch() {
        searchText = ""
        isSearchFieldFocused = false
        withAnimation(SessionListMotion.searchChromeAnimation(reduceMotion: reduceMotion)) { isSearchExpanded = false }
    }

    private var newSessionButton: some View {
        Button("New Session", systemImage: "square.and.pencil") {
            guard let profile else { return }
            navigation.select(.chat(HermesSessionChat(server: entry.server, connection: entry.connection, target: .new(profile: profile))))
        }
        .disabled(viewModel.isViewingCachedData || profile == nil)
    }

    private var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var emptyTitle: String {
        if isSearching { return String(localized: "No matching sessions") }
        return selectedProjectID == nil ? String(localized: "No sessions yet") : String(localized: "No sessions in this project")
    }

    /// The pushed list's Profile menu, named for what it lists.
    private var profileMenu: some View {
        Menu {
            profileFilterActions
        } label: {
            // A Profile name is the user's own text, never a catalog key.
            if viewModel.hermesShowsAllProfiles {
                Text("All Profiles").lineLimit(1)
            } else {
                Text(verbatim: profile ?? "").lineLimit(1)
                    .accessibilityLabel(Text("Profile: \(profile ?? "")"))
            }
        }
    }

    /// A normal button opens the native popover explicitly, independent of nested menu/Picker behavior.
    private var profileFilter: some View {
        Button { isShowingProfileFilter = true } label: {
            Image(systemName: "line.3.horizontal.decrease")
        }
        .buttonStyle(SessionsChromeCircleButtonStyle())
        .accessibilityLabel("Filter")
        .accessibilityValue(viewModel.hermesShowsAllProfiles ? Text("All Profiles") : Text(verbatim: profile ?? ""))
        .accessibilityIdentifier("native-profile-filter")
        .disabled(listedProfiles.isEmpty)
        .popover(isPresented: $isShowingProfileFilter) {
            VStack(alignment: .leading, spacing: 8) {
                profileFilterActions
            }
            .buttonStyle(.plain)
            .font(.subheadline)
            .padding(16)
            .frame(minWidth: 220, alignment: .leading)
            .presentationCompactAdaptation(.popover)
        }
    }

    private var listedProfiles: [String] {
        viewModel.hermesProfiles.isEmpty ? [profile].compactMap(\.self) : viewModel.hermesProfiles
    }

    /// Selecting a Profile changes only this server's list and keeps New Session's host pick.
    @ViewBuilder private var profileFilterActions: some View {
        Button {
            isShowingProfileFilter = false
            Task { await viewModel.showAllHermesProfiles() }
        } label: {
            Group {
                if viewModel.hermesShowsAllProfiles { Label("All Profiles", systemImage: "checkmark") }
                else { Text("All Profiles") }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .disabled(profile == nil)
        ForEach(listedProfiles, id: \.self) { name in
            Button {
                isShowingProfileFilter = false
                Task { await viewModel.selectHermesProfile(name) }
            } label: {
                Group {
                    if !viewModel.hermesShowsAllProfiles && profile == name {
                        Label { Text(verbatim: name) } icon: { Image(systemName: "checkmark") }
                    } else { Text(verbatim: name) }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
    }

    /// More pages may hold rows this list shows: any, or the selected lane's that the host
    /// named and the loaded pages lack.
    private var showsLoadMore: Bool {
        guard viewModel.hasMoreSessions else { return false }
        return selectedProjectID.map(viewModel.hermesLaneIsShort) ?? true
    }

    /// The list's end: the next page loads as it comes into view, or in a lane every page
    /// until the lane is whole, and a tap tries again after a failed one. Keyed by the lane,
    /// so picking another lane loads its pages too. A lane picked while another page was
    /// loading starts its own once that page's rows are in; a failed page changes no rows, so
    /// it never retries on its own.
    private var loadMoreRow: some View {
        Button("Load more") { Task { await loadMore() } }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .disabled(viewModel.isLoadingMoreSessions)
            .frame(maxWidth: .infinity, minHeight: 44)
            .sessionsScreenListRow()
            .onAppear { Task { await loadMore() } }
            .onChange(of: viewModel.sessions.count) {
                guard let selectedProjectID else { return }
                Task { await viewModel.fillHermesLane(selectedProjectID) }
            }
            .id(selectedProjectID)
    }

    private func loadMore() async {
        if let selectedProjectID { await viewModel.fillHermesLane(selectedProjectID) }
        else { await viewModel.loadMoreHermesSessions() }
    }

    /// The Profile's archived sessions, hidden Bot Chats included, where they are restored.
    private var archivedRow: some View {
        Button {
            if let profile { navigation.select(.archived(profile)) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "archivebox")
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text("Archived Sessions")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
        .accessibilityHint("Shows archived sessions.")
        .sessionsScreenListRow()
    }

    /// Opening a row, Mark as Read or Unread, and the row actions `SessionRowActionPolicy`
    /// offers a Hermes row; Duplicate opens the copy (#1051). Move to Project asks first,
    /// and its New Project starts on the session's folder, then asks to move it there if it
    /// was saved on another. A bot's Bot Chat, which only a search lists, opens in that bot
    /// through the app's bot route, as a notification's tap does (#1053).
    private var actions: SessionListRowActions {
        SessionListRowActions(
            retryLoad: { Task { await viewModel.openHermes(modelContext: modelContext) } },
            open: { session in
                if let bot = session.hermesBot(on: entry.server, connectionID: entry.connection.id) {
                    AppIntentRouter.shared.requestDeepLink(ARCHermesDeepLink.botURL(for: bot))
                    return
                }
                // A row of every Profile's cache, before the host settled one, opens in its own.
                guard let listed = profile ?? session.profile,
                      let opened = session.hermesChat(on: entry.server, connection: entry.connection, listedIn: listed) else { return }
                viewModel.beginViewing(session)
                navigation.openChat(opened, lineageRootID: session.id)
            },
            toggleUnread: { viewModel.toggleUnread($0) },
            togglePinned: { session in Task { await togglePinned(session) } },
            archive: { session in Task { await archive(session) } },
            delete: { covers.deleting = $0 },
            rename: { session in
                viewModel.clearRenameError()
                covers.renaming = session
            },
            duplicate: { session in Task { await duplicate(session) } },
            move: { session, projectID in
                guard let project = viewModel.projects.first(where: { $0.projectId == projectID }),
                      let folder = project.hermes?.folder else { return }
                covers.moving = HermesProjectMove(session: session, projectName: project.name ?? folder, folder: folder,
                                           isBusy: viewModel.attentionState(for: session) != nil)
            },
            createProject: { session in covers.creatingProject = HermesProjectCreation(folder: session.workspace ?? "", session: session) },
            refreshProjects: { Task { await viewModel.openHermes(modelContext: modelContext) } },
            export: { session, format in
                let generation = covers.generation
                Task {
                    if let url = await viewModel.export(session, format: format) {
                        covers.present(SessionExportShareItem(fileURL: url), startedAt: generation)
                    }
                }
            }
        )
    }

    /// Clears navigation and covering presentations only for a link addressed to this server.
    private func acceptPendingLink(_ link: HermesSessionDestination?) {
        guard link?.server == entry.server else { return }
        covers.accept(link, on: entry.server)
        isShowingProfileFilter = false
    }

    /// Resolves the held link like a row selection. A refused sign-in holds it for recovery;
    /// cancellation never presents results after the owning list or server leaves.
    private func openPendingLink() async {
        guard let link = pendingLink, link.server == entry.server else { return }
        let wire = BotClient(saved: entry.connection, server: entry.server)
        defer { wire.close() }
        let outcome: HermesSessionLookup.Outcome
        do {
            try await wire.connect()
            outcome = try await HermesSessionLookup.resolve(link, on: wire)
        } catch {
            if !Task.isCancelled, error as? BotFailure != .rejected(401), pendingLink == link { pendingLink = nil }
            return
        }
        guard !Task.isCancelled, pendingLink == link else { return }
        // Anything opened during the lookup closes too.
        acceptPendingLink(link)
        pendingLink = nil
        switch outcome {
        case .found(let session):
            if let bot = session.hermesBot(on: entry.server, connectionID: entry.connection.id) {
                AppIntentRouter.shared.requestDeepLink(ARCHermesDeepLink.botURL(for: bot))
            } else if let profile = session.profile,
                      let opened = session.hermesChat(on: entry.server, connection: entry.connection, listedIn: profile) {
                viewModel.beginViewing(session)
                navigation.openChat(opened, lineageRootID: session.id)
            }
        case .gone:
            if let fallback = MovedWebuiRoute.fallback(for: link) {
                AppIntentRouter.shared.requestDeepLink(fallback)
                return
            }
            let server = entry.server.host ?? entry.server.absoluteString
            showLinkNotice(String(localized: "That chat is no longer on \(server)."))
        case .ambiguous:
            showLinkNotice(String(localized: "That chat is in more than one Profile. Open it from Sessions."))
        case .room:
            break
        }
    }

    /// Opens the new session a Shortcut asked for (#1180) over whatever covers the rows.
    private func openPendingNewChat() {
        if covers.open(pendingNewChat, on: entry, listed: profile, isLive: viewModel.isHermesLive) { pendingNewChat = nil }
    }

    /// Opens a share (#1181) as a new session over whatever covers the rows (#1212), once `transfer`
    /// has moved it into that session's draft and let it go. The share is claimed for the move, so no
    /// home, here or on another server, starts a second one. A transfer that fails stays claimed
    /// and says why, offering Discard (#1196); closing the alert otherwise, or leaving, keeps it
    /// queued. One cut short by leaving hands it back for the next try.
    private func openPendingShare() {
        guard shareTransfer == nil, let share = pendingShare,
              let opening = covers.open(share, on: entry, listed: profile, isLive: viewModel.isHermesLive) else {
            return
        }
        guard case .chat(let chat) = opening else { return didRouteShare(share) }
        guard claimShare(share) else { return }
        shareTransfer = Task {
            do {
                try await share.transfer(into: chat, route: didRouteShare)
                if !Task.isCancelled {
                    covers.bringForward()
                    covers.chat = chat
                }
            } catch is CancellationError {
                didAbandonShare(share)
            } catch {
                if Task.isCancelled {
                    didDeclineShare(share)
                } else {
                    covers.bringForward()
                    failedShare = HermesShareFailure(share: share, error: error)
                }
            }
            if !Task.isCancelled { shareTransfer = nil }
        }
    }

    /// Hands back a failed share the user didn't discard, so it is offered again next time.
    /// Discard clears `failedShare` first, so the alert's dismissal after it does nothing.
    private func queueFailedShareAgain() {
        guard let failedShare else { return }
        self.failedShare = nil
        didDeclineShare(failedShare.share)
    }

    private func showLinkNotice(_ message: String) {
        actionToast.show(ActionToast(message: message, systemImage: "exclamationmark.triangle", accessibilityLabel: message))
    }

    private var mutationAnimation: Animation? { SessionListMotion.sessionMutationAnimation(reduceMotion: reduceMotion) }

    private func togglePinned(_ session: SessionSummary) async {
        if await viewModel.setPinned(session.pinned != true, for: session, animation: mutationAnimation) {
            SessionHaptics.pinStateChanged(isEnabled: isHapticsEnabled)
        }
    }

    /// "Archived · Undo" once the host confirms (#865); Undo restores the row in place.
    private func archive(_ session: SessionSummary) async {
        let listedProfile = session.profile ?? profile
        guard await viewModel.archive(session, animation: mutationAnimation) else { return }
        removeSelectedSession(session, listedIn: listedProfile)
        SessionHaptics.archiveStateChanged(isEnabled: isHapticsEnabled)
        let message = String(localized: "Archived")
        actionToast.show(ActionToast(
            message: message, systemImage: "archivebox",
            accessibilityLabel: String.localizedStringWithFormat(String(localized: "%@, %@"),
                                                                 SessionRowView.displayTitle(for: session), message),
            actionTitle: String(localized: "Undo"),
            action: {
                Task {
                    if await viewModel.unarchive(session, animation: mutationAnimation) {
                        SessionHaptics.archiveStateChanged(isEnabled: isHapticsEnabled)
                    }
                }
            }
        ))
    }

    /// "Moved · Undo" once the host confirms; Undo moves the session back to the folder it left.
    private func move(_ move: HermesProjectMove) async {
        guard let previous = await viewModel.moveHermesSession(move.session, toFolder: move.folder) else { return }
        let message = String(localized: "Moved")
        actionToast.show(ActionToast(
            message: message, systemImage: "folder",
            accessibilityLabel: String.localizedStringWithFormat(String(localized: "%@, %@"),
                                                                 SessionRowView.displayTitle(for: move.session), message),
            actionTitle: String(localized: "Undo"),
            action: { Task { _ = await viewModel.moveHermesSession(move.session, toFolder: previous) } }
        ))
    }

    /// Opens the copy once the host has it (#1051).
    private func duplicate(_ session: SessionSummary) async {
        guard let profile, let copy = await viewModel.duplicate(session),
              let opened = copy.hermesChat(on: entry.server, connection: entry.connection, listedIn: profile) else { return }
        navigation.openChat(opened, lineageRootID: copy.id)
    }

    private func delete(_ session: SessionSummary) async {
        let listedProfile = session.profile ?? profile
        if await viewModel.delete(session, animation: mutationAnimation) {
            removeSelectedSession(session, listedIn: listedProfile)
            SessionHaptics.sessionDeleted(isEnabled: isHapticsEnabled)
        }
    }

    private func removeSelectedSession(_ session: SessionSummary, listedIn profile: String?) {
        guard let profile else { return }
        navigation.remove(session, server: entry.server, connectionID: entry.connection.id, listedIn: profile)
    }

    private func rename(_ session: SessionSummary, to title: String) async -> Bool {
        let renamed = await viewModel.rename(session, to: title)
        if renamed, title != session.title { SessionHaptics.sessionRenamed(isEnabled: isHapticsEnabled) }
        return renamed
    }
}

/// How the Hermes home's Sessions list takes a share (#1181).
enum HermesShareOpening: Equatable {
    /// A new session in New Session's Profile, which opens once its draft holds the share.
    case chat(HermesSessionChat)
    /// Nothing in the share survived staging: it is consumed without a chat, as on webui.
    case nothing
}

extension SharedImportReservation {
    /// What `entry`'s Sessions list opens for this share, in `listed`, the Profile its New Session
    /// uses; nil until the list `isLive`, having read the host and showing no offline cache, as a
    /// Shortcut's new session does.
    @MainActor func hermesOpening(on entry: HermesSessionListEntry, listed: String?, isLive: Bool) -> HermesShareOpening? {
        guard let chat = HermesNewChatDestination(server: entry.server, profile: nil)
            .chat(on: entry, listed: listed, isLive: isLive) else { return nil }
        let isEmpty = ARCHermesShareDraft.composerDraft(from: sharedImport.draft).isEmpty && sharedImport.attachments.isEmpty
        return isEmpty ? .nothing : .chat(chat)
    }

    /// Moves the share into `chat`'s draft, then lets it go with `route` (`ContentView` consumes
    /// it), even when the caller was cancelled after the draft took it: the draft owns it from then
    /// on. A failure rethrows and leaves the share reserved, for the caller to discard or queue.
    @MainActor func transfer(into chat: HermesSessionChat, drafts: ChatDraftStore = .shared,
                             route: (Self) -> Void) async throws {
        try await moveIntoDraft(of: chat, drafts: drafts)
        route(self)
    }

    /// Moves the share into `chat`'s new-session draft, which the chat opens on: its text after
    /// any unsent text, its files after any staged ones, each as a Hermes send takes it
    /// (`BotAttachmentUpload.prepare`, Bot Chat's limits). A file Hermes can't take now (its type or
    /// size, an unreadable image, no room left in the draft) throws its reason and moves nothing, so the
    /// whole share stays recoverable. Once it returns the draft owns the share, under its occurrence
    /// id, so a retry or replay adds nothing while the same content shared again later is added;
    /// a throw leaves the draft as it was.
    @MainActor func moveIntoDraft(of chat: HermesSessionChat, drafts: ChatDraftStore = .shared) async throws {
        let key = chat.target.draftKey(server: chat.server, connectionID: chat.connection.id, lineageRoot: chat.lineageRoot)
        let draft = await drafts.draft(for: key)
        var files: [(data: Data, name: String, mime: String, image: Bool)] = []
        if draft?.sharedImportIDs.contains(occurrenceID) != true {
            let staged = draft?.attachments ?? []
            var room = HermexAttachmentPickerPolicy.maximumBotAttachments - staged.count
            var bytes = staged.reduce(0) { $0 + ($1.size ?? BotAttachmentUpload.maximumFileBytes) }
            for attachment in sharedImport.attachments {
                let prepared: (data: Data, name: String, mime: String, image: Bool)
                do {
                    prepared = try await Task.detached {
                        try BotAttachmentUpload.prepare(data: attachment.data, filename: attachment.filename)
                    }.value
                } catch {
                    throw error as? BotAttachmentFailure ?? .unreadable
                }
                guard room > 0, prepared.data.count <= BotAttachmentUpload.maximumFileBytes,
                      bytes + prepared.data.count <= BotAttachmentUpload.maximumTotalBytes else {
                    throw BotAttachmentFailure.limit
                }
                room -= 1
                bytes += prepared.data.count
                files.append(prepared)
            }
            try Task.checkCancellation()
        }
        try await drafts.appendShare(occurrenceID, text: ARCHermesShareDraft.composerDraft(from: sharedImport.draft), files: files,
                                     to: key, maximumFileBytes: BotAttachmentUpload.maximumFileBytes) { attachments in
            // A composer open on this draft may have added files since the check above.
            guard attachments.count <= HermexAttachmentPickerPolicy.maximumBotAttachments,
                  attachments.reduce(0, { $0 + ($1.size ?? BotAttachmentUpload.maximumFileBytes) })
                    <= BotAttachmentUpload.maximumTotalBytes else { throw BotAttachmentFailure.limit }
        }
    }
}

/// A share the Hermes home couldn't move into a new session's draft (#1196), and why, in words for
/// someone who shared from another app. Nothing in a queued share can be changed, so most failures
/// would repeat on every try; the user discards it and shares again.
struct HermesShareFailure {
    let share: SharedImportReservation
    let reason: String

    init(share: SharedImportReservation, error: Error) {
        self.share = share
        switch error {
        case BotAttachmentFailure.limit, ChatDraftStorageError.attachmentLimit:
            // Counts the files already waiting in the new session's draft too.
            reason = String(localized: "You can attach up to 8 files per message, 25 MB each and 50 MB total. Share fewer or smaller files and try again.")
        case BotAttachmentFailure.type:
            reason = String(localized: "One of these file types isn’t supported. Share supported files separately.")
        case BotAttachmentFailure.unreadable:
            reason = String(localized: "One of the files couldn’t be read.")
        default:
            reason = String(localized: "ARC Hermes couldn’t save the files on this iPhone.")
        }
    }
}

/// What a Shortcut's new session and a share wait on: the request or share, New Session's
/// Profile, the list's live read of the host, and the end of an earlier share's move.
private struct NewChatReadiness: Equatable {
    let request: HermesNewChatDestination?
    let share: String?
    let profile: String?
    let isLive: Bool
    let isTransferringShare: Bool
}

/// What a search runs against: a new query, Profile or All Profiles cancels the one in flight.
private struct SearchScope: Hashable {
    let profile: String?
    let showsAll: Bool
    let text: String
    let showingScheduled: Bool
}

/// A list opened by /sessions keeps ordinary pushed navigation; the home supplies its own shell.
private struct HermesSessionListChrome<ProfileMenu: View, NewSession: View>: ViewModifier {
    @Binding var searchText: String
    @ViewBuilder let profileMenu: ProfileMenu
    @ViewBuilder let newSession: NewSession

    func body(content: Content) -> some View {
        content
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search sessions")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { profileMenu }
                ToolbarItem(placement: .topBarTrailing) { newSession }
            }
    }
}

/// The ARC Sessions shell's navigation and presentation state: selected native surface and
/// its sheets and confirmations. A session link (#1176) for the list's server clears them all, so
/// its chat, or why it can't open, shows on the list itself; a closed chat keeps its draft in the
/// draft store.
struct HermesSessionListCovers {
    var navigation = HermesHomeNavigation()
    var renaming: SessionSummary?
    var deleting: SessionSummary?
    var exported: SessionExportShareItem?
    /// Shares and shortcuts select the same ARC chat destination as row taps.
    var chat: HermesSessionChat? {
        get { navigation.destination?.chat }
        set {
            if let newValue { navigation.openChat(newValue, lineageRootID: newValue.lineageRoot) }
            else if navigation.destination?.chat != nil { navigation.showSessions() }
        }
    }
    var showingScheduled: Bool {
        get { navigation.destination == .scheduled }
        set {
            if newValue { navigation.select(.scheduled) }
            else if showingScheduled { navigation.showSessions() }
        }
    }
    var creatingProject: HermesProjectCreation?
    var renamingProject: ProjectSummary?
    var deletingProject: ProjectSummary?
    var moving: HermesProjectMove?
    /// The Move to Project a project created from a row's Move menu still needs, asked once the
    /// sheet is gone.
    var movingAfterCreation: HermesProjectMove?
    /// The pushed list and scheduled view share one live reader; a covering chat pauses it.
    @MainActor func listDisappeared(_ list: SessionListViewModel) {
        if chat != nil { list.pauseHermes() }
        else if !showingScheduled { list.closeHermes() }
    }

    @MainActor func scheduledDisappeared(_ list: SessionListViewModel) {
        if chat != nil || showingScheduled { list.pauseHermes() }
    }

    /// Counts the links that brought the rows forward, so work started before one (an export)
    /// doesn't cover them again when it finishes.
    private(set) var generation = 0

    /// Brings the rows forward for `link` when it names `server`, the list's own.
    mutating func accept(_ link: HermesSessionDestination?, on server: URL) {
        guard link?.server == server else { return }
        bringForward()
    }

    /// Opens a Shortcut's new session for `entry`'s server (#1180) over everything on the rows,
    /// once `HermesNewChatDestination.chat(on:listed:isLive:)` can. The rows come forward first,
    /// so a chat that paused the list closes and the list, appearing again, reads the host the
    /// request waits on. True once it opened.
    @MainActor mutating func open(_ request: HermesNewChatDestination?, on entry: HermesSessionListEntry, listed: String?,
                                  isLive: Bool) -> Bool {
        guard let request, request.server == entry.server else { return false }
        bringForward()
        guard let chat = request.chat(on: entry, listed: listed, isLive: isLive) else { return false }
        self.chat = chat
        return true
    }

    /// Takes a share for `entry`'s list (#1181) as `open(_:on:listed:isLive:)` takes a Shortcut's
    /// new session: the rows come forward first, so a chat that kept the list closed across the trip
    /// to the sharing app closes, and the list, appearing again, reads the host the share waits on
    /// (#1212). The chat's draft stays in the draft store. What the share opens, once it can.
    @MainActor mutating func open(_ share: SharedImportReservation, on entry: HermesSessionListEntry, listed: String?,
                                  isLive: Bool) -> HermesShareOpening? {
        bringForward()
        return share.hermesOpening(on: entry, listed: listed, isLive: isLive)
    }

    /// The accepted first prompt gives a New Session its durable identity without replacing
    /// its live view. A late callback from a chat that has since closed cannot select it again.
    mutating func identifyChat(_ id: UUID, draftKey: ChatDraftKey) {
        guard let chat, chat.id == id, draftKey.serverID == chat.server.absoluteString,
              case .hermesSession(let connectionID, let profile, let key?) = draftKey.context,
              connectionID == chat.connection.id, profile == chat.target.profile else { return }
        navigation.identify(.session(profile: profile, key: key), chatID: id)
    }

    /// `chat` for a view that builds it now. A New Session the host has named reopens by its key,
    /// so a rebuild (a size-class change, a side switch) shows that session instead of starting
    /// another, and New Chat with Voice doesn't dictate again. A live chat's view keeps its model.
    func building(_ chat: HermesSessionChat) -> HermesSessionChat {
        guard chat.id == self.chat?.id, case .new(let profile, _, _) = chat.target,
              case .session(_, let key)? = navigation.activeTarget else { return chat }
        var named = chat
        named.target = .session(profile: profile, key: key)
        named.autoStartsVoiceInput = false
        return named
    }

    private var selectedSessionKey: String? {
        if case .session(_, let key)? = navigation.activeTarget ?? chat?.target { return key }
        return nil
    }

    var selectedSessionID: String? { navigation.lineageRootID ?? chat?.lineageRoot ?? selectedSessionKey }

    /// A confirmed row mutation can originate in search, outside the loaded pages.
    /// Only its own selected chat closes; a newer selection is left alone.
    mutating func closeChat(for row: SessionSummary) {
        guard let chat, let key = selectedSessionKey,
              row.profile == chat.target.profile,
              row.sessionId == key || row.hermes?.lineageRoot == (chat.lineageRoot ?? key) else { return }
        self.chat = nil
    }

    /// Closes everything over the rows, so what opens next shows on the list itself.
    mutating func bringForward() {
        let next = generation + 1
        var retainedNavigation = navigation
        retainedNavigation.showSessions()
        self = Self()
        navigation = retainedNavigation
        generation = next
    }

    /// Shows an export's share sheet unless a link brought the rows forward since it started at
    /// `generation`.
    mutating func present(_ export: SessionExportShareItem, startedAt generation: Int) {
        if generation == self.generation { exported = export }
    }
}

/// The Tasks screen a home row pushed on a Hermes host (#1040, #709), with the client it reads
/// through and the Profile a new Task starts in.
struct HermesTasksEntry: Hashable, Identifiable {
    let id = UUID()
    let server: URL
    let client: HermesCronClient
    let newTaskProfile: String

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// The Skills screen a home row pushed on a Hermes host (#1069, #709), with the client for the
/// Profile it lists.
struct HermesSkillsEntry: Hashable, Identifiable {
    let id = UUID()
    let client: HermesSkillsClient

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// The Memory screen a home row pushed on a Hermes host (#1073, #709), with the client it reads
/// the Profile's memory through.
struct HermesMemoryEntry: Hashable, Identifiable {
    let id = UUID()
    let server: URL
    let client: HermesMemoryClient

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// The Usage screen a home row pushed on a Hermes host (#1074, #709), with the client for the
/// Profile it reads.
struct HermesInsightsEntry: Hashable, Identifiable {
    let id = UUID()
    let client: HermesInsightsClient

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A project sheet opened for a new Hermes project (#1052), on `folder` (the session's own when
/// it came from a row's Move menu).
struct HermesProjectCreation: Identifiable {
    let id = UUID()
    let folder: String
    /// The session whose Move menu opened the sheet; nil from the list's New Project.
    var session: SessionSummary?

    /// The Move to Project that puts `session` in the project just saved on `folder`, which asks
    /// first as any other does. Nil from the list's New Project, or when the session works in
    /// `folder` itself, which makes it the project's. A session under `folder` is asked too: a
    /// project on a deeper folder may still claim it.
    func move(intoProjectNamed name: String, savedOn folder: String, isBusy: Bool) -> HermesProjectMove? {
        guard let session, session.workspace != folder else { return nil }
        return HermesProjectMove(session: session, projectName: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                 folder: folder, isBusy: isBusy)
    }
}

/// A Move to Project waiting on its confirmation (#1052), with copy that says what it does: Hermes
/// works in the project's folder from then on, and no file moves. A busy session moves mid-turn.
struct HermesProjectMove: Identifiable {
    let session: SessionSummary
    let projectName: String
    let folder: String
    /// A reply runs, or waits on an answer, in the session.
    let isBusy: Bool

    var id: String { session.id }
    var title: String { String(localized: "Move to \(projectName)?") }
    var message: String {
        isBusy
            ? String(localized: "Hermes will work in \(folder) from now on, including the reply that's running now. Files aren't moved.")
            : String(localized: "Hermes will work in \(folder) from now on. Files aren't moved.")
    }
}

extension SessionSummary {
    /// The Hermes session this row opens (#1046): its own `id`, which on a legacy compression
    /// chain is the tip, in the row's Profile, else the listed one. Nil for a webui row.
    func hermesTarget(listedIn profile: String) -> ConversationTarget? {
        guard hermes != nil, let key = sessionId, !key.isEmpty else { return nil }
        return .session(profile: self.profile.flatMap { $0.isEmpty ? nil : $0 } ?? profile, key: key)
    }

    /// The chat this Hermes row opens on `connection`, carrying the parent the row names, so a
    /// branch shows its "Forked from" row (#1051), and its lineage root, which the chat caches
    /// under. A Bot Chat row (Archived), or a legacy chain's "Bot Chat (continued)" tip, opens as
    /// the bot's chat, with its pill and rules (#1145), and carries its root, so it shows its bot's
    /// cached transcript offline (#1144). Nil for a webui row.
    func hermesChat(on server: URL, connection: BotConnection, listedIn profile: String) -> HermesSessionChat? {
        hermesTarget(listedIn: profile).map {
            HermesSessionChat(server: server, connection: connection, target: $0, parentKey: parentSessionId,
                              botChatRoot: hermes?.botChatRoot, lineageRoot: hermes?.lineageRoot)
        }
    }

    /// The bot whose Bot Chat this row is (#1053): the Sessions list opens it there, so one chat
    /// never has two screens and two read marks. Nil for any other row.
    func hermesBot(on server: URL, connectionID: UUID) -> BotDestination? {
        guard hermes?.isBotChat == true, let profile, !profile.isEmpty else { return nil }
        return BotDestination(server: server, connectionID: connectionID, profile: profile)
    }
}
