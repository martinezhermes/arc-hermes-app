import SwiftUI

/// Bounded recent history on a native gateway. Only this Sessions entry uses the
/// REST preview. The interactive chat still requires its own WebSocket contract.
struct HermesGatewayHistoryBrowser: View {
    let entry: HermesSessionListEntry
    let home: HermesHome
    @Binding var pendingLink: HermesSessionDestination?
    @State private var client: HermesGatewayHistory
    @State private var index: Result<HermesGatewayHistory.Index, Error>?
    @State private var path: [HermesGatewayHistory.Session] = []
    @State private var readID = UUID()
    @State private var retryID = 0
    @State private var showsLinkError = false

    init(entry: HermesSessionListEntry, home: HermesHome, pendingLink: Binding<HermesSessionDestination?>) {
        self.entry = entry
        self.home = home
        _pendingLink = pendingLink
        _client = State(initialValue: HermesGatewayHistory(connection: entry.connection, server: entry.server))
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("Read-only") {
                    switch index {
                    case .success(let page):
                        if page.sessions.isEmpty { Text("No sessions yet").foregroundStyle(.secondary) }
                        ForEach(page.sessions) { session in
                            NavigationLink(value: session) { Text(title(for: session)) }
                        }
                    case .failure(let error):
                        failureRow(error, address: entry.connection.address) { retryID += 1 }
                    case nil:
                        ProgressView("Loading sessions")
                    }
                }
            }
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: home.openSettings) { Label("Settings", systemImage: "gearshape") }
                        .contextMenu {
                            AvatarServerSwitcherMenu(model: home.servers, switchToServer: home.switchToServer,
                                                     addServer: home.addServer, manageServers: home.manageServers)
                        }
                }
            }
            .navigationDestination(for: HermesGatewayHistory.Session.self) { session in
                HermesGatewayTranscriptView(session: session, server: entry.server, address: entry.connection.address, client: client)
                    .id(session)
            }
            .refreshable { await load() }
        }
        .task(id: retryID) { await load() }
        .onDisappear { readID = UUID() }
        .onChange(of: pendingLink) { openLink() }
        .alert("Message Action Failed", isPresented: $showsLinkError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Open it from Sessions.")
        }
    }

    private func load() async {
        let id = UUID()
        readID = id
        do {
            let page = try await client.recentSessions()
            guard readID == id, !Task.isCancelled else { return }
            index = .success(page)
            openLink()
        } catch {
            guard readID == id, !Task.isCancelled else { return }
            index = .failure(error)
        }
    }

    private func openLink() {
        guard let link = pendingLink, link.server == entry.server, case .success(let page) = index else { return }
        pendingLink = nil
        guard !link.opensParent, link.movedFrom == nil, link.profile == nil || link.profile == page.profile else {
            showsLinkError = true
            return
        }
        path = [page.sessions.first { $0.id == link.key }
            ?? HermesGatewayHistory.Session(id: link.key, profile: page.profile, title: nil)]
    }

    private func title(for session: HermesGatewayHistory.Session) -> String {
        session.title ?? String(localized: "Untitled Session")
    }
}

private struct HermesGatewayTranscriptView: View {
    let session: HermesGatewayHistory.Session
    let address: URL
    let client: HermesGatewayHistory
    @State private var playback: ChatViewModel
    @State private var result: Result<Displayed, Error>?
    @State private var readID = UUID()
    @State private var retryID = 0

    private struct Displayed {
        let id: UUID
        let transcript: HermesGatewayHistory.Transcript
        let messages: [ChatMessage]
    }

    init(session: HermesGatewayHistory.Session, server: URL, address: URL, client: HermesGatewayHistory) {
        self.session = session
        self.address = address
        self.client = client
        _playback = State(initialValue: ChatViewModel(session: SessionSummary(profile: session.profile), server: server))
    }

    var body: some View {
        VStack(spacing: 0) {
            if playback.showsListenPlaybackBar { ListenPlaybackBar(model: playback) }
            List {
                Section {
                    switch result {
                    case .success(let page):
                        if page.messages.isEmpty { Text("No messages to display.").foregroundStyle(.secondary) }
                        ForEach(Array(page.messages.enumerated()), id: \.element.id) { offset, message in
                            messageRow(message, index: offset, page: page)
                        }
                    case .failure(let error):
                        failureRow(error, address: address) { retryID += 1 }
                    case nil:
                        ProgressView("Loading messages")
                    }
                } header: {
                    HStack {
                        Text("Recent")
                        Spacer()
                        Text("Read-only")
                    }
                }
            }
            .listStyle(.plain)
            .refreshable { await load() }
        }
        .navigationTitle((try? result?.get())?.transcript.title ?? session.title ?? String(localized: "Untitled Session"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: retryID) { await load() }
        .onDisappear {
            readID = UUID()
            playback.stopListening()
        }
        .alert("Message Action Failed", isPresented: Binding(
            get: { playback.messageActionErrorMessage != nil },
            set: { if !$0 { playback.clearMessageActionError() } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(playback.messageActionErrorMessage ?? "")
        }
    }

    private func messageRow(_ message: ChatMessage, index: Int, page: Displayed) -> some View {
        let context = MessageActionContext(message: message, visibleIndex: index, messagesOffset: 0,
                                           offersHistoryActions: false, offersFork: false,
                                           hermesStoredSessionID: page.transcript.localConversationID)
        let menu = context.map { context in
            ChatMessageActionMenu(context: context, listeningMessageID: playback.listeningMessageID,
                                  isViewingCachedData: false, hasActiveStream: false,
                                  isRegeneratingMessage: false, isEditingMessage: false, isForkingMessage: false,
                                  onToggleListening: { context, voice in listen(to: context, voice: voice, page: page) },
                                  onRegenerate: { _ in }, onEdit: { _ in }, onFork: { _ in },
                                  onCopy: { UIPasteboard.general.string = $0.copyText })
        }
        return MessageBubbleView(message: message, transcriptMediaCacheNamespace: "", textOnly: true)
            .chatMessageContextMenu(menu?.items ?? [])
    }

    private func listen(to context: MessageActionContext, voice: ListenVoice, page: Displayed) {
        guard readID == page.id else { return }
        let request = page.transcript.listenRequest {
            guard readID == page.id, !Task.isCancelled else { throw BotFailure.stale }
        }
        playback.toggleListening(to: context, voice: voice, historySpeech: request)
    }

    private func load() async {
        let id = UUID()
        readID = id
        playback.stopListening()
        playback.clearMessageActionError()
        do {
            let transcript = try await client.transcript(for: session)
            guard readID == id, !Task.isCancelled else { return }
            let messages = HermesTranscriptProjection.project(transcript.rows, root: transcript.resolvedID).messages
                .map(HermesChatTurnCoordinator.displayed)
            result = .success(Displayed(id: id, transcript: transcript, messages: messages))
        } catch {
            guard readID == id, !Task.isCancelled else { return }
            result = .failure(error)
        }
    }
}

private func failureRow(_ error: Error, address: URL, retry: @escaping () -> Void) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(BotConnectionAdvice.message(for: error, address: address))
            .foregroundStyle(.secondary)
        Button("Retry", action: retry)
    }
}
