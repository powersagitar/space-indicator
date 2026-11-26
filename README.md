# Space Indicator

A tiny macOS menu bar app that shows each display's current Space as a number.

With one display the menu bar shows e.g. `3`. With several, every display's number is listed left to right, e.g. `2 · 1`. Numbers match the order in Mission Control, starting at 1, and full-screen Spaces count by position. If a display's Space can't be determined, it shows `?` rather than a guess.

Clicking the number opens a menu with **Launch at Login** and **Quit** (⌘Q). There are no windows, no Dock icon, and no permission prompts.

## Requirements

- macOS 27 or later, Apple Silicon only.
- Full Xcode 27 or later to build (the Command Line Tools alone are not enough).

## Install

From the Homebrew tap:

```sh
brew install powersagitar/tap/space-indicator
ln -sfn "$(brew --prefix)/opt/space-indicator/Space Indicator.app" "/Applications/Space Indicator.app"
open "/Applications/Space Indicator.app"
```

The symlink points at Homebrew's `opt` path, so it survives `brew upgrade`. Launch at Login does too.

If the build fails on a fresh machine:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
```

If the number doesn't appear, check System Settings → Menu Bar (items can be hidden there). On notched MacBooks a full menu bar can push it behind the notch.

Turning on Launch at Login makes macOS show a "Background Items Added" notice. That's expected: it writes a user LaunchAgent at `~/Library/LaunchAgents/com.mohandong.SpaceIndicator.plist`.

## Uninstall

Run the cleanup script first, then uninstall:

```sh
space-indicator-cleanup
brew uninstall space-indicator
```

`space-indicator-cleanup` quits the app, removes the LaunchAgent, the `/Applications` symlink (only if it is a symlink into Homebrew) and any preferences, caches or saved state macOS created for the app.

## Build from source

```sh
xcodebuild -project SpaceIndicator.xcodeproj -scheme SpaceIndicator \
  -configuration Release -derivedDataPath build CODE_SIGN_IDENTITY=- build
open "build/Build/Products/Release/Space Indicator.app"
```

Run the tests:

```sh
xcodebuild test -project SpaceIndicator.xcodeproj -scheme SpaceIndicator -derivedDataPath build
sh scripts/test-cleanup.sh
```

## How it works

The app reads each display's Spaces with the private `CGSCopyManagedDisplaySpaces` call and finds the current Space's position in that display's list. It updates on every Space switch and also polls once a second, because macOS sends no notification when Spaces are reordered in Mission Control or a full-screen Space goes away.

Design notes are in [`docs/superpowers/specs`](docs/superpowers/specs/2026-11-26-space-indicator-design.md).

## License

GPL-3.0-only. See [LICENSE](LICENSE).
