# Contributing to ARCHermes

Thanks for your interest in contributing! This document covers local setup,
running tests, code signing for contributors, and the PR workflow. Please also
read the [Code of Conduct](CODE_OF_CONDUCT.md).

## Local setup

- **Xcode 27 or newer**, with an iOS 27 simulator for the primary validation suite. The deployment target is iOS/iPadOS 18; older-system compatibility also needs runtime checks on 18 and 26.
- Clone the repo and open `ARCHermes.xcodeproj`. Dependencies resolve
  automatically via Swift Package Manager — the dependency list is locked in
  `AGENTS.md`; do not add new ones without maintainer approval.
- Build and run the **`ARCHermes`** scheme on an iPhone simulator
  (`iPhone 17` is the reference device; any recent iPhone simulator works).
- Use an ARC Hermes Agent gateway with an accepted Host binding and one
  canonical backend connection. The [product contract](README.md#product-contract)
  and [connection contract](docs/agents/hermes-server.md) define normal chat,
  verified identity and Listen acceptance.

## Running tests

The full XCTest suite is the repo's green bar — it must pass before any PR:

```zsh
scripts/validate
```

The default destination is iPhone 17, iOS 27.0. Set `ARCHERMES_DESTINATION` to
another supported destination from `xcrun simctl list devices available` if
needed. The command prints its checkout, commit, toolchain and evidence path.
`ARCHERMES_VALIDATION_DIR` must be a fresh output directory; `ARCHERMES_DERIVED_DATA`
can reuse a build cache. It uses the debugger-free `ARCHermesValidation` scheme,
which runs the complete `ARCHermesTests` target.

The proposed GitHub workflow uses the same command on the hosted `xcode-27`
runner, without Apple account credentials or server secrets. Simulator builds
retain normal ad-hoc signing. See [delivery control](docs/agents/github-control.md)
for activation and the difference between prepared and enforced CI.

## Code signing for contributors

The project's committed signing identity (`DEVELOPMENT_TEAM`, bundle IDs)
belongs to the maintainer. **Never edit `project.pbxproj` to sign with your own
team** — override locally instead:

1. Create `Config/Local.xcconfig` (it is gitignored, so it never lands in a PR):

   ```xcconfig
   DEVELOPMENT_TEAM = YOUR_TEAM_ID
   // Optional — only needed if provisioning complains about the bundle ID.
   // The app-group entitlement must stay in sync with the bundle ID.
   // APP_BUNDLE_IDENTIFIER = com.yourname.archermes
   // APP_GROUP_IDENTIFIER = group.com.yourname.archermes
   ```

2. Build normally. `Config/Shared.xcconfig` is wired into the project and ends
   with `#include? "Local.xcconfig"`, so your local values override the
   committed defaults for every target — no project-file changes needed.

For simulator-only development you usually don't need any of this: simulator
builds don't require a paid team. The validation command retains signing. `CODE_SIGNING_ALLOWED=NO` is only
for explicit compile-only checks; do not install an unsigned build for tests
or manual use because it breaks Keychain entitlements (see `AGENTS.md`).

## What PRs we welcome (and what we don't)

Bug fixes, test coverage, and focused improvements are always welcome. For
anything larger than a small fix, **open an issue first and wait for a
maintainer nod before writing code** — it protects your time as much as the
review queue. Drive-by rewrites, reformat-the-world diffs, and unannounced
architecture overhauls will be closed without detailed review.

Keep each PR to **one logical change** with a reviewable diff. If a change is
independently useful, it deserves its own PR.

## App bug or server bug?

Reproduce the operation through the same owning ARC Hermes gateway and verify
the deployed native contract. Compare the native Webapp and iOS behavior with
their actual authenticated request and session ownership. Record whether the
failure is in client transport, native execution or ARC identity. Source-verified
generic runtime defects belong in the fork and its upstream integration path.
The app Issue links that evidence and owns the client behavior.

## PR workflow

1. **Start from an issue.** Every change should trace to a GitHub issue —
   comment on it so work isn't duplicated, or open one first (bug/feature
   templates are provided).
2. **Branch** from current `master`. ACH9 implementation uses
   `ACH9/issue-<number>-<short-slug>`.
3. **Make the change**, keeping these repo hard rules (full list in
   [`AGENTS.md`](AGENTS.md)):
   - **Tolerant decoding:** accept additive fields and explicitly validate
     required identity and ownership metadata.
   - **Never invent API endpoints or JSON shapes** — verify against the pinned
     native fork source and the owning gateway under qualification.
   - **No new third-party dependencies** without approval.
4. **Run the full test suite** (command above) and make sure it passes.
5. **Open a PR** against `master` using the PR template — link the issue with
   `Fixes #<number>`, describe what changed and how you tested it. CI must be
   green; automated review bots may comment, and the maintainer reviews and
   merges.
6. **Disclose AI usage** in one line of the PR description: the tool/model
   used (e.g. "built with Claude Code"), or "human-authored". This repo is
   itself built with coding agents, so it's normal context for review — not a
   gate.

`master` is the release-candidate branch. Do not deliver changes directly to it.
Required-review/check enforcement is activated only after the workflow is
proven green; see [delivery control](docs/agents/github-control.md). Releases
and TestFlight uploads are separate maintainer-only operations described in
`TESTFLIGHT.md`; validation never uploads a build.

## Questions

Ask in [GitHub Issues](https://github.com/martinezhermes/arc-hermes-app/issues)
if something here is unclear or wrong — docs fixes are welcome contributions
too.
