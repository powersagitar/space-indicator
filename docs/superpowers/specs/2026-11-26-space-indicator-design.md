# Space Indicator — Design

Date: 2026-11-26

## Intent

A personal macOS menu bar app that shows each display's current Space as a 1-based number, so the owner always knows where they are among their Spaces. Clicking the number opens a tiny menu (Launch at Login, Quit). No windows, no Dock icon. Personal use only: installed from source through the owner's existing Homebrew tap.

## Goals

- Menu bar shows every display's current Space number in one label, ordered left to right and joined by ` · `, e.g. `2 · 1` (a single display shows just `3`), in the system font (SF Pro). A display whose Space can't be determined shows `?`.
- Numbering matches the left-to-right order in Mission Control on that display, starting at 1, counting full-screen Spaces by position.
- Launch at Login that survives `brew upgrade`.
- Asks for no permissions.

## Non-goals

- Space names/labels, settings window, hotkeys, switching Spaces.
- Sandboxing, App Store, notarization, paid developer account.
- Public-API-only implementation (private CGS calls are accepted).
- Intel Macs, macOS earlier than 27.

## Anti-goals

- Quitting from the menu must actually quit (launchd must not relaunch it).
- Launch at Login must not silently break after `brew upgrade`.
- The menu bar number must not be wrong without being `?` — prefer `?` to a guess.

## Constraints

- macOS 27+, Apple Silicon (arm64) only. Deployment target macOS 27.0.
- Xcode is installed at `/Applications/Xcode.app` and is the active developer directory (owner must have accepted the Xcode license).
- License: GPL-3.0-only (repo already has LICENSE).
- Bundle identifier: `com.mohandong.SpaceIndicator`. Formula name: `space-indicator`. App bundle: `Space Indicator.app`, executable `Space Indicator` (`PRODUCT_NAME = "Space Indicator"`; target, scheme and module stay `SpaceIndicator`). The LaunchAgent label and plist filename use the bundle ID. Paths containing the space must be quoted wherever a shell or formula uses them.
- Ad-hoc code signing (`CODE_SIGN_IDENTITY = "-"`), no team.

## Approaches considered

1. **SwiftPM package + manual bundling in the formula.** Plain-text repo, no Xcode needed for Homebrew; bundling done by hand.
2. **Xcode project built with `xcodebuild` in the formula.** Xcode produces the `.app`; target settings in Xcode; pbxproj is noisy; formula needs Xcode.
3. **XcodeGen.** Avoids committing pbxproj but adds a tool for a one-target app.

**Chosen: 2 (Xcode project)** — owner's pick.

## Design

### Project layout

- `SpaceIndicator.xcodeproj` with one app target `SpaceIndicator` (SwiftUI `MenuBarExtra`, Swift, no storyboard/xib) and one unit test target `SpaceIndicatorTests`.
- `Info.plist`: a checked-in `SpaceIndicator/Info.plist` (`GENERATE_INFOPLIST_FILE = NO` on the app target, so every key is visible in one reviewable file; the test target still generates its own). Keys: `LSUIElement = YES`, `CFBundleIdentifier`, `CFBundleShortVersionString = $(MARKETING_VERSION)` (the `MARKETING_VERSION` build setting is bumped to `X.Y.Z` in the commit tagged `vX.Y.Z`, so local builds match; the formula also passes `MARKETING_VERSION=#{version}` to `xcodebuild`), `LSMinimumSystemVersion = 27.0`, `NSHumanReadableCopyright`.
- App also calls `NSApp.setActivationPolicy(.accessory)` at startup.
- Release build: `ARCHS = arm64`, `ONLY_ACTIVE_ARCH = NO`.

### Reading each display's Space (private CGS)

Declared with `@_silgen_name` (no bridging header):

- `CGSMainConnectionID() -> Int32`
- `CGSCopyManagedDisplaySpaces(_ cid: Int32) -> CFArray` — per-display array of dictionaries; each has `"Display Identifier"`, `"Current Space"` (dict with `ManagedSpaceID`), and `"Spaces"` (array in Mission Control order, each with `ManagedSpaceID` and `type`: 0 = desktop, 4 = full-screen).

Algorithm: for each display dict with a `"Spaces"` array, the number is the 1-based index of its `"Current Space"` `ManagedSpaceID` within its own `"Spaces"`. Every Space type counts (desktop 1, desktop 2, full-screen Safari → 3, next desktop → 4). A display's number is `?` if the current ID is missing, 0, not in `Spaces` or in it more than once, or any `Spaces` entry has an unreadable ID (an ID must be an integer `NSNumber`, not a float or a Bool). A display dict that has a `"Display Identifier"` but no readable `"Spaces"` array is `?` too; a dict with neither is skipped. Displays are ordered by screen position (`NSScreen.screens` sorted by `frame.minX`, then `minY`, mapped to display UUID strings, which match CGS's `"Display Identifier"`); unmatched ones follow in CGS order.

This works the same with "Displays have separate Spaces" on (each display's array numbers from 1) or off (a single array spanning displays).

With multiple displays, the menu bar item appears in every display's menu bar with the same text. Owner request (each display's Space visible), plus a spike showing a status item is drawn once and mirrored onto every display, so per-display content is impossible; the one label lists every display's number instead. With "Displays have separate Spaces" off there is one `Main` entry, so one number.

The parsing/numbering is a pure function over the CGS array (`numbers(displays:screenOrder:) -> [Int?]`, `title(for: [Int?])`) so it can be unit-tested with fixture data.

### Single instance

At launch, if another running application has bundle ID `com.mohandong.SpaceIndicator` (`NSRunningApplication.runningApplications(withBundleIdentifier:)`, excluding the current process and any instance that `isTerminated`), wait up to about 1 s in short polls for it to exit; if it's still there, exit. Prevents two menu bar items when the LaunchAgent copy and an `open`-launched copy overlap, without making Quit followed by an immediate relaunch silently exit. *(Designer's call.)*

The model hands focus back to the previously frontmost app when this app gets activated (e.g. by `open` on the running copy). This would fight any window or alert, which the app has none of by design.

### Update triggers

Recompute at launch, every second, and on `NSWorkspace.shared.notificationCenter` `activeSpaceDidChangeNotification`. The poll is a repeating `Timer` (interval 1.0 s, tolerance 0.5 s) on the main run loop in `.common` mode, so it also fires while the menu is open. The model assigns the title only when it changes, so the poll doesn't re-render the label every second.

The poll is the catch-all. A Space's position can change without a Space switch: by reordering desktops or dragging a full-screen Space in Mission Control, or by quitting a full-screen app whose Space comes before the current one. A diagnostic that polled `CGSCopyManagedDisplaySpaces` every 100 ms showed the `Spaces` array changing in these cases (e.g. `[4,6,5,…]` → `[6,5,7,8,4,…]` with current still 4, or a full-screen Space vanishing) while no `NSWorkspace` or distributed notification fired. With no event to hook, polling one WindowServer query each second is the reliable way to meet the anti-goal. The poll also covers display plug/unplug and app quits, with up to about 1.5 s latency, so there are no observers for those. `activeSpaceDidChangeNotification` stays only to give instant feedback on the common case, a Space switch. *(Controller ruling; supersedes the earlier "no polling timer" ruling.)*

Correction (history): an earlier design numbered only the focused display's Space via `CGSGetActiveSpace`, which the app no longer calls. Moving focus between displays changes that value without firing `activeSpaceDidChangeNotification`, so the earlier "multi-display check passed" note was wrong. The label no longer depends on focus (it shows every display). `didActivateApplicationNotification` is observed only for focus restore (see Single instance), and `NSMenu.didBeginTrackingNotification` only for the Launch at Login checkmark.

### Menu bar item

- SwiftUI `MenuBarExtra` (`.menu` style) whose label is a plain `Text` of the number string (see Font); VoiceOver reads the text.
- Font: whatever the system gives a `MenuBarExtra` text label — SF Pro in the same weight as the clock (medium; measured), with proportional digits. The label ignores SwiftUI font, design (`.monospaced`), `.monospacedDigit()` and frame modifiers, so the width follows the digits (a `1` is ~2.5 pt narrower), shifting items to its left slightly on some Space changes; the text sits ~0.5 pt below the clock's. Accepted over the earlier tabular-digit template `NSImage`: that drew in regular weight (`NSFont.menuBarFont` reports regular, but the system draws its own menu bar text in medium), so it looked smaller, and it sat 1 pt low; matching the system by hand needed measured constants that could drift. *(Designer's call; spec said "SF Pro".)*
- Menu (`MenuBarExtra` content):
  - **Launch at Login** — `Toggle` bound to the model's stored `launchAtLogin` (checkmark iff the LaunchAgent plist exists), which the model re-reads from disk at launch, after every toggle (whether or not it succeeded) and on `NSMenu.didBeginTrackingNotification` (confirmed by the owner).
  - separator
  - **Quit** with key equivalent `q` (⌘Q) → `NSApp.terminate(nil)`.

### Launch at Login (user LaunchAgent)

Not `SMAppService`, because the Cellar path changes every version. A spike tested `SMAppService.agent` with a bundled plist: Background Task Management (BTM) records the Cellar path, so after an upgrade the job fails with "No such file", status still reports `.enabled`, and re-registering fails with a code-signing launch-constraint violation (ad-hoc signatures change every build). So the hand-written plist pointing at `opt` stays.

Plist path: `~/Library/LaunchAgents/com.mohandong.SpaceIndicator.plist`. Contents:

```xml
<dict>
  <key>Label</key><string>com.mohandong.SpaceIndicator</string>
  <key>ProgramArguments</key>
  <array><string>{APP_PATH}/Contents/MacOS/Space Indicator</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><false/>
  <key>ProcessType</key><string>Interactive</string>
</dict>
```

Write with `PropertyListSerialization` (XML), creating `~/Library/LaunchAgents` if missing.

- **On**: write the plist. **Off**: delete it. No `launchctl` calls; takes effect at next login.
- **`{APP_PATH}`**: take `Bundle.main.bundleURL` (resolved, no symlinks). If it matches `<prefix>/Cellar/space-indicator/<version>/<rest>`, rewrite to `<prefix>/opt/space-indicator/<rest>` (the prefix is whatever precedes `/Cellar/`, so no need to shell out to `brew`). Otherwise use the bundle path unchanged.
- **Self-repair**: at launch, if the plist exists and its `ProgramArguments[0]` differs from the computed path, rewrite it — but only when the app is running from the Homebrew Cellar (i.e. the computed path is the `opt` path). A dev build from DerivedData or a copied `.app` never rewrites an existing plist. Toggling the menu item from a dev build still writes that build's own path, by explicit user action. *(Designer's call, to avoid a one-off dev run silently pointing login at a path that disappears.)*
- Path computation and plist content generation are pure functions, unit-tested.

Failure to write/delete: show nothing (no windows); log via `os.Logger`; the checkmark reflects the real file state on next menu open. *(Designer's call.)*

### Homebrew formula

In the existing tap `powersagitar/homebrew-tap`, file `Formula/space-indicator.rb` (class `SpaceIndicator`), styled like the existing `how-to.rb` (desc, homepage, url, sha256, `license "GPL-3.0-only"`).

- Source: GitHub tag tarball of `github.com/powersagitar/space-indicator` (already the repo's `origin`). Tags are `vX.Y.Z`, first release `v0.1.0`. The formula is delivered by pull request to the tap, and the owner's `brew pr-pull` workflow adds the `bottle do` block. The tap's test-bot macOS runner is `xcode-27` (GitHub's macOS 27 image; there is no `macos-27` label); PR #10's CI passed and produced a `bottles_xcode-27` artifact. `brew install --build-from-source` still works. *(Tag format is the designer's call.)*
- `depends_on xcode: ["27.0", :build]`, `depends_on arch: :arm64`, and a macOS 27 minimum (use Homebrew's symbol for macOS 27 if it exists, else check `MacOS.version` in `install` and `odie`).
- `install`: `xcodebuild -project SpaceIndicator.xcodeproj -scheme SpaceIndicator -configuration Release -derivedDataPath build CODE_SIGN_IDENTITY=- MARKETING_VERSION=#{version} "OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox" build` (via Homebrew's `xcodebuild` helper, not `system`). The sandbox flag is needed because Swift macro plugins (`@State`, `@Observable`) run their own `sandbox-exec`, which can't nest inside Homebrew's build sandbox. Then `prefix.install "build/Build/Products/Release/Space Indicator.app"`.
- **Early checks in `install`** (before `xcodebuild`): `odie` with the exact fix command if the active developer directory isn't a full Xcode (`xcode-select -p` ends in `CommandLineTools`), if the license isn't accepted (`xcodebuild -license check`), or if first-launch components are missing (`xcodebuild -checkFirstLaunchStatus`). Caveats print only after a successful install (and in `brew info`), so these checks are what a fresh machine actually hits. *(Designer's call, added alongside the caveats requested.)*
- `caveats` — two parts:
  - **Setup:** the one-time symlink command `ln -sfn "#{opt_prefix}/Space Indicator.app" "/Applications/Space Indicator.app"`, how to start it (`open "/Applications/Space Indicator.app"`, or Spotlight once linked), and that Launch at Login is in its menu.
  - **Common pitfalls on a fresh machine:**
    - Full Xcode 27 or later is required. The Command Line Tools alone are not enough. Switch with `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
    - Accept the Xcode license: `sudo xcodebuild -license accept`.
    - Install Xcode's first-launch components: `sudo xcodebuild -runFirstLaunch`.
    - Apple Silicon and macOS 27 or later only.
    - If the number doesn't appear: check System Settings → Menu Bar, where items can be hidden, and on notched MacBooks a full menu bar can push it behind the notch.
    - Nothing asks for permissions. A prompt asking for any means something is wrong.
    - Turning on Launch at Login makes macOS show a "Background Items Added" notice. That's expected: it's the LaunchAgent plist being written.
    - Uninstalling: run `space-indicator-cleanup` *before* `brew uninstall` (see below).
- `test`: assert the bundle's executable exists, `Info.plist` has `LSUIElement`, and `space-indicator-cleanup` is executable.

### Cleanup script (zap equivalent)

Formulas have no `zap` stanza (that's cask-only), so the formula installs a script as `bin/space-indicator-cleanup` (source in the repo at `scripts/space-indicator-cleanup`, POSIX `sh`). It does what a cask `zap` would:

1. Quits the running app (`osascript -e 'quit app id "com.mohandong.SpaceIndicator"'`, falling back to `pkill -x "Space Indicator"`, then `pkill -9 -x "Space Indicator"` if it's still running about 2 s later).
2. `launchctl bootout gui/$(id -u)/com.mohandong.SpaceIndicator` if it's loaded (ignore errors).
3. Removes `~/Library/LaunchAgents/com.mohandong.SpaceIndicator.plist`.
4. Removes `/Applications/Space Indicator.app` only if it's a symlink into the Homebrew prefix (never a real app bundle).
5. Removes anything macOS may have created for the bundle ID: `~/Library/Preferences/com.mohandong.SpaceIndicator.plist`, `~/Library/Caches/com.mohandong.SpaceIndicator`, `~/Library/HTTPStorages/com.mohandong.SpaceIndicator`, and `~/Library/Saved Application State/com.mohandong.SpaceIndicator.savedState`.
6. Prints each item it removed. Running it again when there's nothing left is safe.

It doesn't run `brew uninstall` itself; the caveats say to run it first, then `brew uninstall space-indicator`. *(Designer's call: a script can't run from a formula's uninstall hook, since Homebrew has none.)*

**`/Applications` symlink (owner's requirement):** `/Applications/Space Indicator.app` is a symlink to `<prefix>/opt/space-indicator/Space Indicator.app`. It points at `opt`, not the Cellar, so it survives `brew upgrade`. Homebrew's `post_install` sandbox can only write inside Homebrew's own folders (checked in `Library/Homebrew/formula_installer.rb`), so the formula can't create it. The caveats give the one-time `ln` command, which is also run once during release (see Release and install). Launching through the symlink doesn't affect Launch at Login: `Bundle.main.bundleURL` resolves to the Cellar path, which gets rewritten to `opt` as usual. The builder must confirm that resolution actually happens through the symlink and resolve it explicitly if not.

### Testing

- Unit tests (Swift Testing, in `SpaceIndicatorTests`): numbering over fixture CGS arrays (single display, `Main` single array, separate-spaces multi-display, screen ordering with unknown IDs last, full-screen in the middle, current ID missing or repeated → `?`, float or Bool IDs → `?`, malformed input → skipped or `?`, title joining); single-instance wait (a quitting instance that exits within the wait is ignored); Cellar → opt path rewrite (Cellar path, non-Cellar path, `/usr/local` prefix); plist content (KeepAlive false, path correct); self-repair decision.
- Manual check on the real machine: switching Spaces, full-screen app, plug/unplug a display, toggle Launch at Login and log out/in, Quit doesn't relaunch, launching a second copy exits.

### Release and install (in scope)

The plan ends with a working `brew install powersagitar/tap/space-indicator`:

1. Push this repo to `origin` and tag `v0.1.0`.
2. Write `Formula/space-indicator.rb` in the tap with the real tag-tarball URL and `sha256`, then open a pull request on the tap from branch `space-indicator` (the CI runner change to `xcode-27` is part of the same PR).
3. `brew install powersagitar/tap/space-indicator`, `brew test`, create the `/Applications` symlink, and launch it from there.
4. Check `space-indicator-cleanup` removes everything listed, then reinstall.

Every push needs the owner's confirmation at that moment.

## Left to the builder

- Exact source file breakdown and type names.
- How the `.xcodeproj` is created (Xcode template, then trimmed).
- Exact Homebrew macOS-version DSL.
