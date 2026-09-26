# Herdr Menu Bar

A macOS menu bar app showing the live state of every agent in your Herdr
session. Click an agent to jump straight to its pane.

## What it does

- A monochrome robot head in the menu bar, drawn in the menu bar's own text
  colour so it sits quietly among the system icons. It shows the most urgent
  state present through shape and motion rather than colour: an outlined head
  when everything is idle, a filled head with its ears circling the face while
  an agent works, a filled head that hops when an agent is waiting on you, and
  a filled head with a check punched through it when an agent has finished.
  When Herdr is unreachable the icon looks idle; the dropdown says why. With
  Reduce Motion on the icon holds still, so working and waiting look the same.
- A dropdown listing every agent grouped by workspace, in Herdr's own
  workspace and pane order, including idle and working ones. The order never
  changes with state, so the row under your cursor stays put. State is carried
  visually rather than in text — a turning spinner while an agent works, a
  larger red dot when it wants you, a green dot when it has finished, and a
  faded row when it is idle — so the width goes to names and directories
  instead. The header stays bare unless Herdr becomes unreachable, which it
  says.
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

## Code layout

Sources live under `Sources/HerdrMenuBar`, and each layer only uses the ones
below it.

- `App` — the entry point, which wires everything together at launch.
- `UI` — the menu bar icon and the dropdown's SwiftUI views.
- `State` — `HerdrMonitor`, the live agent list, and the rules for when to notify.
- `Services` — the typed Herdr client, notifications, settings, and raising the terminal.
- `Transport` — the line-delimited Unix socket connection to Herdr.
- `Models` — plain data types: agents, workspaces, statuses.
- `Support` — logging and executable lookup, usable from any layer.

## Debugging

```bash
open --env HERDR_MENUBAR_DEBUG=1 "/Applications/Herdr Menu Bar.app"
tail -f ~/Library/Logs/HerdrMenuBar.log
```
