import SwiftUI

/// The native home's presentation inputs. Credentials and execution stay in the Agent clients.
struct HermesHome {
    let logoText: String
    let colorHex: String
    let servers: AvatarServerSwitcherModel
    let openSettings: () -> Void
    let switchToServer: (ServerAccount) -> Void
    let addServer: () -> Void
    let manageServers: () -> Void
    let pendingBotDestination: Binding<BotDestination?>
    let connectionChanged: () -> Void
}

/// One selected native surface; replacing it is deliberate, showing the sidebar is not.
enum HermesHomeDestination: Hashable {
    case chat(HermesSessionChat)
    case bots
    case tasks(HermesTasksEntry)
    case skills(HermesSkillsEntry)
    case memory(HermesMemoryEntry)
    case insights(HermesInsightsEntry)
    case kanban
    case archived(String)

    var chat: HermesSessionChat? {
        if case .chat(let chat) = self { return chat }
        return nil
    }
}

/// Value state scoped to one server's home. Sidebar gestures never change the selected chat.
struct HermesHomeNavigation {
    var destination: HermesHomeDestination?
    private(set) var activeTarget: ConversationTarget?
    private(set) var lineageRootID: String?
    var isSidebarPresented = true
    var isCompact = true

    init(destination: HermesHomeDestination? = nil, isSidebarPresented: Bool = true, isCompact: Bool = true) {
        self.destination = destination
        activeTarget = destination?.chat?.target
        lineageRootID = nil
        self.isSidebarPresented = isSidebarPresented
        self.isCompact = isCompact
    }

    mutating func select(_ destination: HermesHomeDestination) {
        self.destination = destination
        activeTarget = destination.chat?.target
        lineageRootID = nil
        if isCompact { isSidebarPresented = false }
    }

    /// Selecting the already-visible saved session must not replace its stream or composer.
    mutating func openChat(_ chat: HermesSessionChat, lineageRootID: String? = nil) {
        if let current = destination?.chat, case .session = chat.target,
           current.server == chat.server, current.connection.id == chat.connection.id,
           (activeTarget ?? current.target).profile == chat.target.profile,
           (activeTarget ?? current.target) == chat.target ||
               (lineageRootID != nil && self.lineageRootID == lineageRootID) {
            if self.lineageRootID == nil { self.lineageRootID = lineageRootID }
            if isCompact { isSidebarPresented = false }
            return
        }
        select(.chat(chat))
        self.lineageRootID = lineageRootID
    }

    /// Metadata from the current chat does not replace its view or accept a departed chat's callback.
    mutating func identify(_ target: ConversationTarget?, chatID: UUID) {
        guard destination?.chat?.id == chatID, case .session(_, let key)? = target else { return }
        activeTarget = target
        if lineageRootID == nil { lineageRootID = key }
    }

    mutating func remove(_ session: SessionSummary, server: URL, connectionID: UUID, listedIn profile: String) {
        guard let chat = destination?.chat, chat.server == server, chat.connection.id == connectionID,
              case .session(let activeProfile, let activeKey) = activeTarget ?? chat.target,
              case .session(let removedProfile, let removedKey)? = session.hermesTarget(listedIn: profile),
              activeProfile == removedProfile,
              activeKey == removedKey || lineageRootID == session.id else { return }
        showSessions()
    }

    mutating func showSessions() {
        destination = nil
        activeTarget = nil
        lineageRootID = nil
        isSidebarPresented = true
    }
}

/// ARC's native home keeps both columns mounted. Only selecting another surface resets detail navigation.
struct HermesHomeShell<Sidebar: View, Detail: View>: View {
    @Binding var navigation: HermesHomeNavigation
    @ViewBuilder let sidebar: Sidebar
    @ViewBuilder let detail: Detail

    var body: some View {
        ChatNavigationShell(isPresented: $navigation.isSidebarPresented, isCompact: $navigation.isCompact) {
            sidebar
        } detail: {
            NavigationStack {
                detail
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                navigation.isSidebarPresented.toggle()
                            } label: {
                                Label(navigation.isSidebarPresented ? "Hide Sessions" : "Show Sessions", systemImage: "sidebar.leading")
                            }
                            .accessibilityIdentifier("detail-sidebar-toggle")
                            .keyboardShortcut("s", modifiers: [.command, .control])
                        }
                    }
            }
            .id(navigation.destination)
        }
    }
}
