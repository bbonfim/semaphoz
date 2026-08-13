# Disabled

Code kept out of the build (`build.sh` compiles `Sources/*.swift` only).

## TerminalFocus.swift

Click-a-dot-to-focus-its-terminal. Removed because clicking was buggy in practice.

The parts that were verified working and are worth keeping if this is revisited:

- Session → terminal matching by **controlling terminal** (`ttys004`), read from
  `kinfo_proc.kp_eproc.e_tdev` via `devname()`. Never match on window title: a tab's title
  can name a different session than the shell that owns the tty.
- Walking the process tree to identify the owning terminal app, so the correct AppleScript
  dialect is used instead of assuming one terminal.
- The iTerm2 `select w / select t / select s` sequence, confirmed against a live tab.
- Background (`kind: bg`) sessions have no controlling terminal and cannot be focused.

The untrustworthy part was the click handling in `StatusBarController`: replacing
`statusItem.menu` with a manual `target`/`action` plus `sendAction(on:)`, hit-testing the
click x-offset against dot positions, and re-showing the menu via `performClick`. If
revisited, start there rather than with the focusing logic.

Restoring also needs `NSAppleEventsUsageDescription` back in `build.sh`'s Info.plist.
