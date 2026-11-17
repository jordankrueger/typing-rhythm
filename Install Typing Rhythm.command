#!/bin/zsh
# Installs Typing Rhythm: a private key-timing logger that runs inside Hammerspoon.
# Safe to run again; it won't duplicate anything.
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/TypingRhythm"
INIT="$HOME/.hammerspoon/init.lua"
LINE='dofile(os.getenv("HOME") .. "/TypingRhythm/typing_rhythm.lua")'

echo "Installing Typing Rhythm into $DEST"
mkdir -p "$DEST/data"
cp "$SRC/typing_rhythm.lua" "$SRC/report.py" "$SRC/README.md" "$DEST/"

if [ ! -d "/Applications/Hammerspoon.app" ]; then
  if command -v brew >/dev/null 2>&1; then
    echo "Installing Hammerspoon with Homebrew..."
    brew install --cask hammerspoon
  else
    echo "Hammerspoon isn't installed and Homebrew wasn't found."
    echo "Download it from https://www.hammerspoon.org, move it to Applications, then run this again."
    exit 1
  fi
fi

mkdir -p "$HOME/.hammerspoon"
touch "$INIT"
if ! grep -qF "$LINE" "$INIT"; then
  printf '\n-- Typing Rhythm (key timing only, never key contents)\n%s\n' "$LINE" >> "$INIT"
  echo "Added Typing Rhythm to $INIT"
fi

open -a Hammerspoon
# Reload config if Hammerspoon was already running
osascript -e 'tell application "Hammerspoon" to execute lua code "hs.reload()"' >/dev/null 2>&1 || true

cat <<'MSG'

Almost done. Two clicks left:

 1. Hammerspoon will ask for Accessibility access. Open System Settings >
    Privacy & Security > Accessibility and turn Hammerspoon on.
    (If it doesn't ask, go there yourself and add it.)
 2. In the Hammerspoon menu bar icon, choose "Reload Config".

You'll then see a small keyboard icon in the menu bar. It has Pause,
"Pause for 1 hour", "Open data folder" and "Run report".

Tip: in Hammerspoon's Preferences, turn on "Launch Hammerspoon at login".
MSG
