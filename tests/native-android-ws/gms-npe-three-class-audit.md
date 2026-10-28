# Focused GMS NPE caller audit — 2026-10-28

The r5 stack `gqfi.A:1 → dhmr.b:42 → dhmr.a:19 → dhmo.run:3` matches a
caught pseudonymous-device-ID failure in GMS's pipeline logger. This does not
establish the cause of account-window dismissal or missing map imagery. No
framework API change follows from this finding.

The audit source is committed in `88ba6bd9279ab4fd9f6be8986d3d3426eedc1ff3`;
its SHA-256 is `8435674574849997ba9b3d0ec7d5e1626fa3c83fa9d0d3c7c4456c738d32a983`.
The recorded shared-checkout HEAD during extraction was
`36461232e62345dc5f27327bf9efa281e80ff704`, which includes that source commit.

## Retained evidence

Let `S=/Users/alex/.local/state/vinix/android`.

- Final bundle: `S/gms-npe-three-class-audit-2026-10-28-r2`.
- Complete `sha256.json`: `7759ee648d47e8c22fe9556fe5316d9dc39efd2b48e8edbde8b974f0ee24ed24`.
- External final sealing/readback receipts:
  `S/gms-npe-three-class-controls-2026-10-28-r2`.
- Audit executable: `ac8ab67841e12b2d4b6a0d165f046b03b9d8100a745f0da1ede926537e791d74`.
- Baseline complete bundle: `S/gms-cookie-method-audit-evidence-2026-10-26-r3`,
  manifest `bfdfc413af353e175b802672efa96475f5e7e07799016b9a19bc136b060954ee`.
- Root GMS APK pin: `a34d6a3ccea3ceba491369517e8f12e11df3791e86fec38b1cdf693785e35707`.

The bundle retains the entire baseline, including its nested manifest, unchanged
consumed V/native inputs, generated C, compiler and command identities, argv,
the class-definition owner index, and the three completed producer guard
receipts/logs. Host SDK provenance is not a hermetic toolchain claim. No guest
logs, tokens, account identities, or other user data were consumed or included.
The older r1 extraction remains separate; it does not validate the corrected r2
source.

Actual DEX `class_defs` select the owners; duplicate, missing, or unexpected
matches fail. Only these three definitions were newly disassembled, using
`-Xmx256m -XX:ActiveProcessorCount=2` and baksmali `--jobs 2 --code-offsets`.
The checker requires exactly three regular smali files with exact single class
declarations. All other APK classes remain outside this extraction.

| Definition | Owner | Selected smali SHA-256 |
| --- | --- | --- |
| `dhmo` | `dex/classes2.dex` | `bdef5674a9ecf8f61e23c97aba048161fdfc645569df5ce5b64a855fdb44e633` |
| `dhmr` | `dex/classes2.dex` | `dc1767d10bf589a1204d499c96a1ca9ec8d259a8d100417b891ff04f6910cf58` |
| `gqfi` | `dex/classes3.dex` | `d06ead69cf73478cf15f2894f83f5ff9680393b90f110dfa5047c3f589535496` |

Owner DEX hashes are `a9f2ff847667cb5df29120366b0ca502668902d9f420c73831ac8063caaaa4c1`
and `a37b2c4e9defd752b00ee36a44cc39c6209e4d9651f1f49c1aebacc5b810c71a`,
respectively. Selected files are under the final bundle's `selected/` directory.

## Exact caller evidence

Offsets below are hexadecimal method-relative DEX code offsets; line numbers
are the retained DEX `.line` metadata, followed by the smali file line.

| Method | DEX line / offset | Evidence |
| --- | --- | --- |
| `gqfi.A(Object)` | 1 / `0x0` | Calls `Object.getClass()` on its argument; `gqfi.smali:12`. |
| `dhmr.b()` | 40 / `0x27`; 42 / `0x29` | Reads `PseudonymousIdToken.a:String`, then passes it to `gqfi.A`; `dhmr.smali:244`. The observed getClass failure therefore concerns a null string. |
| `dhmr.b()` | protected `[0x9,0x3f)`; handler 65 / `0x40` | Explicit `NullPointerException` catch covers `0x29`; `dhmr.smali:297`. |
| `dhmr.b()` | 78 / `0x4d`; 82 / `0x51`; 85 / `0x54`; 86 / `0x55` | Catch path logs `GmsPipelineLogger Failed to obtain device id`, sets null, and returns; `dhmr.smali:353`. |
| `dhmr.a()` | 19 / `0x12` | Calls `dhmr.b()` and stores its nullable result; `dhmr.smali:720`. |
| `dhmo.run()` | 3 / `0x2`; 12 / `0xb`; 31 / `0x1e`; 122 / `0x79` | Calls `dhmr.a()`, handles null by setting a future retry time and clearing pending state, then returns; `dhmo.smali:69`, `:93`, `:146`, `:398`. |

## Validation

The build's focused self-test passed unsafe-path, malformed-DEX, missing-owner,
duplicate-owner, unexpected-owner, reference-only-class and duplicate-class
negative fixtures. Independent source review passed. Final extraction, receipt
sealing, and complete bundle readback all passed. Every guarded phase exited
zero, reported cleanup complete and zero swaps, and respected 600 MiB aggregate
RSS, 300 seconds, 1 GiB reserve and 512 MiB volume-growth limits.

| Phase | Peak sampled RSS (bytes) | Wall (ms) |
| --- | ---: | ---: |
| Bootstrap build | 363085824 | 3292 |
| Retained build and self-test | 376258560 | 25935 |
| Three-class extraction and initial seal | 156303360 | 75916 |
| Controls seal | 57540608 | 32995 |
| Final complete readback | 57704448 | 25234 |

Guard binary SHA-256:
`2af530965c86841d5c31c7f8a92590dec602f9246b54d32a892683adc929b7c5`.
Producer receipt hashes, retained inside the final complete seal:

- `bootstrap-build-final.guard.json`: `f47419015f04c4e5d2ee0ca1514cb2f51cdbe6bef52332e0698edff64be71c83`.
- `build-final.guard.json`: `4d2cb8adbbe6f66e6c50d4bbc2ed2e3a6456086da587509a703fb16f1c25af63`.
- `audit-final.guard.json`: `d964b3de64b2ad460d86449619346bec70375c98aa3e8a0ee64900ffd97d69f4`.

External `seal-final.guard.json`:
`0287ac0b6d8e378ad93e4533c60618f4be9856bd89a2ef54934b96ab2005e18a`;
external `check-final.guard.json`:
`cb4262d1a478395135bf8086427128eef26fed6a40eeabfb7b5266060eec1e1b`.
The latter's log confirms the final complete manifest identity above.

Readback uses the retained tool: `ROOT/tools/audit check ROOT`. The retained
command records, including build and extraction argv, are in `ROOT/commands/`.
