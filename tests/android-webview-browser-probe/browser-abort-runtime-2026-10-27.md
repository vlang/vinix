# Browser r17 diagnostic: closed runtime and rejected export

The credential-free browser diagnostic recorded a desktop boot and began a
UART export. Strict collection rejected the export because ordinary log output
interleaved with its frames. No archive was decoded, normalized, recovered or
imported. This run establishes no browser abort callsite, DOM result, successful
browser workflow or Google authentication.

External paths below are relative to
`/Users/alex/.local/state/vinix/android/`. The complete closed run is
`browser-r17-abort-launch-r1`; its staging audit is the sibling
`browser-r17-abort-launch-r1-audit`. Original observations remain unchanged.

## Inputs and lifecycle

The mutable launch tree was freshly restaged from the same inputs as the
immutable preparation, then patched with the frozen PIDFD kernel. It was not a
clone of the prepared image. The preparation and its complete input closure
are documented in [the staging report](browser-abort-stage-2026-10-27.md).
The stager recorded source revision
`15fd6d2eb27cb478e744bd3ed7969050535972bf`.

The retained daemon runner records source revision `1733801d2`, entry-source
SHA-256 `c13a45576372481b911e0623dda7b0080438c7c5ba54b668c681459d57b67e12`
and executable
`2419d0760fa92a3e9caa3e60c5596836400616cad8205ca8e6118ade14979908`.
Its original complete 20-file build-evidence manifest remains
`maps-account-daemon-runner-closure-2026-10-27/sha256.json`, SHA-256
`711c05cc23e68cf81039e37ea0d3d5a92fb52bed8ab083cedaef79cf6153de2f`.
It retains build commands, exact source, used/rebuilt executables and tests;
it is not a hermetic compiler, SDK or QEMU rebuild closure.

Launch began at 2026-10-26 23:21:31 UTC; ownership records PID 97264 with start
time 23:21:32 UTC. The checked SIGTERM request was recorded at 23:28:27 UTC.
The initial stop sent the signal and wrote `stop.json`, then reconciliation
reported differing live identity during exit. A read-only disappearance command
refused the existing stop receipt. The subsequent stop reconciliation succeeded
without another signal: `gone.json` records one absent-PID `ps` snapshot at
23:28:47 UTC, and the QMP socket and pid file are absent.

`qemu.log` records signal 15 from PID 57692. These receipts establish observed
host cleanup. There is no wait/reaped QEMU runtime exit-code receipt;
`launch-result.json` code zero describes daemon launch. This audit issued no
VM launch, QMP command or signal. A second agent independently checked the
lifecycle, source/runner pins, receipt links and export limitation.

| Receipt in closed VM | SHA-256 |
| --- | --- |
| `stage-before-kernel.json` | `5e19633506006ad429e3a61ff9ff495ade62a692de53e686c37929060e8c3a41` |
| `kernel-patch.json` | `622cd8f5b2b230858adf3e09270a4dacf4d520be0fe246360072a00b2858396b` |
| `stage.json` | `49c4063314f0d2f3543765fc1a7f86f30698b6e33b5b02fbf70c48a0294db0a3` |
| `launch.json` | `d92c237804ed0be56ed5741dfbaae8c03bdbeb4025cf5e07963a51bf77d67f1b` |
| `launch-result.json` | `bda4f62ea4277fb633cee85227141c933474e815b562c7016377ba335d2afc43` |
| `ownership.json` | `8682ccbab91a0fda59a69e6044b20d41d5b5f06fba8c9dcdc0d5070d74ac0aca` |
| `stop.json` | `83befa9457b5bf9e4dceb307a9b08f2e928f3a0f51bc643254de6d28098d8aec` |
| `gone.json` | `211f4166981c69c9c88875d63918fa8244323becbda32df84e87007798f4a60c` |
| `qemu.log` | `5825a9a7641864a441998f746765008711582ade1018851c2041e0df2ae6674c` |

The mutable stage and kernel receipt match launch. Their recorded prelaunch
boot hash is `4e01cff85bb325fe497c9a8967895c90e10103f261da1c16930e4a9f56b2a04f`;
the retained browser overlay is
`576b97bcd9fe433c85e548a76033c365d66365a436f4410921d23b9c51b10445`.
The closed-tree seal inventories actual post-run boot and firmware bytes.
Immutable preparation receipts retain their separate original meaning.

## Strict rejection and preserved observations

The raw `serial.log` is 5,221,716 bytes, SHA-256
`cdd14b1a95389fded08dfbf540a26e130822a4900640f91cb462c2b4a6564204`.
The original strict collector is `maps-account-collect-r2`, SHA-256
`f1245b715d75ab41a6f1c8b3c0d45e1aed9158bfe3cd097c939ee845a3b1b29e`.
Its retained owner log, `browser-r17-abort-collect-r1.log`, SHA-256
`247113f079c0c52ac4007855e76986f04705e665a6248156d74b68cdec38a466`,
records `unknown export frame at serial line=5526`. It records 0.60 seconds,
maximum RSS 28,852,224 bytes and zero swaps; it contains no separate exit-code
receipt. The collector was neither modified nor rerun for this audit.

LF-delimited line 5526 carries chunk 5218 with embedded `unix acc` text;
chunk 5219 at line 5527 is also corrupted. Compositor notification/history and
kernel output mix into this export, including text inserted within frame
payload. This is a bounded corruption observation, not an exhaustive malformed
frame count or integrity check of the remaining frames.

BEGIN at LF line 307 and END at 6924 both announce 3,378,290 bytes, 6,599 chunks
and digest `d4c30095a33edf38df2c8bdd0150f84a120e416082e395cf3395e3f2075b25fd`.
Those declarations do not verify an archive hash. No imported result directory
was produced or accepted; no payload bytes are reproduced here. The export
failure prevents accepting the guest's encoded fixture results.

Both retained PNGs are bound without inferring browser contents:

| PNG in closed VM | SHA-256 |
| --- | --- |
| `desktop-initial.png` | `a6c57e61f22239b24216dc61aec02a2be989301f933f2c64154fadab829cdeed` |
| `desktop-ready.png` | `2aa90b6adb23abf36dd30145945b0326c1aabceebdaf9105d33128fa676f3225` |

## Bounded streaming closure

The maintained V sealer is commit `39fc264743f4c211183d8c0a4dd2f75fc7668ea2`,
source SHA-256 `148932aee91df125c2fe56f1631b4c89275868232498c6b92c3530f5415b3a6c`,
reused executable `b12a4d0b2b133714da6876a0ed5cda623984dc72284c482d8e3ae57975304e77`.
It hashes regular bytes through a native 1 MiB buffer with bounded directory
lists. Its byte/mode/symlink/missing/extra/output/pin/special-object/overlap
mutation tests and sparse 64 MiB digest test passed again: 0.38 seconds,
maximum RSS 12,353,536 bytes, zero swaps. No compiler or historical unbounded
sealer was run and no large image was copied.

The frozen root list is
`browser-r17-abort-runtime-stream-plan-2026-10-27-r1/roots.txt`, SHA-256
`255aecd2ebd310bed68f5444959dff7dee6d8ab52291ef33efde4a540875080f`.
Its 54 nonoverlapping roots include the complete closed VM, full staging audit,
all adjacent owner logs, every direct root in both the original 16-root
prelaunch closure and historical 29-root r13 closure, those original seals,
the daemon-runner build evidence, QEMU, canonical firmware and small audit plan.
The plan retains a separately pinned older collector-source snapshot without
asserting source-to-existing-binary build equivalence.

The first seal attempt rejected the firmware's symlink ancestor before creating
output. That guard failure is preserved in the plan. The corrected explicit
canonical firmware referent and QEMU executable hash to the values in launch.
Seal/check logs are adjacent to avoid mutating inventoried roots.

The frozen plan README compresses launch-request time as PID start time and
attributes transient-file removal to reconciliation. The precise ownership time
is recorded above. The frozen runner's reconciliation writes `gone.json` only;
socket/pid absence is a separate observation of the closed tree.

The completed closed-tree manifest is
`browser-r17-abort-runtime-sealed-2026-10-27-r1/manifest.json`, SHA-256
`a19d8c329458189d6dda70263dd0cf02fd299f152c217a37bb203e839777768e`.
Seal plus internal full recheck passed over 54 roots and 6,930 entries in
29.18 seconds, maximum RSS 18,071,552 bytes. A separate full check passed in
15.25 seconds, maximum RSS 22,642,688 bytes. Both recorded zero swaps. These
actual passes remained below 22 MiB RSS; they do not establish a universal
peak for arbitrary input trees. Generated inventory output uses 1,884 KiB of
allocated disk space and the small audit plan uses 48 KiB (`du -sk`).

The adjacent execution receipts have prefix
`browser-r17-abort-runtime-stream-2026-10-27-r1`:

| Suffix | SHA-256 |
| --- | --- |
| `.seal.log` | `e8defcbc450f88c001bd3bf26ea5ade7d0b266fde4c2ee659b1246cbdcffe83e` |
| `.seal.time` | `848616d53acdf3e7d21781db2ea855d531f91ed82992e8f0e1f939d801d1f79d` |
| `.check.log` | `e81f0db2e5a12bd2b7a3391bf45eb4ac61d2f78b66957e469858a2ff4b17a43c` |
| `.check.time` | `ed033f112fa1023b7d77c8431593be577f9943b7f96e02bb39dee800fceb2bc7` |

Original complete roots and historical checkers remain required. In particular,
the prelaunch manifest remains
`3650a056eaa791b22b8ec4ffe919e739e886263841bffc5365f6508e527868a8` and the
r13 historical manifest remains
`e441db6a38048b330918e8935f3ee2abde7acd3dc643d1228ea257a297556de2`.
This trusted-host integrity closure does not replace their checks, resolve all
external symlink dependencies, qualify evidence deletion, establish a valid
export or prove authentication. Compiler, SDK and dynamic-library dependencies
remain external requirements.
