# ARC Hermes domain

Canonical language for the ARC Hermes product, planning and support.

## Hosts, gateways and conversations

| Term | Meaning |
| --- | --- |
| ARC Hermes Agent | The Hermes fork deployed with the ARC plugin and a required accepted Host binding. |
| Host | Stable ARC identity defined in PostgreSQL and presented by its enrolled gateways. |
| Gateway | One installation and backend authority serving its assigned Host. |
| Connection | The app's authenticated route to a gateway's canonical base URL. |
| Installation ID | Native Hermes identity for the gateway installation. |
| Profile | Native configuration within the gateway's assigned Host. |
| Session | Native conversation addressed by gateway, profile and session ID. |
| Persona revision | Accepted Host definition projected into native SOUL and loaded through Hermes's prompt lifecycle. |
| Voice binding | The Host's accepted service and speaker selection for speech. |
| Presentation preferences | Client labels, initials and colors used for display. |
| Connection mode | LAN, private network or HTTPS access instructions for the same gateway connection. |

Multiple gateways can serve the same Host. The normal session list presents
authorized conversations from those gateways and preserves each operation's
owner. Creating a conversation selects its execution gateway. Opening an
existing conversation continues it on its owner.

The app verifies ARC identity during connection setup. Normal chat includes
new and existing sessions, sending, streaming, stop, approvals and reconnect.
Listen uses that chat's accepted identity and configured voice. Read-only
identity metadata supports discovery and authorization.

## Kanban

**Kanban**:
The ARCHermes destination for organizing and operating server-backed work across workflow states.
_Avoid_: Boards, Tasks

**Board**:
A named container of Kanban work and its workflow states.
_Avoid_: Kanban, project

**Card**:
An individual unit of work on a Board.
_Avoid_: Task, Kanban task, work item

**Status**:
The workflow state of a Card: Triage, To Do, Scheduled, Ready, Running, Blocked, Review, Done, or Archived. Scheduled and Review exist only on a Hermes server.
_Avoid_: Column, lane, stage

**Scheduled**:
The Status of a Card parked until a time or condition, waiting on the clock rather than a person. The Dispatcher skips it.
_Avoid_: Delayed, snoozed

**Review**:
The Status of a Card whose work is finished and waits for a person to check it before Done.
_Avoid_: Awaiting approval, QA

**Column**:
A visual grouping of Cards that share a Status.
_Avoid_: Status, lane

**Lane**:
An optional visual grouping of Cards by Profile, including an Unassigned lane.
_Avoid_: Status, column

**Profile**:
A Hermes agent configuration that can perform Card work.
_Avoid_: Assignee, user, agent

**Assignment**:
The relationship between a Card and the Profile selected to perform it. A Card without that relationship is Unassigned.
_Avoid_: Ownership

**Prerequisite**:
A Card that must precede another Card in a dependency relationship.
_Avoid_: Parent, blocker

**Dependent**:
A Card that relies on a Prerequisite.
_Avoid_: Child, blocked card

**Dispatcher**:
The server operation that claims eligible Ready Cards and may launch worker processes.
_Avoid_: Runner, launcher

**Preview Dispatch**:
A dry run that reports expected Dispatcher outcomes without launching workers.
_Avoid_: Test run, simulate dispatcher

**Run Dispatcher**:
The action that invokes the Dispatcher and may launch workers or consume API budget.
_Avoid_: Dispatch, run

**Dispatch Run**:
The recorded execution of the Dispatcher.
_Avoid_: Run, dispatcher result

**Archived**:
The Status of a Card removed from the active workflow.
_Avoid_: Deleted

**Archive Card**:
The action that changes a Card's Status to Archived.
_Avoid_: Delete Card, remove Card

**Archive Board**:
The action that removes a non-default Board from active use. ARCHermes cannot restore an archived Board in-app.
_Avoid_: Delete Board, remove Board

**Bulk Action**:
A named operation applied to multiple selected Cards.
_Avoid_: Bulk update, batch operation

**Select Cards**:
The mode for choosing Cards before applying a Bulk Action.
_Avoid_: Multi-select, bulk mode

## Tasks

**Task Run**:
One execution of a Task. On a Hermes server it is a session `cron_<task>_<time>`, and its output is that session's final reply; on a webui server it is an output file.
_Avoid_: job run, execution

## Sessions

**Project**:
A named group of sessions in the session list. On a webui server it is a tag the session carries, which Move to Project sets. On a Hermes server it is a set of host folders: a session belongs to the project with the deepest folder its working folder sits in, the host groups the rest into automatic per-repository projects, and Move to Project changes the session's working folder.
_Avoid_: tag (for a Hermes project), workspace

**Stored key**:
The durable id that names a Hermes session, together with its Profile. ARC Hermes caches, links, drafts and registers push by it, and REST routes and `session.resume` take it. Lists and caches identify a row by its lineage root (`_lineage_root_id ?? id`), so a session that a legacy compression continued under a new key stays one row.
_Avoid_: session id (when the kind matters)

**Runtime ID**:
The id of the host's live runtime for a session, returned by `session.resume` or `session.create`. Session-scoped RPCs and the event `seq` use it. It changes when the host reaps the runtime (4001), so ARC Hermes never stores it; reattaching to the stored key returns the new one.
_Avoid_: session id (when the kind matters)

## Chat

**Fork**:
A chat created from another chat's history by Fork From Here or `/branch` (`/api/session/branch`). The server marks it `session_source: fork` with a `parent_session_id`, and ARC Hermes shows a "Forked from" row that opens the parent. Agent child sessions (subagents, cron, CLI `/new`) also carry a parent but are not Forks. On a Hermes host it is `session.branch`'s copy, marked by `_branched_from` in its row's `model_config`; a Hermes Duplicate is an independent copy with no parent, and no Fork.
_Avoid_: Branch (for the chat), child session

**Conversation target**:
Which Hermes session a conversation attaches to: a bot's canonical Bot Chat, found by its title; a stored session, by its stored key; or a new session, created on first attach. Each target has its own draft (`ConversationTarget`).
_Avoid_: chat target, session kind

**Turn identity**:
Which run a chat is following: a webui stream id, or for a Hermes session its stored key and the host's `turn_started_at`. A Hermes turn ends once `message.complete` and `session.info {running: false}` have both arrived.
_Avoid_: stream id (for a Hermes turn), run id
