# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Personal macOS 27+ (arm64 only) menu bar app showing each display's current Space number. Distributed from source via the Homebrew tap `powersagitar/homebrew-tap` (`Formula/space-indicator.rb`, a separate repo). The full design and its rationale live in `docs/superpowers/specs/2026-11-26-space-indicator-design.md`; read it before changing behavior, since many choices there are deliberate rulings (e.g. polling, no `SMAppService`).

## Commands

```sh
# Build (same flags the formula uses; formula also passes
# "OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox" for Homebrew's sandbox)
xcodebuild -project SpaceIndicator.xcodeproj -scheme SpaceIndicator -configuration Release -derivedDataPath build CODE_SIGN_IDENTITY=- build

# All unit tests (Swift Testing)
xcodebuild test -project SpaceIndicator.xcodeproj -scheme SpaceIndicator -derivedDataPath build

# One test suite
xcodebuild test -project SpaceIndicator.xcodeproj -scheme SpaceIndicator -derivedDataPath build -only-testing:SpaceIndicatorTests/SpaceNumberingTests

# Cleanup script tests (sandboxed temp HOME; prints PASS)
sh scripts/test-cleanup.sh
shellcheck scripts/*   # if installed
```

Output app: `build/Build/Products/Release/Space Indicator.app`.

## Architecture

- `SpaceIndicator/Core/` — pure, testable logic. These files are compiled into **both** the app target and the host-less `SpaceIndicatorTests` target (tests never launch the app), so Core must not depend on anything in `App/`.
  - `SpaceNumbering`: pure function over the `CGSCopyManagedDisplaySpaces` array → per-display `[Int?]` and the joined title (`2 · 1`, `?` when untrustworthy).
  - `LaunchAgent` / `LaunchAgentStore`: Cellar → `opt` path rewrite, plist content, file IO, and self-repair (only rewrites an existing plist when running from the Homebrew Cellar).
  - `SingleInstance`: briefly waits for a quitting instance before deciding to exit.
- `SpaceIndicator/App/` — wiring: `CGS.swift` (private calls via `@_silgen_name`, screen ordering by `NSScreen` UUIDs), `SpaceIndicatorModel` (`@Observable`; 1 s `.common`-mode timer + `activeSpaceDidChangeNotification`; focus-restore; Launch at Login state re-read from disk), `SpaceIndicatorApp` (`MenuBarExtra` with a plain text title; see the spec's Font note).
- `scripts/space-indicator-cleanup` — POSIX `sh` "zap" installed by the formula as `bin/space-indicator-cleanup`. `SI_SKIP_PROCESSES` and `SI_APPLICATIONS_DIR` env vars exist for the test script.

## Invariants (anti-goals from the spec)

- Prefer `?` over a possibly wrong number.
- Quit must really quit: LaunchAgent has `KeepAlive` false; no `launchctl` calls from the app.
- Launch at Login must survive `brew upgrade`: the plist points at `<prefix>/opt/space-indicator/...`, never the Cellar.
- No permission prompts, no windows (the focus-restore logic assumes there are none).
- Identity strings are fixed: bundle ID `com.mohandong.SpaceIndicator` (also LaunchAgent label), `PRODUCT_NAME = "Space Indicator"` (quote paths with the space); target/scheme/module `SpaceIndicator`. Ad-hoc signing (`CODE_SIGN_IDENTITY = -`).

## Releases

Tags are `vX.Y.Z`; the formula is updated by PR to the tap (whose test-bot runner is `xcode-27`). Confirm with the owner before every push.
