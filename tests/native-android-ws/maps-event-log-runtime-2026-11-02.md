# EventLog ARM pass and missing Build ABI-field failure

The signed EventLog regression **passed on ARM**, preserving payload-preparation
results and reporting its unavailable binary backend. GMS attaches its
authenticator, then exits after missing Build.SUPPORTED_64_BIT_ABIS while loading
Cronet. No manual Maps launch, Sign in, credentials or imagery check occurred;
current map rendering and authentication remain unverified.

Core `b87e5c134`, producer `460a026d5`, fixture `6b7b41c08`, delivery `a77aa71cd`,
[SDK/native pair](event-log-pair-2026-11-02.md) `7cfe91a6d` and
[media profile](maps-event-log-stage.md) `644b7f6d4` are committed.
EventLog is the sole added class, growing membership from 2,116 to 2,117 while
preserving all existing canonical classes and the retained native bundle.
Prepared manifest is
`04e6b12c1b1a2336c6103b611c36989b4b869551c8f14e2c8c43ed588b0d462f`.
All 56 module readbacks and complete input rechecks passed in 359,564 ms at
90,439,680/92,094,464 bytes sampled/detailed RSS, zero swaps, both exits zero and
complete cleanup. Clone/kernel installation passed in 6,908/49,217 ms before boot
under original limits.

Complete evidence remains below `/Users/alex/.local/state/vinix/android`:
`maps-event-log-runtime-audit-2026-11-02-r1` (`A`), matching live controls,
separate `maps-event-log-preparation-2026-11-02-r1`, prepared `maps-event-log-r1`,
stopped `maps-event-log-vm-2026-11-02-r1` with four clone sidecars, and
`event-log-api-transfer-live-2026-11-02-r1`. `A/runtime-result.md` closes the
pending plan without changing it or the independent validation note. Historical
complete bundles and their original auditors remain required.

The isolated UID/GID 10151 child 1243 exited zero with six exact input identities
and eleven unchanged checks. Receipt SHA-256 is
`f510831415931c4e831aba6ba70f0f6dd4fb3ac69dc29fe65f7f2cc992bc3c0f`.
The complete 9,343-byte, 108-line child hashes to
`f8088568acfb8a165a4f514ee06b2ec020113d77dfde1dd712ad6658d7e2c530`:
one exact PASS at line 93, readiness at 102 and normal teardown through 108.
Independent `A/fixture-validation.md` hashes to
`1e2eeb0dc7bf1465c15b00a40be039ae261d908df43d599ad6252369a90ecb10`.
It verifies 91 actual write calls, 35 scalar and 56 array, with 50 -ENODEV (-19),
16 -EIO (-5) and 25 exact IllegalArgumentException outcomes, plus five separate
reflection metadata probes. These execution counts stay distinct from the
132 host source-oracle inputs. Assertions cover overload/primitive/static/varargs
metadata, accepted boxed types, nulls, rejection without stringification,
reference preservation, array-prefix and size/error ordering, and explicit
char-array UTF boundaries. This establishes the exercised unavailable-backend
write contract without successful event delivery or storage. Unchanged
zero-removal diagnostic import preserved 30 chunks of the 15,154-byte fixture
archive, without strict fixture-protocol extension or health waiver.

After releasing the fixture mount, the controller ran from 21:04:55 to 21:06:00
UTC. Receipt
`b489d626f33b08c4cc94a220a68bf84c2f24d3e8cf58089da217b1eab75892e1`
records broker 48797, readiness true, failed/exit 1, drain EOF true/status 1,
382,875 bytes, errno zero and zero cleanup survivors. The uncaught RuntimeException
rethrown by StandaloneSchedulingEngine is caused by missing static
`Build.SUPPORTED_64_BIT_ABIS:String[]`. The cause reaches `aegy.a` source 12 →
`aeat.h` 76 → `DynamiteModuleApi.onBeforeApkLoad` 29 during the
`PlayServicesCronetProvider.createBuilder` path. GMS then calls killProcess on
itself and System.exit(0), recording native VM status zero; the controller records
the broker failure. Readiness and that native value do not establish successful
startup or Google authentication.

Automatic export finished with guest input idle. Before stopping the VM, the
unchanged strict collector passed 21 entries, 2,831 chunks and 1,449,024 bytes,
archive `d3cb389c5dc6004889cec1a51c333832dd962dad6535f842c755e14ce822326c`.
Import took 293 ms at 29,556,736 bytes sampled RSS; both exits are zero with
complete cleanup. The full private broker log remains separately at
`A/broker-log-diagnostic/child.log`, 382,875 bytes, SHA-256
`a360e63f9bb83b9ff776233bdac965a5869fb1a4eac67f4c2da2b13f8da0df5a`.
The existing guest-pinned canonical-base64 decoder and fresh readback passed
without modifying original UART or payload bytes. Private logs stay outside the
strict account archive apart from hashes. GMS exited before a manual Maps open;
cleanup removed the live protected session required by the supported launcher.

Owned exclusive 12 GiB/four-CPU VM 11404 started at 21:01:42 UTC. One SIGTERM was
requested at 21:07:47; QEMU records signal 15. The first stop returned 1 on an
ownership race; no second signal was sent. Qualified reconciliation returned
zero, with gone.json at 21:07:55 and an independent empty exit-1 ps query
confirming absence. Final UART equals the immutable after-broker-log full
snapshot, both SHA-256
`47316f3f0baa8f63b4d6d8a5f3623915e6e82c8b2fce582a6fc1a66c3382c39a`.
No compiler or Java ran while the VM was live. Ten closed roots passed complete
sealing and a separate fresh-process readback of all 728 typed entries. The
manifest at `maps-event-log-runtime-sealed-2026-11-02-r1/sealed/manifest.json`
hashes to `22a05b158e016e1889169071a665cd2fd389fb608971cabbdc5fddac9d2abdea`.
Seal/readback took 8,437/6,243 ms at 15,581,184/22,986,752 bytes sampled RSS,
with 65,527,808/815,104 bytes observed shared growth and zero swaps. Both seal
and readback guards/children exited zero with complete cleanup under the original
600 MiB RSS, 900-second, 64 MiB shared-growth and 1 GiB reserve limits. Failed
source and tool-attempt history remains preserved in the required upstream bundles.
