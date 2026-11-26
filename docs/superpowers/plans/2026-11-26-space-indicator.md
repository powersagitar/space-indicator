# Space Indicator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS menu bar app showing each display's current Space 1-based number, with a Launch at Login / Quit menu, installed from source via `brew install powersagitar/tap/space-indicator`.

**Architecture:** One Xcode project. Pure logic (Space numbering, LaunchAgent paths and plist IO) lives in `SpaceIndicator/Core/` and is compiled into both the app target and a host-less unit test target, so tests never launch the app. SwiftUI wiring (`MenuBarExtra`, notifications, private CGS calls) lives in `SpaceIndicator/App/`. A Homebrew formula in the existing tap builds the project with `xcodebuild` and installs a cleanup script.

**Tech Stack:** Swift 6, SwiftUI (`MenuBarExtra`), Swift Testing, Xcode 27.2, Homebrew formula (Ruby), POSIX `sh`.

**Spec:** `docs/superpowers/specs/2026-11-26-space-indicator-design.md`

## Global Constraints

- Deployment target `MACOSX_DEPLOYMENT_TARGET = 27.0`; `ARCHS = arm64`; `ONLY_ACTIVE_ARCH = NO` for Release.
- Bundle ID `com.mohandong.SpaceIndicator`; `PRODUCT_NAME = "Space Indicator"` → `Space Indicator.app/Contents/MacOS/Space Indicator`; target, scheme and module `SpaceIndicator`.
- `LSUIElement = YES`; `CFBundleShortVersionString = $(MARKETING_VERSION)`; `LSMinimumSystemVersion` 27.0.
- Ad-hoc signing: `CODE_SIGN_IDENTITY = "-"`, `CODE_SIGN_STYLE = Manual`, no `DEVELOPMENT_TEAM`. App Sandbox off. Hardened runtime off.
- SwiftUI `MenuBarExtra` UI (owner's decision, replaces AppKit-only): no storyboard, no xib, no windows.
- LaunchAgent label and filename: `com.mohandong.SpaceIndicator` / `~/Library/LaunchAgents/com.mohandong.SpaceIndicator.plist`; `RunAtLoad` true, `KeepAlive` false, `ProcessType` `Interactive`.
- Formula `space-indicator` (class `SpaceIndicator`), `license "GPL-3.0-only"`, no bottle, tags `vX.Y.Z`, first `v0.1.0`.
- Every path containing `Space Indicator` is quoted in shell and Ruby.
- No `launchctl` calls from the app. The app asks for no permissions.
- Every `git push` (this repo, tag, tap) needs the owner's confirmation at that moment.
- Work happens on branch `feat/space-indicator`; it is fast-forwarded into `main` only in Task 6.
- Every commit message (this repo and the tap) ends with the line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Space IDs arrive as `NSNumber`, sometimes negative-typed `Int64`.** The CGS dictionaries bridge as `NSNumber`, and a reader that only accepts `UInt64` gets `?` forever. Expected: any integer `NSNumber` is read as the ID. Test `idsReadFromAnyIntegerNSNumber` in Task 2.
2. **One display's entry is malformed while another is fine.** Expected: a display dict with a `Display Identifier` but no `Spaces` array is `nil` (shown as `?`), a dict with neither is skipped, and the other displays are still numbered. If a display's own `Spaces` array has an entry without a readable ID, or holds its current ID more than once, that display is `nil` (shown as `?`), since its index can't be trusted; the other displays keep their numbers. Tests `identifiedDisplayWithoutSpacesIsNil`, `skipsDisplayWithNeitherIdentifierNorSpaces`, `unreadableEntryMakesThatDisplayNil` and `duplicateCurrentIDMakesThatDisplayNil` in Task 2.
3. **The LaunchAgent plist exists but is corrupt.** Expected: the checkmark stays on because the file exists, and self-repair from a Cellar install overwrites it with a valid plist. Test `repairOverwritesCorruptPlist` in Task 3.
4. **`~/Library/LaunchAgents` doesn't exist on a fresh account.** Expected: turning it on creates the directory. Test `installCreatesMissingDirectory` in Task 3.
5. **A revision version (`0.1.0_1`) or an Intel-style `/usr/local` prefix.** Expected: it still rewrites to `opt`. Test `rewritesRevisionAndUsrLocal` in Task 3.

---

## File Structure

```
SpaceIndicator.xcodeproj/project.pbxproj                    # hand-written, objectVersion 77, synchronized folders
SpaceIndicator.xcodeproj/xcshareddata/xcschemes/SpaceIndicator.xcscheme   # shared scheme: build app, test SpaceIndicatorTests
SpaceIndicator/App/SpaceIndicatorApp.swift    # @main App: single-instance check, MenuBarExtra scene
SpaceIndicator/App/SpaceIndicatorModel.swift  # title, observers, Launch at Login binding, launch-time self-repair
SpaceIndicator/App/CGS.swift           # @_silgen_name private decls + live read
SpaceIndicator/Core/SpaceNumbering.swift  # pure numbering + title
SpaceIndicator/Core/LaunchAgent.swift     # pure path/plist + LaunchAgentStore file IO
SpaceIndicator/Core/SingleInstance.swift  # wait briefly for a quitting instance (final fix wave)
SpaceIndicator/Core/TitleImage.swift      # title string → tabular-digit template NSImage
SpaceIndicatorTests/SpaceNumberingTests.swift
SpaceIndicatorTests/LaunchAgentTests.swift
SpaceIndicatorTests/TitleImageTests.swift
SpaceIndicatorTests/SingleInstanceTests.swift
scripts/space-indicator-cleanup        # POSIX sh, installed to bin/
scripts/test-cleanup.sh                # sandboxed test of the cleanup script
<tap>/Formula/space-indicator.rb       # tap = /opt/homebrew/Library/Taps/powersagitar/homebrew-tap (origin git@github.com:powersagitar/homebrew-tap.git)
```

---

### Task 1: Xcode project skeleton that builds and tests

**Files:**
- Create: `SpaceIndicator.xcodeproj/project.pbxproj`, `SpaceIndicator.xcodeproj/xcshareddata/xcschemes/SpaceIndicator.xcscheme`
- Create: `SpaceIndicator/App/main.swift` (temporary placeholder, deleted in Task 4), `SpaceIndicator/Core/SpaceNumbering.swift` (temporary placeholder `enum SpaceNumbering {}`)
- Test: `SpaceIndicatorTests/SpaceNumberingTests.swift` (one placeholder `@Test func placeholder() { #expect(Bool(true)) }`)

**Interfaces:**
- Produces: buildable targets `SpaceIndicator` (app) and `SpaceIndicatorTests` (unit test bundle); later tasks add files under the synchronized folders without touching the pbxproj.

Project decisions (the pbxproj is hand-written; no Xcode GUI, no XcodeGen):
- `objectVersion = 77`, using `PBXFileSystemSynchronizedRootGroup` for `SpaceIndicator/App`, `SpaceIndicator/Core` and `SpaceIndicatorTests`.
- App target `fileSystemSynchronizedGroups` = App + Core. Test target = Core + SpaceIndicatorTests. Core is compiled into both.
- Test target: `com.apple.product-type.bundle.unit-test`, **no** `TEST_HOST`/`BUNDLE_LOADER`, `PRODUCT_BUNDLE_IDENTIFIER = com.mohandong.SpaceIndicatorTests`, no target dependency on the app.
- App target: `GENERATE_INFOPLIST_FILE = YES`, `INFOPLIST_KEY_LSUIElement = YES`, `MARKETING_VERSION = 0.1.0`, `CURRENT_PROJECT_VERSION = 1`, plus every value in Global Constraints. `SWIFT_VERSION = 6.0`.
- Shared scheme `SpaceIndicator`: builds the app, its Test action runs `SpaceIndicatorTests`, Run uses Debug and Archive uses Release.

- [ ] **Step 1: Create branch** — `git switch -c feat/space-indicator`
- [ ] **Step 2: Write the pbxproj, the scheme, and the placeholder files above.**
- [ ] **Step 3: Verify the project parses**
  Run: `xcodebuild -list -project SpaceIndicator.xcodeproj`
  Expected: targets `SpaceIndicator`, `SpaceIndicatorTests`; scheme `SpaceIndicator`.
- [ ] **Step 4: Verify the Release build and bundle shape**
  Run: `xcodebuild -project SpaceIndicator.xcodeproj -scheme SpaceIndicator -configuration Release -derivedDataPath build CODE_SIGN_IDENTITY=- MARKETING_VERSION=9.9.9 build && A="build/Build/Products/Release/Space Indicator.app" && /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' -c 'Print :LSUIElement' -c 'Print :CFBundleShortVersionString' -c 'Print :LSMinimumSystemVersion' "$A/Contents/Info.plist" && lipo -archs "$A/Contents/MacOS/Space Indicator" && codesign -dv "$A" 2>&1 | grep Signature`
  Expected: `com.mohandong.SpaceIndicator`, `true`, `9.9.9`, `27.0`, `arm64`, `Signature=adhoc`.
- [ ] **Step 5: Verify tests run**
  Run: `xcodebuild test -project SpaceIndicator.xcodeproj -scheme SpaceIndicator -derivedDataPath build`
  Expected: `** TEST SUCCEEDED **`, and no Space Indicator process launched during the run.
- [ ] **Step 6: Ignore build output** — append `/build/` to `.gitignore`.
- [ ] **Step 7: Commit** — `git add -A && git commit -m "Add Xcode project skeleton"`

---

### Task 2: Space numbering

**Files:**
- Modify: `SpaceIndicator/Core/SpaceNumbering.swift`
- Test: `SpaceIndicatorTests/SpaceNumberingTests.swift` (replace placeholder)

**Interfaces:**
- Produces:
  - `enum SpaceNumbering`
  - `static func numbers(displays: [[String: Any]], screenOrder: [String]) -> [Int?]` returns, per display, the 1-based position of its `"Current Space"` in its own `"Spaces"` array; displays in `screenOrder` (by `"Display Identifier"`) come first, the rest in CGS order.
  - `static func title(for numbers: [Int?]) -> String` joins with ` · `, nil as `?`, empty as `?`.
  - Changed after Task 4 (owner request; a spike showed a status item is mirrored across displays, so one label lists every display's number). This replaced the original single-number API.

Rules:
- An ID is read from key `ManagedSpaceID` as `NSNumber` → `uint64Value`, accepting any integer NSNumber (not a float, and not a Bool/CFBoolean — final fix wave).
- Current ID missing, unreadable or 0 → that display is `nil`.
- A display dict with a `"Display Identifier"` but no `[[String: Any]]` `"Spaces"` → `nil` (changed in the final fix wave; it was skipped). A dict with neither is skipped.
- A display whose `Spaces` has any entry with an unreadable ID, lacks the current ID, or contains it more than once → `nil`.
- `type` is ignored, because every Space counts.

Fixture helper in the test file: `func space(_ id: Any, type: Int = 0) -> [String: Any]` and `func display(_ spaces: [[String: Any]], current: Any? = nil, id: String = "Main") -> [String: Any]` (sets `"Display Identifier": id` and, when `current` is non-nil, `"Current Space": ["ManagedSpaceID": current]`). The suite's `numbers(_:order:)` calls `SpaceNumbering.numbers(displays:screenOrder:)` with `order` defaulting to `[]`.

- [ ] **Step 1: Write the failing tests** (`@Suite struct SpaceNumberingTests`, 11 tests):
  - `singleDisplay`: spaces 10, 11, 12; current 11 → `[2]`.
  - `mainSingleArrayOneNumber`: spaces 10, 11, 20 in one `Main` array; current 20 → `[3]`.
  - `fullScreenCountsByPosition`: 10 (type 0), 11 (type 0), 50 (type 4), 12 (type 0); current 50 → `[3]`; current 12 → `[4]`.
  - `eachDisplayHasItsOwnNumber`: display A [10, 11] current 10, display B [20, 21, 22] current 22 → `[1, 3]`.
  - `orderedByScreenOrderUnknownLast`: A [10, 11] current 11, B [20, 21] current 20, C [30, 31, 32] current 32; order `["B", "A"]` → `[1, 2, 3]`; order `["C"]` → `[3, 2, 1]`.
  - `missingOrUnknownCurrentIsNil`: spaces 10, 11 with no current → `[nil]`; current 0 → `[nil]`; current 99 → `[nil]`; `displays: []` → `[]`.
  - `idsReadFromAnyIntegerNSNumber`: ids given as `NSNumber(value: Int64(10))`, `NSNumber(value: UInt64(11))`, `NSNumber(value: Int32(12))`; current `NSNumber(value: Int32(12))` → `[3]`; current `NSNumber(value: 11.0)` → `[nil]`.
  - `identifiedDisplayWithoutSpacesIsNil` (was `skipsMalformedOtherDisplay`): `["Display Identifier": "X"]` (no Spaces), `["Display Identifier": "Y", "Spaces": "bad"]`, then display [10, 11] current 11 → `[nil, nil, 2]`.
  - Final fix wave additions: `boolIDsAreUnreadable`, `floatEntryInSpacesMakesThatDisplayNil`, `skipsDisplayWithNeitherIdentifierNorSpaces`.
  - `unreadableEntryMakesThatDisplayNil`: A [10, `space("bad")`, 12] current 12, B [20, 21] current 21 → `[nil, 2]`.
  - `duplicateCurrentIDMakesThatDisplayNil`: A [10, 11, 10] current 10, B [20, 21] current 21 → `[nil, 2]`.
  - `titleFormatting`: `title(for: [2, 1]) == "2 · 1"`, `title(for: [3]) == "3"`, `title(for: [3, nil]) == "3 · ?"`, `title(for: []) == "?"`.
- [ ] **Step 2: Run, expect failure**
  Run: `xcodebuild test -project SpaceIndicator.xcodeproj -scheme SpaceIndicator -derivedDataPath build -only-testing:SpaceIndicatorTests/SpaceNumberingTests`
  Expected: build fails (`numbers`/`title` not found).
- [ ] **Step 3: Implement `SpaceNumbering.numbers` and `title`** per the rules above.
- [ ] **Step 4: Run, expect pass** (same command): `** TEST SUCCEEDED **`, 11 tests.
- [ ] **Step 5: Commit** — `git commit -am "Add Space numbering"` (add new files first if any).

---

### Task 3: LaunchAgent logic and store

**Files:**
- Create: `SpaceIndicator/Core/LaunchAgent.swift`
- Test: `SpaceIndicatorTests/LaunchAgentTests.swift`

**Interfaces:**
- Produces:
  - `enum LaunchAgent`
    - `static let label = "com.mohandong.SpaceIndicator"`
    - `static func stableAppPath(resolvedBundlePath: String) -> String`. It matches `^(.+)/Cellar/space-indicator/[^/]+/(.+)$` and returns `"$1/opt/space-indicator/$2"`; otherwise it returns the input unchanged.
    - `static func isCellarPath(_ resolvedBundlePath: String) -> Bool`, true when that regex matches.
    - `static func executablePath(appPath: String) -> String` returns `appPath + "/Contents/MacOS/Space Indicator"`.
    - `static func plist(executablePath: String) -> [String: Any]` returns exactly the keys `Label`, `ProgramArguments` = `[executablePath]`, `RunAtLoad` = true, `KeepAlive` = false and `ProcessType` = `"Interactive"`.
  - `struct LaunchAgentStore`
    - `init(directory: URL)`
    - `static var user: LaunchAgentStore`, with directory `~/Library/LaunchAgents` taken from `FileManager.default.homeDirectoryForCurrentUser`.
    - `var plistURL: URL` is `directory/com.mohandong.SpaceIndicator.plist`.
    - `func isInstalled() -> Bool` checks only that the file exists.
    - `func install(executablePath: String) throws` creates the directory and writes an XML plist via `PropertyListSerialization`, atomically.
    - `func uninstall() throws` is a no-op if the file is absent.
    - `func installedExecutablePath() -> String?` returns `ProgramArguments[0]`, or nil if the file is missing or unparseable.
    - `@discardableResult func repairIfNeeded(resolvedBundlePath: String) throws -> Bool` returns true when it rewrote the file. It rewrites only if `isInstalled()`, `LaunchAgent.isCellarPath(resolvedBundlePath)`, and `installedExecutablePath() != executablePath(appPath: stableAppPath(...))`.

Tests use a fresh temp directory per test: `FileManager.default.temporaryDirectory/UUID`. Constants: `cellar = "/opt/homebrew/Cellar/space-indicator/0.1.0/Space Indicator.app"`, `opt = "/opt/homebrew/opt/space-indicator/Space Indicator.app"`.

- [ ] **Step 1: Write the failing tests** (`@Suite struct LaunchAgentTests`):
  - `rewritesCellarToOpt`: `stableAppPath(cellar) == opt`, `isCellarPath(cellar)`.
  - `rewritesRevisionAndUsrLocal`: `"/usr/local/Cellar/space-indicator/0.1.0_1/Space Indicator.app"` → `"/usr/local/opt/space-indicator/Space Indicator.app"`.
  - `leavesOtherPathsUnchanged`: for each of `"/Users/me/Library/Developer/Xcode/DerivedData/X/Build/Products/Debug/Space Indicator.app"`, `"/Applications/Space Indicator.app"`, `"/opt/homebrew/Cellar/other/1.0/Space Indicator.app"` and `"/opt/homebrew/Cellar/space-indicator/Space Indicator.app"`, the output equals the input and `isCellarPath` is false.
  - `plistContents`: for `executablePath(appPath: opt)`, `Label == "com.mohandong.SpaceIndicator"`, `ProgramArguments == [opt + "/Contents/MacOS/Space Indicator"]`, `RunAtLoad == true`, `KeepAlive == false`, `ProcessType == "Interactive"`, and the dict has exactly 5 keys.
  - `installCreatesMissingDirectory`: the store's directory is `tmp/LaunchAgents`, which doesn't exist. After `install`, `isInstalled()` is true, `installedExecutablePath()` equals the path, and the file starts with `<?xml`.
  - `uninstallRemovesAndIsIdempotent`: install, uninstall, then `isInstalled() == false`. A second uninstall doesn't throw.
  - `repairRewritesStaleCellarPath`: install `"/old/path"`. Then `repairIfNeeded(cellar)` returns true and the installed path is `opt + "/Contents/MacOS/Space Indicator"`. A second call returns false.
  - `repairOverwritesCorruptPlist`: write `"garbage"` to `plistURL`. `isInstalled()` is true and `repairIfNeeded(cellar)` returns true, after which `installedExecutablePath()` is non-nil.
  - `repairSkipsNonCellarBuild`: install `"/old/path"`. `repairIfNeeded(<DerivedData path>)` returns false and the path is still `"/old/path"`.
  - `repairSkipsWhenNotInstalled`: `repairIfNeeded(cellar)` returns false and no file is created.
- [ ] **Step 2: Run, expect failure**
  Run: `xcodebuild test -project SpaceIndicator.xcodeproj -scheme SpaceIndicator -derivedDataPath build -only-testing:SpaceIndicatorTests/LaunchAgentTests`
  Expected: build fails (`LaunchAgent` not found).
- [ ] **Step 3: Implement `LaunchAgent` and `LaunchAgentStore`** per the interface above, using `NSRegularExpression` or a Swift `Regex` for the rewrite.
- [ ] **Step 4: Run all tests, expect pass**
  Run: `xcodebuild test -project SpaceIndicator.xcodeproj -scheme SpaceIndicator -derivedDataPath build`
  Expected: `** TEST SUCCEEDED **`, 21 tests (11 numbering + 10 LaunchAgent; `TitleImageTests` adds 2 more in Task 4, for 23).
- [ ] **Step 5: Commit** — `git add -A && git commit -m "Add LaunchAgent path logic and store"`

---

### Task 4: App wiring (CGS, menu bar extra, triggers, single instance)

**Files:**
- Create: `SpaceIndicator/App/CGS.swift`, `SpaceIndicator/App/SpaceIndicatorApp.swift`, `SpaceIndicator/App/SpaceIndicatorModel.swift`, `SpaceIndicator/Core/TitleImage.swift`
- Test: `SpaceIndicatorTests/TitleImageTests.swift` (`"1"` and `"8"` give equal widths; `"?"` gives a template image)
- Delete: `SpaceIndicator/App/main.swift`

**Interfaces:**
- Consumes: `SpaceNumbering.numbers(displays:screenOrder:)`, `SpaceNumbering.title(for:)`, `LaunchAgent.stableAppPath/executablePath`, `LaunchAgentStore.user` and its methods.
- Produces:
  - `enum CGS` with `@MainActor static func spaceNumbers() -> [Int?]` (private `@_silgen_name` declarations of `CGSMainConnectionID`, `CGSCopyManagedDisplaySpaces` at file scope; casts to `[[String: Any]]`, empty if the cast fails; screen order from `NSScreen.screens` sorted by `minX` then `minY`, mapped to display UUID strings).
  - `@main struct SpaceIndicatorApp: App` with a `MenuBarExtra` scene, `.menuBarExtraStyle(.menu)`.
  - `@MainActor @Observable final class SpaceIndicatorModel`.

Behaviour to implement:
- `SpaceIndicatorApp.init`: if another process has bundle ID `com.mohandong.SpaceIndicator` (ignoring `isTerminated` ones, after waiting up to 1 s via `SingleInstance.anotherInstanceRemains` for it to exit — final fix wave), call `exit(0)`; then `NSApplication.shared.setActivationPolicy(.accessory)` and create the model.
- Label: `Image(nsImage: TitleImage.make(model.title))` with `.accessibilityLabel(model.title)`; `TitleImage` also sets the image's `accessibilityDescription` to the title (MenuBarExtra ignores font modifiers; `TitleImage` in Core draws the tabular-digit font into a template image). Content: `Toggle("Launch at Login")`, `Divider()`, `Button("Quit")` with `.keyboardShortcut("q")` calling `NSApp.terminate(nil)`.
- Model init: `refresh()` (title = `SpaceNumbering.title(for: CGS.spaceNumbers())`), observers for `NSWorkspace.activeSpaceDidChangeNotification` (workspace center) and `NSApplication.didChangeScreenParametersNotification` (both call `refresh()`), an observer for `NSMenu.didBeginTrackingNotification` that re-invalidates the Launch at Login state, then `repairIfNeeded(resolvedBundlePath: Bundle.main.bundleURL.resolvingSymlinksInPath().path)`, logging errors.
- Launch at Login binding: getter returns `LaunchAgentStore.user.isInstalled()`; setter installs or uninstalls, logging errors with `Logger(subsystem: "com.mohandong.SpaceIndicator", category: "LaunchAgent")`, never showing UI.
- Correction: focus changes between displays do not fire `activeSpaceDidChangeNotification`, but the label no longer depends on focus. The model observes `NSWorkspace.didActivateApplicationNotification` to restore focus to the previous app when this app is activated.
- Final fix wave: `refresh()` also runs on `didActivateApplicationNotification`, `NSWorkspace.didTerminateApplicationNotification` and `NSMenu.didBeginTrackingNotification`, because a Space's position can change without a Space switch (reordering in Mission Control, quitting a full-screen app before the current Space).
- Final fix wave, follow-up (supersedes "no polling timer"): a diagnostic showed macOS posts no notification for Mission Control reordering or full-screen Space removal; the `Spaces` array just changes. So the model also holds a repeating `Timer` (1.0 s, tolerance 0.5 s, main run loop, `.common` mode; closure `[weak self]` + `MainActor.assumeIsolated { self?.refresh() }`), and `refresh()` assigns `title` only when it differs, so @Observable doesn't re-render the label every second. The notification triggers stay for instant response.

- [ ] **Step 1: Write the `TitleImageTests`, then implement the files above.**
- [ ] **Step 2: Build and run tests**
  Run: `xcodebuild test -project SpaceIndicator.xcodeproj -scheme SpaceIndicator -derivedDataPath build`
  Expected: `** TEST SUCCEEDED **`, 23 tests, with no warnings in App/ or Core/ files about Sendable or MainActor isolation.
- [ ] **Step 3: Manual check, single display.** Run `open "build/Build/Products/Debug/Space Indicator.app"` and check:
  - A number appears, there's no Dock icon, and no permission prompt appears.
  - Switching Spaces with Ctrl-←/→ updates the number.
  - Making an app full screen shows its position (e.g. `3` after Desktop 1 and 2).
  - The menu shows Launch at Login (unchecked), a separator, and Quit ⌘Q.
  - Toggling Launch at Login creates `~/Library/LaunchAgents/com.mohandong.SpaceIndicator.plist` containing the DerivedData path, and the checkmark is on when you reopen the menu. Toggling again removes it.
  - Running the `open` command a second time doesn't add a second number.
  - Quit removes the item.
- [ ] **Step 4: Manual check, multiple displays** (ask the owner to do this if no second display is attached):
  - Turn on "Displays have separate Spaces".
  - The label shows one number per display, left to right as the displays are arranged, joined by ` · ` (e.g. `2 · 1`), and the same label appears in every display's menu bar.
  - Switch Spaces on one display: only that display's number changes.
  - Click into a window on the other display: the label does not change (it doesn't depend on focus).
  - Plugging or unplugging a display refreshes the label (one number fewer or more).
  - Turn "Displays have separate Spaces" off (needs log out): the label shows a single number.
- [ ] **Step 5: Commit** — `git add -A && git commit -m "Wire menu bar extra, menu, Space triggers and Launch at Login"`

---

### Task 5: Cleanup script

**Files:**
- Create: `scripts/space-indicator-cleanup` (mode 755), `scripts/test-cleanup.sh` (mode 755)

**Interfaces:**
- Produces: `space-indicator-cleanup` takes no arguments and exits 0. It honours `SI_APPLICATIONS_DIR` (default `/Applications`) and `SI_SKIP_PROCESSES=1`, which skips the quit and `launchctl` steps; both exist for testing. It uses `$HOME`.

Behaviour (spec §Cleanup), in order:
1. Unless `SI_SKIP_PROCESSES=1`:
   - If `pgrep -x "Space Indicator"` finds it, run `osascript -e 'quit app id "com.mohandong.SpaceIndicator"'`. If it's still running after 2 seconds, run `pkill -x "Space Indicator"`; if it's still running up to 2 seconds after that, run `pkill -9 -x "Space Indicator"` (final fix wave).
   - Run `launchctl bootout "gui/$(id -u)/com.mohandong.SpaceIndicator" 2>/dev/null || true`.
2. Remove `$HOME/Library/LaunchAgents/com.mohandong.SpaceIndicator.plist`.
3. Remove `$SI_APPLICATIONS_DIR/Space Indicator.app` only if it's a symlink (`[ -L ]`) whose `readlink` matches `*/opt/space-indicator/Space Indicator.app` or `*/Cellar/space-indicator/*/Space Indicator.app` (i.e. points into the Homebrew prefix). Otherwise print `skipped (not a Homebrew symlink): <path>`.
4. Remove `$HOME/Library/Preferences/com.mohandong.SpaceIndicator.plist`, `$HOME/Library/Caches/com.mohandong.SpaceIndicator`, `$HOME/Library/HTTPStorages/com.mohandong.SpaceIndicator` and `"$HOME/Library/Saved Application State/com.mohandong.SpaceIndicator.savedState"`.
5. For each path actually removed, print `removed: <path>`. If nothing was removed, print `nothing to clean up`.

- [ ] **Step 1: Write `scripts/test-cleanup.sh`.** It makes a temp `HOME` and a temp apps dir, sets `SI_SKIP_PROCESSES=1`, and asserts these cases (exit 1 on any failure, print `PASS` at the end):
  - **(a)** Seed all 4 Library items, the plist, and a symlink `Space Indicator.app` → `/opt/homebrew/opt/space-indicator/Space Indicator.app` (a dangling link is fine). After the run all 6 are gone, and the output has 6 `removed:` lines.
  - **(b)** Run again: the output is `nothing to clean up` and the exit status is 0.
  - **(c)** A real directory `Space Indicator.app` in the apps dir still exists after the run, and the output contains `skipped`.
  - **(d)** A symlink to `/somewhere/else/Space Indicator.app` still exists after the run, and the output contains `skipped`.
  - **(e)** A lookalike symlink to `/elsewhere/space-indicator/Space Indicator.app` still exists after the run, and the output contains `skipped`.
  - **(f)** A dangling Cellar-style symlink to `/opt/homebrew/Cellar/space-indicator/0.1.0/Space Indicator.app` is removed.
- [ ] **Step 2: Run, expect failure** — `sh scripts/test-cleanup.sh` fails because the script is missing.
- [ ] **Step 3: Implement `scripts/space-indicator-cleanup`** (`#!/bin/sh`, `set -eu`, every path quoted).
- [ ] **Step 4: Run, expect pass** — `sh scripts/test-cleanup.sh` prints `PASS`. If `shellcheck` is installed, `shellcheck scripts/*` should be clean.
- [ ] **Step 5: Commit** — `git add scripts && git commit -m "Add cleanup script"`

---

### Task 6: Release, formula, install

**Files:**
- Create: `/opt/homebrew/Library/Taps/powersagitar/homebrew-tap/Formula/space-indicator.rb`

**Interfaces:**
- Consumes: the scheme and product path from Task 1, and `scripts/space-indicator-cleanup` from Task 5.

Formula decisions:
- **Metadata:**
  - `desc "Menu bar app showing the current macOS Space number"`
  - `homepage "https://github.com/powersagitar/space-indicator"`
  - `url "https://github.com/powersagitar/space-indicator/archive/refs/tags/v0.1.0.tar.gz"`, plus its `sha256`
  - `license "GPL-3.0-only"`
- **Dependencies:** `depends_on xcode: ["27.0", :build]`, `depends_on arch: :arm64`, `depends_on macos: :golden_gate` (that's macOS 27 in Homebrew's `macos_version.rb`).
- **`install`:**
  - Run the early checks first; each failure calls `odie` with the fix command:
    - `Utils.safe_popen_read("xcode-select", "-p")` containing `CommandLineTools` → the `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` fix
    - `quiet_system("xcodebuild", "-license", "check")` false → `sudo xcodebuild -license accept`
    - `quiet_system("xcodebuild", "-checkFirstLaunchStatus")` false → `sudo xcodebuild -runFirstLaunch`
  - Then `system "xcodebuild", "-project", "SpaceIndicator.xcodeproj", "-scheme", "SpaceIndicator", "-configuration", "Release", "-derivedDataPath", "build", "CODE_SIGN_IDENTITY=-", "MARKETING_VERSION=#{version}", "build"`.
  - Then `prefix.install "build/Build/Products/Release/Space Indicator.app"` and `bin.install "scripts/space-indicator-cleanup"`.
- **`caveats`:** the Setup and Common pitfalls lists from the spec, word for word in substance, using `#{opt_prefix}` in the `ln -sfn` command. This includes that turning on Launch at Login shows macOS's "Background Items Added" notice, which is expected.
- **`test`:**
  - `assert_predicate prefix/"Space Indicator.app/Contents/MacOS/Space Indicator", :executable?`
  - `assert_equal "true", shell_output("/usr/libexec/PlistBuddy -c 'Print :LSUIElement' '#{prefix}/Space Indicator.app/Contents/Info.plist'").strip`
  - `assert_predicate bin/"space-indicator-cleanup", :executable?`

- [ ] **Step 1: Merge and push the app repo (confirm with the owner first).**
  - `git switch main && git merge --ff-only feat/space-indicator`
  - Ask the owner. Then `git push origin main && git tag v0.1.0 && git push origin v0.1.0`.
- [ ] **Step 2: Get the sha256**
  - Run: `curl -fsSL https://github.com/powersagitar/space-indicator/archive/refs/tags/v0.1.0.tar.gz | shasum -a 256`
  - Expected: a 64-hex digest.
- [ ] **Step 3: Write the formula** per the decisions above.
- [ ] **Step 4: Lint**
  - Run: `brew style powersagitar/tap/space-indicator && brew audit --strict --new powersagitar/tap/space-indicator`
  - Expected: no offenses. The tap's CI runs `brew test-bot --only-tap-syntax` on push, so this has to be clean.
- [ ] **Step 5: Install from source and test**
  - Run: `brew install --build-from-source powersagitar/tap/space-indicator && brew test powersagitar/tap/space-indicator`
  - Expected: the install succeeds, the caveats print, and the test passes.
  - Confirm the installed version: `/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$(brew --prefix)/opt/space-indicator/Space Indicator.app/Contents/Info.plist"` → `0.1.0`.
- [ ] **Step 6: Symlink and launch**
  - Run: `ln -sfn "$(brew --prefix)/opt/space-indicator/Space Indicator.app" "/Applications/Space Indicator.app" && open "/Applications/Space Indicator.app"`
  - Turn on Launch at Login. The plist's `ProgramArguments[0]` should be `/opt/homebrew/opt/space-indicator/Space Indicator.app/Contents/MacOS/Space Indicator`, not a Cellar or `/Applications` path. This confirms the symlink resolves.
  - Ask the owner to log out and back in. The number should appear. Quit, and it should stay quit.
- [ ] **Step 7: Check self-repair**
  - Quit the app.
  - Replace `ProgramArguments[0]` with `/old/path`: `plutil -replace ProgramArguments.0 -string /old/path ~/Library/LaunchAgents/com.mohandong.SpaceIndicator.plist`.
  - Run `open "/Applications/Space Indicator.app"`. The plist should show the `opt` path again.
- [ ] **Step 8: Check cleanup, then reinstall**
  - Run: `space-indicator-cleanup`. Expected: `removed:` lines for the plist and the `/Applications` symlink, and the app quits.
  - Then run `brew uninstall space-indicator && brew install --build-from-source powersagitar/tap/space-indicator`, recreate the symlink, and relaunch.
- [ ] **Step 9: Commit and push the tap (confirm with the owner first).**
  - Commit in the tap: `git -C /opt/homebrew/Library/Taps/powersagitar/homebrew-tap add Formula/space-indicator.rb && git -C … commit -m "space-indicator 0.1.0 (new formula)"`.
  - Ask the owner. Then `git -C … push origin main`.
  - Expected: the tap's test-bot workflow passes on that push. Check with `gh run list -R powersagitar/homebrew-tap -L 1`.
