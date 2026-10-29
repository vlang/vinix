# Platform Fragment media tools with uncached hashing

Fresh qualification over source revision
`a95eb8b70e83f3dda711f73c00b48bd4638ead39` is retained at
`/Users/alex/.local/state/vinix/android/maps-platform-fragments-uncached-tools-2026-10-30-r1`.
This rebuild incorporates the per-descriptor macOS cache policy described in
[maps-uncached-hash.md](maps-uncached-hash.md) into the stager. The separate kernel
patcher owns its own hash implementation and does not acquire that policy.

The source, compiler and final tool SHA checks passed. Frozen inherited compiler
closure and flagged C inputs compare byte-for-byte with the previous closed
qualification. Retained generated C uses SDK `struct stat` size/alignment,
`fstat()` and `fcntl(fd, F_NOCACHE, 1)` on the opened hash descriptor, with explicit
metadata cleanup. Production C commands and flags are retained unchanged; host
SDK and system libraries remain recorded environmental inputs.

Serial V generation, exact emitted C compilation, both self-tests, complete actual
framework/native input audit and helper enumeration passed. The audit preserves
the exact two native source changes, unchanged JNI/bindings, 2,104→2,105 canonical
class delta and consumed Activity change with the other 67 classes equal. The
patcher passed every historical profile and the new profile's negative cases.
Runtime JAR, DEX, native library and APK pins remain unchanged from
[maps-platform-fragments-stage.md](maps-platform-fragments-stage.md).

All eight phases used 600 MiB aggregate RSS, 300 seconds, 512 MiB observed growth
and 1 GiB reserve. Guard and time-reported maxima both passed; every phase recorded
zero swaps, clean exit and complete cleanup.

| Phase | Guard seconds | Sampled RSS bytes | Time maximum bytes |
| --- | ---: | ---: | ---: |
| Stager generation | 3.439 | 306282496 | 310312960 |
| Stager C compile | 6.512 | 260931584 | 242860032 |
| Stager self-test | 0.252 | 1245184 | 18497536 |
| Actual input audit | 3.439 | 51429376 | 50282496 |
| Helper enumeration | 0.364 | 28508160 | 37421056 |
| Patcher generation | 3.381 | 341606400 | 366051328 |
| Patcher C compile | 11.135 | 337215488 | 327761920 |
| Patcher self-test | 17.306 | 44449792 | 37355520 |

The complete one-root, 591-entry seal and separate-process full readback passed
under 600 MiB/900-second/64 MiB growth/1 GiB reserve limits:
`/Users/alex/.local/state/vinix/android/maps-platform-fragments-uncached-tools-sealed-2026-10-30-r1/sealed/manifest.json`,
SHA-256 `85e9cffc9b463a31d68d6d4d92936f7a88d4201c837d85733a35de79c184fe29`.
The input and seal roots are closed. Final tools below the qualification root:

- `stager-project/maps-platform-fragments-stage`: `f61342792d540ee731969ba683528b8724a2bef15a1c65590ccef5dc0e4c6ee3`
- `patcher-project/patch-kernel`: `69f89dd0991b20c1266eccb10eb2ee774e8826afca27523f9af957e80be22b5a`

This qualification prepared no image and launched no VM. It establishes neither
reduced host swapping nor Google authentication or map rendering. Those require
separate measurements and guest evidence.
