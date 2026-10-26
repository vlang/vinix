# Wine startup diagnostic checkpoint — 2026-10-26

Wine remains unqualified. On the original x86_64 kernel, the signed Win64
probe exits 1 with empty output before READY. A fresh bounded foreground
wineserver probe receives SIGABRT (raw wait status 6) before its startup
message; the background probe exits 1 (raw status 256). Neither times out.
The `sock_init: shutdown() causes EOF` line is a normal debug classification.
The debugger replay below identifies the abort as a refused socket chmod.
Version commands and the presence of a private
lock/socket do not establish successful server initialization.

The maintained controller records checked nonblocking setup, raw 32-bit wait
statuses, EINTR retries, and bounded server-directory metadata. A separate
guest probe passes empty nonblocking pipe reads, raw fork/WNOHANG/kill/reap,
and the redirected `os.Process` path. Diagnostics retain the failed signed
launch's identity, environment and sandbox; they cannot satisfy its PASS gate.

Both captures use source baseline
`75066fba303a0b748fc14bd13f347cb0cb1525ef` plus the source snapshots and hashes
in each `capture-report.json`. The captured maintained source hashes are:

| Source | SHA-256 |
| --- | --- |
| `tests/packages/wine-native/main.v` | `6fff17917adad60f80d7adbfda099572cef14054a92b944c3f48506c185b914e` |
| `tests/packages/wine-process-probe/main.v` | `24dd3eb92a4bb0860465c9d7ed595f37adf280e610b19785abf9f2aa81d4f6ee` |
| `tests/packages/wine-startup-check.v` | `43309ad5062207a2156e1a4157353e53a023211181dd360c573b11987dd8a735` |
| `tests/packages/winesource/closure.v` | `09afc720d6598b1d5529186ab4c91ef8ca1fb10708ddd7ff825b5c7503cae601` |

Complete bundles are outside Git under
`/Users/alex/Library/Caches/vinix-codex/section14/`. SHA-256 values below name
each bundle's `SHA256SUMS`, which covers its ordinary files; `objects.json`
separately records symlinks and special objects. Independent verification
re-read every retained ordinary file and checked those objects.

| Bundle | Result | `SHA256SUMS` SHA-256 |
| --- | --- | --- |
| `wine-proc-20261026` | Process primitives PASS; 199 selected inputs, 238 ordinary files, 2 special objects | `d19148f9a6c3589c1bb227263f78cdb9cc3c0e000682a73033c9879b06242137` |
| `wine-srv2-20261026` | Signed Wine refusal retained; bounded diagnostics complete in 67.648 s; 2,514 selected inputs, 3,560 ordinary files, 3 special objects | `679d0941220805e5353455dd6479817b8a984c7cf71f1c5322195d161d536b7d` |

The controller uses the production `-gc none -manualfree` mode and compares
the discovered and built parsed V source closure with `winesource.admit`.
Its selected-path inventories agree before and after the run. They do not
admit the complete sysroot, GCC runtime, headers or actual linker closure.
The server run reuses frozen signed extras from `wine-dbg-20261026`, including
older package tooling/runtime. It is diagnostic evidence, not fresh package
qualification or a hermetic build claim.

Earlier failed attempts are also preserved, without rewriting their evidence:

| Bundle | Failure | `SHA256SUMS` SHA-256 |
| --- | --- | --- |
| `wine-server-debug-2026-10-26` | QMP socket pathname too long; no guest started | `1001dc455bf2788aa0f5fe619d2d6e9bd0ac0d7a6543e1106d3091340938939e` |
| `wine-dbg-20261026` | Foreground diagnostic stalled; later fixture ownership fix means this is not a server-hang qualification | `f2d4d2dfb916d366a2a013130426f915479bc54a0704fc1801bac1a8d8ec1a69` |

The initial lightweight host controller also aborted during inventory cleanup.
Its binary, crash report and empty attempt directory are preserved beside
`wine-server-tools-20261026`; its exact historical source closure was not
captured. The current controller and guest diagnostics explicitly free owned
strings separately from raw array storage, and release only storage for
borrowed launch arguments. The two fresh bundles above use those fixes.

ARM translated fork, successful signed Wine execution, and the generation
lease interval from client exit through detached wineserver exit remain
unqualified. These diagnostics add no acceptance exceptions.

## Refused socket chmod and scoped launch fix

A read-only LLDB replay of the unchanged retained ISO and original kernel
stops at `userland__exit_with_fatal_signal(6)`, called from the pending pledge
violation path. Its saved syscall is x86_64 number 90 (`chmod`), first argument
`socket`, second argument 384 (`0600`), with pending promise bit `0x100`
(`fattr`). This matches Wine 9.17's private server socket initialization. The
final maintained producer, `wine-pledge-debug.v`, pins both kernel and ISO
hashes before using the retained kernel's addresses and DWARF layout. It
binds the selected debugger/emulator/source inputs before and after replay;
it does not admit their complete library/toolchain closure or qualify Wine.

All four small debugger bundles retain their selected input bytes, producer
source/executable, argv and logs. A separate verify pass re-read every sealed
file and selected-input mapping. The first two exploratory attempts have
initial input maps only; the final two also verify inputs after the replay.
The immutable ISO and identical input blobs share hardlinks to avoid copying
large frozen inputs. Source baseline is `6d8c5fdc68755d46f00c440798e518266014d97f`
plus the exact `producer.v` snapshot in each bundle.

| Bundle | `SHA256SUMS` SHA-256 |
| --- | --- |
| `wine-gdb-20261026` | `45563c5a33d0bdb02eff792c6b8e2bcfcc4cb49caf1ed0553aa95262f752b6b6` |
| `wine-gdb2-20261026` | `dd5d536c87c633e19aa213cb03f02a51380e24151227e0946ff5eb93e9342623` |
| `wine-gdb3-20261026` | `0f404567579997058bb1053e28abf4174efe621110cc3e2cd863442b48c786a2` |
| `wine-gdb4-20261026` | `60d523f1f4ac802f6c8750207a915fb1e019c6bf631670454933e2f72a9aaafa` |

Windows launch plans now receive exactly one `fattr` promise, allowing Wine to
set private prefix/socket metadata. Other package kinds keep their prior
promises; payload/runtime `rx` and private data `rwc` paths are unchanged.
The promise vector reserves its new maximum of 13 strings, avoiding manualfree
growth in the Windows terminal/network/process case.

This scope relies on production admission and Unix ownership as well as
unveil. Ordinary CLI and service execution refuse alternate package roots.
`load_config` requires real-root trust/config/state objects to be root-owned,
non-symlinks and not group/other writable. Installed namespace and payload
verification bind every app/runtime/dependency object to that state owner,
signed modes, hashes and expected link counts before launch under its lease.
Sandbox setup drops identity, supplementary groups, capabilities and inherited
descriptors >=3. Thus the ordinary child cannot change admitted root-owned
payload metadata even through a read-only file descriptor. Descriptor metadata
operations do not all consult unveil; no general descriptor isolation claim is
made, and existing standard-I/O descriptors retain their existing authority.

Host assertions cover all package kinds on both architectures, optional
process permission present/absent, and exact unchanged unveil paths. The
36-case ownership matrix passes 1,000 warmed plan/close cycles per case with
zero retained tracked bytes. ASan/UBSan also pass. These checks qualify host
plan construction and ownership only; signed Wine execution remains required.

The selected source/compiler/output capture is
`wine-fattr-host-20261026`, `SHA256SUMS` SHA-256
`96bfda42b0903577a762656c1b573be23087f609810885212faa30130aae04f5`.
It retains both passing binaries/logs and their selected inputs; its scope
explicitly excludes a complete imported-source/C/toolchain closure. The pinned
debugger producer also refuses a different kernel and a different ISO before
creating output or starting QEMU.

The dedicated `wine-metadata-probe` now passes on the original x86_64 kernel
in 13.077 seconds. With `fattr` granted, sandboxed UID/GID 1000 changes its
private file and Unix socket to mode `0600`. Descriptor chmod, explicit
timestamps and access ACL changes to a root-owned `0644` payload each return
`EPERM`; its metadata and bytes remain unchanged. The generated C confirms
32-bit descriptors, native `stat`/`timespec` layouts and a stack socket address.
Independent review covered the process cleanup and ownership boundary.

This is an ownership analogue using a byte-bound production sandbox binary,
not a signed package launch. The `metadata` controller mode admits its parsed
V closure and compares selected inputs before and after the run; complete
sysroot/GCC/header/linker admission remains outside its scope. Source baseline
is `5045cd10595759b384c5b51457045b0ef6244065` plus the three maintained source
snapshots in `wine-meta4-20261026/capture-report.json`. That bundle also retains
the three preboot failures, including an accidentally selected host compiler
and a corrected C name collision. Its `SHA256SUMS` SHA-256 is
`37500739f5a0002b77f3d161473d2740ec999830d292522b3727616f413949cf`;
the bundle retains 200 selected inputs. A separate verify pass re-read all
261 ordinary files and the inventory of two special objects. Signed Wine execution
and detached-server lease coverage remain unqualified.

## Explicit current-CLI diagnostic admission

The server diagnostic accepts an optional absolute CLI path and expected
lowercase SHA-256 after its original arguments:

```text
wine-startup-check server OUTPUT KERNEL EXTRAS SYSROOT GCC_RUNTIME CURRENT_CLI EXPECTED_SHA256
```

All three original seven-argument modes retain their behavior. Only `server`
accepts the additional pair. Admission occurs before output creation and
requires a bounded ordinary executable with one link, no special mode bits,
an x86_64 ELF64 executable header, and the exact supplied digest. This is a
header filter, not full ELF or current-source qualification. Source identity,
metadata and bytes are checked again during staging and after the run.

After cloning the frozen extras, the controller replaces only
`usr/bin/vinix-package`. Ordinary directory ancestry, an ordinary single-link
target and a distinct source inode are required. The receipt records the old
target digest, selected digest and resulting metadata; the exact staged bytes
and permissions are checked before boot and afterward. Frozen extras retain
their original input comparison. The full `HWTEST PASS packaged-Wine` marker
and all failure markers remain unchanged. These path rechecks assume trusted,
stopped host writers and do not exclude hostile concurrent rename races.

The maintained `wine-current-cli-host.v` builds both the controller and
`wine-current-cli-check.v` with `-prod -gc none -manualfree`. Its final run
passes 13 control groups covering original arguments, server-only selection,
digest/header/mode/link refusals, exact staged bytes, preserved frozen bytes,
changed input/target and replacement-inode refusals. The actual controller
also refuses a wrong digest with exit 1 before creating output. Discovery and
build agree on 270 control and 322 controller source paths. Those inputs are
retained by digest and rechecked after the controls, together with both built
binaries. Independent source review covered the admission, staging ownership,
argument compatibility and receipt runner.

The complete host bundle is
`/Users/alex/Library/Caches/vinix-codex/section14/wine-current-cli-host-20261026`;
its `bundle.sha256` SHA-256 is
`230dba1f6702bcd2b0a49cef2c7e90c5e42eb60af45b3d052f5e0a9c41fd57de`.
The adjacent `.tar.gz` SHA-256 is
`efa2286a74da6b49c3b856e9052e6cd612a0652f7c4cc6b881527c916635c765`.
Source baseline is `25b7aaff2` plus the final maintained source snapshots in
`run-03`; earlier compiler failures and the preceding passing control run are
preserved as diagnostic records. The host producer bootstrap and selected
compiler inputs are recorded, but their complete library/header/linker
closure is outside scope. No image or guest was produced by these controls.
Successful signed Wine execution with the selected CLI and the detached-server
lease interval still require native qualification.
