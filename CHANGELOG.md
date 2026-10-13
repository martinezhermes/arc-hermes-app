# Changelog

Notable changes to ARCHermes. Version headings correspond to App Store releases;
unreleased changes accumulate at the top. Format follows
[Keep a Changelog](https://keepachangelog.com/) with Added / Changed / Fixed /
Security sections per release.

## [Unreleased]

## [1.10.4] - Unreleased

### Fixed

- Chat no longer forces a full-width material banner behind its navigation title and buttons. The toolbar background is transparent and the transcript uses the system's soft top scroll-edge treatment; native button glass remains.
- Opening or closing Sessions no longer adds a selection haptic alongside keyboard dismissal/restoration. Send, completion and other action feedback retain their existing preference.

### Testing

- Scroll chat content beneath the title in light and dark appearance. Check for a smooth edge with no rectangular backdrop or separator and readable controls.
- Open and close Sessions while typing. Check draft/caret return, horizontal scrolling and Files navigation; repeat with Reduce Transparency and larger text.
- On iPhone, repeat with app haptics enabled and confirm drawer/keyboard transitions stay quiet while action feedback still works.

## [1.10.3] - Unreleased

### Fixed

- The drawer's detail card extends through the status, home and side safe areas, with one rounded surface, outline and shadow. Native toolbar controls in the unfolded Duo's side rail remain inside that surface.
- Sidebar and detail keep the same background color. The full-card darkening and tint are removed; tapping or swiping the exposed card still closes Sessions.
- Native toolbar and composer placement retain their safe areas, including keyboard avoidance and the existing typing-focus restoration.

### Testing

- Open Sessions in light and dark appearance. Inspect the full-height corners, edge and shadow; no separate top/bottom band or whole-card wash should remain.
- Close by tapping or swiping the exposed chat, then repeat while typing a draft. Check the keyboard returns with the same text and caret.
- Rotate, resize an iPad window, and check toolbar/composer controls, sidebar resizing, Reduce Motion and RTL.

## [1.10.2] - Unreleased

### Fixed

- Compact drawer transitions temporarily dismiss the keyboard and restore the same composer when a swipe cancels or the same chat returns. Draft text and caret remain with the mounted editor.
- Wrong-direction pulls do not suspend typing. Existing horizontal-control exclusions remain in place.
- A newer editing action, explicit keyboard dismissal, changed screen, or scene interruption supersedes pending focus restoration.

### Testing

- Type a draft, open Sessions, and return to the same chat. Test cancelled and reversed swipes, rapid reopen, and a previously unfocused chat.
- Verify search or another editing field can take focus without the composer stealing it back. Check background/foreground, rotation, wide layouts, Reduce Motion, and hardware-keyboard input.
- Swipe composer controls, attachments, tables and code horizontally with the keyboard open; check that ordinary scrolling retains focus and deliberate drawer navigation still works.
- This patch implements temporary dismissal and restoration. Keeping a visible keyboard attached to the shifted chat remains under investigation in #68.

## [1.10.1] - Unreleased

### Fixed

- Horizontal composer controls, attachment strips, tables, code/diffs, math and approval text retain their gestures without accidentally opening Sessions or clearing keyboard focus. The existing SwiftUI drawer still handles normal reveal and close gestures.
- The exposed chat has an adaptive one-point outline, and its dimming overlay follows the rounded leading corners. Closing from either the sidebar or exposed chat ignores inactive chat controls.

### Changed

- The non-glassy girl is the default app icon in light and dark appearance. Removed pixel-caduceus choices and unused pixel catalogs while retaining all six girl alternatives and the ARC Helmet.

### Testing

- Type a draft and keep the keyboard visible while scrolling horizontal controls and content. Test deliberate drawer reveal, reverse, cancellation and closing over tables/code.
- Inspect the chat outline in light/dark; check iPad resizing, rotation, larger text, RTL, VoiceOver, Reduce Motion and hardware-keyboard behavior.
- Check the default icon and upgrade from a retired pixel-caduceus selection; verify retained alternatives still work.
- Exact sideways attachment of the system keyboard remains under investigation. Deliberate drawer focus behavior is unchanged. Utility-row swipe activation also reproduced on 1.10.0 in simulator automation and remains for device review.

## [1.10.0] - Unreleased

### Added

- Native Hermes workspace browsing, file previews, `@` file references and working-folder selection in the shared chat.
- Native Git status/diffs, staging, unstaging, discard, commits, push and branch switching, with guards for active turns and unsafe selections.
- Fast mode, loop/heartbeat controls, plans, turn outcomes, delegated-work status/interrupts and richer app-connection/sign-in requests in ordinary Hermes chats.
- Server-qualified session links that select the correct host and Profile, retain drafts and dismiss covering screens.

### Changed

- Bot conversations now use the regular chat, shared turn lifecycle and offline cache. Removed the obsolete separate Bot Chat screen, its quick replies/reactions and unused helpers.
- Simplified streamed-text reveal and removed the old fade/lab machinery.
- Reply images, audio and files load through the Hermes host; audio recovers from stale loads after reattachment.
- ARC adaptive sidebar, keyboard/input ownership, depth/fade, accent controls, branding/icons and release/CI configuration remain in place.

### Testing

- Validate main native features across sessions/chat, Workspace/Git, Bots, Tasks, Skills, Memory, Usage and Kanban; feature-wide acceptance continues in #60.
- Test streaming recovery, drafts, requests, server/Profile isolation, attachments/media and session links.
- Check iPhone/iPad layouts, keyboard/sidebar gestures, light/dark, Dynamic Type, RTL, VoiceOver and Reduce Motion.
- Native Git Fetch/Pull and password-vault prompt cards remain unavailable. Share, Shortcuts, push and Live Activity native follow-ups are outside this imported upstream snapshot.

## [1.9.2] - 2026-10-11

### Fixed

- The compact Sessions pane now gently recedes to 97% size with the existing fade as chat covers it, then returns to full size on reveal. Both effects follow the same swipe progress, including reversal and cancellation.
- The leading edge stays anchored in left-to-right and right-to-left layouts. Wide-layout sizing and Reduce Motion keep the sidebar at full size.

### Testing

- Review the depth and fade during slow, fast, cancelled and reversed swipes in light/dark appearance, including keyboard-open and actively scrolling sessions.
- Confirm drafts and active responses survive, and iPad sidebar resizing, larger text, VoiceOver and Reduce Motion remain correct.

## [1.9.1] - 2026-10-11

### Fixed

- Sessions stays anchored during compact swipe navigation while the selected chat covers it, with a subtle fade that follows and reverses with the drag.
- Sidebar, chat and resize-divider positions correctly mirror in right-to-left layouts.
- Reduce Motion suppresses the added fade; mounted pane identity, draft and stream ownership, keyboard/scrolling protection and regular-width sidebar sizing are preserved.

### Testing

- Test cover/reveal, short cancelled and reversed swipes, including keyboard-open and actively scrolling sessions, on iPhone and narrow iPad windows.
- Verify light/dark appearance, Reduce Motion, right-to-left layout, and saved sidebar width after iPad resizing.

## [1.9.0] - Unreleased

### Added
- Connect native sessions and chat directly to the Hermes Agent dashboard,
  with its username/password sign-in and custom connection headers.
- Native Agent screens for Profiles, Projects, Tasks, Kanban, Skills, Memory,
  Usage and Bots inside ARC's adaptive sidebar.
- ARC onboarding, app icon choices, pixel wordmark, logo color and per-server
  identity alongside the native Agent connection.
- Browse cached native sessions by Profile or across all Profiles while offline.
- Lock ARC Hermes with Face ID or the device passcode. The lock is off until
  enabled, and the app switcher hides chats while it is on.
- PDFs, Office and iWork documents, and other files ARC Hermes can't preview open
  in Quick Look, up to 25 MB, from Files, chat file links, and attachments.
- Chat settings to dismiss the keyboard after sending and to start reading a
  completed response from its beginning.
- Press ↑ on a hardware keyboard to recall your last message; staged documents
  show a preview instead of a generic icon.
- Approval cards say what Allow session and Always allow cover.
- Bot Mode: answer password-vault, save-login, and 2FA prompts on the phone;
  open and reply inside room threads; see who is in a new group chat; copy a
  reply from its footer; and save or share a previewed attachment.
- Bot Mode: add a Hermes host as its own server from onboarding or Settings,
  with custom headers for hosts behind Cloudflare Access or another proxy.

### Changed
- Keep the active chat and draft mounted while revealing or resizing the
  sidebar. Compact covered panes pause input and scrolling; visible wide
  panes stay interactive.
- Search, Close Search and the search cursor follow the header logo color.
  New Session, Filter and Settings share matching circular glass controls
  and the same per-server accent color.
- Larger Dynamic Type text for Settings controls, values and supporting copy.
- Display the reasoning level as "Extra High" while retaining the server's
  existing reasoning setting.
- Settings opens as a sheet. Remove duplicate native home navigation and
  obsolete parallel Agent screens; server identity uses initials instead of photos.
- Tapping a finished Live Activity removes it.
- Listen uses the server's saved text-to-speech voice and provider. Very long
  responses, or a failed server request, still fall back to on-device speech.
- Retained draft attachments share a 200 MB storage budget, reclaiming the
  oldest unused copies first.
- Bot Mode keeps its connection through Control Center and banners, and closes
  it when ARC Hermes moves to the background.

### Fixed
- Profile filtering opens reliably, keeps offline choices available and uses
  full tappable rows.
- Content scrolling beneath the sharp, pinned wordmark gets the native soft
  scroll-edge effect.
- Landscape sidebar resizing retains the chosen width after release and
  restores it after temporary window constraints.
- Revealing the compact sidebar releases keyboard focus without losing the
  draft. Superseded focus requests cannot restore a covered editor's keyboard.
- Reopening the selected session, including a compressed session lineage,
  preserves its chat instead of replacing it. Confirmed archive/delete clears
  only the matching selected session.
- After a Hermes Agent update, sends refused until Hermes WebUI restarts
  explain the problem and offer a fix prompt instead of a raw HTTP 409.
- A long /goal notice no longer hides the newest tool calls and replies.
- Long transcript text stays behind the navigation bar instead of overlapping
  the title.
- Inline LaTeX renders sub- and superscripts and tuples accurately.
- Dictation keeps the screen awake and its orientation while recording.
- A queued keyboard dismissal no longer interrupts newer typing.
- Live Activity taps open the session on the server that owns it. A stale Bot
  activity that is waiting on you says so instead of "Not connected".
- Bot Mode: failed turns say why, a rejected password opens the sign-in form,
  sign-in errors name the real problem, withdrawn requests say why, and a
  pasted dashboard link is accepted. Reattaching mid-turn keeps the running
  turn's tool rows and reasoning. Hosts older than Hermes 0.21.3 are refused
  with an explanation.

### Beta limitations
- Bot Mode remains a preview. Some share, system new-chat/session-link and
  workspace/Git flows still depend on a configured legacy WebUI server.
- ARC push pairing is not configured in this build. Live Activities and local
  response-completion alerts remain separate features.

## [1.8.0] - 2026-10-01

### Added
- Long-press Send during a session run to choose Queue, Steer, or Stop and send
  for that message without changing the default.
- File-edit tool rows show added and removed line counts and expandable diffs.
  Diff and patch code blocks also highlight additions and deletions.
- Web links open in an in-app Safari sheet, and forked chats link back to their
  parent session.
- The working pill shows elapsed time, and long user messages can be folded.
- Undo a session archive from its confirmation toast. Search sessions with
  multiple words in any order, and switch chats with iPad keyboard shortcuts.
- Bot Mode: Tapback reactions that sync with Hermes Desktop, editable
  quick-reply chips, message timestamps, and Desktop sections in the inbox.
  Move bots between sections from the phone.
- Bot Mode: answer requests to connect an app, and view host status on the
  Hermes connection screen. Working bots and bots waiting for an answer sort
  first in the inbox; chat titles also show waiting and failed states.
- A notification prompt after the first run starts, and a Send Test
  Notification button in Settings for push-paired servers.

### Changed
- Chat opening, typing, streaming, and scrolling do less repeated work. Code
  highlighting runs off the main thread, transcript image caches have memory
  limits, and large workspace Markdown and diff previews render lazily.
- Bot replies use the streaming renderer, finished Bot turns fold behind a
  Worked for row, and Bot Chat uses the session chat's haptics. Working bot
  faces settle into a still pose after a short animation.
- Chat has a comfortable reading width on larger screens, clearer table edges,
  smoother Send and Stop transitions, autocomplete selection feedback, and a
  shorter landscape composer.
- Session times update while the list is idle. The list restores the last chat
  sooner, the iPad sidebar keeps its state when switching chats, and Kanban
  keeps the loaded board when returning from a card or refreshing in the
  background.
- Shared-file imports, cache writes, model picking, networking, and Live
  Activity updates use less memory or do less repeated work.
- The support link now points to memberships.

### Fixed
- Session streams wait while offline and reconnect when the network returns,
  showing Waiting for network instead of exhausting retries.
- Queued messages survive leaving a chat mid-run. A refused steering request
  no longer stops the active run.
- New chats use the selected profile; chats started from the session list
  under a project filter join that project. Sessions refresh on foregrounding.
- The composer stays above the keyboard after returning from Files, and
  dismissing a chat no longer unexpectedly restores keyboard focus. Camera
  dismissal does less work on the main thread.
- Local reply notifications name and open the right chat and include failed
  runs. Approval and question push alerts still arrive during a Live Activity,
  with Time Sensitive approval alerts supported through Focus. Denied
  notification permission is reported accurately.
- Bot approvals and questions work with Hermes 0.21.4, and app-connection
  responses use the shape expected by 0.21.4 and 0.21.5 hosts. Credential
  prompts support Password AutoFill and clear the previous request's secret.
- Bot host identity survives address changes, and tapping the Bot transcript
  dismisses the keyboard.
- Plain HTTP connections work with local hostnames and Tailscale addresses.
  On-device dictation tries the user's other languages when the current locale
  has no model.
- Session rows no longer pulse a redundant streaming dot, and transcript link
  rows avoid unnecessary redraws.
- App and share-extension privacy manifests declare required-reason APIs.

## [1.7.0] - 2026-09-24

### Added
- Bot Mode (beta, off until enabled in Settings): connect directly to a Hermes
  agent host and chat with its bots from a Bots inbox. Create, duplicate,
  edit, and delete bots, including their face, model, capabilities, and
  instructions. Follow tools, reasoning, and delegated work live; steer,
  queue, or interrupt a working bot; answer approvals, questions, and
  credential prompts; send attachments; mention teammates and files with `@`
  and skills with `/`; dictate on-device; search bots and messages; and take
  part in group rooms.
- Optional push notifications through an open-source relay you can self-host.
  Notification text is encrypted on your Hermes host and decrypted only on
  the iPhone. Turn them on from the Hermes connection screen and tune them
  under Settings > Interaction. Tapping a notification opens the right
  session or bot.
- Live Activities for working bots and WebUI runs keep updating while the
  phone is locked, and show tool counts and how fresh the update is.
- Session rows show unread replies.
- Select text in responses and ask Hermex about the selection.
- Steering hints appear inline in the transcript.
- A custom photo and camera picker for attachments.
- The Usage screen shows provider account limits.
- An optional "Buy Uzi a coffee" link, and rating requests at quiet moments.

### Fixed
- Live streams resume from the last event after a reconnect, and the reconnect
  probe retries after a transport drop.
- Pending approvals stay visible across stream transitions, and clarification
  requests stay above the keyboard.
- Long conversations scroll with less lag and do less math formatting work.
- Native composer text gestures and manual composer scrolling work again, and
  the profile chip stays inside the composer.
- Attachment thumbnails are cached per server.
- Reduce Motion is honored in chat, Git toasts, and onboarding.
- Interface strings added since 1.6 that showed in English in every language
  are now translated.

## [1.6.0] - 2026-09-05

### Added
- Redesigned chat transcript: settled tool calls, live tool activity, and
  thinking render as compact log rows, finished turns fold behind one
  elapsed-time row, a working-for counter sits at the transcript tail, and
  each message carries a timestamp and copy button. Expanded rows are capped at
  a scrollable window and new rows fade in.
- Pill-shaped Liquid Glass composer with a toolbar row when focused, combined
  model and effort controls with provider glyphs, and haptics for disclosures,
  copies, and Git actions.
- Reference workspace files from the composer with `@path` chips.
- Slash and skill autocomplete triggers at the caret, ranks by match quality,
  and shows a picked skill as a chip in the composer and in the sent bubble.
- Workspace file tree that loads lazily, a syntax-coloured source viewer for
  files, file-type icons, and chat file links that open in the viewer.
- Git review surface that shows every changed file in one diff.
- Markdown workspace images render inline and zoom in a full-bleed viewer;
  Markdown files render in workspace previews.
- Tasks list rebuilt as an agenda with filters, row actions, and recent runs
  across all tasks; Task Detail redesigned with per-task run history and a
  model, provider, and profile picker.
- Insights rebuilt as a Usage screen with a window chart.
- Session rows show Approval, Input, and Working states, and search results
  show why they matched.
- `/clear` clears the session's server-side history.
- Settings > Default Model and Default Profile share the composer's model
  picker; Providers gets matching glyphs and list chrome.
- The clarification card pins above the composer.
- Attachments can be sent without composer text.

### Changed
- Reasoning effort changes are scoped to the session instead of applying
  globally.
- The "Checking stream" chip and status polls stay hidden while transport
  heartbeats are fresh.
- HTTP 403 responses surface the server's reason.

### Fixed
- Partial streams survive relaunch, foreground stream recovery no longer races
  itself, and late events after a response completes are ignored.
- Unsent composer text, attachments, and settings persist as drafts.
- The default model persists with its provider and the picker exposes the full
  model catalog.
- Trusted-header and OIDC sign-in report their real state, and stale auth
  status is invalidated when the URL or headers change during onboarding.
- Incoming shares are transactional and no longer leave half-staged imports.
- "Working for" and "Worked for" count from the server's turn start.
- Transcript scroll position survives reloads and disclosure toggles, and
  auto-follow is an explicit latch.
- CLI and messaging sessions can be continued from the app, and duplicating a
  session uses the server's duplicate endpoint instead of branching.
- Kanban restores the browsed Board per server after relaunch, and the Board
  picker stays visible for long Board names.
- Server First dictation runs until the user stops it, and oversized
  transcription uploads are rejected before they fail.
- Inline assignment math renders correctly.
- Streaming thinking stays responsive, cached-message lookups are batched, and
  settled Markdown math layouts are cached.

## [1.5.0] - 2026-08-04

### Added
- Kanban boards: browse cards by status column, view card detail with comments
  and operational history, create and edit cards, move cards through their
  workflow, act on many cards at once with accessible bulk actions, manage
  boards with shared active-board controls, preview and run the dispatcher from
  a toolbar sheet, and stay current through live updates with offline
  reconciliation.
- Settings toggles to hide unused parts of the app: session-list entries
  (Tasks, Kanban, Skills, Memory, Insights, Active Profile, Projects) and chat
  controls (Files button, Git actions). Everything stays visible by default.
- Opt-in response speed metrics.
- Public open-source release of the ARCHermes codebase.

### Fixed
- Interrupted backend streams now recover instead of stalling the response.
- Opening a transcript no longer jitters.
- Reopening a chat bounds the cached transcript instead of loading it all.
- Deep-linked sessions no longer lose the race to last-session restore.
- The file browser keeps the latest directory navigation.
- The session list refreshes after returning from a new chat.
