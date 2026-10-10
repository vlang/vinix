# smcprobe

Reads, under macOS, the keys the Vinix SMC driver uses from the SMC of the
Mac it runs on: whether each key is there, its four-character type, its size,
its attribute bits, and its bytes in the order the SMC holds them.

```sh
tools/apple-smc/smcprobe              # the keys kernel/apple/smc reads
tools/apple-smc/smcprobe B0RM TB0T    # these keys
tools/apple-smc/smcprobe --all        # every key the SMC lists
```

It needs a V compiler (found as for every other tool, through
`build-support/find-v.sh`) and the command line tools of Xcode. It runs as an
ordinary user and only reads: through the `AppleSMC` user client it sends the
commands that describe a key, read a key and name the key with a given
number, and it has no code that writes one.

## What it is for

The driver takes a key for what Linux's drivers say it is, and reads it with
the size the SMC itself gives for it ([M1 battery](../../docs/m1-battery.md)).
Before the driver is trusted on a machine it has never run on, this says what
that machine's SMC has, from the system that is known to work on it:

- a key the driver wants that is `absent` will have no file in `/sys`;
- a key whose size is not the one in the table of
  [docs/m1-battery.md](../../docs/m1-battery.md) is left out by the driver
  (`keys_odd_sized` in `/sys/devices/platform/apple-smc/smc/status` counts
  them), and that is worth knowing before booting;
- `BCF0` of one byte means the remaining charge `B0RM` is little-endian, of
  four bytes that it is big-endian: compare `B0RM` both ways with `B0FC`.

Once Vinix runs on the machine, `/sys/devices/platform/apple-smc/smc/keys`
lists the same thing as the driver saw it, one `key type size attributes`
line each, to be laid beside this tool's output.

## Recorded

A MacBook Pro `Mac17,6` (M5 Max) under macOS 26.5 (25F71), 2026-10-11. This
is not the machine the driver is for; it confirms types, sizes and byte
orders, not which keys an M1 has.

| Key | Type | Size | Notes |
| --- | --- | --- | --- |
| `BUIC`, `BRSC` | `ui8 ` | 1 | `BRSC` is one byte here; the driver's fallback for it expects two and is used only where there is no `BUIC` |
| `B0AV`, `B0FC`, `B0DC`, `B0CT`, `B0TE`, `B0TF`, `BITV` | `ui16` | 2 | little-endian; `B0TE` and `B0TF` were `ffff` on the charger with a full battery |
| `B0RM` | `ui16` | 2 | big-endian on this firmware: `1f99` is 8089 mAh beside a `B0FC` of 8175 |
| `B0AC` | `si16` | 2 | |
| `B0AP` | `si32` | 4 | |
| `BSFC` | `flag` | 1 | |
| `BCF0` | `ui32` | 4 | four bytes, with a big-endian `B0RM`: Linux's rule holds here |
| `BMDN` | `ch8*` | 32 | `bq40z651`, NUL padded |
| `BMSN` | `ch8*` | 21 | |
| `CH0R` | `hex_` | 4 | |
| `CHCE`, `CHCC`, `CHSC` | `ui8 ` | 1 | |
| `CHNC` | `hex_` | 8 | `0100400000000000` with the battery full: bit 0 |
| `CHIS` | `ui32` | 4 | |
| `CHWA`, `AC-i` | absent | | this firmware has neither; nor `CHLS`, `CH0C`, `CH0I` |
| `TH0x`, `TB0T`, `TCHP`, `TW0P` | `flt ` | 4 | 37.2, 34.5, 54.8 and 56.9 degrees |
| `FNum` | `ui8 ` | 1 | 2 |
| `F0Ac`, `F0Mn`, `F0Mx`, `F1Ac`, `F1Mn`, `F1Mx` | `flt ` | 4 | 3454, 1350 and 5349 rpm for the first fan |

Of the 3668 keys this SMC lists, 361 begin with `T`: 344 are `flt `, 9 are
`ioft` (48.16 fixed point, little-endian: `TG0B` read `33b3220000000000`,
34.70 degrees) and 8 are `si32`. None is `sp78`.
