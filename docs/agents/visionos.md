# Native visionOS support

The native client targets **visionOS 27.0 and newer**. It uses the
`ARCHermesVisionOS` target and shared scheme in `ARCHermes.xcodeproj`; the
`ARCHermes` target and its extensions continue to target iOS/iPadOS 18.0+.
This is the same product and bundle identity, built for a different platform.
The initiative is [#85](https://github.com/martinezhermes/arc-hermes-app/issues/85).

## First build boundary

The first gate, [#86](https://github.com/martinezhermes/arc-hermes-app/issues/86),
provides one native resizable operator window, initially 1,100 × 750 points with
a 700 × 560 point content minimum. The window shares root routing, authentication,
networking, streaming, persistence, drafts, and feature sources with iOS.
Global authentication is intentional while the app supports only one window;
independent windows require a separate state-ownership decision.

The native app includes shared files and resources explicitly in its Sources
and Resources phases. When adding a shared source or resource, decide membership
for both app targets and every extension that consumes it. Never attach an iOS
extension target to the native target merely to reuse its source.

Platform adaptations preserve the iOS behavior:

- ActivityKit calls become inert on visionOS; no Live Activity or background
  activity relay route is created. The run-state model remains shared.
- Touch haptics, alternate app icons, and camera capture are unavailable. Files
  and Photos remain in the attachment menu.
- The system owns the spatial keyboard and window glass. Shared inset surfaces
  use materials or opaque accessibility fallbacks; iOS-only scroll-edge,
  keyboard-dismissal, Liquid Glass, and toolbar-spacer APIs are excluded.
- Swift code highlighting uses the existing cached Highlightr engine on visionOS.
  iOS retains Splash. The pinned Splash release does not build for visionOS;
  neither a package fork nor a new dependency is needed.
- Composer-chip rendering uses the containing view's display-scale traits,
  including cache identity and trait-change redraws.

The first gate proves native compilation and root-window launch. It does not
certify signed-in workflow parity, streaming recovery, server isolation, voice,
spatial keyboard ergonomics, gaze/pinch accessibility, notifications, App Intents,
Optic ID, or physical headset behavior. Those require the remaining initiative
gates. The iOS share extension and Live Activity widget are not native visionOS
extensions. The initial native target has no release app icon configured;
layered visionOS icon artwork and distribution validation belong to the release
gate. Do not use this Simulator build as an App Store or TestFlight archive.

## Build and verification

Use Xcode with a visionOS 27+ SDK:

```zsh
scripts/validate-visionos
```

This builds the real app in Debug with normal Simulator signing, checks the
native SDK, deployment minimum, device family, and Swift 5 mode, verifies the
signature, and produces `ARCHermesVisionOS-Simulator.zip` outside the checkout.
The matching CI job uploads the Simulator package and build evidence. It does
not replace `scripts/validate`, which still runs the full iOS XCTest suite and
builds the iOS extensions. A native XCTest target is not part of this first gate.

To launch, select `ARCHermesVisionOS` and a visionOS 27 Simulator in Xcode, or
install the built `.app` with `xcrun simctl install <udid> <app-path>` and launch
`com.martinezhermes.archermes`. Do not disable signing or hand-sign the app.
Use an isolated Simulator for synthetic evidence; do not copy credentials or
cached server content from a maintainer device.

For native-window changes, read `visionos-developer`,
`spatial-app-architecture`, `spatial-swiftui-developer`, and `app-resizability`,
plus the repository's existing architecture, Swift, build, and signing skills.
Keep the implementation in the shared feature code and small platform helpers.
RealityKit, immersive spaces, ARKit, SharePlay, and independent multiwindow
sessions are outside the first release scope.
