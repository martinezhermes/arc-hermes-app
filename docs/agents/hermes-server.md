# ARC Hermes gateway connection

This is the product contract for the native app's connection, identity and
normal chat flow. Runtime and device evidence belongs in the implementing
Issues and PRs.

## One backend per gateway

A gateway is one ARC Hermes Agent installation with a required ARC Host binding.
It has one backend authority for authentication, native session ownership,
execution, identity and speech. Webapp and administration are interfaces to that
authority.

The app stores the canonical gateway base, including its deployment prefix.
ACH9 cloud uses `https://ach9.hermes.endurance.network/gateways/cloud`.
Every HTTP request, socket, file operation and speech request retains the
selected gateway and native profile. Administrative UI paths are presentation
routes within that gateway.

Separate computers are separate gateways. Each has its own installation ID,
credentials and session store while presenting the same enrolled ARC Host.
The app groups sessions by verified Host membership and routes each operation
to its owning gateway.

## Identity and connection admission

Native authentication establishes the caller. The public `/api/status`
installation ID identifies the runtime installation. ARC's authenticated v1
API supplies the assigned Host and accepted binding.

After signing in, include the selected native `?profile=` selector when
reading `/capabilities`, `/hosts` and `/hosts/{host_id}/bindings` under
`/api/plugins/arc/v1` on the same connection. The authenticated binding
response establishes enrollment for that selector. Compare the binding's
`installation_id` with the native `/api/status` `install_id` prefixed by
`hermes-install:`.

Keep the returned opaque `profile_id` with the selected native profile
selector, accepted Host ID and gateway connection. Verify the binding again
when the selected profile changes before admitting chat for that profile.
Treat missing ARC routes, an empty Host result, an unavailable binding or
an installation mismatch as a deployment setup error.

Use `/api/plugins/arc/v1/sessions/{session_id}/identity` for the exact
conversation's accepted Host and persona revision. The current approved voice
selection has its own revision. Historical persona revisions remain attached
to their native conversations. Identity editing uses ARC's authorized
management lifecycle. Client name, initials and color settings are presentation.

The [ARC identity API](https://github.com/martinezhermes/arc/blob/main/integrations/hermes-plugin-arc/IDENTITY-API.md)
owns these wire shapes. The app reads them through the gateway.

## Native authentication and transport

Reuse native password or supported browser sign-in and the existing scoped
credential store. Each gateway connection owns its credentials, cookies,
tickets and refresh lifecycle. Secrets stay in Keychain or request memory and
are sent only to the verified connection.

Qualify the exact native ticket and WebSocket path served by the owning gateway.
A `session_authority` handshake identifies the gateway's session protocol.
The client must support that protocol through its normal conversation engine.
Treat incompatible protocol or authentication as an explicit connection error.

Use current fork handlers and the deployed revision alongside
`HERMES_AGENT_TESTED_SHA` when implementing transport. Record the exact
request, response and event contract in the implementation review. Client
capabilities and source inspection establish supported behavior together with
an authenticated integration test.

## Normal conversation lifecycle

The same connection supports these actions in the existing chat UI.

- Open an existing session and continue it on its native owner.
- Create a new session on the selected gateway and receive its canonical reference.
- Submit a turn and render streamed answer, tool and completion events.
- Stop execution and answer the owning session's approval or clarification request.
- Reconnect after backgrounding or transport loss using native receipts and replay.
- Preserve drafts and reject stale work after a gateway, profile or session change.

References include gateway installation, native profile and session ID.
Runtime handles and stored conversation IDs retain their native meanings.
An uncertain submission is reconciled through its native receipt before a
user-directed retry. An offline cache is labelled with its availability.
Online acceptance requires the complete conversation flow.

## Listen in the same chat

Listen uses the selected reply and the exact accepted session identity.
Send native `POST /api/audio/speak` on the owning connection and profile with
`text` and `session_id`. Verify the returned provider and supported audio,
then play it through the native controls.

Identity, configuration, synthesis and playback failures remain visible.
A missing ARC route is an identity deployment failure. Device accessibility
speech is a separately requested action. Qualify Listen after normal chat
works on that same gateway and obtain the owner's audible voice confirmation
on the physical iPhone.

## State and migration

Reuse the existing connection, native chat and Keychain abstractions. Connection
changes cancel stale requests and clear only the affected private cache.
Preserve saved conversations and drafts when reconciling old address aliases.
Verify installation ID and ARC Host membership before translating a saved
reference. Product connections continue to use one canonical backend per gateway.

`UPSTREAM_TESTED_SHA` and older WebUI adapters may supply migration evidence for
existing state. Review migration separately with its exact data boundary.
Source and deployment review precede changes to serving routes or state.

## Evidence and observability

Record source/build revisions, the owning gateway route, safe binding metadata
and completed user actions. Keep credentials, transcripts, raw requests and
reference audio out of logs and GitHub evidence. HTTP success, isolated identity
reads and synthesized audio each establish only the operation exercised.

The client gate covers new and existing chat, approvals, reconnect and Listen
on the physical device. Multiple-gateway acceptance also verifies correct
routing with duplicate local session IDs and one offline gateway.
