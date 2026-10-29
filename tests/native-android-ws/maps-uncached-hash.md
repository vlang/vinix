# Per-descriptor macOS hash caching

`mapsaccountstage.digest()` now uses `fstat()` on its newly opened descriptor.
For regular macOS inputs of at least 64 MiB it requires
`fcntl(fd, F_NOCACHE, 1)` before the original 1 MiB streaming SHA loop. Stat
storage uses the native SDK `struct stat`, `sizeof` and alignment; its owned
pointer is explicitly freed on every return. Deferred file close covers policy,
read and hash failures. The read-to-EOF loop, SHA updates, complete inventories,
input rechecks and disk/memory guards are preserved. Non-macOS policy is a no-op.

The installed SDK's `sys/fcntl.h` defines `F_NOCACHE` as command 48 for an open
descriptor. Apple's [fcntl manual source](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/man/man2/fcntl.2)
documents its nonzero argument; [XNU's implementation](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_descrip.c)
sets an open-file-description flag, separately from vnode-global `F_GLOBAL_NOCACHE`.
Apple's [file-system guidance](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/FileSystem/Articles/FilePerformance.html)
discusses avoiding cache pollution from large sequential reads. This change is a
targeted precaution: the hypothesis that our hashing contributed to host swapping
or shared-volume declines remains unproven. It performs no global purge, mount
change, readahead change or external-process action.

Corrected functional snapshots over source revision
`dbf0fc764ef2a2d43ce3fca84127395cba00be99` are retained at
`/Users/alex/.local/state/vinix/android/maps-uncached-hash-check-2026-10-29-r2`.
Source identities:

- `mapsaccountstage/bundle.v`: `39166e4b3c2745409b6f8547f3af9379c133b3f1d17542978ed80222f32125f2`
- `mapsaccountstage/cache_test.v`: `ebd00b454e190afa909ed3dec18cc39b29ba479fedc91aff2fa5b5d1b7a246c4`
- `cache-project/cache_test`: `6c7293ff5fa4fc39ec9a94f496c751d39fcacda4d0a68121467d936d41dcef6c`

The three compiled tests passed: exact threshold boundaries with fresh descriptors,
invalid-descriptor and nonregular-file controls, empty/small binary vectors, and a
sparse 64 MiB file plus a 17-byte binary tail compared with independent streaming
V SHA-256. The fixture holds only a 1 MiB reference buffer. It uses explicit error
returns throughout, so production assertion removal cannot suppress its checks.
Independent emitted-C review confirmed live comparisons/error propagation,
native SDK stat storage, real `fstat`/`fcntl` calls and cleanup before every return.

Linux/arm64 C generation also passed; its policy function returns success/false
without `fstat` or `fcntl`. This is generated-code evidence, not a Linux runtime run.
All phases used the original 600 MiB RSS/300-second/512 MiB growth/1 GiB reserve:

| Phase | Guard seconds | Sampled RSS bytes | Time maximum bytes |
| --- | ---: | ---: | ---: |
| macOS serial generation | 1.961 | 308936704 | 270663680 |
| C compile | 2.100 | 152584192 | 134430720 |
| Functional execution | 0.800 | 14729216 | 15646720 |
| Linux/arm64 generation | 1.947 | 314261504 | 270581760 |

Every successful phase recorded zero swaps. The earlier R1 is preserved: its
production-generated assertion bodies were absent and cannot establish functional
correctness. Its C compile was refused before spawning because free disk had fallen
below reserve (`pid=0`, no supervised groups); no R1 binary was built. The corrected
R2 resumed only after the same full reserve/growth backing returned. No cap was raised.

The complete two-root, 624-entry seal and fresh-process readback passed under
600 MiB/900-second/64 MiB growth/1 GiB reserve:
`/Users/alex/.local/state/vinix/android/maps-uncached-hash-sealed-2026-10-29-r1/sealed/manifest.json`,
SHA-256 `ee93b59347c7289082e0f435aa769bc726d3b060383cc87311ef223fa7dbcd17`.
Both check roots are closed. Generated C/commands, frozen inputs, original refusal,
logs and resource receipts remain outside Git. Host SDK/system libraries remain
recorded environmental inputs. No image, VM, Google authentication or map rendering
was exercised by this qualification.

Fresh staging-tool qualification is required before using this policy for media.
The separate kernel patcher owns its own hash implementation and does not inherit
this helper's cache policy from a rebuild alone.
