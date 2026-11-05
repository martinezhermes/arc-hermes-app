import XCTest
@testable import ARCHermes

final class APIClientTTSTests: APIClientTestCase {
    func testSynthesizeSpeechPostsJSONAndReturnsRawAudioBytes() async throws {
        // Not valid MPEG audio — the client must return the bytes untouched,
        // never attempt to JSON-decode a 2xx TTS response.
        let audioBytes = Data([0xFF, 0xF3, 0x18, 0xC4, 0x00, 0x01])
        let client = makeClient { request in
            XCTAssertEqual(request.url?.path, "/api/tts")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            guard let body = apiTestBodyData(from: request) else {
                XCTFail("Missing request body")
                throw URLError(.badServerResponse)
            }
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["text"] as? String, "Hello from ARCHermes.")
            // The server defaults to `zh-CN-XiaoxiaoNeural`, so the voice must
            // always be sent explicitly.
            XCTAssertEqual(json["voice"] as? String, "en-US-AriaNeural")
            XCTAssertEqual(json["engine"] as? String, "edge")
            XCTAssertEqual(json.count, 3)

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "audio/mpeg"]
            )!
            return (response, audioBytes)
        }

        let data = try await client.synthesizeSpeech(text: "Hello from ARCHermes.", voice: "en-US-AriaNeural")

        XCTAssertEqual(data, audioBytes)
    }

    func testProviderEngineIsExplicitAndAbsentVoiceUsesProviderConfiguration() async throws {
        for engine in [TTSEngine.openai, .elevenlabs] {
            let client = makeClient { request in
                let body = try XCTUnwrap(apiTestBodyData(from: request))
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                XCTAssertEqual(json["text"] as? String, "Hello")
                XCTAssertEqual(json["engine"] as? String, engine.rawValue)
                XCTAssertNil(json["voice"], "No voice lets the provider's configured one apply")
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data([1]))
            }
            let audio = try await client.synthesizeSpeech(text: "Hello", voice: nil, engine: engine)
            XCTAssertEqual(audio, Data([1]))
        }
    }

    func testSettingsDecodesTTSPreferencesTolerantly() async throws {
        for (json, engine, voice) in [
            (#"{"tts_engine":"edge","tts_voice":"tr-TR-EmelNeural"}"#, "edge", "tr-TR-EmelNeural"),
            (#"{}"#, nil, nil),
            (#"{"tts_engine":null,"tts_voice":null}"#, nil, nil),
            (#"{"tts_engine":[],"tts_voice":{"future":true}}"#, nil, nil),
            (#"{"tts_engine":12,"tts_voice":false}"#, nil, nil)
        ] as [(String, String?, String?)] {
            let client = makeClient { request in
                XCTAssertEqual(request.url?.path, "/api/settings")
                return apiTestJSONResponse(json, for: request)
            }
            let settings = try await client.settings()
            XCTAssertEqual(settings.ttsEngine, engine)
            XCTAssertEqual(settings.ttsVoice, voice)
        }
    }
}

/// Listen's speech from a Hermes host (#1072) over a connected `BotClient`, against a host
/// scripted with the replies `scripts/local-hermes` gave at the pin (0.21.5, ca678285).
@MainActor final class HermesSpeakTests: XCTestCase {
    private let record = BotConnection(id: UUID(), name: "Host", address: URL(string: "https://hermes.example")!,
                                       username: "user", password: "secret")

    override func tearDown() {
        HermesHostFixture.reset()
        super.tearDown()
    }

    /// The host's provider picks the format; every format comes back as its bytes.
    func testSpeechIsTheTextSpokenInTheProfilesVoice() async throws {
        let client = try await connectedClient()
        defer { client.close() }
        var sent: URLRequest?
        _ = HermesHostFixture.configuration { request in
            guard request.url?.path == "/api/audio/speak" else { return nil }
            sent = request
            return .json(200, .object(["ok": .bool(true), "data_url": .string("data:audio/ogg;base64,T2dnUwACAA=="),
                                       "mime_type": .string("audio/ogg"), "provider": .string("openai")]))
        }

        let audio = try await client.speech(text: "Hi there.", profile: "research")

        XCTAssertEqual(audio, Data([0x4F, 0x67, 0x67, 0x53, 0x00, 0x02, 0x00]))
        XCTAssertEqual(sent?.httpMethod, "POST")
        XCTAssertEqual(sent?.url?.query, "profile=research")
        XCTAssertEqual(try sent.flatMap(apiTestBodyData).map { try JSONDecoder().decode(BotJSON.self, from: $0) },
                       .object(["text": .string("Hi there.")]), "The host takes no voice, engine or rate")
    }

    func testARefusalOrAnUnreadableReplyThrows() async throws {
        let client = try await connectedClient()
        defer { client.close() }
        let refusals: [(String, HermesHostFixture.Reply)] = [
            ("empty text", .json(400, .object(["detail": .string("Text is required")]))),
            ("provider failure", .json(500, .object(["detail": .string("Speech synthesis failed")])))
        ]
        let unreadable: [(String, String?)] = [
            ("not base64", "data:audio/mpeg;base64,not*base64"),
            ("not base64-encoded", "data:audio/mpeg,T2dnUw=="),
            ("not a data URL", "https://hermes.example/speech.mp3"),
            ("no audio", "data:audio/mpeg;base64,"),
            ("no data_url", nil)
        ]
        let replies: [(String, HermesHostFixture.Reply)] = refusals + unreadable.map { label, url in
            var body: [String: BotJSON] = ["ok": .bool(true)]
            body["data_url"] = url.map(BotJSON.string)
            return (label, .json(200, .object(body)))
        }
        for (label, reply) in replies {
            _ = HermesHostFixture.configuration { $0.url?.path == "/api/audio/speak" ? reply : nil }
            do {
                _ = try await client.speech(text: "Hi.", profile: "research")
                XCTFail("\(label): expected a throw")
            } catch {
                if refusals.contains(where: { $0.0 == label }) {
                    XCTAssertEqual(error as? BotArtifactFailure, .unavailable, label)
                } else {
                    XCTAssertEqual(error as? BotFailure, .unsupported, label)
                }
            }
        }
    }

    func testARCListenKeepsTheNativeBearerProfileAndDeploymentPrefix() async throws {
        let base = try BotConnection.address("https://hermes.example/gateways/cloud")
        let saved = BotConnection(id: UUID(), name: "Fixture", address: base, username: "", password: "",
                                  headers: [CustomHeader(name: "X-Access", value: "fixture")],
                                  oauth: HermesOAuth(provider: "nous", userID: "u1", refreshToken: "fixture-refresh"))
        let prefix = base.path
        let profile = "fixture-profile"
        let sessionID = ARCSpeechFixture.sessionID
        let configuration = HermesHostFixture.configuration { request in
            switch request.url?.path {
            case prefix + "/api/status":
                return .json(200, .object(["auth_required": .bool(true), "auth_flows": .array([.string("native_pkce")])]))
            case prefix + "/auth/native/refresh":
                return .json(200, .object(["access_token": .string("fixture-access")]))
            case prefix + "/api/auth/me":
                return .json(200, .object(["provider": .string("nous"), "user_id": .string("u1")]))
            case prefix + ARCSpeechFixture.capabilitiesPath: return ARCSpeechFixture.capabilities
            case prefix + ARCSpeechFixture.identityPath: return ARCSpeechFixture.identity()
            case prefix + ARCSpeechFixture.speakPath: return ARCSpeechFixture.audio()
            default:
                XCTFail("Unexpected request: \(request.url?.path ?? "nil")")
                return .json(404, .object([:]))
            }
        }
        let client = BotClient(connection: saved, configuration: configuration)
        defer { client.close() }
        let result = try await client.listenSpeech(text: "Fixture reply", profile: profile, sessionID: sessionID,
                                                  validateDispatch: {})
        guard case .arc(let bytes) = result else { return XCTFail("Expected ARC speech") }
        XCTAssertEqual(bytes, ARCSpeechFixture.bytes)
        let speechRequests = Array(HermesHostFixture.requests.suffix(3))
        XCTAssertEqual(speechRequests.map { $0.url?.path }, [
            prefix + ARCSpeechFixture.capabilitiesPath, prefix + ARCSpeechFixture.identityPath,
            prefix + ARCSpeechFixture.speakPath
        ])
        XCTAssertEqual(speechRequests.map(\.httpMethod), ["GET", "GET", "POST"])
        for request in speechRequests {
            XCTAssertEqual(request.url?.host, base.host)
            XCTAssertEqual(request.url?.query, "profile=" + profile)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-access")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Access"), "fixture")
        }
        let body = try XCTUnwrap(speechRequests.last.flatMap(apiTestBodyData))
        XCTAssertEqual(try JSONDecoder().decode(BotJSON.self, from: body),
                       .object(["text": .string("Fixture reply"), "session_id": .string(sessionID)]))
    }

    private func connectedClient() async throws -> BotClient {
        let client = BotClient(http: BotSocketHost().connection(record))
        try await client.connect()
        return client
    }
}

/// Synthetic metadata follows ARC identity v1. A historical persona and today's voice
/// selection can come from different Host revisions.
enum ARCSpeechFixture {
    static let sessionID = "local-accepted"
    static let capabilitiesPath = "/api/plugins/arc/v1/capabilities"
    static let identityPath = "/api/plugins/arc/v1/sessions/\(sessionID)/identity"
    static let speakPath = "/api/audio/speak"
    static let bytes = Data([0xFF, 0xF3, 0x18, 0xC4])
    static let capabilities = HermesHostFixture.Reply.json(200, .object([
        "api_version": .number(1), "read_only": .bool(true),
        "session_types": .array([.string("local_dm")]), "speech_context": .string("session_id")
    ]))

    static func identity(sessionID: String = ARCSpeechFixture.sessionID, state: String = "configured") -> HermesHostFixture.Reply {
        let selection: BotJSON = state == "configured" ? .object([
            "binding_revision": .string("7"), "display_name": .string("Fixture Voice"),
            "selection_host_revision": .number(2), "voice_id": .string("fixture-voice")
        ]) : .null
        return .json(200, .object([
            "session_id": .string(sessionID), "persona_revision": .number(1),
            "host_id": .string("b6fdbe73-9f57-4c73-9b19-c30867484c34"), "display_name": .string("Fixture Host"),
            "binding": .object(["installation_id": .string("hermes-install:fixture"), "profile_id": .string("arc-profile:fixture")]),
            "voice": .object(["state": .string(state), "selection": selection])
        ]))
    }

    static func refusal(_ status: Int, _ code: String) -> HermesHostFixture.Reply {
        .json(status, .object(["detail": .object(["code": .string(code), "message": .string("Fixture refusal")])]))
    }

    static func audio(provider: String = "arc") -> HermesHostFixture.Reply {
        .json(200, .object(["ok": .bool(true), "data_url": .string("data:audio/mpeg;base64," + bytes.base64EncodedString()),
                            "mime_type": .string("audio/mpeg"), "provider": .string(provider)]))
    }
}
