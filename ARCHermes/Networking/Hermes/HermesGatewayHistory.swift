import Foundation

/// The authenticated gateway's bounded REST history, available when its WebSocket
/// advertises session authority. Browsing uses the same deployment and serving Profile.
@MainActor struct HermesGatewayHistory {
    struct Session: Identifiable, Hashable {
        let id: String
        let profile: String
        let title: String?
    }

    struct Index {
        let profile: String
        let sessions: [Session]
    }

    struct Transcript {
        /// The physical transcript can advance to a continuation. ARC speaks for the
        /// canonical local conversation that owns it.
        let resolvedID: String
        let localConversationID: String?
        let title: String?
        let rows: [BotJSON]
        fileprivate let profile: String
        fileprivate let wire: BotClient

        @MainActor func listenRequest(validate: @escaping @MainActor () throws -> Void) -> HermesListenRequest {
            HermesListenRequest(wire: wire, profile: profile, sessionID: localConversationID, validate: validate)
        }
    }

    private let wire: BotClient

    init(connection: BotConnection, server: URL) {
        wire = BotClient(saved: connection, server: server)
    }

    init(http: HermesConnection) {
        wire = BotClient(http: http)
    }

    func recentSessions() async throws -> Index {
        let profiles = try await read(.profilesActive)
        guard let profile = profiles["current"].text, !profile.isEmpty else { throw BotFailure.unsupported }
        let body = try await data(.sessionList(profile: profile, offset: 0))
        let page = try JSONDecoder().decode(HermesSessionPage.self, from: body)
        var ids = Set<String>()
        var sessions: [Session] = []
        for row in page.rows.prefix(HermesREST.sessionPageSize) {
            guard row.profile == profile else { throw BotFailure.wrongIdentity }
            if ids.insert(row.id).inserted {
                sessions.append(Session(id: row.id, profile: profile, title: MessageAttachment.hermesTitle(row.title)))
            }
        }
        return Index(profile: profile, sessions: sessions)
    }

    func transcript(for session: Session) async throws -> Transcript {
        let selected = try await exactRow(session.id, profile: session.profile)
        let owner = Self.localConversationID(selected)
        let reply = try await read(.sessionMessages(key: session.id, profile: session.profile, offset: 0, inlineImages: false))
        guard reply["profile"].text == session.profile,
              let resolved = reply["session_id"].text, !resolved.isEmpty else { throw BotFailure.wrongIdentity }
        guard let rows = reply["messages"].list else { throw BotFailure.unsupported }
        if resolved != session.id {
            let continuation = try await exactRow(resolved, profile: session.profile)
            guard let owner, Self.localConversationID(continuation) == owner else { throw BotFailure.wrongIdentity }
        }
        return Transcript(resolvedID: resolved, localConversationID: owner,
                          title: MessageAttachment.hermesTitle(selected["title"].text),
                          rows: Array(rows.suffix(HermesREST.transcriptPageSize)), profile: session.profile, wire: wire)
    }

    private func exactRow(_ key: String, profile: String) async throws -> BotJSON {
        let row = try await read(.sessionRow(key: key, profile: profile))
        guard row["id"].text == key, row["profile"].text == profile else { throw BotFailure.wrongIdentity }
        return row
    }

    private static func localConversationID(_ row: BotJSON) -> String? {
        guard let rawOrigin = row["origin_json"].text,
              let origin = try? JSONDecoder().decode(BotJSON.self, from: Data(rawOrigin.utf8)),
              origin["platform"].text == "local", origin["chat_type"].text == "dm",
              let owner = row["chat_id"].text, !owner.isEmpty, origin["chat_id"].text == owner else { return nil }
        return owner
    }

    private func read(_ endpoint: HermesREST) async throws -> BotJSON {
        try JSONDecoder().decode(BotJSON.self, from: try await data(endpoint))
    }

    private func data(_ endpoint: HermesREST) async throws -> Data {
        try Task.checkCancellation()
        let body = try await wire.http.data(endpoint, validateDispatch: { try Task.checkCancellation() })
        try Task.checkCancellation()
        return body
    }
}
