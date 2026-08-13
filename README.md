# Semaphoz

A macOS menu bar widget showing the state of every running Claude Code session as a row
of coloured dots.

```
①②③④⑤⑥⑦⑧⑨   ● ●
└─ 9 fixed slots ─┘  └ overflow ┘
```

Each slot dot carries its number, so the grid stays readable without opening the
dropdown — the number is exactly the `[n]` you can claim with `/rename`. Overflow dots
are deliberately unnumbered, since positions past the grid are not claimable.

At the default 18pt dots the full row is ~194pt wide.

- 🟡 **yellow** — running
- 🔴 **red** — waiting for your input (permission prompt)
- 🟢 **green** — idle / turn finished
- ○ **hollow** — empty slot

## Install

Download the latest `Semaphoz-x.y.z.zip` from
[Releases](https://github.com/bbonfim/semaphoz/releases), unzip it, and drag
**Semaphoz.app** into your Applications folder. Universal binary — Apple Silicon and
Intel. Requires macOS 13 or later.

**macOS will block it the first time.** Semaphoz is not signed with an Apple Developer ID
(that requires a paid Apple Developer account), so Gatekeeper does not recognise it. This
is a one-time step:

- **macOS 13 / 14** — right-click the app → **Open** → **Open**.
- **macOS 15 or later** — double-click it, let it be blocked, then go to
  **System Settings → Privacy & Security**, scroll down to the message about Semaphoz,
  and click **Open Anyway**. (Apple removed the right-click shortcut in macOS 15.)

If you instead see *"Semaphoz is damaged and can't be opened"*, macOS has quarantined the
download. Remove the flag with:

```sh
xattr -dr com.apple.quarantine /Applications/Semaphoz.app
```

Then enable **Launch at Login** from the dropdown if you want it to start automatically.

## Build from source

Requires only the Xcode Command Line Tools (no Xcode).

```sh
./install.sh     # build, install to ~/Applications, enable launch at login
```

Use this rather than `build.sh` for day-to-day updates. The login item registration
follows the app bundle's **path**, and `build.sh` deletes and recreates the bundle in the
project directory — so a login item pointing there breaks on the next build. `install.sh`
keeps the launched copy in `~/Applications`, which does not move. (`~/Applications` rather
than `/Applications` so no admin password is needed.)

Launch at login can be toggled from the dropdown, and appears in System Settings →
General → Login Items, so it can be revoked there too.

To build without installing:

```sh
./build.sh              # native arch, fast
./build.sh --universal  # arm64 + x86_64, as shipped in releases
open Semaphoz.app
```

Clicking the menu bar opens the dropdown. To stop it, use **Quit Semaphoz** there, or
`pkill Semaphoz`.

### Cutting a release

```sh
./release.sh 0.2.0      # universal build, zipped, published to GitHub Releases
```

The zip is produced with `ditto` rather than `zip`, which preserves the bundle's symlinks
and extended attributes — a plain `zip` can yield an `.app` that will not launch.

## How session state is detected

Claude Code maintains a live session registry at `~/.claude/sessions/<pid>.json`, one file
per session, which it keeps current within a couple of seconds:

```json
{"pid":86942,"sessionId":"…","cwd":"/Users/you/project","procStart":"Tue Aug 11 12:08:06 2026",
 "kind":"interactive","name":"my-project-1a","status":"busy","statusUpdatedAt":1786450225904}
```

Semaphoz only reads this. Nothing is scraped and no session is instrumented.

Two details that are easy to get wrong:

- **`status` is `busy | idle | waiting`**, mapping directly onto the three lights.
  `waiting` is easy to miss: sample the registry when nothing is blocked and you will only
  ever observe `busy` and `idle`, and wrongly conclude that a permission prompt cannot be
  distinguished from a finished turn. It can — no hooks and no session restart required.
  Sessions on older builds emit it too (confirmed on 2.1.220).
- **`procStart` is written in UTC**, not local time, and PIDs get recycled. Liveness is
  therefore `sysctl` process start time matched against `procStart` within 2s, not a bare
  `kill(pid, 0)` — otherwise a recycled PID renders a phantom session.

## Slot model

A **fixed grid of 9 slots** (`Layout.slotCount`), always drawn. Because the grid is fixed,
dots never slide: a slot is either occupied or hollow, and its position never depends on
what else is running.

### Claiming a slot

Put `[n]` anywhere in a session name to pin it to slot *n*:

```
/rename api refactor [3]
/rename [3] api refactor        # equivalent
```

The number is the only thing that pins a position — there is no separate config, and
nothing to keep in sync. `/rename` persists into the registry, and a `--resume`d session
keeps its name, so it returns to its slot on its own.

- Claims are resolved **before** any auto-assignment, so an unnumbered session can never
  squat a claimed slot.
- Everything else fills the **lowest available slot**, oldest first.
- Sessions past 9 append to the **right of a wider gap** and simply vanish when they
  exit, rather than leaving a hollow slot. This keeps the row bounded.
- Session exits → the slot is immediately free. There are no reservations and no state
  to prune; occupancy is purely a function of what is live right now.

A claim is refused when the number is outside 1–9, or when an older live session already
holds it — oldest wins, so the outcome doesn't depend on file read order. Refused sessions
fall back to the lowest free slot and the dropdown says why (`[3] taken`), so an unexpected
position is self-diagnosing.

Only brackets wrapping digits count, so `[wip] foo` and `foo [bar]` stay ordinary names.
The tag is stripped from the dropdown, and lifting it out of the middle of a name does not
leave a double space behind.

Allocation is intentionally stateless, so unnumbered sessions can change slot when an
earlier session exits. Numbered ones never move.

## Layout

| File | Role |
| --- | --- |
| `Sources/Registry.swift` | Reads and validates the session registry |
| `Sources/Layout.swift` | Slot allocation |
| `Sources/StatusBarController.swift` | Menu bar rendering and dropdown |
| `Sources/LoginItem.swift` | Launch-at-login registration |
| `Sources/main.swift` | App entry point (`.accessory`, no Dock icon) |

## Roadmap

All three lights and `[n]` claiming work today. A hook layer was planned to derive the red
state and turned out to be unnecessary — the registry already reports it.

- Click a dot to focus its terminal — built, then pulled back out because clicking was
  buggy. The working parts are preserved in `disabled/`, with notes on where to restart.
- Configurable slot count (currently `Layout.slotCount`).
- Fitting the row into the ~100pt available beside a MacBook notch, where macOS currently
  drops the item entirely rather than clipping it.
- Sessions from the Claude desktop app are expected to appear automatically — the registry
  is read regardless of `entrypoint` — but this is unverified. Cloud/remote sessions will
  not appear, since they have no local process to match.

## License

MIT — free to use, modify and redistribute, including commercially.
See [LICENSE](LICENSE).

By bbonfim.
