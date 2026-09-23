# Herdr Menu Bar

A macOS menu bar app showing the live state of every agent in your Herdr
session. Click an agent to jump straight to its pane.

## What it does

- A robot head in the menu bar, carrying a small dot at its top right for the
  most urgent state present. The dot encodes state in shape as well as colour,
  so the states stay apart without relying on colour vision: a filled dot means
  an agent is waiting on you (red, and larger), has finished (green), or is
  working (accent); a faint hollow ring means everything is idle; and no dot at
  all, with the head dimmed, means Herdr is unreachable.
- A dropdown listing every agent grouped by workspace, most urgent first,
  including idle and working ones. State is carried visually rather than in
  text — a turning spinner while an agent works, a red dot when it wants you, a
  green dot when it has finished, and a faded row when it is idle — so the
  width goes to names and directories instead. Hover a row to read its state.
- Clicking an agent focuses its pane in Herdr and brings the hosting terminal
  to the front.
- A desktop notification when an agent becomes blocked, with toggles for
  finish notifications, sound, and launch at login.

## Build and install

```bash
./build.sh
cp -R "build/Herdr Menu Bar.app" /Applications/
open "/Applications/Herdr Menu Bar.app"
```

Install it to `/Applications` rather than running from the build directory;
macOS treats notifications from unregistered locations differently.

## Notifications

There are three tiers, tried in order.

1. **`UNUserNotificationCenter`** — the native path, with a "Jump to pane"
   button. macOS only grants this to apps signed with a real Developer ID, so
   an ad-hoc local build will not get it. If you sign the bundle with a
   Developer ID certificate, it starts working with no code changes.
2. **`terminal-notifier`** — used when installed, and the recommended option
   for a local build. Notifications keep a working click action: clicking
   focuses the pane and raises the terminal.
   ```bash
   brew install terminal-notifier
   ```
3. **AppleScript** — the last resort. It shows a banner but cannot carry a
   click action, and the notification is attributed to Script Editor.

Herdr itself uses the same second and third tiers, so tier 2 also improves
Herdr's own `[ui.toast] delivery = "system"` notifications.

## Notes on Herdr's event API

Two behaviours drove the design, both worth knowing before changing this code.

`pane.agent_status_changed` is scoped to a single pane, so covering a whole
session needs one subscription per pane. Those subscriptions start at the
server's current event sequence, so they never replay.

Every other lifecycle subscription (`pane.created` and friends) starts at
sequence 0 and replays the server's entire retained event buffer when you
subscribe. A client that treats those replays as news will resync, re-subscribe,
replay, and loop forever. This app therefore does not subscribe to them at all:
it reconciles the pane set from `session.snapshot` every five seconds instead.

`pane.updated` is also avoided. It fires about ten times a second while agents
are working, because agent terminal titles animate.

Event names are spelled inconsistently: lifecycle events arrive as
`pane_updated`, while subscription-generated ones arrive as
`pane.agent_status_changed`. The handler normalises both.

## Debugging

```bash
open --env HERDR_MENUBAR_DEBUG=1 "/Applications/Herdr Menu Bar.app"
tail -f ~/Library/Logs/HerdrMenuBar.log
```
