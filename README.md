# Digital Classic

A rebuild of the fenix 5 Plus stock digital watch face for the **fenix 8 Solar /
tactix 8 Solar 51mm** (280x280, MIP).

- Large centred time, no colon, with tightened letter spacing
- Two complications on one row separated by a dim `|` (default: date + steps)
- An optional second time zone above the time, off by default
- A single second marker running around the rim, kept ticking in low-power
  mode via `onPartialUpdate()`

> **Before installing on the watch:** check that `MOCK_STEPS` in
> `source/ClassicDigitalView.mc` is `-1`, which shows the real step count.
> Setting it to a number freezes the steps field for layout work.

## Settings

From Connect IQ Store app -> the face -> Settings, or Garmin Express:

- **Leading zero on hour**
- **Show extra time zone** - the row above the time
- **Extra zone label** - up to six characters, e.g. `HOME`, `LON`, `NY`
- **Extra zone offset from UTC** - hours, halves and quarters allowed
- **Left field** / **Right field** - off / date / steps / battery / calories /
  distance / notifications

### The extra time zone

```
  HOME 11:21
     2121
  Sun 16 | 0
```

`ZONE_Y = 72` mirrors `FIELD_Y = 208` about `TIME_Y = 140`, so the zone row
and the complication row sit the same distance from the digits. The row keeps
its colon even though the big time has none: four bare digits are unreadable
at complication size, and there is no colon above to clash with.

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
  -o bin/DigitalClassic.prg \
  -f monkey.jungle \
  -y developer_key.der \
  -d fenix8solar51mm \
  -w
```

## Run in the simulator

```sh
open -a "$SDK/bin/ConnectIQ.app"
"$SDK/bin/monkeydo" bin/DigitalClassic.prg fenix8solar51mm
```

## Install on the watch

Plug the fenix 8 in over USB and copy the `.prg` across:

```sh
cp bin/DigitalClassic.prg /Volumes/GARMIN/GARMIN/APPS/
```

Eject, then pick it from Watch Face on the device. Settings live under
Connect IQ Store app -> the face -> Settings, or in Garmin Express.

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
