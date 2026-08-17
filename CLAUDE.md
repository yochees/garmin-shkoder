# Fenix 5X - Connect IQ watch face

This directory **is** the repo. One project, one canonical checkout, remote at
`github.com/yochees/fenix8-digital-classic` (private).

A rebuild of the fenix 5 Plus stock digital face for Algis's **fenix 8 Solar
51mm** (`fenix8solar51mm`, 280x280 MIP). It is the face he actually wears, and
it is **sideloaded** over MTP - never installed from the Connect IQ store.
That single fact drives most of what follows.

## Names do not match, and that is expected

| | |
| --- | --- |
| name on the watch | **Fenix 5X** |
| file pushed | `Fenix5X.prg` |
| repo + GitHub remote | `fenix8-digital-classic` |
| source files and classes | `ClassicDigital*` |

It was called *Digital Classic* until 2026-08-17. Only the display name and
the `.prg` were renamed; the repo and the code were not. There is no second
project - if a task mentions any of these names, it is this one.

`~/Code/garmin` used to hold two faces. The other one, `fenix5x-face` (a fenix
**5X** replica, never installed on the watch), was deleted on 2026-08-17 and
sits in `~/.Trash` - it had three commits and **no remote**, so that is the
only copy.

## Read the README before touching settings

`README.md` documents three non-obvious constraints that took a long
debugging session to find, each verified on the watch by building Garmin's own
`Analog` sample and comparing. Breaking any of them makes the settings
unreachable, and **the simulator will not catch it**:

1. `getSettingsView()` must return a plain `View`, never a `Menu2`.
2. Changing the app substantially needs a **new manifest app id** - the watch
   caches per-id metadata and a reboot does not clear it.
3. Nothing may wait for a `MENU` press; on fenix 8 that never arrives inside a
   settings view.

Also: **XML app settings can never work here.** A sideloaded app has no store
record, so the Connect IQ phone app does not list it at all and Garmin Express
lists it but greys its Settings out. `resources/settings/settings.xml` was
removed for this reason; `resources/settings/properties.xml` stays, because
that is what defines the properties themselves.

## Build, run, push

Java must be on `PATH` first - Homebrew's `openjdk` is keg-only, and without
this `monkeyc` fails with "Unable to locate a Java Runtime":

```sh
export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"
export SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2"

cd ~/Code/garmin
"$SDK/bin/monkeyc" -o bin/Fenix5X.prg -f monkey.jungle \
  -y developer_key.der -d fenix8solar51mm -r      # drop -r for a debug build

open -a "$SDK/bin/ConnectIQ.app"
"$SDK/bin/monkeydo" bin/Fenix5X.prg fenix8solar51mm   # holds the terminal - background it

./tools/mtp-push bin/Fenix5X.prg Fenix5X.prg
```

- The watch is **MTP**, not mass storage - there is no `/Volumes/GARMIN`.
- **Quit Garmin Express first**, or the push dies with
  `libusb_claim_interface() = -3`.
- Confirm what landed with `mtp-files | grep -A3 Fenix5X`, rather than
  trusting the transfer message.
- `mtp-detect` reporting "No raw devices found" usually just means the charging
  clip is seated for power but not data.

## Simulator notes

- A setting that is off by default cannot be exercised without flipping its
  default in `properties.xml`, building to a throwaway `-test.prg`, and putting
  the file back. The simulator does not read Garmin Connect settings.
- On-device settings open via **Settings > Trigger App Settings**. Treat a pass
  here as meaningless for the real device - see the three constraints above.
- Screenshots: the simulator window's AppleScript bounds are in points and
  `screencapture -R` does not line up with them. Capture the whole screen and
  crop at `image.width / 1512`. Raise the window with
  `open -a "$SDK/bin/ConnectIQ.app"` - `set frontmost` is unreliable.

## Signing key

`developer_key.der` / `.pem` are gitignored and are **not** in the git history.
They fix the app's identity on the watch. Copying the repo without them gives a
face the watch treats as a different app.
