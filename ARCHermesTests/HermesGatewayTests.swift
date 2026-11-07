import XCTest
@testable import ARCHermes

/// One saved connection's shared gateway socket, against a scripted host and scripted
/// sockets. The consumers are real `BotClient`s, one per screen, as the inbox, a chat,
/// a room and the editor hold them.
@MainActor final class HermesGatewayTests: XCTestCase {
    private let record = BotConnection(id: UUID(), name: "Host", address: URL(string: "https://hermes.example")!,
                                       username: "user", password: "secret")
    /// Every socket the gateway opened, in order.
    private var sockets: [BotScriptedSocket] = []

    override func tearDown() {
        HermesHostFixture.reset()
        sockets = []
        super.tearDown()
    }

    func testSessionAuthorityGatewayUsesItsOwnTicketAndRequiredIdentity() async throws {
        let http = HermesConnection(connection: record, configuration: HermesHostFixture.configuration { request in
            switch request.url?.path {
            case "/api/status":
                return .json(200, .object(["version": .string("0.22.5"), "auth_required": .bool(true),
                                          "auth_providers": .array([.string("basic")]), "install_id": .string("test-install")]))
            case "/api/profiles/active":
                return .json(200, .object(["active": .string("default"), "current": .string("default")]))
            case "/api/plugins/arc/v1/capabilities":
                return .json(200, .object(["api_version": .number(1), "read_only": .bool(true),
                                          "session_types": .array([.string("local_dm")]), "speech_context": .string("session_id")]))
            case "/api/plugins/arc/v1/hosts":
                return .json(200, .object(["hosts": .array([.object([
                    "host_id": .string("00000000-0000-4000-8000-000000000001"),
                    "display_name": .string("Test Host"), "latest_revision": .number(1)
                ])])]))
            case "/api/plugins/arc/v1/hosts/00000000-0000-4000-8000-000000000001/bindings":
                return .json(200, .object(["bindings": .array([.object([
                    "installation_id": .string("hermes-install:test-install"), "profile_id": .string("test-profile")
                ])])]))
            case "/api/webapp/socket-ticket":
                return .json(200, .object(["ticket": .string("owning-gateway-ticket")]))
            case "/api/auth/ws-ticket":
                return .json(403, .object(["detail": .string("Use the owning gateway")]))
            default:
                return nil
            }
        }, gateway: .init { [weak self] request in
            XCTAssertEqual(request.url?.path, "/api/ws")
            let socket = BotScriptedSocket(ready: #"{"replay_epoch":"owner-epoch","session_authority":true}"#)
            self?.sockets.append(socket)
            return socket
        })
        let chat = BotClient(http: http)
        try await chat.connect()
        defer { chat.close() }
        XCTAssertEqual(HermesHostFixture.count("/api/webapp/socket-ticket"), 1)
        XCTAssertEqual(HermesHostFixture.count("/api/auth/ws-ticket"), 0)
        XCTAssertEqual(HermesHostFixture.count("/api/plugins/arc/v1/hosts"), 1)
        XCTAssertEqual(sockets.count, 1)
    }

    func testListingAnotherNativeProfileVerifiesItsHostBeforeTheRPC() async throws {
        let host = BotSocketHost()
        host.always("session.list", .init(result: .object(["sessions": .array([])])))
        let http = host.connection(record, sessionAuthority: true)
        let client = BotClient(http: http)
        try await client.connect()
        defer { client.close() }
        let result = try await client.call(.sessionList(profile: "other"))
        XCTAssertEqual(result["sessions"], .array([]))
        let binding = try XCTUnwrap(HermesHostFixture.requests.last { $0.url?.path.hasSuffix("/bindings") == true })
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(binding.url), resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "profile" }?.value, "other")
        XCTAssertEqual(http.verifiedARCIdentity(profile: "other")?.hostID, http.arcIdentity?.hostID)
        XCTAssertEqual(host.requests.last { $0["method"].text == "session.list" }?["params"]["profile"], .string("other"))
    }

    func testConcurrentConsumersShareOneSignInTicketSocketAndHandshake() async throws {
        let http = connection()
        let inbox = BotClient(http: http), chat = BotClient(http: http), editor = BotClient(http: http)
        async let inboxConnected: Void = inbox.connect()
        async let chatConnected: Void = chat.connect()
        async let editorConnected: Void = editor.connect()
        _ = try await (inboxConnected, chatConnected, editorConnected)
        defer { inbox.close(); chat.close(); editor.close() }
        for client in [inbox, chat, editor] { _ = try await client.call(.profilesList(includeSessions: false)) }
        let room = BotClient(http: http)
        try await room.connect()
        defer { room.close() }
        _ = try await room.call(.groupsCapabilities)

        XCTAssertEqual(sockets.count, 1, "A screen that connects later joins the open socket")
        XCTAssertEqual(["/auth/password-login", "/api/webapp/socket-ticket"].map(HermesHostFixture.count), [1, 1])
        XCTAssertEqual(sockets[0].outbound.map { $0["method"].text },
                       ["client.capabilities", "profiles.list", "profiles.list", "profiles.list", "groups.capabilities"])
    }

    func testLeavingEndsOnlyThatConsumersCallsAndCallbacks() async throws {
        let http = connection()
        let chat = BotClient(http: http), inbox = BotClient(http: http)
        try await chat.connect()
        try await inbox.connect()
        defer { chat.close() }
        var chatHeard: [BotJSON] = [], inboxHeard: [BotJSON] = [], inboxLost = 0
        chat.onEvent = { chatHeard.append($0) }
        inbox.onEvent = { inboxHeard.append($0) }
        inbox.onDisconnect = { _ in inboxLost += 1 }
        let socket = try XCTUnwrap(sockets.first)
        let sent = expectation(description: "both calls on the wire")
        sent.expectedFulfillmentCount = 2
        socket.withholdReply = { _ in sent.fulfill(); return true }
        let prompt = Task { try await chat.call(.promptSubmit(sessionID: "runtime", text: "hello")) }
        let roster = Task { try await inbox.call(.profilesList(includeSessions: true)) }
        await fulfillment(of: [sent], timeout: 2)

        inbox.close()
        do { _ = try await roster.value; XCTFail("A closed consumer's call must end") }
        catch { XCTAssertEqual(error as? BotFailure, .transport) }
        // The inbox's late reply reaches no one; the chat's event and reply still land.
        let delta = BotJSON.object(["session_id": .string("runtime"), "seq": .number(1), "type": .string("message.delta")])
        try answer(socket, "profiles.list", with: .object(["profiles": .array([])]))
        socket.enqueue(frame(["method": .string("event"), "params": delta]))
        try answer(socket, "prompt.submit", with: .object(["status": .string("queued")]))
        let accepted = try await prompt.value
        XCTAssertEqual(accepted["status"], .string("queued"))
        XCTAssertEqual(chatHeard, [delta])
        XCTAssertEqual(inboxHeard, [])
        XCTAssertEqual(inboxLost, 0, "Leaving is not a disconnect")
        XCTAssertFalse(socket.isClosed, "The chat still holds the socket")
        do { _ = try await inbox.call(.profilesList(includeSessions: false)); XCTFail("A closed consumer sends nothing") }
        catch { XCTAssertEqual(error as? BotFailure, .stale) }
        XCTAssertEqual(socket.sentRequests.count, 2)
    }

    /// Replies settle only the call that sent them. Events and server requests go to every
    /// attached consumer, each once, in the host's order; each consumer admits its own.
    func testRepliesEventsAndServerRequestsInterleaveToTheirTargets() async throws {
        let http = connection()
        let chat = BotClient(http: http), inbox = BotClient(http: http)
        try await chat.connect()
        try await inbox.connect()
        defer { chat.close(); inbox.close() }
        var chatHeard: [BotJSON] = [], inboxHeard: [BotJSON] = []
        chat.onEvent = { chatHeard.append($0) }
        inbox.onEvent = { inboxHeard.append($0) }
        let socket = try XCTUnwrap(sockets.first)
        let sent = expectation(description: "both calls on the wire")
        sent.expectedFulfillmentCount = 2
        socket.withholdReply = { _ in sent.fulfill(); return true }
        let resume = Task { try await chat.call(.sessionResume(profile: "inbox-triage", sessionID: "tip", omitMessages: true)) }
        let roster = Task { try await inbox.call(.profilesList(includeSessions: false)) }
        await fulfillment(of: [sent], timeout: 2)

        let changed = BotJSON.object(["type": .string("sessions.changed")])
        let request = BotJSON.object(["jsonrpc": .string("2.0"), "id": .string("srq-1"), "method": .string("sudo"),
                                      "params": .object(["session_id": .string("runtime")])])
        try answer(socket, "profiles.list", with: .object(["profiles": .array([.object(["name": .string("inbox-triage")])])]))
        socket.enqueue(frame(["method": .string("event"), "params": changed]))
        socket.enqueue(frame(request.fields ?? [:]))
        try answer(socket, "session.resume", with: .object(["session_id": .string("runtime")]))

        let rows = try await roster.value["profiles"].list
        XCTAssertEqual(rows?.first?["name"], .string("inbox-triage"))
        let resumed = try await resume.value
        XCTAssertEqual(resumed["session_id"], .string("runtime"))
        XCTAssertEqual(chatHeard, [changed, request])
        XCTAssertEqual(inboxHeard, [changed, request])
    }

    func testASocketFaultTellsEachConsumerOnceAndTheirReconnectsShareOneReplacement() async throws {
        let http = connection()
        let chat = BotClient(http: http), inbox = BotClient(http: http)
        try await chat.connect()
        try await inbox.connect()
        defer { chat.close(); inbox.close() }
        var lost: [String] = []
        let told = expectation(description: "both consumers told")
        told.expectedFulfillmentCount = 2
        chat.onDisconnect = { _ in lost.append("chat"); told.fulfill() }
        inbox.onDisconnect = { _ in lost.append("inbox"); told.fulfill() }
        let first = try XCTUnwrap(sockets.first)
        let sent = expectation(description: "stop on the wire")
        first.withholdReply = { _ in sent.fulfill(); return true }
        let stop = Task { try await chat.call(.sessionInterrupt(sessionID: "runtime")) }
        await fulfillment(of: [sent], timeout: 2)

        first.cancel()
        await fulfillment(of: [told], timeout: 2)
        do { _ = try await stop.value; XCTFail("The stop's outcome is unknown") }
        catch { XCTAssertEqual(error as? BotFailure, .transport) }
        XCTAssertEqual(lost.sorted(), ["chat", "inbox"])

        async let chatBack: Void = chat.connect()
        async let inboxBack: Void = inbox.connect()
        _ = try await (chatBack, inboxBack)
        _ = try await inbox.call(.profilesList(includeSessions: false))
        XCTAssertEqual(sockets.count, 2, "One replacement for both")
        XCTAssertEqual(HermesHostFixture.count("/api/webapp/socket-ticket"), 2, "A fresh ticket for it")
        XCTAssertEqual(HermesHostFixture.count("/auth/password-login"), 1, "On the same sign-in")
        XCTAssertEqual(sockets[1].outbound.map { $0["method"].text }, ["client.capabilities", "profiles.list"])
        XCTAssertEqual(first.sentRequests.filter { $0["method"].text == "session.interrupt" }.count, 1, "Never resent")
    }

    /// The socket fails both consumers' sends and then its reader: one report each. A
    /// consumer that has not reconnected stays out of the replacement: it sends nothing,
    /// hears nothing, and is not told when the replacement drops.
    func testOneSocketsFailuresReportOnceAndAStaleConsumerStaysOut() async throws {
        let http = connection()
        let chat = BotClient(http: http), inbox = BotClient(http: http)
        try await chat.connect()
        try await inbox.connect()
        defer { chat.close(); inbox.close() }
        var reports = 0
        let told = expectation(description: "each consumer told once")
        told.expectedFulfillmentCount = 2
        chat.onDisconnect = { _ in reports += 1; told.fulfill() }
        inbox.onDisconnect = { _ in reports += 1; told.fulfill() }
        let first = try XCTUnwrap(sockets.first)
        first.sendFailure = URLError(.networkConnectionLost)
        let chatSend = Task { try await chat.call(.profilesList(includeSessions: false)) }
        let inboxSend = Task { try await inbox.call(.sessionActiveList) }
        for send in [chatSend, inboxSend] {
            do { _ = try await send.value; XCTFail("A failed send cannot succeed") }
            catch { XCTAssertEqual(error as? BotFailure, .transport) }
        }
        await fulfillment(of: [told], timeout: 2)

        try await chat.connect()
        XCTAssertEqual(sockets.count, 2)
        let second = try XCTUnwrap(sockets.last)
        var chatHeard: [BotJSON] = [], inboxHeard: [BotJSON] = []
        chat.onEvent = { chatHeard.append($0) }
        inbox.onEvent = { inboxHeard.append($0) }
        let changed = BotJSON.object(["type": .string("sessions.changed")])
        second.enqueue(frame(["method": .string("event"), "params": changed]))
        _ = try await chat.call(.profilesList(includeSessions: false))
        XCTAssertEqual(chatHeard, [changed])
        XCTAssertEqual(inboxHeard, [])
        do { _ = try await inbox.call(.profilesList(includeSessions: false)); XCTFail("The inbox has not reconnected") }
        catch { XCTAssertEqual(error as? BotFailure, .stale) }

        let chatTold = expectation(description: "the chat hears the replacement drop")
        chat.onDisconnect = { _ in chatTold.fulfill() }
        second.cancel()
        await fulfillment(of: [chatTold], timeout: 2)
        XCTAssertEqual(reports, 2, "The inbox is not told about a socket it never joined")
    }

    /// A call that may have reached the agent has an unknown outcome once cancelled, so its
    /// consumer ends as if closed. The socket and the other consumer's work stay.
    func testCancellingAnUncertainCallEndsOnlyItsConsumer() async throws {
        let http = connection()
        let chat = BotClient(http: http), inbox = BotClient(http: http)
        try await chat.connect()
        try await inbox.connect()
        defer { inbox.close() }
        let socket = try XCTUnwrap(sockets.first)
        let sent = expectation(description: "three calls on the wire")
        sent.expectedFulfillmentCount = 3
        socket.withholdReply = { _ in sent.fulfill(); return true }
        let prompt = Task { try await chat.call(.promptSubmit(sessionID: "runtime", text: "hello")) }
        let workers = Task { try await chat.call(.subagentList(sessionID: "runtime")) }
        let roster = Task { try await inbox.call(.profilesList(includeSessions: false)) }
        await fulfillment(of: [sent], timeout: 2)

        prompt.cancel()
        for call in [prompt, workers] {
            do { _ = try await call.value; XCTFail("The chat's calls end with it") }
            catch { XCTAssertEqual(error as? BotFailure, .transport) }
        }
        do { _ = try await chat.call(.profilesList(includeSessions: false)); XCTFail("The chat must reconnect first") }
        catch { XCTAssertEqual(error as? BotFailure, .stale) }
        try answer(socket, "profiles.list", with: .object(["profiles": .array([])]))
        let rows = try await roster.value["profiles"].list
        XCTAssertEqual(rows, [])
        XCTAssertFalse(socket.isClosed)
        XCTAssertEqual(socket.sentRequests.filter { $0["method"].text == "prompt.submit" }.count, 1, "Never resent")
    }

    /// A Profile read controls nothing on the host, so a screen whose task ends while it waits
    /// (a chat pushed over the Sessions list) keeps its place on the socket.
    func testCancellingAProfilesReadKeepsItsConsumer() async throws {
        let http = connection()
        let list = BotClient(http: http)
        try await list.connect()
        defer { list.close() }
        let socket = try XCTUnwrap(sockets.first)
        let sent = expectation(description: "roster on the wire")
        socket.withholdReply = { _ in sent.fulfill(); return true }
        let roster = Task { try await list.call(.profilesList(includeSessions: false)) }
        await fulfillment(of: [sent], timeout: 2)

        roster.cancel()
        do { _ = try await roster.value; XCTFail("A cancelled read gets no reply") }
        catch { XCTAssertTrue(error is CancellationError, "\(error)") }
        socket.withholdReply = nil
        let rows = try await list.call(.profilesList(includeSessions: false))["profiles"].list
        XCTAssertEqual(rows, [], "the screen still reads on the socket")
    }

    /// A required call left unanswered past its deadline ends only its consumer, which hears
    /// it once as a lost connection. The heartbeat and the silence deadline decide whether
    /// the socket itself is gone, so the other consumer stays and the reconnect joins it.
    func testARequiredCallsDeadlineEndsOnlyItsConsumer() async throws {
        let http = connection(rpcDeadline: .milliseconds(50))
        let chat = BotClient(http: http), inbox = BotClient(http: http)
        try await chat.connect()
        try await inbox.connect()
        defer { chat.close(); inbox.close() }
        var chatLost: [BotFailure?] = [], inboxLost = 0
        let told = expectation(description: "the chat told")
        chat.onDisconnect = { chatLost.append($0 as? BotFailure); told.fulfill() }
        inbox.onDisconnect = { _ in inboxLost += 1 }
        let socket = try XCTUnwrap(sockets.first)
        socket.withholdReply = { $0["method"].text == "session.resume" }

        do {
            _ = try await chat.call(.sessionResume(profile: "inbox-triage", sessionID: "tip", omitMessages: true))
            XCTFail("An unanswered call cannot succeed")
        } catch { XCTAssertEqual(error as? BotFailure, .transport) }
        await fulfillment(of: [told], timeout: 2)
        XCTAssertEqual(chatLost, [.transport])
        XCTAssertEqual(inboxLost, 0, "Another consumer's deadline is not a lost socket")
        XCTAssertFalse(socket.isClosed)
        _ = try await inbox.call(.profilesList(includeSessions: false))

        try await chat.connect()
        _ = try await chat.call(.profilesList(includeSessions: false))
        XCTAssertEqual(sockets.count, 1, "The reconnect joins the open socket")
        XCTAssertEqual(HermesHostFixture.count("/api/webapp/socket-ticket"), 1)
    }

    /// Bot Chat's `@` lookup keeps the required-call policy: left unanswered, it ends its
    /// screen's connection, as it did before the Hermes chat's own lookup (#1113) failed alone.
    func testBotChatsUnansweredCompletionEndsItsConsumer() async throws {
        let http = connection(rpcDeadline: .milliseconds(50))
        let chat = BotClient(http: http)
        try await chat.connect()
        defer { chat.close() }
        var lost: [BotFailure?] = []
        let told = expectation(description: "the chat told")
        chat.onDisconnect = { lost.append($0 as? BotFailure); told.fulfill() }
        let socket = try XCTUnwrap(sockets.first)
        socket.withholdReply = { $0["method"].text == "complete.path" }

        do {
            _ = try await chat.call(.completePath(word: "Sou", sessionID: "runtime", profile: "default"))
            XCTFail("An unanswered call cannot succeed")
        } catch { XCTAssertEqual(error as? BotFailure, .transport) }
        await fulfillment(of: [told], timeout: 2)
        XCTAssertEqual(lost, [.transport])
    }

    /// `session.compress` waits on the model's summary as Desktop does (#1050): the usual
    /// deadline, which still ends another screen's call, never ends it.
    func testACompressionOutlivesTheUsualDeadline() async throws {
        let http = connection(rpcDeadline: .milliseconds(50))
        let chat = BotClient(http: http), other = BotClient(http: http)
        try await chat.connect()
        try await other.connect()
        defer { chat.close(); other.close() }
        var chatLost = 0
        chat.onDisconnect = { _ in chatLost += 1 }
        let socket = try XCTUnwrap(sockets.first)
        let sent = expectation(description: "compress on the wire")
        socket.withholdReply = { request in
            if request["method"].text == "session.compress" { sent.fulfill(); return true }
            return request["method"].text == "session.resume"
        }

        let compress = Task { try await chat.call(.sessionCompress(runtime: "runtime", focus: nil, profile: "default")) }
        await fulfillment(of: [sent], timeout: 2)
        do {
            _ = try await other.call(.sessionResume(profile: "default", sessionID: "tip", omitMessages: true))
            XCTFail("An unanswered call cannot succeed")
        } catch { XCTAssertEqual(error as? BotFailure, .transport, "the usual deadline passed") }
        try answer(socket, "session.compress", with: .object(["status": .string("compressed"), "removed": .number(4)]))

        let reply = try await compress.value
        XCTAssertEqual(reply["removed"].integer, 4)
        XCTAssertEqual(chatLost, 0)
    }

    /// The socket closes with the last screen to leave, and the next screen opens a fresh
    /// one on the same sign-in.
    func testTheSocketLivesWhileAConsumerHoldsItAndReopensFresh() async throws {
        let http = connection()
        let chat = BotClient(http: http), inbox = BotClient(http: http)
        try await chat.connect()
        try await inbox.connect()
        let first = try XCTUnwrap(sockets.first)
        chat.close()
        XCTAssertFalse(first.isClosed)
        inbox.close()
        XCTAssertTrue(first.isClosed)

        try await inbox.connect()
        defer { inbox.close() }
        XCTAssertEqual(sockets.count, 2)
        XCTAssertEqual(["/auth/password-login", "/api/webapp/socket-ticket"].map(HermesHostFixture.count), [1, 2])
        XCTAssertEqual(sockets[1].outbound.map { $0["method"].text }, ["client.capabilities"])
    }

    /// The app going to the background closes the socket once and tells no screen (#902):
    /// each screen suspends on `.background` itself, and its return opens one fresh socket
    /// with a new ticket and one handshake.
    func testTheBackgroundClosesTheSocketOnceAndSilently() async throws {
        let http = connection()
        let chat = BotClient(http: http), inbox = BotClient(http: http)
        try await chat.connect()
        try await inbox.connect()
        var lost = 0
        chat.onDisconnect = { _ in lost += 1 }
        inbox.onDisconnect = { _ in lost += 1 }
        let first = try XCTUnwrap(sockets.first)
        let sent = expectation(description: "read on the wire")
        first.withholdReply = { _ in sent.fulfill(); return true }
        let read = Task { try await chat.call(.profilesList(includeSessions: false)) }
        await fulfillment(of: [sent], timeout: 2)

        http.gateway.closeForBackground()
        XCTAssertTrue(first.isClosed)
        XCTAssertEqual(lost, 0, "The background close is silent")
        do { _ = try await read.value; XCTFail("A closed socket answers nothing") }
        catch { XCTAssertEqual(error as? BotFailure, .transport) }
        // Then each screen suspends, which leaves nothing more to close.
        chat.close(); inbox.close()
        XCTAssertEqual(lost, 0)

        async let chatBack: Void = chat.connect()
        async let inboxBack: Void = inbox.connect()
        _ = try await (chatBack, inboxBack)
        defer { chat.close(); inbox.close() }
        XCTAssertEqual(sockets.count, 2)
        XCTAssertEqual(["/auth/password-login", "/api/webapp/socket-ticket"].map(HermesHostFixture.count), [1, 2])
        XCTAssertEqual(sockets[1].outbound.map { $0["method"].text }, ["client.capabilities"])
    }

    func testLeavingWhileTheSocketOpensOpensNothing() async throws {
        let parked = expectation(description: "ticket in flight")
        HermesHostFixture.onPark = { parked.fulfill() }
        let http = connection { $0.url?.path == "/api/webapp/socket-ticket" ? .park : nil }
        let chat = BotClient(http: http)
        let connecting = Task { try await chat.connect() }
        await fulfillment(of: [parked], timeout: 2)
        chat.close()
        HermesHostFixture.releaseParked()
        do { try await connecting.value; XCTFail("A closed consumer must not connect") }
        catch { XCTAssertEqual(error as? BotFailure, .stale) }
        XCTAssertEqual(sockets.count, 0, "The late ticket opens no socket")
    }

    /// The connection is retired when its server, UUID or credentials are replaced.
    func testRetiringTheConnectionTellsEachConsumerOnceAndRefusesReconnects() async throws {
        let http = connection()
        let chat = BotClient(http: http), inbox = BotClient(http: http)
        try await chat.connect()
        try await inbox.connect()
        var reasons: [BotFailure?] = []
        chat.onDisconnect = { reasons.append($0 as? BotFailure) }
        inbox.onDisconnect = { reasons.append($0 as? BotFailure) }
        let socket = try XCTUnwrap(sockets.first)
        let sent = expectation(description: "read on the wire")
        socket.withholdReply = { _ in sent.fulfill(); return true }
        let read = Task { try await chat.call(.profilesList(includeSessions: false)) }
        await fulfillment(of: [sent], timeout: 2)

        http.retire()
        XCTAssertEqual(reasons, [.stale, .stale])
        do { _ = try await read.value; XCTFail("A retired socket answers nothing") }
        catch { XCTAssertEqual(error as? BotFailure, .transport) }
        XCTAssertTrue(socket.isClosed)
        do { try await chat.connect(); XCTFail("A retired connection cannot reconnect") }
        catch { XCTAssertEqual(error as? BotFailure, .stale) }
        XCTAssertEqual(HermesHostFixture.count("/api/webapp/socket-ticket"), 1)
        XCTAssertEqual(reasons.count, 2)
    }

    /// A saved connection whose gateway opens scripted sockets, kept in `sockets`.
    private func connection(rpcDeadline: Duration = .seconds(30),
                            _ answer: @escaping (URLRequest) -> HermesHostFixture.Reply? = { _ in nil }) -> HermesConnection {
        HermesConnection(connection: record, configuration: HermesHostFixture.configuration(answer),
                         gateway: .init(rpcDeadline: rpcDeadline) { [weak self] _ in
                             let socket = BotScriptedSocket()
                             self?.sockets.append(socket)
                             return socket
                         })
    }

    /// Answers the first sent request for `method`.
    private func answer(_ socket: BotScriptedSocket, _ method: String, with result: BotJSON) throws {
        let request = try XCTUnwrap(socket.sentRequests.first { $0["method"].text == method })
        socket.enqueue(frame(["id": request["id"], "result": result]))
    }

    private func frame(_ fields: [String: BotJSON]) -> URLSessionWebSocketTask.Message {
        .string(String(decoding: (try? JSONEncoder().encode(BotJSON.object(fields))) ?? Data(), as: UTF8.self))
    }
}

@MainActor final class HermesCanonicalSessionTests: XCTestCase {
    private func identity(profile: String = "default", arcProfile: String = "arc-profile:default") -> HermesARCHostIdentity {
        HermesARCHostIdentity(hostID: "00000000-0000-4000-8000-000000000001", displayName: "Test Host",
                              revision: 2, installationID: "test-install", profileID: arcProfile, profile: profile)
    }

    private func snapshot(id: String = "session", profile: String = "default",
                          nativeProfile: String = "native-default", epoch: String = "epoch-default",
                          generation: Int = 3, prompts: [BotJSON] = []) -> BotJSON {
        .object([
            "session_id": .string(id), "stored_session_id": .string(id), "messages": .array([]),
            "running": .bool(false), "revision": .number(4), "execution_generation": .number(Double(generation)),
            "replay_epoch": .string(epoch), "last_sequence": .number(7), "pending": .array([]),
            "subscription_id": .string("subscription-" + profile),
            "prompts": .array(prompts), "open_requests": .array([]),
            "info": .object(["profile_id": .string(nativeProfile), "profile_name": .string(profile)])
        ])
    }

    @discardableResult
    private func attach(_ adapter: HermesCanonicalSession, consumer: Int = 1, profile: String = "default",
                        arcProfile: String = "arc-profile:default", nativeProfile: String = "native-default",
                        epoch: String = "epoch-default", prompts: [BotJSON] = []) throws -> BotJSON {
        let host = identity(profile: profile, arcProfile: arcProfile)
        let call = HermesCall.sessionResume(profile: profile, sessionID: "session", omitMessages: true)
        let request = try adapter.prepare(call, consumer: consumer, params: call.params(), identity: host)
        XCTAssertNil(request.params["close_on_disconnect"])
        return try adapter.result(snapshot(profile: profile, nativeProfile: nativeProfile, epoch: epoch, prompts: prompts),
                                  call: call, request: request, consumer: consumer, identity: host)
    }

    func testNativeAndARCProfileIDsRemainDistinctInTheNormalSnapshot() throws {
        let adapter = HermesCanonicalSession()
        let result = try attach(adapter)
        XCTAssertEqual(result["info"]["profile_id"], .string("native-default"))
        XCTAssertEqual(result["info"]["stored_session_id"], .string("session"))
        XCTAssertEqual(result["info"]["replay_epoch"], .string("epoch-default"))
        XCTAssertEqual(adapter.replayEpoch(for: 1), "epoch-default")
        let stop = HermesCall.sessionInterrupt(sessionID: "session")
        let request = try adapter.prepare(stop, consumer: 1, params: stop.params(), identity: identity())
        XCTAssertEqual(request.params["profile"], .string("default"))
        XCTAssertEqual(request.params["execution_generation"], .number(3))
    }

    func testLostCreateAcknowledgementRetainsTheRequestIdentityAcrossReconnect() throws {
        let adapter = HermesCanonicalSession()
        let call = HermesCall.sessionNew(profile: "default")
        let first = try adapter.prepare(call, consumer: 1, params: call.params(), identity: identity())
        adapter.resetAttachments()
        let retry = try adapter.prepare(call, consumer: 1, params: call.params(), identity: identity())
        XCTAssertEqual(first.params["request_id"], retry.params["request_id"])
        XCTAssertNotNil(first.params["request_id"]?.text)
        _ = try adapter.result(snapshot(), call: call, request: retry, consumer: 1, identity: identity())
        let next = try adapter.prepare(call, consumer: 1, params: call.params(), identity: identity())
        XCTAssertNotEqual(first.params["request_id"], next.params["request_id"])
    }

    func testResumeRejectsAnotherConversationEvenOnTheSameProfile() throws {
        let adapter = HermesCanonicalSession()
        let call = HermesCall.sessionResume(profile: "default", sessionID: "selected", omitMessages: true)
        let request = try adapter.prepare(call, consumer: 1, params: call.params(), identity: identity())
        XCTAssertThrowsError(try adapter.result(snapshot(id: "different"), call: call, request: request,
                                               consumer: 1, identity: identity())) {
            XCTAssertEqual($0 as? BotFailure, .wrongIdentity)
        }
    }

    func testPromptAdmissionMustNameTheAttachedNativeOwner() throws {
        let adapter = HermesCanonicalSession()
        try attach(adapter)
        let call = HermesCall.promptSubmit(sessionID: "session", text: "hello")
        let request = try adapter.prepare(call, consumer: 1, params: call.params(), identity: identity())
        XCTAssertEqual(request.params["queued"], .bool(true))
        XCTAssertNotNil(request.params["submission_id"]?.text)
        let receipt: BotJSON = .object([
            "admission_id": .string("admission"), "status": .string("queued"),
            "ref": .object(["session_id": .string("session"), "profile_id": .string("native-default")])
        ])
        let result = try adapter.result(receipt, call: call, request: request, consumer: 1, identity: identity())
        XCTAssertEqual(result["session_id"], .string("session"))
        XCTAssertEqual(result["submission_id"], request.params["submission_id"])
        var crossed = receipt.fields!
        crossed["ref"] = .object(["session_id": .string("session"), "profile_id": .string("native-other")])
        XCTAssertThrowsError(try adapter.result(.object(crossed), call: call, request: request,
                                               consumer: 1, identity: identity()))
    }

    func testSameLocalSessionIDOnTwoProfilesKeepsEventsAndControlsOnTheirOwner() throws {
        let adapter = HermesCanonicalSession()
        try attach(adapter)
        try attach(adapter, consumer: 2, profile: "other", arcProfile: "arc-profile:other",
                   nativeProfile: "native-other", epoch: "epoch-other")
        let event: BotJSON = .object([
            "type": .string("turn.start"), "session_id": .string("session"),
            "replay_epoch": .string("epoch-other"), "execution_generation": .number(8), "payload": .object([:])
        ])
        XCTAssertTrue(adapter.events(event, for: 1).isEmpty)
        XCTAssertEqual(adapter.events(event, for: 2).count, 1)
        let stop = HermesCall.sessionInterrupt(sessionID: "session")
        let first = try adapter.prepare(stop, consumer: 1, params: stop.params(), identity: identity())
        let second = try adapter.prepare(stop, consumer: 2, params: stop.params(),
                                         identity: identity(profile: "other", arcProfile: "arc-profile:other"))
        XCTAssertEqual(first.params["profile"], .string("default"))
        XCTAssertEqual(first.params["execution_generation"], .number(3))
        XCTAssertEqual(second.params["profile"], .string("other"))
        XCTAssertEqual(second.params["execution_generation"], .number(8))
        XCTAssertThrowsError(try adapter.prepare(stop, consumer: 1, params: stop.params(),
                                                identity: identity(profile: "other", arcProfile: "arc-profile:other")))
        let ambiguous: BotJSON = .object(["method": .string("sudo"), "id": .string("request"),
                                         "params": .object(["session_id": .string("session")])])
        XCTAssertTrue(adapter.events(ambiguous, for: 1).isEmpty)
        XCTAssertTrue(adapter.events(ambiguous, for: 2).isEmpty)
    }

    func testApprovalUsesTheDisplayedPromptAndExecutionGeneration() throws {
        let adapter = HermesCanonicalSession()
        let prompt: BotJSON = .object([
            "kind": .string("approval"), "prompt_id": .string("approval"),
            "execution_generation": .number(3), "choices": .array([.string("once"), .string("deny")])
        ])
        let state = try attach(adapter, prompts: [prompt])
        XCTAssertEqual(state["open_requests"].list?.first?["params"]["request_id"], .string("approval"))
        let call = HermesCall.approvalRespond(sessionID: "session", requestID: "approval", choice: .once)
        let request = try adapter.prepare(call, consumer: 1, params: call.params(), identity: identity())
        XCTAssertEqual(request.method, "approval.respond")
        XCTAssertEqual(request.params["prompt_id"], .string("approval"))
        XCTAssertEqual(request.params["execution_generation"], .number(3))
        XCTAssertNil(request.params["request_id"])
        let response = try adapter.result(.object(["status": .string("resolved"), "prompt_id": .string("approval")]),
                                          call: call, request: request, consumer: 1, identity: identity())
        XCTAssertEqual(response["resolved"], .number(1))
        XCTAssertThrowsError(try adapter.prepare(call, consumer: 1, params: call.params(), identity: identity()))
    }

    func testClarificationUsesTheOwningPromptAndReturnsItsNativeResolution() throws {
        let adapter = HermesCanonicalSession()
        let prompt: BotJSON = .object([
            "kind": .string("clarify"), "prompt_id": .string("clarification"),
            "execution_generation": .number(3), "question": .string("Which option?"),
            "choices": .array([.string("A"), .string("B")]), "multi_select": .bool(false)
        ])
        let state = try attach(adapter, prompts: [prompt])
        XCTAssertEqual(state["open_requests"].list?.first?["params"]["questions"].list?.first?["question"], .string("Which option?"))
        let call = HermesCall.requestAnswer(id: "clarification", result: .answer("A"))
        let request = try adapter.prepare(call, consumer: 1, params: call.params(), identity: identity())
        XCTAssertEqual(request.method, "clarify.respond")
        XCTAssertEqual(request.params["answer"], .string("A"))
        XCTAssertEqual(request.params["session_id"], .string("session"))
        XCTAssertEqual(request.params["execution_generation"], .number(3))
        let response = try adapter.result(.object(["status": .string("resolved"), "prompt_id": .string("clarification")]),
                                          call: call, request: request, consumer: 1, identity: identity())
        XCTAssertEqual(response["status"], .string("ok"))
    }

    func testOldTurnCannotOfferAnApprovalAfterTheExecutionAdvanced() throws {
        let adapter = HermesCanonicalSession()
        try attach(adapter)
        _ = adapter.events(.object([
            "type": .string("turn.start"), "session_id": .string("session"),
            "replay_epoch": .string("epoch-default"), "execution_generation": .number(4), "payload": .object([:])
        ]), for: 1)
        let stale: BotJSON = .object([
            "type": .string("approval.request"), "session_id": .string("session"),
            "replay_epoch": .string("epoch-default"), "execution_generation": .number(3),
            "payload": .object(["prompt_id": .string("old-approval"), "execution_generation": .number(3)])
        ])
        XCTAssertTrue(adapter.events(stale, for: 1).isEmpty)
    }
}


@MainActor final class HermesARCIdentityTests: XCTestCase {
    private var record: BotConnection {
        BotConnection(id: UUID(), name: "Saved gateway",
                      address: URL(string: "https://hermes.example")!, username: "user", password: "secret")
    }

    override func tearDown() {
        HermesHostFixture.reset()
        super.tearDown()
    }

    func testMissingARCPreventsTheGatewaySocketFromOpening() async throws {
        var sockets = 0
        let http = HermesConnection(connection: record, configuration: HermesHostFixture.configuration { request in
            request.url?.path == "/api/plugins/arc/v1/capabilities"
                ? .json(404, .object(["detail": .string("Plugin not found")])) : nil
        }, gateway: .init { _ in
            sockets += 1
            return BotScriptedSocket()
        })
        let client = BotClient(http: http)
        do { try await client.connect(); XCTFail("An unbound deployment cannot admit chat") }
        catch { XCTAssertEqual(error as? HermesARCIdentityFailure, .unavailable) }
        XCTAssertEqual(sockets, 0)
        XCTAssertEqual(HermesHostFixture.count("/api/webapp/socket-ticket"), 0)
    }

    func testBindingMustMatchTheAuthenticatedInstallation() async throws {
        let http = HermesConnection(connection: record, configuration: HermesHostFixture.configuration { request in
            if request.url?.path.hasSuffix("/bindings") == true {
                return .json(200, .object(["bindings": .array([.object([
                    "installation_id": .string("hermes-install:another"), "profile_id": .string("arc-profile:fixture")
                ])])]))
            }
            return nil
        })
        do { _ = try await http.verifyARCIdentity(profile: "default"); XCTFail("Crossed installation binding") }
        catch { XCTAssertEqual(error as? HermesARCIdentityFailure, .bindingMismatch) }
        XCTAssertNil(http.arcIdentity)
    }

    func testAuthenticatedStatusCanSupplyAnIDWithheldFromThePublicStatus() async throws {
        var authenticated = false
        let http = HermesConnection(connection: record, configuration: HermesHostFixture.configuration { request in
            if request.url?.path == "/auth/password-login" { authenticated = true }
            if request.url?.path == "/api/status", !authenticated {
                return .json(200, .object(["version": .string("unknown"), "auth_required": .bool(true),
                                          "auth_providers": .array([.string("basic")])]))
            }
            return nil
        })
        let identity = try await http.verifyARCIdentity(profile: "default")
        XCTAssertEqual(identity.installationID, "fixture")
        XCTAssertEqual(http.connection.installID, "fixture")
        XCTAssertEqual(http.connection.arcIdentity, identity)
    }

    func testChangingProfilesCannotSilentlyChangeTheHost() async throws {
        let second = "00000000-0000-4000-8000-000000000002"
        let http = HermesConnection(connection: record, configuration: HermesHostFixture.configuration { request in
            let profile = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
                .queryItems?.first { $0.name == "profile" }?.value
            if request.url?.path == "/api/plugins/arc/v1/hosts", profile == "other" {
                return .json(200, .object(["hosts": .array([.object([
                    "host_id": .string(second), "display_name": .string("Other Host"), "latest_revision": .number(1)
                ])])]))
            }
            if request.url?.path == "/api/plugins/arc/v1/hosts/" + second + "/bindings" {
                return .json(200, .object(["bindings": .array([.object([
                    "installation_id": .string("hermes-install:fixture"), "profile_id": .string("arc-profile:other")
                ])])]))
            }
            return nil
        })
        let first = try await http.verifyARCIdentity(profile: "default")
        do { _ = try await http.verifyARCIdentity(profile: "other"); XCTFail("The gateway has one assigned Host") }
        catch { XCTAssertEqual(error as? HermesARCIdentityFailure, .bindingMismatch) }
        XCTAssertEqual(http.arcIdentity?.hostID, first.hostID)
    }

    func testAdministrationAliasKeepsTheSavedConnectionIdentityOnTheCanonicalBackend() throws {
        for path in ["admin", "dashboard", "webapp", "dashboard/admin"] {
            XCTAssertEqual(try BotConnection.address("https://hermes.example/gateways/cloud/" + path),
                           URL(string: "https://hermes.example/gateways/cloud"))
        }
        let alias = URL(string: "https://hermes.example/gateways/cloud/dashboard/admin")!
        let canonical = URL(string: "https://hermes.example/gateways/cloud")!
        var saved = record
        saved.address = alias
        let http = HermesConnection(connection: saved, configuration: HermesHostFixture.configuration { _ in nil })
        XCTAssertEqual(try BotConnection.address(alias.absoluteString), canonical)
        XCTAssertEqual(http.connection.address, canonical)
        XCTAssertEqual(http.connection.id, saved.id)
        XCTAssertEqual(http.connection.username, saved.username)
        XCTAssertEqual(http.connection.password, saved.password)
        XCTAssertTrue(http.adopt(saved), "Canonicalizing an address keeps the current credential and socket owner")
    }
}
