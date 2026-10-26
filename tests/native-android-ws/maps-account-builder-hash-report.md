# Maps controller builder hash memory — 2026-10-27

`build-maps-account-guest.v` now releases its 1 MiB read buffer and SHA workspace
after each file. It uses the already verified launch/JNI builder implementation:
stack CommonCrypto state on macOS and an explicitly freed pure V digest elsewhere.
Input pins, copied provenance and output seals still use the same SHA-256 bytes.
The read-only `--hash-file PATH COUNT` diagnostic exercises the production helper
and frees each returned hexadecimal string.

Both source snapshots were compiled separately with the pinned
`v-tccbin-bootstrap-20261026/v` and
`-new-compiler -gc none -nocache -cc cc`. The before snapshot adds only the probe
to the original hash implementation. `/usr/bin/time -l` measured these macOS
peak resident set sizes while hashing the same 1 MiB fixture:

| Calls | Before | Fixed |
| --- | ---: | ---: |
| 1 | 3,014,656 bytes | 3,014,656 bytes |
| 128 | 139,247,616 bytes | 4,194,304 bytes |

All four runs returned
`f7cef56a05920e8f77e68473ec718b7a8bdd0f31795c746bbc6e91879c2c296d`.
The existing builder self-test passed. The retained
`current-builder-hash-check.v` executable also passed all 12 fixtures (empty,
SHA padding boundaries, 1 MiB read boundaries, 3 MiB and 32 MiB), checking every
digest against pure V and `shasum`. Missing files, directory reads and invalid
iteration counts failed as required. Its 4,096 repeated one-byte hashes peaked
at 2,195,456 bytes, versus a 1,966,080-byte one-call baseline.

An independent source review confirmed that `checksum.hex()` creates a separate
owned string before deferred checksum cleanup, and that success/error paths
release the buffer and digest allocations. The non-macOS branch was reviewed
but not executed. This measures one leaking builder path; it does not establish
the cause of the reported 92 GiB session peak or a guest/account-login result.

Evidence is outside Git at
`/Users/alex/.local/state/vinix/android/maps-account-builder-hash-check-2026-10-27-r1`.
It retains source snapshots, binaries, compile/self-test/time logs and fixtures.
The outer `sha256.txt`, which also pins the complete `verified/sha256.json`, is
`4b32388c1fafe935ab1f0cd814bc1f10bbffe2d6eb911c4f1248c0795aa14370`.
The verified checker bundle seal is
`7f59ddb33d82e347d4279d5846ebeb1919d3b98982c38e833ca123a805084f0e`.

The checker recorded revision `8fa48d6081fbc1fa95e3e335b0c1e04bf288bc97`.
The exact tested fixed builder source is
`17f4c31648950e2da1050cbabb72a59de3e94a9828fdf49128bce53a18e7adcf`;
the original hash with only the probe added is
`5c1c68fab0942762885fd0783f483ab0a81a7e862dbd65255523cb22a4299a43`.
The pinned compiler is
`0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe`;
the reused checker executable is
`d236cef872ae786f3509425c819532856881ea6714c0071b6c237c2b8da1e432`.
No full controller build or VM boot was performed for this check.
