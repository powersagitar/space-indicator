# Space Indicator — Design

Date: 2026-11-26

## Intent

A personal macOS menu bar app that shows the 1-based number of the active Space, so the owner always knows where they are among their Spaces. Clicking the number opens a tiny menu (Launch at Login, Quit). No windows, no Dock icon. Personal use only: installed from source through the owner's existing Homebrew tap.

## Goals

- Menu bar shows only the active Space number, e.g. `3`, in the system font (SF Pro). `?` when the active Space can't be determined.
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
- `Info.plist`: `LSUIElement = YES`, `CFBundleIdentifier`, `CFBundleShortVersionString = $(MARKETING_VERSION)` (the formula passes `MARKETING_VERSION=#{version}` to `xcodebuild`, so it always matches the tag), `LSMinimumSystemVersion = 27.0`.
- App also calls `NSApp.setActivationPolicy(.accessory)` at startup.
- Release build: `ARCHS = arm64`, `ONLY_ACTIVE_ARCH = NO`.

### Reading the active Space (private CGS)

Declared with `@_silgen_name` (no bridging header):

- `CGSMainConnectionID() -> Int32`
- `CGSCopyManagedDisplaySpaces(_ cid: Int32) -> CFArray` — per-display array of dictionaries; each has `"Display Identifier"`, `"Current Space"` (dict with `ManagedSpaceID`), and `"Spaces"` (array in Mission Control order, each with `ManagedSpaceID` and `type`: 0 = desktop, 4 = full-screen).
- `CGSGetActiveSpace(_ cid: Int32) -> UInt64` — the Space with keyboard focus.

Algorithm: find the display whose `"Spaces"` contains the active Space ID; the number is that Space's 1-based index in that array. Every Space type counts (desktop 1, desktop 2, full-screen Safari → 3, next desktop → 4). If the active ID is 0, isn't found, or the data is malformed → `?`.

This works the same with "Displays have separate Spaces" on (each display's array numbers from 1) or off (a single array spanning displays).

With multiple displays, the menu bar item appears in every display's menu bar with the same text; it shows the number for the Space that has focus.

The parsing/numbering is a pure function over the CGS array (`[[String: Any]]` + active ID → `Int?`) so it can be unit-tested with fixture data.

### Single instance

At launch, if another running application has bundle ID `com.mohandong.SpaceIndicator` (`NSRunningApplication.runningApplications(withBundleIdentifier:)`, excluding the current process), exit immediately. Prevents two menu bar items when the LaunchAgent copy and an `open`-launched copy overlap. *(Designer's call.)*

### Update triggers

Recompute at launch, on `NSWorkspace.shared.notificationCenter` `activeSpaceDidChangeNotification`, and on `NSApplication.didChangeScreenParametersNotification`.

Verified by the owner on a multi-display setup: moving focus between displays updates the number with `activeSpaceDidChangeNotification` alone, so no `didActivateApplicationNotification` observer is needed.

### Menu bar item

- SwiftUI `MenuBarExtra` (`.menu` style) whose label is `Image(nsImage:)` of the number string (see Font).
- Font: `NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)`, drawn into a template `NSImage` (`TitleImage`) because the MenuBarExtra label ignores SwiftUI font modifiers — SF Pro with tabular digits so width doesn't jitter between e.g. 1 and 8. *(Designer's call; spec said "SF Pro".)*
- Menu (`MenuBarExtra` content):
  - **Launch at Login** — `Toggle` whose binding reads the LaunchAgent plist's existence on every read (checkmark iff it exists); the model also re-invalidates it on `NSMenu.didBeginTrackingNotification` (confirmed by the owner). The model hands focus back to the previously frontmost app when this app gets activated (e.g. by `open`).
  - separator
  - **Quit** with key equivalent `q` (⌘Q) → `NSApp.terminate(nil)`.

### Launch at Login (user LaunchAgent)

Not `SMAppService`, because the Cellar path changes every version.

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

- Source: GitHub tag tarball of `github.com/powersagitar/space-indicator` (already the repo's `origin`). Tags are `vX.Y.Z`, first release `v0.1.0`. No bottle — builds from source. *(Tag format is the designer's call.)*
- `depends_on xcode: :build`, `depends_on arch: :arm64`, and a macOS 27 minimum (use Homebrew's symbol for macOS 27 if it exists, else check `MacOS.version` in `install` and `odie`).
- `install`: `xcodebuild -project SpaceIndicator.xcodeproj -scheme SpaceIndicator -configuration Release -derivedDataPath build SYMROOT=build CODE_SIGN_IDENTITY=- build`, then `prefix.install "build/.../Space Indicator.app"`.
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
    - Uninstalling: run `space-indicator-cleanup` *before* `brew uninstall` (see below).

### Cleanup script (zap equivalent)

Formulas have no `zap` stanza (that's cask-only), so the formula installs a script as `bin/space-indicator-cleanup` (source in the repo at `scripts/space-indicator-cleanup`, POSIX `sh`). It does what a cask `zap` would:

1. Quits the running app (`osascript -e 'quit app id "com.mohandong.SpaceIndicator"'`, falling back to `pkill -x "Space Indicator"`).
2. `launchctl bootout gui/$(id -u)/com.mohandong.SpaceIndicator` if it's loaded (ignore errors).
3. Removes `~/Library/LaunchAgents/com.mohandong.SpaceIndicator.plist`.
4. Removes `/Applications/Space Indicator.app` only if it's a symlink into the Homebrew prefix (never a real app bundle).
5. Removes anything macOS may have created for the bundle ID: `~/Library/Preferences/com.mohandong.SpaceIndicator.plist`, `~/Library/Caches/com.mohandong.SpaceIndicator`, `~/Library/HTTPStorages/com.mohandong.SpaceIndicator`, and `~/Library/Saved Application State/com.mohandong.SpaceIndicator.savedState`.
6. Prints each item it removed. Running it again when there's nothing left is safe.

It doesn't run `brew uninstall` itself; the caveats say to run it first, then `brew uninstall space-indicator`. *(Designer's call: a script can't run from a formula's uninstall hook, since Homebrew has none.)*

- `test`: assert the bundle's executable exists, `Info.plist` has `LSUIElement`, and `space-indicator-cleanup` is executable.

**`/Applications` symlink (owner's requirement):** `/Applications/Space Indicator.app` is a symlink to `<prefix>/opt/space-indicator/Space Indicator.app`. It points at `opt`, not the Cellar, so it survives `brew upgrade`. Homebrew's `post_install` sandbox can only write inside Homebrew's own folders (checked in `Library/Homebrew/formula_installer.rb`), so the formula can't create it. The caveats give the one-time `ln` command, and the release step in this plan runs it. Launching through the symlink doesn't affect Launch at Login: `Bundle.main.bundleURL` resolves to the Cellar path, which gets rewritten to `opt` as usual. The builder must confirm that resolution actually happens through the symlink and resolve it explicitly if not.

### Testing

- Unit tests (Swift Testing, in `SpaceIndicatorTests`): numbering over fixture CGS arrays (single display, separate-spaces multi-display, full-screen in the middle, active ID missing → nil, malformed input → nil); Cellar → opt path rewrite (Cellar path, non-Cellar path, `/usr/local` prefix); plist content (KeepAlive false, path correct); self-repair decision.
- Manual check on the real machine: switching Spaces, full-screen app, plug/unplug a display, toggle Launch at Login and log out/in, Quit doesn't relaunch, launching a second copy exits.

### Release and install (in scope)

The plan ends with a working `brew install powersagitar/tap/space-indicator`:

1. Push this repo to `origin` and tag `v0.1.0`.
2. Write `Formula/space-indicator.rb` in the tap with the real tag-tarball URL and `sha256`, then commit and push it to the tap's remote.
3. `brew install powersagitar/tap/space-indicator`, `brew test`, create the `/Applications` symlink, and launch it from there.
4. Check `space-indicator-cleanup` removes everything listed, then reinstall.

Every push needs the owner's confirmation at that moment.

## Left to the builder

- Exact source file breakdown and type names.
- How the `.xcodeproj` is created (Xcode template, then trimmed).
- Exact Homebrew macOS-version DSL.
