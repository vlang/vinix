# Maps direct-boot runtime validation

The generic direct-boot metadata fixture passed in the actual ARM guest. GMS
still exited: the filtered Java exception identifies missing
`Context.createCredentialProtectedStorageContext()`. No actual Maps launch
after that broker failure or authentication success is established.

All artifact names below are under
`/Users/alex/.local/state/vinix/android/`. Complete external inputs and prior
closures remain required; this report is not a replacement for them.

The closed runtime is `maps-direct-boot-vm-r1`. Source and producer revisions:

| Input | Revision or complete manifest SHA-256 |
| --- | --- |
| Memory controller fix | `d55f919c628712617a8c8cda0b68e5f683fd5270` |
| Controller producer `maps-account-guest-build-2026-10-27-r7` | `680942c83d4877b8258e5f53ac454aebc3c021331470a002754bc1647ae1e890` |
| Memory stage `maps-controller-memory-r1` | `944007c40fff691ad3c2973970ad5e840aea7bff7370bda5486377c274a1fd21` |
| Direct-boot framework fix | `96b4bafdd` |
| `combined-account-webview-direct-boot-framework-2026-10-27-r1` | `a3445b78a7c4049fa71ee0f81469dca7da2236c36788500cd8bd3c8bb0b81552` |
| Stage source | `374dfb6c1842c3523b49c582403347fc49be99f6` |
| Immutable stage `maps-direct-boot-r1` | `fa9e552f7faf4aabfcf17821efc442918bab5576ea230d25eb9dcd6788d62285` |
| `direct-boot-fixture-2026-10-27-r1` | `12dfc238b637266100e8545b67ba263d91c9bf477fbdfcb14df337dae07d2cfa` |

The stage preserves the eleven memory-stage modules and adds the six-file
direct-boot framework overlay. The retained PIDFD kernel patch preserves all
twelve modules. Exact clone, source/dependency snapshots, tool identities,
preparation and patch receipts are included. [Stage](maps-direct-boot-stage.md),
[memory](maps-controller-memory.md), [fixture](direct-boot.md) and
[transfer](direct-boot-transfer-2026-10-27.md) reports describe their separate
qualification scopes.

The validated runner launched owned QEMU PID90432 at 01:19:45 UTC with 12GiB
and four CPUs. `stop.json` records SIGTERM at 01:30:33. The first stop returned
1 during the ownership/exit race after writing that receipt; reconciliation
passed at 01:30:44, with the owned PID absent. The QMP socket and PID file are
absent. This establishes stopped ownership, without a QEMU reap-status claim.

The UART records the isolated ARM polling fixture at lines411–412: 18,000
iterations over 64 synthetic process rows, 173,094 bytes peak scratch used,
393,216 bytes capacity, 25,760KiB maximum RSS, 1.25s and exit0. This fixture
does not spawn the actual broker. The retained host QEMU RSS of 7,154,848KiB is
one snapshot, not a peak or an explanation of the earlier 92GiB observation.

`broker-exit.png` shows actual transport readiness followed by broker exit.
Filtered UART6083 reports `NoSuchMethodError` for the credential-storage Context
method through `GmsApplication.attachBaseContext`; native SIGSEGV follows at
6094. The public receipt has status `failed`, `service_ready=true`, broker
exit1 and zero cleanup survivors. Readiness establishes the transport listener.
Empty initialization-failure arrays do not establish account readiness.

The subsequent generic fixture receipt records profile `direct-boot`,
uid/gid10117, child65107 and wait status0. Its checks require exactly one PASS
and native READY, live input until both, bounded log, drain through EOF, clean
exit and unchanged pinned inputs. The JAR, two APKs and ARM runner hashes match
their retained producers. UART6166 records `SERVICE-QUERY-RUN-PASS`; the exact
fixture marker at6169 ends in `direct-boot-metadata`. This validates the generic
metadata behavior, including disabled-component metadata and no initialization.

The unchanged strict collector remains **FAIL**. Its independent closed-UART
rerun exited1 at line2364; the proposed `maps-direct-boot-closed-results-r1`
directory does not exist. Kernel exec/ELF text and ten console `ps` lines
(header plus nine process rows) interrupt chunk963. The original UART is
retained byte-for-byte:

- 2,303,462 bytes; SHA-256
  `a83c197a0871b1cd254963179042e640fe0ad3714873fbcaee646e1fc31c2af9`.
- Main announced archive: 1,439,710 bytes /2,812 chunks /21 entries, SHA-256
  `1dd24d02c9474df123b385297e507d26ad7ef151892804af17fb8ef3279c6499`.
- Separate fixture archive: 16,027 bytes /32 chunks /2 entries, SHA-256
  `ba4f5dcfdd26d21c2c22d3824756abb3aebee0c438b338214bfbd108c25aeb7a`.

The separately labeled diagnostic tool selects one complete export from the
full pinned UART. The main plan removes 24 exact literal ranges; the fixture
plan removes zero bytes. Both verify the full announced size/SHA, canonical
chunks and every entry before saving diagnostic artifacts. No repaired serial
or strict import is written. Version1 historical guards remain unchanged.
The source change is `373ed9a537b86170f854ee335c287d98f1961068`; all eight
positive and 38 rejection tests passed. Actual main/fixture derivations passed
at 33,751,040B/10,764,288B maximum RSS. Private app logs remain excluded; only
broker-log hash `b3bf38fe4ff260b75a30d3c2aeb7048bc3dd084288ae4811e605bb48ce1a1573`
is retained in the public metadata.

`maps-direct-boot-vm-r1-stream-plan-2026-10-27-r1` retains both exact plans,
frozen source/executable, public receipts, build/self-test/derivation logs,
timings and explicit 55-root list. Independent read-only reviews passed its
canonical nonoverlapping roots, all 22 exact direct stage inputs, source guards,
actual diagnostic metadata and strict-failure scope. The new roots retain
complete new originals and reference the original complete historical trees.
Their unchanged full checks freshly passed: controller closure
`f2407f1b7b23ae6c453afef451831e5f24889eee6933f49e79d51441d7ce6da5`
(60 roots /51,109 entries) and service-query closure
`0341a63a280f6a8c43db20a663dc873d0918676c61b739ce52b7808169a80f32`
(44 roots /8,005 entries). Historical requirements remain unchanged.

The final closure is `maps-direct-boot-vm-r1-runtime-sealed-2026-10-27-r1`,
manifest SHA-256
`addc98839b845b800d966932221a2d33b0d5c4f98c07e3dd1070900315e9dea0`.
Its streaming seal plus internal full check passed all 55 roots /11,445 entries
in 15.83s at 18,432,000B maximum RSS. A separate pinned full check passed in
8.74s at 18,333,696B. Both recorded zero swaps. Adjacent
`maps-direct-boot-runtime-stream-2026-10-27-r1.{seal,check}.{log,time}` retain
the results. The seal occupies 2,956KiB and the small diagnostic plan 1,956KiB
as recorded by `du -sk`; large originals were hashed in place without copies.
Scope excludes recursive historical ancestry and a hermetic SDK/C/shared-library/
QEMU rebuild closure.
