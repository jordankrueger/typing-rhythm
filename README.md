# Typing Rhythm

A private logger for Mac that records how you type, never what you type. It builds a
personal baseline over a couple of months, so slow changes in typing rhythm show up
against your own normal.

It runs inside [Hammerspoon](https://www.hammerspoon.org), a free Mac automation app.
Background: [How to check your own writing over time](https://jordankrueger.com/blog/check-your-own-writing-over-time/).

## Install

1. Download this repo (green **Code** button → **Download ZIP**) and unzip it.
2. Double-click **Install Typing Rhythm.command**. If macOS says it can't verify the file,
   right-click it and choose **Open**. The installer installs Hammerspoon with Homebrew if
   needed, copies the files to `~/TypingRhythm`, and adds one line to
   `~/.hammerspoon/init.lua`.
3. Turn on Hammerspoon in System Settings → Privacy & Security → Accessibility, then
   choose **Reload Config** from the Hammerspoon menu.
4. In Hammerspoon's Preferences, turn on **Launch at login**.

A small keyboard icon appears in your menu bar. Click it to see today's key count, pause,
open the data folder, or run the report.

## What it records

- How long each key is held down (milliseconds)
- The gap between one key press and the next
- Typing speed during bursts, pauses, and how often you use backspace
- Which keyboard type was used, so a switch between the laptop keyboard and an external
  one doesn't look like a change in you

All of it is rolled up into hourly totals and histograms in `~/TypingRhythm/data/`, one
file per day (a few KB each).

## What it never records

- Which keys you press, any text, or which app you're in. Key codes are held in memory
  for a split second to pair each press with its release, then dropped.
- Keyboard shortcuts (Cmd or Ctrl combinations), held-key repeats, arrows, Tab, Escape
  and function keys. These are skipped entirely.
- Password fields. macOS "Secure Input" blocks this kind of monitoring there, so
  1Password and login screens never reach it.

Nothing is sent anywhere. Pause it anytime from the menu bar icon.

## Reading it

Menu bar icon → **Run report**, or `python3 ~/TypingRhythm/report.py` in Terminal.

- The first 8 weeks of typing days (300+ keys) become your baseline.
- After that, the report compares your last 4 weeks with it. Numbers are in units of your
  normal day-to-day swing: under 1 is ordinary, and 2 or more for weeks on end is worth
  a look.
- The measure research leans on most is **hold-time variability**: how much the time a key is held down varies. MIT's [neuroQWERTY study](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5050498/) used hold times to pick out early Parkinson's, and [later researchers re-analyzing MIT's data](https://pmc.ncbi.nlm.nih.gov/articles/PMC6597101/) built a much simpler index from how much hold times vary.

## What moves the numbers besides health

Sleep, caffeine, stress, illness, new medication, a new keyboard, cold hands, and typing
on a lap versus a desk. That's why it compares weeks, not single days.

This is a personal tracking tool, not a medical test. If something keeps showing up,
take it to a doctor, who can use real tests.

## Uninstall

Remove the Typing Rhythm lines from `~/.hammerspoon/init.lua`, reload Hammerspoon, and
delete `~/TypingRhythm`.
