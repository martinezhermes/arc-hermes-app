import Foundation

/// Adapts the existing conversation engine to the native session authority.
/// State belongs to a socket consumer and its verified profile, never a display name.
@MainActor final class HermesCanonicalSession {
    struct Request {
        let method: String
        let params: [String: BotJSON]
    }

    private struct Session {
        let id: String
        let profile: String
        let profileID: String
        let arcProfileID: String
        let subscriptionID: String
        var revision: Int
        var generation: Int
        var epoch: String
        var prompts: [String: BotJSON] = [:]
    }

    private struct Creation {
        let call: HermesCall
        let requestID: String
    }

    private var sessions: [Int: Session] = [:]
    private var creations: [Int: Creation] = [:]

    func resetAttachments() {
        sessions.removeAll()
    }

    func replayEpoch(for consumer: Int) -> String? {
        sessions[consumer]?.epoch
    }

    func isAttached(_ consumer: Int, sessionID: String, profile: String) -> Bool {
        sessions[consumer]?.id == sessionID && sessions[consumer]?.profile == profile
    }

    func validateIdentity(_ identity: HermesARCHostIdentity, consumer: Int?) throws {
        guard let consumer, let session = sessions[consumer] else { throw BotFailure.stale }
        guard identity.profile == session.profile, identity.profileID == session.arcProfileID else {
            throw HermesARCIdentityFailure.bindingMismatch
        }
    }

    func profile(params: [String: BotJSON], consumer: Int?) throws -> String? {
        if let profile = params["profile"]?.text { return profile }
        if params["session_id"]?.text != nil {
            guard let consumer, let session = sessions[consumer],
                  session.id == params["session_id"]?.text else { throw BotFailure.stale }
            return session.profile
        }
        return consumer.flatMap { sessions[$0]?.profile }
    }

    func prepare(_ call: HermesCall, consumer: Int?, params original: [String: BotJSON],
                 identity: HermesARCHostIdentity?) throws -> Request {
        var params = original
        let session = consumer.flatMap { sessions[$0] }
        if params["profile"] != nil || params["session_id"] != nil || session != nil {
            guard let identity else { throw HermesARCIdentityFailure.unavailable }
            params["profile"] = .string(identity.profile)
            if let session, params["session_id"]?.text == session.id,
               identity.profileID != session.arcProfileID {
                throw HermesARCIdentityFailure.bindingMismatch
            }
        }

        switch call {
        case .sessionCreate, .sessionNew:
            guard let consumer else { throw BotFailure.stale }
            let creation = creations[consumer].flatMap { $0.call == call ? $0 : nil }
                ?? Creation(call: call, requestID: UUID().uuidString)
            creations[consumer] = creation
            params["request_id"] = .string(creation.requestID)
        case .sessionResume:
            params.removeValue(forKey: "close_on_disconnect")
        case .sessionList:
            params["scope"] = .string("stored")
        case .sessionEventsSince:
            if let session { params["replay_epoch"] = .string(session.epoch) }
        case .promptSubmit:
            params["submission_id"] = .string(UUID().uuidString)
        case .sessionInterrupt, .sessionSteer, .sessionRedirect:
            guard let session, session.id == params["session_id"]?.text else { throw BotFailure.stale }
            params["execution_generation"] = .number(Double(session.generation))
        case .approvalRespond(_, let id, _):
            return try promptResponse("approval", id: id, params: params, session: session)
        case .requestAnswer(let id, let answer):
            if session?.prompts[id]?["kind"].text == "clarify" {
                var response = params
                if case .answer(let text) = answer { response["answer"] = .string(text) }
                else { response["answer"] = .string("") }
                return try promptResponse("clarify", id: id, params: response, session: session)
            }
        case .sessionTitle, .sessionRename:
            return try mutation("rename", payload: ["title": params["title"] ?? .null],
                                params: params, session: session)
        case .sessionCwdSet:
            return try mutation("workspace", payload: ["cwd": params["cwd"] ?? .null],
                                params: params, session: session)
        case .sessionDelete:
            if let key = params.removeValue(forKey: "session_key") { params["session_id"] = key }
            return try mutation("delete", payload: [:], params: params, session: session)
        case .sessionWorkspaceMove:
            if let key = params.removeValue(forKey: "session_key") { params["session_id"] = key }
            return try mutation("workspace", payload: ["cwd": params["cwd"] ?? .null],
                                params: params, session: session)
        case .sessionClose:
            guard let session, session.id == params["session_id"]?.text else { throw BotFailure.stale }
            return Request(method: "session.detach", params: [
                "profile": .string(session.profile), "session_id": .string(session.id),
                "subscription_id": .string(session.subscriptionID)
            ])
        case .sessionCompress:
            return try mutation("compress", payload: params["focus_topic"].map { ["focus": $0] } ?? [:],
                                params: params, session: session)
        default:
            break
        }
        return Request(method: call.method, params: params)
    }

    private func promptResponse(_ kind: String, id: String, params: [String: BotJSON],
                                session: Session?) throws -> Request {
        guard let session, let prompt = session.prompts[id], prompt["kind"].text == kind,
              prompt["execution_generation"].integer == session.generation else { throw BotFailure.stale }
        let field = kind == "approval" ? "choice" : "answer"
        return Request(method: kind + ".respond", params: [
            "profile": .string(session.profile), "session_id": .string(session.id),
            "prompt_id": .string(id), "execution_generation": .number(Double(session.generation)),
            field: params[field] ?? .string("")
        ])
    }

    private func mutation(_ operation: String, payload: [String: BotJSON],
                          params: [String: BotJSON], session: Session?) throws -> Request {
        guard let session, session.id == params["session_id"]?.text else { throw BotFailure.stale }
        return Request(method: "session.mutate", params: [
            "profile": .string(session.profile), "session_id": .string(session.id),
            "request_id": .string(UUID().uuidString), "expected_revision": .number(Double(session.revision)),
            "expected_generation": .number(Double(session.generation)),
            "operation": .string(operation), "payload": .object(payload)
        ])
    }

    func result(_ value: BotJSON, call: HermesCall, request: Request, consumer: Int?,
                identity: HermesARCHostIdentity?) throws -> BotJSON {
        guard let consumer else { return value }
        switch call {
        case .sessionCreate, .sessionNew, .sessionResume:
            guard let identity, let id = value["session_id"].text, !id.isEmpty,
                  let profileID = value["info"]["profile_id"].text, !profileID.isEmpty,
                  value["info"]["profile_name"].text == identity.profile,
                  let subscriptionID = value["subscription_id"].text, !subscriptionID.isEmpty,
                  let revision = value["revision"].integer,
                  let generation = value["execution_generation"].integer,
                  let epoch = value["replay_epoch"].text, !epoch.isEmpty else { throw BotFailure.wrongIdentity }
            if case .sessionResume = call, let requested = request.params["session_id"]?.text,
               !requested.isEmpty, id != requested, value["stored_session_id"].text != requested {
                throw BotFailure.wrongIdentity
            }
            var session = Session(id: id, profile: identity.profile, profileID: profileID,
                                  arcProfileID: identity.profileID,
                                  subscriptionID: subscriptionID,
                                  revision: revision, generation: generation, epoch: epoch)
            if let previous = sessions[consumer], previous.id == id,
               previous.profileID == profileID, previous.epoch == epoch {
                session.revision = max(previous.revision, revision)
                session.generation = max(previous.generation, generation)
            }
            var projected = value.fields ?? [:]
            var info = value["info"].fields ?? [:]
            for key in ["stored_session_id", "running", "replay_epoch", "last_sequence", "execution_generation"] {
                info[key] = value[key]
            }
            let pending = (value["pending"].list ?? []).map { row -> BotJSON in
                var fields = row.fields ?? [:]
                fields["user"] = row["text"]
                return .object(fields)
            }
            info["pending_submissions"] = .array(pending)
            projected["pending_submissions"] = .array(pending)
            let prompts = value["prompts"].list ?? []
            var open = value["open_requests"].list ?? []
            for prompt in prompts {
                guard let id = prompt["prompt_id"].text, let kind = prompt["kind"].text else { throw BotFailure.unsupported }
                session.prompts[id] = prompt
                open.append(promptEnvelope(prompt, sessionID: session.id))
                var fields = prompt.fields ?? [:]
                fields["request_id"] = .string(id)
                projected["pending_" + kind] = .object(fields)
            }
            projected["open_requests"] = .array(open)
            projected["session_key"] = value["stored_session_id"]
            if let queued = (value["pending"].list ?? []).first(where: { $0["status"].text == "queued" }) {
                projected["queued"] = .object(["user": queued["text"]])
            }
            projected["info"] = .object(info)
            sessions[consumer] = session
            creations.removeValue(forKey: consumer)
            return .object(projected)
        case .sessionList:
            var result = value.fields ?? [:]
            result["sessions"] = .array((value["sessions"].list ?? []).map { row in
                var fields = row.fields ?? [:]
                if fields["resolved_id"] == nil { fields["resolved_id"] = fields["session_id"] ?? fields["id"] }
                return .object(fields)
            })
            return .object(result)
        case .promptSubmit:
            if value["voice_stopped"].flag == true, value["admission_id"] == .null, value["ref"] == .null {
                return .object(["voice_stopped": .bool(true)])
            }
            guard let session = sessions[consumer],
                  value["ref"]["session_id"].text == session.id,
                  value["ref"]["profile_id"].text == session.profileID,
                  value["admission_id"].text?.isEmpty == false else { throw BotFailure.wrongIdentity }
            var result = value.fields ?? [:]
            result["session_id"] = .string(session.id)
            result["submission_id"] = request.params["submission_id"]
            return .object(result)
        case .promptReceipt, .promptCancel:
            guard let session = sessions[consumer],
                  value["ref"]["session_id"].text == session.id,
                  value["ref"]["profile_id"].text == session.profileID,
                  value["admission_id"] == request.params["admission_id"] else { throw BotFailure.wrongIdentity }
            return value
        case .approvalRespond:
            guard let id = value["prompt_id"].text,
                  id == request.params["prompt_id"]?.text,
                  ["resolved", "already_resolved"].contains(value["status"].text ?? "") else { throw BotFailure.unsupported }
            sessions[consumer]?.prompts.removeValue(forKey: id)
            return .object(["resolved": .number(value["status"].text == "resolved" ? 1 : 0)])
        case .requestAnswer:
            if request.method == "clarify.respond" {
                guard value["prompt_id"] == request.params["prompt_id"],
                      ["resolved", "already_resolved"].contains(value["status"].text ?? "") else { throw BotFailure.unsupported }
                if let id = value["prompt_id"].text { sessions[consumer]?.prompts.removeValue(forKey: id) }
                return .object(["status": .string(value["status"].text == "resolved" ? "ok" : "expired")])
            }
        default:
            break
        }
        if request.method == "session.mutate", let revision = value["revision"].integer {
            guard var session = sessions[consumer], value["session_id"].text == session.id else {
                throw BotFailure.wrongIdentity
            }
            session.revision = max(session.revision, revision)
            sessions[consumer] = session
        }
        return value
    }

    /// The authority's replay epoch distinguishes identical local IDs in different profiles.
    func events(_ frame: BotJSON, for consumer: Int) -> [BotJSON] {
        let event = frame["method"].text == "event" ? frame["params"] : frame
        let sid = event["session_id"].text ?? event["params"]["session_id"].text
        guard let sid else { return [event] }
        guard var session = sessions[consumer], session.id == sid else { return [] }
        if let epoch = event["replay_epoch"].text, epoch != session.epoch { return [] }
        let profile = event["profile"].text ?? event["params"]["profile"].text
        if let profile, profile != session.profile { return [] }
        if event["replay_epoch"].text == nil, profile == nil {
            let owners = Set(sessions.values.filter { $0.id == sid }.map(\.profileID))
            guard owners.count == 1 else { return [] }
        }
        if let generation = event["execution_generation"].integer ?? event["payload"]["execution_generation"].integer {
            guard generation >= session.generation else { return [] }
            session.generation = generation
        }
        let payload = event["payload"]
        if let revision = payload["revision"].integer, revision > session.revision { session.revision = revision }
        var result = [event]
        if let id = payload["prompt_id"].text, let type = event["type"].text {
            if type == "approval.request" || type == "clarify.request" {
                var prompt = payload.fields ?? [:]
                prompt["kind"] = .string(type == "approval.request" ? "approval" : "clarify")
                session.prompts[id] = .object(prompt)
                result.append(promptEnvelope(.object(prompt), sessionID: sid))
            } else if type.hasSuffix(".settled") {
                session.prompts.removeValue(forKey: id)
                result.append(.object(["method": .string("request.cancel"),
                                       "params": .object(["id": .string(id), "session_id": .string(sid)])]))
            }
        }
        sessions[consumer] = session
        return result
    }

    private func promptEnvelope(_ prompt: BotJSON, sessionID: String) -> BotJSON {
        var params = prompt.fields ?? [:]
        params["session_id"] = .string(sessionID)
        params["request_id"] = prompt["prompt_id"]
        if prompt["kind"].text == "clarify" {
            params["questions"] = .array([.object(["question": prompt["question"], "choices": prompt["choices"],
                                                "multi_select": prompt["multi_select"]])])
        }
        return .object(["id": prompt["prompt_id"], "method": prompt["kind"], "params": .object(params)])
    }
}
