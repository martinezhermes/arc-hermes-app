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
