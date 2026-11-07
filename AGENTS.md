# ARC Hermes contributor contract

ARC Hermes is the native SwiftUI iPhone and iPad client for ARC Hermes Agent.
The product is the Hermes fork deployed with a required ARC Host identity.
Each gateway is one installed backend authority with one canonical connection
for authentication, native sessions, execution, identity and speech. Webapp
and administration use that same authority.

Connection setup verifies the assigned ARC Host. The normal chat experience
opens and continues existing sessions, creates new sessions, sends, streams,
stops, handles approvals and reconnects. Listen is qualified on a reply in that
same flow. The read-only identity API supplies metadata. Missing ARC capability
or an inconsistent binding is a deployment error.

The app presents the server's accepted identity and voice. Local names, initials
and colors are presentation preferences. Host definitions and persona revisions
belong to ARC's authorized management lifecycle. Multiple gateways can serve
the same Host while retaining their own native session stores and credentials.

The Xcode target and scheme are `ARCHermes`, and the device display name is
`ARC Hermes`. The app, share extension and Live Activity widget route through
the owning gateway. The phone owns interaction, drafts and credential custody.
Hermes owns execution and native session state.

## Product and terminology authority

Hermes Martinez (`martinezhermes`) owns this fork's product decisions.
ACH9001 authors implementation and evidence. Hermex is the application upstream,
and Nous Research Hermes Agent is the runtime upstream. Their source and release
documentation inform compatibility. The reviewed ARC Hermes contracts govern
this product.

- **Host** is the stable, verified ARC identity assigned to a deployment.
- **Gateway** is an installation serving that Host through one backend authority.
- **Connection** is the app's authenticated route to a gateway's canonical base.
- **Profile** is native configuration within that gateway's assigned Host.
- **Session** is a native conversation identified by gateway, profile and session ID.
- **Presentation preferences** are local labels and appearance.
- **Tasks** are scheduled cron jobs. Kanban work units are **Cards**.
- **Slice** is an independently reviewable contribution to a complete user flow.

`CONTEXT.md` defines the domain vocabulary.
`docs/agents/hermes-server.md` defines connection and chat acceptance.
Keep changes small, state ownership explicit and interactions responsive.

## Start with the current state

1. Inspect `git status` and preserve changes you did not create.
2. The selected GitHub issue is the scope and the handoff. Read it with its comments (`gh issue view <n> --comments`) before anything else. Implement only the issue the maintainer selected or one labeled `ready-for-agent`; an open issue list is not an instruction to implement everything.
3. Read the product and connection contracts linked here, then the selected Issue. Resolve a narrower Issue against the required product flow before implementation.
4. On "wrap up": verify the build and tests, commit the validated code, and leave the resumable state (what landed, how it was validated, what is next) as a comment on the issue or in the PR body. A push still needs approval.

## Agent skills and checkout ownership

Use the installed Apple skills by name and read their `SKILL.md` before the
relevant work. Load only the references needed for the selected issue.

| Work | Required skill |
| --- | --- |
| App architecture, state ownership, modules, shared Swift packages | `apple-app-architecture-reviewer` |
| Writing/reviewing Swift, concurrency, Observation, modern APIs | `coding-standards-enforcer` |
| Builds, XCTest, Simulator/device launch, logs and crashes | `build-run-debug` |
| Apple teams, provisioning, capabilities, Keychain/app groups | `signing-entitlements` |
| Git/GitHub implementation identity | `agentic-host-ach9` |
| Independent review and review handoff | `peer-review` |
| Issues, Projects, CI and branch protection | `github-governance` |

Use `agentic-guest-martinezhermes` only for an explicitly authorized owner
operation. A skill does not confer authority to approve the agent's own work.
Do not copy these skill bundles into this repository. If a required skill is
missing, identify it rather than inventing its guidelines. The checked-in
project remains authoritative: Swift 5 language mode, targeted concurrency,
iOS/iPadOS 18+, and the team inherited from `Config/Shared.xcconfig`. Do not migrate
language mode or add architectural layers merely to match a generic example.

The maintainer's main checkout is the Xcode/device workspace. Leave its branch
and files alone while implementing in a temporary, issue-bound worktree from
current `origin/master`. Use `ACH9/issue-<n>-<slug>` and ACH9001 commit authorship;
record the agent engine in a commit trailer, not the author identity. Keep
local signing overrides local and never replace shared signing defaults to
make CI pass.

Before claiming work is saved, account for every intended modified/untracked
file and compare the tested tree with the committed tree. A green isolated
slice does not validate other pending files. Never copy snapshots over a
checkout with Xcode open. After an authorized merge, update the maintainer's
checkout only when clean; use a fast-forward and reload the same Xcode project
if it reports stale/missing files. Verify the actual merged checkout before
handoff. Remove the temporary worktree and branch after the PR is merged or
closed and all intended changes are committed; preserve and report unique work.

## The three ways to hurt yourself

1. **Killing by pattern.** Never `pkill -f`, `pgrep | kill`, or `kill` a PID you found by matching a name, path, or worktree string. Your own agent process has this worktree's path in its argv, and this Mac runs several simulators and agent sessions at once. Kill only a PID you captured at spawn. The same goes for `rm -rf`, `git push --force`, and `simctl shutdown all`: suggest them and let the maintainer run them.
2. **Touching the live server.** The owning ARC Hermes gateways hold real sessions and credentials on cloud and native hosts. Reading from it with `curl` is fine, and the best way to verify a contract (see Working with the server). Never restart it, change its tunnel or Tailscale routes, or run mutations against its sessions. A mutating smoke uses one disposable session you created and cleans up only that session and anything it branched.
3. **Installing an unsigned build.** `CODE_SIGNING_ALLOWED=NO` is for compile-only checks and CI. It strips entitlements, so Keychain writes fail with `errSecMissingEntitlement` and login silently breaks. Put the app on the simulator via XcodeBuildMCP `build_run_sim` or a plain signed Debug build, and never hand-sign a simulator app: a normal sim build is ad-hoc signed and that is exactly what works.

## Hit every surface

The most common defect in this repo is a change that works on the path you tested and is missing everywhere else. Before calling UI work done, walk this list and say which entries applied:

- **Entry points.** A behavior reachable from the chat view is usually also reachable from the session list's context menus, Settings, hardware-keyboard shortcuts, deep links, App Intents, the share extension, and Live Activity taps. Fixing one is not fixing the feature.
- **Targets.** Main app, `ARCHermesShareExtension`, `ARCHermesLiveActivityWidget`, and `ARCHermesTests`. A shared model or resource change needs a target-membership decision for every target that consumes it.
- **Servers.** Multiple configured servers are real. Switch between two and check that credentials, custom headers, cache, drafts, identity, selections, and defaults stay with their server. Read `docs/agents/multi-server-state-isolation.md` before touching auth, server switching, cache keying, or per-server settings.
- **Contracts.** Anything crossing the wire goes through `Endpoint` and a tolerant `Codable` model. Change endpoint construction, request body, decode, and SSE handling together, and verify each against upstream (see Working with the server).
- **Reverse states.** If you added a way in, add the way out and the way to see it. Archive needs restore. Pin needs unpin. Start needs stop. Optimistic mutation needs rollback. A one-way door is a bug.
- **Connection modes.** `localhost`, Tailscale, and tunnel behave differently; Cloudflare closes quiet streams. Backgrounding, reconnecting, and reattaching to a live stream instead of resending the message are real cases.
- **Native quality.** Dynamic Type, VoiceOver labels, Reduce Motion, light and dark appearance, keyboard focus, and localization. Read `docs/agents/i18n.md` before touching the String Catalog, plurals, casing, or RTL.
- **Docs.** Agent conventions live in `docs/agents/`; new vocabulary in `CONTEXT.md`; build and simulator mechanics in `DEVELOPMENT.md`; upstream parity status in `docs/agents/feature-gap-index.md`; Kanban contract and behavior rules in `docs/agents/kanban.md`. `CHANGELOG.md` is written at release time, not per PR.

## Working with the server

- Verify the owning gateway at its canonical HTTPS base, including its deployment prefix. ACH9 cloud uses `https://ach9.hermes.endurance.network/gateways/cloud`.
- Verify native authentication, ARC capabilities and the accepted Host binding during connection setup. Webapp, administration and mobile clients use the same backend authority.
- Inspect the deployed fork revision, native handlers and current protocol before changing requests. `HERMES_AGENT_TESTED_SHA` records client compatibility, and deployment receipts identify the runtime under test. Advance the pin only after the normal chat path passes.
- Qualify the owning gateway's authenticated ticket and WebSocket contract, including its session authority. Fix the client transport when the protocol differs. A separate read-only session browser cannot qualify normal chat.
- Prove both existing-session continuation and new-session creation, sending, streaming, stop, approvals and reconnect before accepting Listen.
- Preserve saved conversations, drafts and credential ownership during reviewed connection migration. `UPSTREAM_TESTED_SHA` and the WebUI reference support migration of existing state.
- Server-facing models decode supported responses tolerantly. Missing required identity or ownership metadata produces an explicit error.
- Keep credentials, private transcripts and provider configuration in approved custody. Add dependencies only with the maintainer's approval.
- Source-verified native gaps require a bounded generic change in the fork. ARC identity and PostgreSQL logic belong in the ARC plugin.

## Test data

A live server is not a test fixture. Unit tests run against `URLProtocol` mocks, Keychain doubles, in-memory SwiftData, and scripted SSE fixtures (`ARCHermesTests/ScriptedSSEStreamFixture.swift`); prefer the established pattern for the area you touch.

- Read-only checks against a live server are fine when the maintainer has put one in scope. Mutation follows rule 2.
- Real credentials, App Store Connect secrets, and tester data stay out of the repo and out of command output.

## Verifying

- Smallest proof that the change works while iterating: focused XCTest for the behavior you touched, via XcodeBuildMCP `test_sim`. Defaults live in `.xcodebuildmcp/config.yaml` (scheme `ARCHermes`, sim **iPhone 17**); if that sim is missing, pick a nearby iPhone and say which.
- **Run `scripts/validate` (the full XCTest suite) before asking for review or committing a slice.** A failing build or test becomes the current task; fix it before writing more code on top.
- Behavior changes ship with focused tests for that behavior.
- Async flows wait on expectations and scripted fixtures, never on sleeps or polling. A test that needs a timeout to pass is wrong.
- UI or runtime changes get one integrated pass in the real app: build, install, and launch a signed Debug build (`build_run_sim`), then hand the maintainer a short manual simulator test plan. Capture screenshots or logs when they are evidence. Subagents do not launch their own builds.
- Run `scripts/check-swift-file-sizes` when a production Swift file grows. It is a warning, not a gate: use it to notice a missing seam, not to force unrelated refactors into the current issue.

## Pull requests

- Never push a branch, open or update a PR, or merge unless the developer explicitly asks you to do so.
- One issue → one `ACH9/issue-<n>-slug` branch → one PR (`ACH9/chore-...` or `ACH9/fix-...` for approved work without an issue). `master` is the internal-TestFlight candidate: keep it buildable, never commit or push implementation directly to it. Platform enforcement is activated through the procedure in `docs/agents/github-control.md`; do not assume it exists from this policy alone.
- Conventional commit titles, plain language: `fix(chat): recover the active stream after foregrounding`.
- Body: follow the PR template. `Fixes #<n>`, the problem in a sentence or two, then how you fixed it and exactly how it was tested. End with the model and harness that did the work.
- UI changes need before/after images. Motion or timing needs a short video.
- Upload PR evidence to GitHub. Never commit PR-only screenshots or assets.
- One concern per PR. If the description says "also", split it.
- When babysitting: poll checks and comments newer than the last push, verify each bot finding against the source, fix real ones, dismiss false positives with a written reason. Stay quiet when nothing is new. Stop when the bots are green on the latest commit.

## Plans and work artifacts

- Do not commit implementation plans, research notes, or agent scratch files. Keep temporary working material outside the worktree.
- Track active maintainer work in the GitHub issue that owns it. Issue, label, and staged-versus-express conventions live in `docs/agents/issue-tracker.md` and `docs/agents/triage-labels.md`. External proposals follow `CONTRIBUTING.md`.
- Put durable architecture, constraints, and decisions in the checked-in docs (`docs/agents/`, `CONTEXT.md`, `DEVELOPMENT.md`). Update those docs when the product changes so agents find current facts instead of abandoned intentions.
- A merged PR is the implementation record. Close or update its issue when the work lands; do not preserve a second checklist in the repository.

## How it works

`ARCHermesApp` owns the scene, `AuthManager`, and the SwiftData container. `ContentView` routes unconfigured, logged-out, and logged-in states; the logged-in subtree is keyed by the active server so a switch rebuilds server-bound views. Feature views own `@MainActor @Observable` _view models_, which call the `APIClient` actor through feature-specific extensions; `Endpoint` centralizes paths and query construction. `SSEClient` decodes chat events, `ChatStreamCoordinator` owns response lifecycle, reconnect, replay, and Live Activity updates, and `KanbanEventStreamClient` handles Kanban live updates. Keychain holds credentials, the server registry, and custom headers; SwiftData holds server-keyed cached sessions and messages; draft and attachment stores keep unsent composer work. The share extension stages imports through the app group; App Intents, deep links, notifications, and Live Activities route the user back into the app.

Canonical vocabulary: `CONTEXT.md`.

## Where code lives

- `ARCHermes/ARCHermesApp.swift` and `ARCHermes/ContentView.swift` - app entry and root routing.
- `ARCHermes/Features/` - feature views, view models, and coordinators for Chat, SessionList, Settings, Workspace, Tasks, Skills, Memory, Insights, Kanban, Onboarding, and Share.
- `ARCHermes/Networking/` - `Endpoint`, `APIClient` and its extensions, SSE, request encoding, API errors.
- `ARCHermes/Models/` - server and presentation models, including the server registry.
- `ARCHermes/Auth/` - authentication and Keychain access.
- `ARCHermes/Persistence/` - SwiftData cache models and stores.
- `ARCHermes/AppIntents/` and `ARCHermes/LiveActivities/` - system entry points and activity coordination.
- `ARCHermesShareExtension/` and `ARCHermesLiveActivityWidget/` - separate targets. Shared files need target-membership checks.
- `ARCHermesTests/` - the XCTest suite, one target directory. Keep tests near the behavior in name and scope.
- `Config/`, `ci/`, and `.github/workflows/` - signing, CI, and release configuration. Treat edits there as release-sensitive. App identity resolves through xcconfig and is not grep-able: bundle ID `com.martinezhermes.archermes`, tests `….tests`, Team `ACBA2466CM`, SKU `hermes-mobile-ios`.
- `.codex-tmp/hermes-webui/` - the read-only reference for existing WebUI data migration.

## Taste

- Complexity belongs at the networking boundary. `Endpoint` and the `APIClient` extensions absorb the server contract, view models own screen state, views stay dumb.
- The server owns execution. The app owns mobile interaction, presentation, drafts, credentials, and the read-only offline cache. Do not move server responsibilities into this repo.
- Make async ownership explicit. Cancellation, stale results, reconnects, and duplicate events are normal mobile conditions; never mutate state after the owning view or task is gone.
- Optimistic UI only when failure has a clear rollback. Never show success before the server says the operation succeeded.
- Destructive and privacy-sensitive actions stay deliberate: file writes, Git operations, server administration, and credential changes get copy that states the real consequence.
- Comments describe how a thing is used, and move when the code moves. To be used mostly to describe functions, not to annotate every line of behavior.
- Our users drive agents from a phone all day and notice a dropped frame, a lying spinner, and a stale label. The intended feel is dense, calm, and operator-grade. No continuously repainting animations; every animation respects Reduce Motion.
- The look is compact and glass-forward: a Liquid-Glass composer with the runtime controls in its bottom row, dense native pickers rather than marketing pages, and no third-party UI packages to get there.
- The target builds in Swift 5 language mode with targeted concurrency. Fix what the build flags, not what strict Swift 6 would.
- If a rule here fights the task in front of you, say so loudly and get a human sign-off before breaking it.

## Branch TestFlight (maintainer-only)

"push to branch testflight" means upload the current branch to the side-by-side **ARC Hermes Branch** internal TestFlight app (`com.martinezhermes.archermes.branch`). It is a TestFlight upload, **not** a git push. Validate first, use a unique `CURRENT_PROJECT_VERSION` (e.g. `YYYYMMDDHHMM`), and follow the archive and export commands in `DEVELOPMENT.md`. Never touch the production `com.martinezhermes.archermes` app, invite testers, or change App Store Connect state unless explicitly asked. `TESTFLIGHT.md` owns release gates.

## Additional tips

- Don't drive the simulator UI or take screenshots unless the user explicitly agrees or the slice needs visual evidence. The maintainer runs the manual checks.
- Surface tradeoffs in plain English before non-obvious choices. Product decisions belong to the maintainer: an issue labeled `ready-for-human` is a question, not a task.
- After each slice, report: (1) files changed (2) build/test command run (3) result (4) next suggested step, plus a short manual simulator test plan when UI changed.
- Security is important, but should not be over-indexed on, especially for dev mode/maintainer-only features. Credential-like values (server URLs, sessions, headers) live in Keychain, not `UserDefaults`.
- If something here surprises you or contradicts the project, tell the developer and propose an `AGENTS.md` edit rather than silently editing it. Every line here is a Band-Aid for what can't be fixed in code, tests, or tooling.
