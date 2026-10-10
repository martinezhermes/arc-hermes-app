# Hermex upstream integration

The application upstream is `https://github.com/uzairansaruzi/hermex.git`, branch
`master`. `origin` remains the ARC fork. Application syncs preserve upstream Git
ancestry and ARC's app-owned names. `UPSTREAM_TESTED_SHA` and
`HERMES_AGENT_TESTED_SHA` track backend compatibility, not the application merge
parent; advance them only after their live contract validation.

## Prepare one integration gate

Create a child gate under the selected migration or delivery initiative. Record
the ARC base and exact upstream commit. Inventory pending checkout changes and
unpublished Agent prototypes separately; preserve them before integrating a
replacement. Work in an issue-bound worktree from current `origin/master` and
leave the maintainer's Xcode checkout unchanged.

Fetch upstream without executing its scripts. Merge the reviewed SHA using
standard Git, allowing new files to follow the recorded directory moves:

```sh
git fetch --no-tags upstream master
git rev-parse upstream/master
git -c merge.directoryRenames=true -c rerere.enabled=true \
  -c rerere.autoupdate=false merge --no-ff --no-commit <reviewed-upstream-sha>
```

`rerere` can reuse prior resolutions, but review the resulting changes before
staging. Record reviewed resolutions with `git -c rerere.enabled=true rerere`.
Keep the merge commit in the integration PR and use GitHub's merge-commit method
when that PR is accepted, preserving the upstream parent for the next sync.

## Preserve the ARC boundary

| Upstream directory/module | ARC directory/module |
| --- | --- |
| `HermesMobile` | `ARCHermes` |
| `HermesMobileTests` | `ARCHermesTests` |
| `HermesShareExtension` | `ARCHermesShareExtension` |
| `HermesLiveActivityWidget` | `ARCHermesLiveActivityWidget` |
| `HermesNotificationService` | `ARCHermesNotificationService` |

Git follows file moves; new file contents still need their exact app-owned
identifier mappings. Adapt module imports, commands, focused values, deep-link
helpers and target/resource membership using the existing refactor as evidence.
Backend types and wire names still describe Hermes Agent and retain their
protocol identity. Review app text and localization keys deliberately rather
than replacing every occurrence of Hermes or Hermex.

Preserve the ARC bundle identifiers, app groups, Keychain service, shared Apple
team defaults, iOS 27 policy, Swift language mode, icons and themes. Reconcile
the Xcode project and incoming workflow/test paths with those values.

Resolve behavior conflicts individually. Reuse the proven ARC adaptive
navigation and interaction where it meets the feature contract; connect the
upstream Agent transport/coordinators underneath the shared screens. Inventory
the #44–47 Agent prototypes as recoverable work, but do not import their
parallel onboarding, connection or session viewer. Upstream owns those paths. A new upstream phone navigation surface does not by
itself establish iPad or native macOS parity.

## Validate and hand off

Run focused checks while resolving changes, then `scripts/validate` on the exact
candidate. Verify app, share extension, widget and tests, plus signed iPhone/iPad
behavior, server isolation and backend compatibility for changed paths. Publish
the branch/PR only when authorized, require green `Apple validation` on its latest
head and independent review, and merge only with the maintainer's acceptance.
CI execution and conflict resolution do not grant merge approval. Record the
upstream SHA, retained ARC changes and validation in the PR; use smaller regular
syncs after the initial catch-up.

## Native connection limits

Upstream's integrated form detects the backend and gates Hermes behind Bot Mode
beta opt-in. Native Sessions and Bots use the shared Hermes connection. The main
chat, feature clients, caches and server registry support a Hermes server kind;
WebUI remains available for recovery and features whose native contract is absent.
System new-chat/share/session-link routes and workspace/Git screens still have
WebUI dependencies. The upstream native home uses its own stack and bottom bar;
retaining ARC's legacy sidebar tests does not establish identical native iPad layout.

The minimum Hermes release is independent of ARC's last live validation pin.
A fork's marketing version is not evidence of an equivalent gateway contract;
verify its provenance and live behavior before adding an exception. Captured
upstream fixtures keep their own provenance next to their manifest, separate from
`HERMES_AGENT_TESTED_SHA`. Advancing either live compatibility pin still requires
AGENTS.md's read-only/auth and disposable-session checks.

The imported notification extension shares only push pairing keys with the app;
existing credentials retain their default Keychain group. Upstream's relay accepts
its own bundle identifiers, so ARC's identity is unsupported until a separately
approved relay/APNs integration exists. Provisioning refuses unsupported builds
before touching a host. No ARC relay or automatic push setup is introduced.
