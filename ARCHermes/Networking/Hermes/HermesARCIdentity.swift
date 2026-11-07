import Foundation

enum HermesARCIdentityFailure: LocalizedError, Equatable {
    case unavailable
    case bindingMismatch

    var errorDescription: String? {
        switch self {
        case .unavailable:
            String(localized: "A verified ARC Host is required to open chat on this gateway.")
        case .bindingMismatch:
            String(localized: "The ARC Host binding does not match this connection.")
        }
    }
}

@MainActor extension HermesConnection {
    /// Authenticate and resolve the required Host for this native profile selector.
    /// The opaque ARC profile ID is verified against session snapshots, never used as a selector.
    func verifyARCIdentity(profile requested: String? = nil,
                           validateDispatch: (@MainActor () throws -> Void)? = nil) async throws -> HermesARCHostIdentity {
        let status = try await requiredARCReply(.status, validateDispatch: validateDispatch)
        guard let installID = status["install_id"].text, !installID.isEmpty else {
            throw HermesARCIdentityFailure.unavailable
        }
        try connection.requireSameInstall(installID)

        let profile: String
        if let requested, !requested.isEmpty, requested != "current" {
            profile = requested
        } else {
            let active = try await requiredARCReply(.profilesActive, validateDispatch: validateDispatch)
            guard let current = active["current"].text, !current.isEmpty else {
                throw HermesARCIdentityFailure.unavailable
            }
            profile = current
        }

        let capabilities = try await reply(.arcSpeechCapabilities(profile: profile), validateDispatch: validateDispatch)
        guard (try? ARCListenContract.isAdvertised(capabilities)) == true else {
            throw HermesARCIdentityFailure.unavailable
        }
        let hosts = try await requiredARCReply(.arcHosts(profile: profile), validateDispatch: validateDispatch)
        guard let rows = hosts["hosts"].list, rows.count == 1,
              let hostID = rows[0]["host_id"].text, UUID(uuidString: hostID) != nil,
              let name = rows[0]["display_name"].text, !name.isEmpty,
              let revision = rows[0]["latest_revision"].integer, revision > 0 else {
            throw HermesARCIdentityFailure.unavailable
        }
        let result = try await requiredARCReply(.arcBindings(hostID: hostID, profile: profile),
                                                validateDispatch: validateDispatch)
        guard let bindings = result["bindings"].list, bindings.count == 1,
              bindings[0]["installation_id"].text == "hermes-install:" + installID,
              let profileID = bindings[0]["profile_id"].text, !profileID.isEmpty else {
            throw HermesARCIdentityFailure.bindingMismatch
        }
        let identity = HermesARCHostIdentity(hostID: hostID, displayName: name, revision: revision,
                                            installationID: installID, profileID: profileID, profile: profile)
        try acceptARCIdentity(identity)
        return identity
    }

    private func requiredARCReply(_ route: HermesREST,
                                  validateDispatch: (@MainActor () throws -> Void)?) async throws -> BotJSON {
        let response = try await reply(route, validateDispatch: validateDispatch)
        guard response.status == 200,
              let value = try? JSONDecoder().decode(BotJSON.self, from: response.body) else {
            throw HermesARCIdentityFailure.unavailable
        }
        return value
    }
}
