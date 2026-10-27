# Maps account controller polling memory

The `-gc none` guest controller now resets a scoped arena after process,
launch-receipt and stop-request observations. Identities retained between polls
own cloned start ticks outside the arena; replacements free the previous clone.
Typed JSON metadata is initialized before scoped decoding. Cleanup preserves
completed inventories even when another inventory fails. Broker output reserves
one bounded 16 MiB buffer and releases each pipe-read block.

Two independent reviewers checked arena escapes, persistent identities, errors,
JSON caches, output buffers and defer ordering before this change was committed.
The native complete `--self-test` passed, including 256 reset/poison iterations.

The credential-free `--poll-memory-self-test` parses 64 synthetic process stat
rows and a Maps launch receipt per iteration. It changes one retained process
identity each time, checks copied errors after arena reuse, verifies the 4 MiB
arena-capacity bound and tests fragmented readiness with a fixed output buffer.
The separate profiler uses exact-child `wait4` RSS, a 1 GiB RSS guard and a
60 second deadline; its host executable uses Boehm GC.

Measured on macOS on 2026-10-27:

| Fixture | Polls | Peak RSS | Elapsed |
| --- | ---: | ---: | ---: |
| Same parser workload without reclamation | 4,096 | 410,288,128 B | 933 ms |
| Scoped polling | 18,000 | 2,867,200 B | 9,464 ms |

The scoped run recycled 2,642,212,652 bytes of temporary allocations; its largest
arena capacity was 393,216 bytes and all 35 copied errors survived reset. These
are bounded synthetic fixtures, not measurements of the previous ARM binary or
Google authentication. They do not establish the cause of the reported 92 GiB
host event. Live guest controller RSS and actual Maps login need separate runs.

The audit files are outside Git at
`/Users/alex/.local/state/vinix/android/maps-controller-poll-memory-2026-10-27-r1/`.
The source baseline was `57a10806915c7539c6ac50468f81d2a700051f58`.

| File | SHA-256 |
| --- | --- |
| `maps-account-guest.v` source | `3814ca3348883814cb0b25e94d3dabb1d8300a7df35b7ab3921b4eb65301538a` |
| `maps-account-poll-profile.v` source | `8967dd439daecc8b409620827f1fbaf8081a37f63b5ad5c2f2251ccf76cc1716` |
| `maps-account-guest-final` | `57d2df9af1e8b4d527ffbb4be93d11f3aa1bc124906b61abd14582b922da7633` |
| `maps-account-poll-profile-final` | `b280d7273187b7e6f28f85157a52caf25e3055bc2a5a85ad65dd2f443046f964` |
| `poll-profile-final.json` | `a4d48c04fa83690bab1f8fece05aa5197a9f726cc5765ab386b3817ae698ed7a` |

`native-final-build.log`, `profile-final-build.log`, `self-test-final.log` and
`profile-final-run.log` retain the native qualification. The pinned compiler is
`/Users/alex/code/v-tccbin-bootstrap-20261026/v`, SHA-256
`0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe`.

The complete static ARM producer is retained at
`/Users/alex/.local/state/vinix/android/maps-account-guest-build-2026-10-27-r7/`,
from source revision `d55f919c628712617a8c8cda0b68e5f683fd5270` and the controller
source digest above. Its frozen native complete self-test passed; generation,
cross-compilation, static linking and input-closure verification passed. The
producer took 70.57 seconds, used at most 460,374,016 bytes RSS and reported zero
swaps. `producer-build.log` is retained in the polling audit directory.

| Producer file | SHA-256 |
| --- | --- |
| `sha256.json` | `680942c83d4877b8258e5f53ac454aebc3c021331470a002754bc1647ae1e890` |
| `bin/maps-account-guest` | `9c213a85235b802fc3b068ff2d195ea207ba82ded7fe6cdee408e0bd55921c0c` |
| `build.json` | `c6fe1e548a38fa149e27aecc8ebae6c40a2c5929dfd5a2ce0e19904290ee620b` |

This producer has not yet been booted in the guest. The measured native fixture
does not substitute for live ARM process RSS or an authenticated Maps session.
