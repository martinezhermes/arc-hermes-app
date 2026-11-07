import Foundation

@MainActor struct HermesListenRequest {
    let wire: any BotTransport
    let profile: String
    let sessionID: String?
    let validate: @MainActor () throws -> Void

    func synthesize(_ text: String) async throws -> HermesListenAudio {
        try await wire.listenSpeech(text: text, profile: profile, sessionID: sessionID, validateDispatch: validate)
    }
}

enum HermesListenAudio: Sendable {
    case profile(Data?)
    case arc(Data)
}

enum HermesListenFailure: LocalizedError, Equatable {
    case signInRequired
    case unsupportedContract
    case identityDenied
    case identityUnbound
    case identityUnavailable
    case voiceUnavailable
    case replyTooLong
    case synthesisFailed
    case playbackFailed

    var errorDescription: String? {
        switch self {
        case .signInRequired: String(localized: "Sign in to Hermes to use Listen.")
        case .unsupportedContract: String(localized: "ARC Listen requires a compatible Hermes gateway.")
        case .identityDenied: String(localized: "Hermes denied access to this conversation’s ARC identity.")
        case .identityUnbound: String(localized: "This conversation needs an accepted ARC identity.")
        case .identityUnavailable: String(localized: "Couldn’t verify this conversation’s ARC identity.")
        case .voiceUnavailable: String(localized: "The ARC Host voice is unavailable for this conversation.")
        case .replyTooLong: String(localized: "This reply exceeds the length limit for ARC Listen.")
        case .synthesisFailed: String(localized: "Hermes couldn’t synthesize speech.")
        case .playbackFailed: String(localized: "This device couldn’t play the speech audio.")
        }
    }
}

/// The subset of the ARC v1 identity contract that gates native speech (#92).
enum ARCListenContract {
    private struct Capabilities: Decodable {
        let apiVersion: Int?
        let readOnly: Bool?
        let sessionTypes: [String]?
        let speechContext: String?
    }

    private struct Identity: Decodable {
        struct Binding: Decodable {
            let installationId: String?
            let profileId: String?
        }
        struct Voice: Decodable {
            struct Selection: Decodable {
                let voiceId: String?
            }

            let state: String?
            let selection: Selection?
        }

        let sessionId: String?
        let hostId: String?
        let binding: Binding?
        let voice: Voice?
    }

    /// Discovery distinguishes an absent contract from an advertised but invalid one.
    static func isAdvertised(_ reply: (body: Data, status: Int)) throws -> Bool {
        if reply.status == 404 {
            let detail = (try? JSONDecoder().decode(BotJSON.self, from: reply.body))?["detail"].text
            if detail == "Not Found" || detail == "Plugin not found"
                || detail == "No such API endpoint: /api/plugins/arc/v1/capabilities" { return false }
        }
        try checkStatus(reply)
        guard let capabilities = try? decode(Capabilities.self, from: reply.body),
              capabilities.apiVersion == 1, capabilities.readOnly == true,
              capabilities.sessionTypes?.contains("local_dm") == true,
              capabilities.speechContext == "session_id" else {
            throw HermesListenFailure.unsupportedContract
        }
        return true
    }

    static func verifyVoice(_ reply: (body: Data, status: Int), sessionID: String, host: HermesARCHostIdentity) throws {
        try checkStatus(reply)
        guard let identity = try? decode(Identity.self, from: reply.body),
              identity.sessionId == sessionID, identity.hostId == host.hostID,
              identity.binding?.installationId == "hermes-install:" + host.installationID,
              identity.binding?.profileId == host.profileID else {
            throw HermesListenFailure.identityUnavailable
        }
        guard identity.voice?.state == "configured", identity.voice?.selection?.voiceId?.isEmpty == false else {
            throw HermesListenFailure.voiceUnavailable
        }
    }

    private static func checkStatus(_ reply: (body: Data, status: Int)) throws {
        guard reply.status != 200 else { return }
        let code = (try? JSONDecoder().decode(BotJSON.self, from: reply.body))?["detail"]["code"].text
        switch (reply.status, code) {
        case (401, _): throw HermesListenFailure.signInRequired
        case (403, _), (404, "profile_unavailable"), (404, "host_unavailable"), (404, "session_unavailable"):
            throw HermesListenFailure.identityDenied
        case (409, "session_identity_unbound"): throw HermesListenFailure.identityUnbound
        case (404, _): throw HermesListenFailure.unsupportedContract
        default: throw HermesListenFailure.identityUnavailable
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: data)
    }
}
