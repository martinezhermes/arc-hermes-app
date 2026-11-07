# Development

Develop ARC Hermes against the canonical backend of an ARC Hermes Agent
deployment. The product requires a verified ARC Host identity and normal chat.
See [README.md](README.md), [AGENTS.md](AGENTS.md) and the
[connection contract](docs/agents/hermes-server.md).

TestFlight and App Store Connect operations require an explicit maintainer
publication request and the appropriate Apple account access.

## Gateway qualification target

ACH9 cloud uses `https://ach9.hermes.endurance.network/gateways/cloud`.
Use native sign-in and keep the deployment prefix on requests. Resolve the
authorized ARC Host and binding during connection setup.

Qualification opens and continues an existing conversation, creates a new one,
sends, streams, stops, handles approvals and reconnects through that same
backend. Listen follows on a real reply in the normal chat UI.

## Native contract and local fixtures

`HERMES_AGENT_TESTED_SHA` records native client compatibility. Inspect the
deployed fork revision and its handlers before changing the transport. Qualify
the owning gateway's ticket, WebSocket and session-authority protocol. Verify
all identity and chat operations through its canonical connection.

Local fixtures exercise the same client entry points with synthetic
identity/session data. Their results are protocol evidence. Authenticated
deployment qualification and physical playback have their own acceptance.
Use an isolated profile for local runtime fixtures and scope live mutations
to an owned test conversation.

`UPSTREAM_TESTED_SHA` and the older WebUI adapters support reviewed migration
of existing saved state. The product connection is the ARC Hermes gateway.

## One validation command

Run `scripts/validate` from the checkout you intend to deliver. It uses the
complete `ARCHermesTests` target through `ARCHermesValidation`, serial Simulator
execution, normal signing, and saves an `.xcresult` plus build log outside the
repository. It never changes Xcode selection, contacts a server, installs on a
phone, or uploads to TestFlight. See `CONTRIBUTING.md` for output/destination
overrides. Physical-device signing and interaction remain separate evidence.

## Local Validation With XcodeBuildMCP

Defaults and the verification flow live in `AGENTS.md` § Verifying. Human/CLI equivalents:

```zsh
xcodebuildmcp simulator list --enabled
```

```zsh
xcodebuildmcp simulator test --output jsonl
```

```zsh
xcodebuildmcp simulator build-and-run --output jsonl
```

Update `.xcodebuildmcp/config.yaml` only when a new simulator should become the shared repo default.

### Signing a simulator in

Each simulator has its own Keychain, so a fresh or erased one starts logged out. When the installed Debug build shows the login screen (or Bots has no connection), run:

```zsh
HERMEX_BUNDLE_ID=com.martinezhermes.archermes scripts/sim-login <simulator-udid>
```

It relaunches the app with `HERMEX_DEV_*` environment variables read from the macOS Keychain; `DevAutoLogin.swift` (DEBUG builds only) signs in through the normal login paths. Nothing is printed and nothing is stored in the repo. One-time setup, prompting for each password:

```zsh
security add-generic-password -s hermex-webui -a <server-host> -w
security add-generic-password -s hermex-bot -a <bot-username> -j <bot-address> -w
```

`hermex-bot` is optional; with it the script also saves the Bot connection and turns Bot Mode on.

`HERMEX_BUNDLE_ID=com.martinezhermes.archermes scripts/sim-login <simulator-udid> --hermes` also adds a Hermes server at the `hermex-bot` address, signed in with the same username and password, and opens it once per launch; switching away afterwards sticks until the next run. It needs `hermex-bot`, or all three of `HERMEX_BOT_ADDRESS`, `HERMEX_BOT_USERNAME` and `HERMEX_BOT_PASSWORD` in the environment, which replace the Keychain item for that run. Without `--hermes` the script behaves as before.

### Local Hermes test server

For tool and approval turns without a real model or the real host, run the pinned hermes-agent on this Mac:

```zsh
scripts/local-hermes
```

The root compatibility pin can lag imported upstream fixtures; do not treat this fixture as proof of the new Agent contracts or bump that pin without the live checks in `AGENTS.md`.

The first run clones the commit in `HERMES_AGENT_TESTED_SHA` into `~/Library/Caches/hermex-local-hermes/` and installs it with `uv` (network needed); later runs start in seconds. It serves `http://127.0.0.1:9199` with the credentials it prints (`hermex` / `hermex-local`), backed by a scripted stub model: every turn says "Let me run a quick check.", asks to run `python3 -c "print(1)"` behind a manual approval, then replies "The command returned: …" with the result or the denial. **Approving really runs that command on this Mac.** Each run uses a temporary Hermes home, deleted on exit, with a fixed install id, so a saved connection keeps working across restarts. Ctrl-C stops only the process group the script started.

It listens on loopback, so only the simulator can reach it. To open it as a Hermes server, run:

```zsh
HERMEX_BOT_ADDRESS=http://127.0.0.1:9199 HERMEX_BOT_USERNAME=hermex HERMEX_BOT_PASSWORD=hermex-local \
  HERMEX_BUNDLE_ID=com.martinezhermes.archermes scripts/sim-login <simulator-udid> --hermes
```

Use fixture connections only for their named synthetic protocol checks. Real ARC Hermes qualification uses the canonical enrolled gateway and the normal chat acceptance above.

## Launch arguments and profiling

Debug builds read these launch arguments; Release builds compile none of them in.

| Argument | What it does |
|---|---|
| `--rating-prompt-eligible` | Makes this launch eligible for the App Store rating prompt, so its real navigation and stream guards can be exercised. It rewrites the stored rating and tip-jar counters. |
| `--stale-runtime-send` | Fails the first chat send of this launch with hermes-webui's `agent_runtime_stale` 409 instead of sending it, so the composer's restart banner and **Copy fix prompt** can be checked without updating Hermes on a server (#955). Later sends go to the server as usual. |
| `--hitch-meter` | Shows a frame-hitch readout in the top-leading corner, such as `12.4 ms/s · 3 hitches · 60 Hz`: late-frame milliseconds per second, hitch count, and the refresh rate the display link reports, over the last second. It takes no touches, VoiceOver skips it, and it updates at most twice a second. |

```zsh
xcrun simctl launch <simulator-udid> com.martinezhermes.archermes --hitch-meter
```

The `HERMEX_DEV_*` environment variables (`HERMEX_DEV_SERVER_URL`, `HERMEX_DEV_PASSWORD`, `HERMEX_DEV_BOT_ADDRESS`/`_USERNAME`/`_PASSWORD`, and `HERMEX_DEV_HERMES_SERVER=1` for a Hermes server) sign a Debug build in; `scripts/sim-login` sets them from the macOS Keychain (§ Signing a simulator in).

### Recording signposts

`ARCHermes/Config/PerformanceSignposts.swift` marks six intervals in every build, under the bundle ID as subsystem (`com.martinezhermes.archermes`, or `com.martinezhermes.archermes` for Hermex Branch) and category `Performance`. Metadata is counts only; never add text, titles, paths, URLs, or IDs.

| Interval | Measures | Metadata |
|---|---|---|
| `Session Open` | A session-list open (tap or keyboard) to the first transcript frame, or to the empty state when the transcript is empty | `messages` |
| `Transcript Apply` | Painting the cached transcript, or applying a reloaded one | `messages` |
| `Markdown Parse` | Parsing one markdown block | `chars` |
| `Stream Batch Apply` | Applying one batch of streamed tokens | `mutated` (0 or 1) |
| `Cache Read` | A SwiftData read of cached sessions or messages | `rows` |
| `Cache Write` | A SwiftData write of cached sessions or messages | `rows` |

In Xcode: Product → Profile (a Release build), choose the Animation Hitches or Time Profiler template, add the `os_signpost` instrument from the library, and filter it by the subsystem and category `Performance`.

From the command line, with the app running on a simulator (`--attach` takes the app's display name, `Hermex`), then print the recorded intervals as XML:

```zsh
xcrun xctrace record --template 'Time Profiler' --instrument os_signpost \
  --device <simulator-udid> --attach Hermex --time-limit 30s --output /tmp/hermex.trace
xcrun xctrace export --input /tmp/hermex.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="OSSignpostIntervals"][1]'
```

### Watching the Bot connection log

`HermesConnection` logs Bot sign-ins and the gateway socket's lifecycle under the bundle ID as subsystem and the category `HermesConnection` (`docs/agents/bots.md`). In Console.app, select a cabled iPhone, start streaming, and filter `subsystem:com.martinezhermes.archermes category:HermesConnection` (`com.martinezhermes.archermes` for Hermex Branch). Check it on a device: the simulator's `log show` doesn't show these lines.

## Swift File-Size Policy

`scripts/check-swift-file-sizes` warns on production app Swift files (`ARCHermes/`) over 500 LOC; tests, generated files, preview files, the share extension, and the live activity widget are exempt. It exits successfully even with warnings — it makes drift visible without blocking current work. Override the threshold for local experiments with `ARCHERMES_SWIFT_FILE_SIZE_LIMIT=300 scripts/check-swift-file-sizes`.

## Supported OS and Concurrency

Signing is inherited by all targets from `Config/Shared.xcconfig`, using Hermes's
Apple team `ACBA2466CM`. `E7A828PV52` appears in the development certificate's
display name but is not its team ID. Do not add target-level or simulator-only
team overrides: they mask the shared configuration and can break signing when
switching branches. Contributors can use the ignored `Config/Local.xcconfig`.

The app, share extension, Live Activity widget, notification service extension,
and test target deploy to iOS/iPadOS 18.0 or newer and build with Xcode 27+.
Use an iOS 27 simulator for the primary validation suite; compatibility changes
also need runtime checks on iOS/iPadOS 18 and 26 when available.
The deployment target controls the oldest supported OS, independently of the
Xcode/SDK version used to build.
Swift language mode remains 5 with targeted concurrency checking;
`InferSendableFromCaptures` enables checked sendability inference for immutable
key-path literals, including SwiftData predicates.

Audio activation/deactivation uses the iOS 27 asynchronous APIs through
`AudioSessionCoordinator`. On iOS 18–26, a dedicated actor runs the older blocking
`setActive` API off the main actor. Every playback/capture owns a token; only
releasing the last owner deactivates the session. Capture keeps priority over
playback. Tests use an injected driver and explicit continuations, with no
microphone hardware.

Newer-system UI remains availability-gated: Liquid Glass uses standard materials
on iOS 18, pinned session headers use `safeAreaInset` before iOS 26, and native
soft scroll edges and toolbar spacers apply only where supported. Keep these
fallbacks in the existing adaptive view helpers rather than duplicating screens.
For an installed older simulator runtime, run the same suite with
`ARCHERMES_DESTINATION='platform=iOS Simulator,id=<simulator-udid>' scripts/validate`.
On older hardware, check session-header placement, the keyboard/composer,
recording/playback handoffs, share import, and Live Activity routing as well as
streaming and foreground recovery.

The hosted test bundle uses the app’s linked MarkdownUI implementation. Do not
add a second MarkdownUI package-product link to the test target: Xcode then
repackages its transitive C modules as frameworks and emits a module-map warning.

## Raw xcodebuild Fallback

Use raw `xcodebuild` when XcodeBuildMCP is unavailable, when validating lower-level build failures, or when matching the GitHub Actions release/archive commands exactly. The TestFlight workflows continue to use raw `xcodebuild` and are not replaced by XcodeBuildMCP.

List available simulators:

```zsh
xcrun simctl list devices available
```

Build for an available iPhone simulator:

```zsh
xcodebuild -project ARCHermes.xcodeproj -scheme ARCHermes -destination 'platform=iOS Simulator,name=iPhone 17' build
```

If `iPhone 17` is not installed, choose a nearby available iPhone simulator.

## TestFlight

Production internal/external uploads, signing setup, release gates, and review notes
live in [`TESTFLIGHT.md`](TESTFLIGHT.md). The separate branch-app upload is below.

### Branch TestFlight upload (CLI) — the "push to branch testflight" command

When the owner says **"push to branch testflight"**, upload the current *feature branch*
to the side-by-side **ARC Hermes Branch** internal TestFlight app. This is a TestFlight
upload, **not** a Git push. Never merge, Git push, or upload the production
`com.martinezhermes.archermes` TestFlight app unless the owner explicitly asks.

Branch TestFlight app identity:

- App Store Connect app name: `ARC Hermes Branch`
- Main bundle ID: `com.martinezhermes.archermes.branch`
- Share extension bundle ID: `com.martinezhermes.archermes.branch.shareextension`
- Live Activity widget bundle ID: `com.martinezhermes.archermes.branch.liveactivitywidget`
- Display name: `ARC Hermes Branch`
- App group: `group.com.martinezhermes.archermes.branch`
- URL scheme: `hermes-agent-branch`
- SKU: `hermes-mobile-ios-branch`

Steps:

1. Validate the branch first: at minimum `git diff --check` plus a simulator build; run
   focused or full tests based on the branch's risk.
2. Use a unique `CURRENT_PROJECT_VERSION` for every upload — prefer a timestamp-like
   number such as `YYYYMMDDHHMM`.
3. Archive with the reusable branch build config `Config/BranchTestFlight.xcconfig`:

   ```zsh
   xcodebuild -project ARCHermes.xcodeproj -scheme ARCHermes -configuration Release \
     -destination 'generic/platform=iOS' -archivePath build/HermesAgentBranch.xcarchive \
     -xcconfig Config/BranchTestFlight.xcconfig CURRENT_PROJECT_VERSION=<unique-build-number> \
     archive -allowProvisioningUpdates
   ```

4. Upload with the reusable export config `Config/BranchTestFlightExportOptions.plist`:

   ```zsh
   xcodebuild -exportArchive -archivePath build/HermesAgentBranch.xcarchive \
     -exportOptionsPlist Config/BranchTestFlightExportOptions.plist \
     -exportPath build/HermesAgentBranchExport -allowProvisioningUpdates
   ```

5. After upload succeeds, tell the owner the version/build number and that App Store
   Connect/TestFlight may need processing time before it appears on the phone.

## Full-App Manual Regression Checklist

Use this before internal TestFlight smoke builds and again before adding external testers.
Capture bugs, polish notes, and follow-up ideas in [GitHub Issues](https://github.com/uzairansaruzi/hermex/issues).

### Onboarding/Auth
- Fresh install opens onboarding.
- Valid server URL + password logs in.
- Wrong password shows clear error.
- Server/tunnel down shows useful error.
- Sign out and reconfigure returns to onboarding.

### Sessions
- Load sessions online.
- Pull to refresh.
- Search sessions.
- Create new session.
- Pin/unpin.
- Archive/restore.
- Move to project and back to no project.
- Duplicate/fork.
- Delete disposable session only.
- Offline cached session list displays clearly.

### Chat/Streaming
- Open existing session at latest message.
- Send normal message.
- Watch response stream.
- Stop response.
- Send while streaming using each configured behavior.
- Background/foreground during active stream.
- Long response over 2 minutes.
- Network interruption recovery.
- Offline cached transcript is read-only.

### Message Actions
- User message: edit, fork, copy.
- Assistant message: listen, stop listening, select text, regenerate, fork, copy.
- Older edit/regenerate shows discard warning.
- Local assistant command cards do not expose destructive message actions.

### Composer
- Model picker and favorites/recents.
- Reasoning picker.
- Workspace picker.
- Profile switch, including new-session confirmation.
- Attach file.
- Capture a photo with the camera; check denial, cancellation, and attachment import.
- Attach one photo.
- Attach multiple photos.
- Paste image/file.
- Failed upload preserves draft.
- Voice input allowed, denied, stopped, and sent.
- Haptics on send/response completion on device.

### Slash Commands
- `/help`
- `/new`
- `/model`
- `/workspace`
- `/reasoning`
- `/title`
- `/personality`
- `/skills`
- Direct skill slash shortcut.
- `/queue`
- `/steer`
- `/interrupt`
- `/status`
- `/btw`
- `/background` and `/bg`
- `/branch` and `/fork`
- `/undo`
- `/retry`
- `/compress` and `/compact`
- Unsupported commands show friendly local message.

### Server Panels
- Files list/search.
- Text file preview.
- Image preview.
- Unsupported binary preview.
- Tasks list/detail/output.
- Skills list/search/detail/linked file.
- Memory notes/profile.
- Usage analytics timeframe switching.

### Polish/Launch
- Light and dark mode.
- Portrait and landscape.
- Largest Dynamic Type.
- VoiceOver core path.
- App icon visible.
- Launch screen acceptable.
- Privacy permission prompts readable.
- TestFlight install path documented.

## Optional App Store Connect CLI helper

`scripts/app-store` runs `asc` in read-only mode by default. Configure
`ARCHERMES_ASC_APP_ID` and `ARCHERMES_ASC_PROFILE` explicitly for the intended ARC
Hermes app and local authentication profile; the wrapper never selects upstream's
app or account. `--write` is only for an explicitly authorized maintainer operation.
The existing archive/export and release gates above remain authoritative.
