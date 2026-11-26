#!/bin/sh
# Tests for space-indicator-cleanup. Never touches the real HOME or /Applications.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
script="$here/space-indicator-cleanup"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }

# Runs the script and asserts $app is still there as type $2 (test -d or -L)
# and that the script said it skipped it.
expect_kept() {
  out=$(sh "$script")
  test "$2" "$app" || fail "$1 removed"
  case "$out" in *skipped*) ;; *) fail "$1 no skipped message" ;; esac
}

export SI_SKIP_PROCESSES=1
export HOME="$tmp/home"
export SI_APPLICATIONS_DIR="$tmp/apps"
ID=com.mohandong.SpaceIndicator
L="$HOME/Library"
app="$SI_APPLICATIONS_DIR/Space Indicator.app"

seed() {
  mkdir -p "$L/LaunchAgents" "$L/Preferences" "$L/Caches/$ID" \
    "$L/HTTPStorages/$ID" "$L/Saved Application State/$ID.savedState" \
    "$SI_APPLICATIONS_DIR"
  : > "$L/LaunchAgents/$ID.plist"
  : > "$L/Preferences/$ID.plist"
}

# (a) full cleanup
seed
ln -s "/opt/homebrew/opt/space-indicator/Space Indicator.app" "$app"
out=$(sh "$script")
for p in "$L/LaunchAgents/$ID.plist" "$L/Preferences/$ID.plist" "$L/Caches/$ID" \
  "$L/HTTPStorages/$ID" "$L/Saved Application State/$ID.savedState"; do
  [ ! -e "$p" ] || fail "(a) still exists: $p"
done
[ ! -L "$app" ] || fail "(a) symlink remains"
n=$(printf '%s\n' "$out" | grep -c '^removed: ' || true)
[ "$n" -eq 6 ] || fail "(a) expected 6 removed lines, got $n"

# (b) idempotent
out=$(sh "$script")
[ "$out" = "nothing to clean up" ] || fail "(b) output: $out"

# (c) real directory is kept
mkdir "$app"
expect_kept "(c) directory" -d
rmdir "$app"

# (d) foreign symlink is kept
ln -s "/somewhere/else/Space Indicator.app" "$app"
expect_kept "(d) foreign symlink" -L
rm "$app"

# (e) lookalike symlink is kept
ln -s "/elsewhere/space-indicator/Space Indicator.app" "$app"
expect_kept "(e) lookalike symlink" -L
rm "$app"

# (f) Cellar-style symlink is removed
ln -s "/opt/homebrew/Cellar/space-indicator/0.1.0/Space Indicator.app" "$app"
sh "$script" >/dev/null
[ ! -L "$app" ] || fail "(f) Cellar symlink remains"

echo PASS
