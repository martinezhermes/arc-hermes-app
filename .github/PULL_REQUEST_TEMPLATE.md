<!-- Read CONTRIBUTING.md and docs/agents/github-control.md before opening a PR. -->

## Linked work

Closes #
Refs # <!-- Parent issue, or explain why this is standalone. -->

## Problem and resulting behavior

<!-- Describe the concrete trigger and before/after behavior. Keep one executable gate per PR. -->

## Validation

<!-- Commands, toolchain/destination, results, and any limitations. UI changes need before/after evidence. -->

## Risk and rollback

<!-- What can regress? How is this change safely rolled back? -->

## Data and secrets impact

<!-- Server contracts, persistence, credentials, permissions, signing, and live mutation: state the actual impact or none. -->

## Ownership

<!-- Name the implementation actor, independent reviewer, model and harness. Do not represent agent work as owner approval. -->

## Checklist

- [ ] The full XCTest suite passes on a supported iOS 27+ destination; failures are not hidden or silently skipped
- [ ] Changed UI/runtime behavior has signed build and relevant device/simulator evidence
- [ ] Shared changes cover the main app, share extension, widget and tests where applicable
- [ ] Server-facing models decode tolerantly and wire contracts are verified when changed
- [ ] Per-server state, cancellation and stale-result behavior remain correct
- [ ] No new third-party dependency without approval
- [ ] Linked issue/parent, scope and validation evidence are ready for independent review
