# ARC Hermes

ARC Hermes is the native SwiftUI iPhone and iPad client for
[ARC Hermes Agent](https://github.com/martinezhermes/arc-hermes-agent).
It connects to the owner's deployed gateways and presents their verified ARC
Host identity, conversations and voice.

## Product contract

ARC Hermes Agent includes the Hermes fork, the ARC identity plugin and an
accepted Host binding. Every gateway exposes one backend authority and one
canonical connection for authentication, sessions, execution, identity and
speech. Webapp and administration use that authority.

One Host can operate through several gateways. ACH9 cloud and Temporal Loom
are separate installations of the same identity. Each keeps its native session
store, credentials and execution environment. The app lists authorized sessions
with their owning gateway and routes every action to that owner.

The app receives Host identity from the authenticated gateway during connection
setup. Persona and voice are governed by ARC's accepted definitions and bindings.
Local names, avatars and colors are presentation preferences.

## Connect and converse

Use the canonical gateway address. ACH9 cloud uses
`https://ach9.hermes.endurance.network/gateways/cloud`.
Sign in through native Hermes authentication, then verify the assigned ARC Host.
Missing identity capability or an inconsistent binding requires deployment repair.

The normal chat flow must open and continue existing conversations, create new
sessions, send messages, stream work, stop, handle approvals and reconnect.
Listen uses the selected conversation's accepted Host identity and approved
server voice in that same chat. Explicitly requested device accessibility
speech has its own action.

The [connection contract](docs/agents/hermes-server.md) defines acceptance.
GitHub Issues and PR evidence establish which implementations have qualified
against a selected runtime and physical device.

## Identity and data ownership

ARC PostgreSQL owns Host definitions, revisions and gateway/profile bindings.
The ARC plugin projects the accepted persona into native `SOUL.md`.
Hermes owns loading, execution and its SQLite sessions. The app reads identity
through gateway APIs and keeps credentials in Keychain and drafts in their
owning connection scope.

Existing saved connections, drafts and transcripts are preserved through
reviewed migration. Connection aliases are reconciled against verified
installation and Host identities. The product uses one backend connection per
gateway throughout that migration.

## Development

The Xcode project and app scheme are `ARCHermes`. Follow
[DEVELOPMENT.md](DEVELOPMENT.md) for the toolchain and signed builds, and
[TESTFLIGHT.md](TESTFLIGHT.md) for distribution.

Run `scripts/validate` before publishing a change. The governing references
are [AGENTS.md](AGENTS.md), [CONTEXT.md](CONTEXT.md) and the
[delivery contract](docs/agents/github-control.md).
[GitHub Issues](https://github.com/martinezhermes/arc-hermes-app/issues) own active
scope, dependencies and acceptance.

## Upstream and license

Hermex supplies the native application foundation. Nous Research Hermes Agent
supplies the runtime and native protocol. ARC Hermes maintains its product
contract through the owned forks and ARC plugin.

The application uses the MIT license. See [LICENSE](LICENSE) and
[CONTRIBUTING.md](CONTRIBUTING.md). The workspace icons derive from Pierre's
`@pierre/trees` under Apache-2.0 and T3 Code under MIT.
