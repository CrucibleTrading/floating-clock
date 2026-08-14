# FloatingClock — project context

Read this first. It exists so a fresh session can be productive without
re-deriving decisions or re-introducing bugs that were already fixed.

## What this is

A macOS menu-bar utility that displays an **always-on-top `HH:MM:SS` clock**.

Single-file AppKit app, ~200 lines of Swift. No dependencies, no Xcode project —
it compiles with `swiftc` directly.

## Why it exists

macOS has no built-in way to do this, and it is worth understanding why before
proposing "just use a widget":

- **Desktop widgets render *behind* all windows** by design (Sonoma onward). That
  is the opposite of the requirement.
- **The stock Clock widget has no seconds display** at any size. There is no
  setting for it — the option does not exist.
- The **menu-bar clock** can show seconds (System Settings → Control Center →
  Clock Options) but it is menu-bar sized, not large.
- **WidgetKit cannot be promoted to always-on-top.** There is no supported API.

Floating above windows requires a regular app with a borderless `NSWindow` at a
raised `NSWindow.Level`. That is what this is.

## Build and run

```bash
swiftc -O FloatingClock.swift -o FloatingClock          # build binary

# rebuild the double-clickable bundle
mkdir -p FloatingClock.app/Contents/MacOS
cp FloatingClock FloatingClock.app/Contents/MacOS/
codesign --force --deep -s - FloatingClock.app          # ad-hoc sign
open FloatingClock.app
```

`Info.plist` lives in the bundle and is committed. `LSUIElement=true` keeps the
app out of the Dock — menu-bar only.

Built and verified on **macOS 26.4.1 (Tahoe), Swift 6.3.1, Xcode 26.4.1**.

## Layout

| Path | Purpose |
|---|---|
| `FloatingClock.swift` | Entire app — `ClockView` (drawing) + `AppDelegate` (window, menu, timer) |
| `FloatingClock.app/` | Bundle. Only `Info.plist` is tracked; the binary is gitignored |
| `README.md` | User-facing docs |
| `CLAUDE.md` | This file |

## Design decisions — do not "simplify" these away

Each of these exists for a measured reason.

**Monospaced digits.** `NSFont.monospacedDigitSystemFont`. With a proportional
font the panel width jitters every second as digit shapes change — unbearable at
72pt+.

**Sizing measures an ARRAY of samples, taking the widest.**
`monospacedDigitSystemFont` only monospaces *digits*. The letters in `" AM"` and
`" PM"` are proportional and differ in width, so measuring one and rendering the
other clips.

**Redraw only when the rendered string changes.** The timer polls at 10 Hz for
accurate second boundaries, but `needsDisplay` is set roughly once per second.
Do not repaint on every tick.

**Timer added to `RunLoop.main` in `.common` mode.** The default mode stalls
during window-drag tracking, so the clock would freeze while being moved.

**`resizeToFit()` pins the visual top-left.** AppKit origins are bottom-left;
holding the origin fixed makes the panel grow upward off its corner when the
font size changes.

**Two window levels, user-selectable.** `.floating` sits above normal windows
(sane default). `.screenSaver` covers nearly all system UI — useful on a second
monitor, intrusive on a laptop. Both are intentional.

**`collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`**
so it follows across Spaces and survives fullscreen apps.

## Bug already fixed — do not reintroduce

**Clipped leading/trailing characters at launch** (fixed in `fix clipped digits
at launch`).

The window was sized from a bare `"00:00:00"` while 12-hour mode renders
`"10:07:20 AM"` — three characters longer. `resizeToFit()` had the correct
sample but only ran on a size/format *change*, never at startup. Text is
centred, so it overflowed equally on both sides.

Measured shortfall: 17pt at 32pt font, 44 at 48, 83 at 72, **141 at 108**.

**If you touch sizing, re-verify** that window width ≥ widest renderable string
at every size in both 12h and 24h. Current slack is 40–48pt.

## Testing

There is no test suite; it is a GUI utility. The practical loop:

1. `swiftc -O FloatingClock.swift -o FloatingClock` — must compile clean.
2. Rebuild bundle, `open FloatingClock.app`, confirm the process starts.
3. `pkill -f "FloatingClock.app"` to clean up — **do not leave a test instance
   running on Shane's screen.**

For geometry changes, write a throwaway `swiftc` script that measures
`NSString.size(withAttributes:)` against the window width across all four font
sizes and both formats. That is how the clipping bug was quantified, and it beats
eyeballing screenshots.

Note: `String(format:)` with `%@` and a Swift `String` segfaults in a
command-line context — use string interpolation in throwaway measuring scripts.

## State and preferences

Persisted in `UserDefaults` (`com.shanec.floatingclock`): `fontSize`, `use24Hour`,
`aggressiveLevel`, `visible`, `origin`. Position is saved on
`NSWindow.didMoveNotification`.

To reset during debugging: `defaults delete com.shanec.floatingclock`.

## Possible next steps

Not committed to, just the obvious candidates:

- Global hotkey to toggle visibility (needs a Carbon hotkey or an `NSEvent`
  monitor with Accessibility permission — the current menu-bar toggle needs no
  permissions, which is why it was chosen first)
- Custom colour / opacity / font-family
- Multiple clocks for different timezones
- Optional date line
- Proper Developer ID signing + notarisation if it is ever distributed
  (currently ad-hoc signed, so Gatekeeper will complain on another Mac)
