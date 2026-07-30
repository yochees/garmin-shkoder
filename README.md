# Digital Classic

A rebuild of the fenix 5 Plus stock digital watch face for the **fenix 8 Solar /
tactix 8 Solar 51mm** (280x280, MIP).

- Large centred time with a colon and tightened letter spacing
- Two complications on one row separated by a dim `|` (default: date + steps)
- Second marker of three squares running around the rim, on the previous
  second, the current one and the next - so at the top of a minute it reads
  59 / 00 / 01. Kept ticking in low-power mode via `onPartialUpdate()`

> **Before installing on the watch:** `MOCK_STEPS` in
> `source/ClassicDigitalView.mc` is set to `15000` for layout work. Set it to
> `-1` to show the real step count.

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

So the clock uses **RobotoCondensedBold** and fakes proportional digits:
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
