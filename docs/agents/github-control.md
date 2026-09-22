# ARC Hermes GitHub delivery control

- Repository: [martinezhermes/arc-hermes-app](https://github.com/martinezhermes/arc-hermes-app)
- Project: [ARC Hermes Delivery](https://github.com/users/martinezhermes/projects/10)
- Initial initiative: [Native navigation and maintainability](https://github.com/martinezhermes/arc-hermes-app/issues/1)

## Authority

The repository owns durable architecture, contracts and contributor policy.
GitHub Issues own scope, acceptance, ownership and dependencies. The Project
owns execution status, priority, workstream and scheduling. PRs and checks own
implementation and review evidence. Do not maintain a second roadmap ledger in
Markdown or the Wiki.

The Project is private and owned by `martinezhermes`. `ACH9001` operates it with
Write access using `gh-ach9` and the GitHub Projects API. Owner-level access,
visibility and ownership changes remain owner decisions. Other Projects,
including Endurance Rollout Control, have separate scopes.

## Issue hierarchy

A parent issue describes an outcome. Each child is one independently verifiable
change, linked with GitHub's actual sub-issue relationship. Use actual blocked-by
relationships for prerequisites. The `blocked` label exposes those issues in the
blocked-work view; remove it only after checking that prerequisites have cleared.

Before a child becomes Ready, record scope, exclusions, acceptance criteria,
validation, risk, rollback and implementation/review ownership. A PR closes one
executable child and references its parent. Standalone work states why no parent
is needed. Existing pending changes must have their own disposition rather than
being silently absorbed into the next fix.

## Project fields and views

| Field | Contract |
| --- | --- |
| Status | Backlog, Ready, In progress, In review, Done |
| Priority | Now, Next, Later |
| Workstream | Native navigation; Quality & delivery; Chat architecture; Shared surfaces; Feature cleanup |
| Start Date | Actual start of work |
| Target Date | Owner-scheduled delivery commitment; otherwise blank |

Status board exposes flow. Active delivery excludes Done. Blocked work shows
open dependency gates. Initiatives roadmap presents parent outcomes on the date
axis. Area/risk labels and assignees stay on the issue rather than becoming
additional Project fields.

Auto-add is scoped to this repository's open issues and their sub-issues. Linked
PRs are available through the issue's Linked pull requests field; avoid adding a
duplicate PR item for the same work. Native closure/merge workflows may move
accepted work to Done. Local implementation, a successful build, or an open PR
alone is not Done. In review requires a validated review-ready PR.

## Delivery and review

1. Read the selected issue and comments; inspect and preserve the worktree.
2. Work on an issue-scoped branch using the configured ACH9 prefix.
3. Validate the changed behavior with focused tests and signed runtime evidence.
4. Run the complete repository integration gate before committing or requesting review.
5. Publish a branch/PR only when the maintainer requests it. Include the child,
   parent, risk, validation, data/secrets impact, rollout/rollback and actor identities.
6. Independent human review and acceptance precede merge and Done.

CI and branch-protection implementation is tracked in [#12](https://github.com/martinezhermes/arc-hermes-app/issues/12).
A documented policy is not proof that GitHub enforces it. A required check must
exist and be demonstrated green before making it a branch-protection gate.

See [issue-tracker.md](issue-tracker.md), [triage-labels.md](triage-labels.md),
[../../DEVELOPMENT.md](../../DEVELOPMENT.md) and [../../AGENTS.md](../../AGENTS.md)
for repository-specific execution rules.

## Repository and agent delivery setup

The maintainer's Xcode checkout stays on `master`; implementation uses an
issue-bound temporary worktree. `AGENTS.md` routes Apple work through the
installed architecture, coding, build/debug and signing skills. ACH9001 owns
implementation; `martinezhermes` owns independent review. CODEOWNERS names the
human owner. No repository-specific skill bundle or custom policy engine is
needed.

`scripts/validate` is the local/CI entry point. `.github/workflows/validation.yml`
uses GitHub's `xcode-27` public-preview hosted image, a 25-minute timeout, and
seven-day test artifacts. The public repository uses standard hosted runners;
private forks must account for their own Actions minute allowance and billing.
Preview-image availability and Xcode updates remain external dependencies. CI
uses no private Apple certificate, App Store key, production server or test
account. It validates Simulator behavior and all built targets; it cannot prove
physical microphone, haptics, lock-screen presentation, or device provisioning.

Runner source: https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md

## Activate enforcement after a green published check

The checked-in ruleset is a desired policy, not proof it is active. Preparing
these files does not change GitHub protection, Project ACLs or Actions settings.
Keep issue #12 open until the remote gate is proven and protection is read back.
Its UI-fixture dependency (#4) is separate work and is not completed by CI setup.

1. With publication authorized, push the setup branch and open one PR linked to
   #12 and parent #1. The workflow runs on PRs including drafts.
2. Wait for `Apple validation` on the latest PR head. Investigate failures using
   the uploaded `.xcresult` and build log; do not require a nonexistent check.
3. Hand off only after CI passes. Request `martinezhermes` review, then merge
   only with owner authorization and resolved review findings.
4. With activation authorized, apply `.github/master-ruleset.json` using the
   standard GitHub API. Inspect existing rulesets first; update the matching
   ruleset rather than creating duplicates. For first activation:

   ```sh
   gh-ach9 api repos/martinezhermes/arc-hermes-app/rulesets
   gh-ach9 api --method POST repos/martinezhermes/arc-hermes-app/rulesets \
     --input .github/master-ruleset.json
   gh-ach9 api --method PATCH repos/martinezhermes/arc-hermes-app \
     -F delete_branch_on_merge=true
   ```

5. Read the returned ruleset back and verify enforcement, code-owner approval,
   stale-approval dismissal, resolved conversations, strict `Apple validation`
   checks, and blocked force-push/deletion. There are no agent bypass actors.
6. Fast-forward the clean maintainer checkout, verify signing/build behavior
   there, and remove the completed worktree/local branch. Never discard unique
   commits or pending files as branch cleanup.

If a required runner/check becomes unavailable, repair it on a PR or let the
owner explicitly adjust the ruleset. Never add an agent bypass, fake a passing
check, or weaken signing to clear the gate. Revert this setup through a reviewed
PR if necessary; an owner can disable the identified ruleset through GitHub's
normal UI/API during recovery.
