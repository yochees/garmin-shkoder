# Shkoder

A rebuild of the fenix 5 Plus stock digital watch face for the **fenix 8 Solar /
tactix 8 Solar 51mm** (280x280, MIP).

> **Naming.** The face is called **Shkoder** on the watch and ships as
> `Shkoder.prg`. It was called *Digital Classic* until 2026-08-17 and *Fenix 5X*
> until 2026-09-29, so the repo is still `fenix5x-watchface` and the source
> files and classes are still `ClassicDigital*`. Same thing, older names - do
> not go looking for a second project.

- Large centred time, no colon, with tightened letter spacing
- Two complications on one row below the time, separated by a dim `|`
  (default: date + steps)
- A third complication above the time, off by default. It takes the same values
  as the other two, plus a second time zone
- A single second marker running around the rim, kept ticking in low-power
  mode via `onPartialUpdate()`

> **Before installing on the watch:** check that `MOCK_STEPS` in
> `source/ClassicDigitalView.mc` is `-1`, which shows the real step count.
> Setting it to a number freezes the steps field for layout work.

## Settings

**On the watch:** apply the face, then press its edit icon -> **Customize**.
The menu opens straight away.

- **Top field** / **Left field** / **Right field** - off / date / steps /
  battery / calories / distance / notifications / time zone / HR / solar /
  barometer / temperature / watch temp. Top is the row above the time and is
  the only one that starts off; left and right share the row below it
- **Leading zero on hour**
- **Time zone label** - up to six characters, e.g. `HOME`, `LON`, `NY`. Typed
  on the watch with `TextPicker`, with a preset list and an explicit *(none)*
  for devices without one
- **Time zone offset from UTC** - a two column picker, hours and quarter
  hours, so `+05:45` (Nepal) and `-03:30` (Newfoundland) are reachable

The label and offset apply wherever **Time zone** is chosen, so any of the
three fields can be the second zone - though the label makes it wide enough
that the top row is the only comfortable home for it.

### Why the settings are on the device and not in the phone app

This face is **sideloaded** - the `.prg` is copied into `GARMIN/APPS` over MTP
rather than installed from the Connect IQ store. That rules out both official
settings routes, permanently:

- **Connect IQ phone app** - lists apps from the Garmin *account's*
  installed-app records. A sideloaded app has no record, so the face never
  appears at all.
- **Garmin Express** - reads the *device*, so it does list the face, but it
  fetches the settings *schema* by app id from the store. No store entry means
  no schema, so its Settings option is greyed out.

So XML app settings (`resources/settings/settings.xml`) can never work here,
and that file has been removed. `AppBase.getSettingsView()` in
`source/ClassicDigitalApp.mc` provides the menu instead, built in
`source/ClassicDigitalSettings.mc`.

### Three things that stop getSettingsView() working, all learned the hard way

Verified on the watch by building Garmin's own `Analog` sample for it and
comparing behaviour. Change any of these back and the settings become
unreachable again:

1. **Return a plain `View`, never a `Menu2`.** Returning a `Menu2` straight
   from `getSettingsView()` compiles, and works in the simulator, but the watch
   then offers **no Customize entry at all**. The `Analog` sample returns a
   `View` whose delegate opens the menu; that is the shape the firmware
   accepts.
2. **A changed app needs a new app id.** The watch caches per-app metadata
   keyed by the manifest `id`, including whether the app has settings. The id
   was first installed before this face had a settings view, and no amount of
   reinstalling or **rebooting** cleared that - Customize only appeared after
   the id was regenerated. If settings stop showing after a big change, mint a
   fresh id.
3. **Do not wait for `MENU`.** `Analog` shows a "Press MENU for settings" hint,
   which is dead on a fenix 8 - MENU is a long press of UP and never reaches
   `onMenu()` inside a settings view. `SettingsLauncherView.onShow()` opens the
   menu itself, guarded by a flag so that backing out does not loop straight
   back in. START, ENTER, MENU and DOWN are wired as fallbacks.

The simulator will not catch any of this: **Settings > Trigger App Settings**
happily opens a `Menu2` returned directly. Only the watch tells the truth.

### The extra time zone

```
  HOME 11:21
     2121
  Sun 16 | 0
```

Both rows hang off `TIME_INK_Y`, not `TIME_Y`: `TEXT_JUSTIFY_VCENTER` centres
the font's whole box, and the digits use none of the descender space at the
bottom of it, so their ink sits about 4px above the value asked for. Mirroring
about `TIME_Y` therefore left 18.5px above the digits and 24.5px below.
Measured on device the ink runs 99..174, so `TIME_INK_Y = 137` with
`ROW_GAP = 68` puts both rows 21.5px clear.

The zone row keeps its colon even though the big time has none: four bare
digits are unreadable at complication size, and there is no colon above to
clash with.

It is a **fixed offset from UTC**, not a named zone, so it does not follow
summer time on its own - change the offset when that zone switches. Connect IQ
can do DST properly only through `Gregorian.localMoment(location, moment)`,
which needs the zone's coordinates rather than a name, so a fixed offset is the
honest trade for a setting you type in. The offset is clamped to -12..+14 and
snapped to the quarter hour, so 5.5 (India) and 5.75 (Nepal) land exactly.

The always-on second marker is only possible because this is a MIP device.
The AMOLED fenix 8 models disable per-second partial updates in low-power mode.

## Build

The SDK needs Java on PATH, and Homebrew's `openjdk` is keg-only:

```sh
export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"
export SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-2026-06-09-92a1605b2"

"$SDK/bin/monkeyc" \
  -o bin/Shkoder.prg \
  -f monkey.jungle \
  -y developer_key.der \
  -d fenix8solar51mm \
  -w
```

## Run in the simulator

```sh
open -a "$SDK/bin/ConnectIQ.app"
"$SDK/bin/monkeydo" bin/Shkoder.prg fenix8solar51mm
```

## Install on the watch

The fenix 8 mounts as **MTP**, not mass storage, so there is no
`/Volumes/GARMIN` to copy into. Use the helper:

```sh
./tools/mtp-push bin/Shkoder.prg Shkoder.prg
```

It writes to `GARMIN/APPS` (parent `16777226`, storage `0x00020001`). libmtp's
own `mtp-sendfile` fails here - it asks the device to infer a storage id from
the parent and the fenix 8 refuses - so `mtp-push` sets both ids itself. Build
it with the command at the top of `tools/mtp-push.c`; it needs `libmtp`.

Unplug, then pick the face from Watch Face on the device.

Two things that bite:

- **Garmin Express grabs the USB port.** While it runs, `mtp-push` dies with
  `libusb_claim_interface() = -3`. Quit Express first.
- **Verify what landed** rather than trusting the transfer:
  `mtp-files | grep -A3 Shkoder` prints the file and its size off the watch.

## Clock font

The built-in `FONT_NUMBER_*` fonts are tabular - every digit gets the same
advance, so `1` sits in a cell as wide as `8` and leaves a hole beside it.
Bundled custom fonts have to be bitmap `.fnt`, and every scalable face the
device exposes through `Graphics.getVectorFont` is tabular except
`PridiSemiBoldGarmin`, which is proportional but not a plain sans.

So the clock uses **BionicSemiBold** - the face the built-in `FONT_NUMBER_*`
bitmaps are cut from, which is why the time reads as Garmin's own - and fakes
proportional digits:
`drawTime` advances each digit by its own cell and `TRIM_ONE` claws back a
fraction of the `1` cell, keeping the ink centred in what is left. Raise
`TRIM_ONE` to tighten `1` further, lower it to loosen.

Measured digit advances at size 100 (`1` / `8`) are listed above `TIME_FACE` in
the source. Set `TIME_FACE` to `null` to fall back to the bitmap numerals.

## Tuning the look

Every layout number is a `const` at the top of
`source/ClassicDigitalView.mc` - time position, gap, ring radii, tick lengths,
marker width. Change, rebuild, look at it in the simulator.

## Signing key

`developer_key.der` signs the build. Back it up somewhere outside this repo.
Regenerate (only if you have never published) with:

```sh
openssl genrsa -out developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt
```
