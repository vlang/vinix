# Foreground performance supervisor

`foreground-supervise.v` owns the maintained `run-x86 run STATE SHA256`
adapter. It requires a fresh prepared runtime with all six scenarios
(`ops,churn,cache,idle,apps,drag`), the foreground `mon:stdio` QEMU mux,
and an adapter executable matching the prepared input digest.

It also owns a fixed `run-x86 prepare` operation. Preparation profiles name
canonical `adapter`, `directory`, `base`, `kernel`, `desktop`, and fresh
`prepared_state` paths, with `adapter_sha256`, `kernel_sha256`,
`desktop_sha256`, `base_mode` (the complete lstat mode), and
`base_manifest_sha256` pins. They select absolute canonical `compiler`,
`qemu`, `firmware`, `cc`, `readelf`, `mkfs`, `xorriso`, `limine`, and `sdk`
paths, and the same `charged_roots`, `input_roots`, `charged_limit_kib`,
`timeout_seconds`, and `log_limit_bytes` fields. The preparation timeout is
120..1800 seconds. Both fresh output states must be covered by charged roots
and separate from each other and from every selected input tree.

`admit-prepare NEW-STATE PROFILE.json` records a read-only selected input
map for review, without scanning the base, staging a runtime or running a VM.
Copy its `admission.json` `inputs_sha256` value into the reviewed profile.
`prepare NEW-STATE PROFILE.json` requires that exact selected input map and
runs the adapter under the foreground process owner and live budget watcher.
The selected map excludes the profile file itself to avoid a digest fixed
point; the complete before/after map separately binds the profile bytes and
mode. Both operations record the fixed argv. Tool selection is typed, with
fixed environment variable names and private compiler caches, rather than
an arbitrary command or environment map.

The fixed workload is `new=DESKTOP --scenarios=ops,churn,cache,idle,apps,drag
--settle=3 --seconds=5 --rounds=1 --mem=3072 --timeout=2400`. Preparation
requires APFS clones. The adapter inventories the complete base before
creating the prepared destination, refuses a different approved manifest
digest, and reuses those bytes as `base-before.tsv`. This literal manifest
binds entry contents, modes, directories and link targets; it does not bind
inode numbers, ownership or timestamps. The base root mode is pinned
separately. Guest absolute links are never followed by the supervisor's
host input inventory. Existing adapter verification still inventories the
base and staged runtime after preparation. The owner checks the prepared
receipt's exact roots, ordered arguments, storage mode, input pins,
manifest digests and QEMU command before retaining `preparation.json`.
Preparation does not execute QEMU. Its reviewed prepared receipt can then
be used with the existing `run` profile below.

New x86 preparation also selects canonical `sysroot` and `gcc` directories and
an absolute `ld.lld` driver alias in `linker`. GCC may be outside the sysroot.
Both trees use one bounded literal inventory; guest links are never resolved
through host paths. The x86 adapter receives `VINIX_PERF_X86_SYSROOT`,
`VINIX_PERF_X86_GCC` and `VINIX_PERF_X86_LINKER`, with `CC_AMD64` selecting
Clang. The prepared receipt binds both paths and the retained
`sysroot-before.tsv`/`gcc-before.tsv` hashes. The adapter verifies their exact
current text; the owner requires unchanged before/after literal maps. Runtime
receipts declaring any closure field require all fields. Historical receipts
with every closure field empty retain their existing admission behavior.

The sourcecommand owner reserves the child leader with WNOWAIT, uses a
private process group, and performs the sole raw i32 waitpid reap. One
combined pipe preserves stdout/stderr ordering and enforces the output
limit before retaining each chunk. Refusal retains the accepted log prefix,
allows 30 seconds for TERM cleanup, then retires the group. Receipts require
group absence and ECHILD after retirement. A refusal records the child exit
status as unavailable rather than inventing it.

The adapter owns QEMU in a separate session. Success additionally requires
the adapter's zero-status receipt, its exact verified input map (allowing
only the runtime disk digest to change), and the exact guest completion
line. Failure does not prove cleanup of arbitrary escaped descendants.

The outer deadline must exceed the adapter deadline by 60 seconds and is
limited to two hours. While the child owner runs through cleanup, actual df,
allocated `du -skl` and apparent `du -skAl` observations are scheduled one second
from each actual sample start. A start gap or complete probe/journal window
over five seconds refuses qualification. Admission needs 2 GiB free, continued
execution needs 1 GiB, and declared nonoverlapping roots plus supervisor
state default to at most 512 MiB in either measure. Both du invocations count
each hard-link occurrence. One MiB is reserved inside the selected ceiling for
the next journal row and final receipts. An explicitly reviewed `charged_limit_kib`
may select a limit from 524288 to 4718592 KiB (4.5 GiB). The prepared runtime
must be covered by a charged root. These are sampled bounds, not a filesystem
quota. The retained phase12 baseline preparation used its approved 2 GiB
limit; each subsequent phase needs its own reviewed profile and inclusive
projection. Historical states outside its declared roots remain outside that phase's
inclusive total and must be reported separately.

The append-only `budgets.jsonl` retains actual starts, raw df/du output and
completed probe times. Each next row carries the previous sample's completion
after its checked journal write/close; `supervisor.json` supplies the final
sample's completion and maximum complete window/start gap. Rows are limited to
256 KiB and the journal to 32 MiB. Cap/floor refusals retain the measured raw
data before reporting failure; failed probe commands and malformed output
retain their errors. A successful child gets a final sample after group/child
cleanup, then a five-second final receipt guard. This timing scope covers the
owned child and cleanup. Preparation/run input inventories and later result
writing are separate operations and need their own observations if a caller
requires continuous supervision across that entire phase.

Build with a complete selected V installation and private temporary/module
directories; preserve coherent V, VEXE and caller compiler environment
markers. For example, from the checkout:

```sh
v -enable-globals -nocache -keepc -cc /absolute/clang \
  -path '@vlib|@vmodules|tools|tests/desktop-perf|tests/hardware-platform|tests/linuxkpi' \
  -o /external/foreground-supervise tests/desktop-perf/foreground-supervise.v
```

The profile is an explicit reviewed document:

```json
{
  "adapter": "/external/run-x86",
  "prepared_state": "/external/attempt/prepared",
  "prepared_sha256": "REVIEWED_SHA256",
  "directory": "/absolute/source-checkout",
  "timeout_seconds": 3660,
  "log_limit_bytes": 33554432,
  "charged_limit_kib": 524288,
  "charged_roots": ["/external/attempt", "/absolute/source-worktree"],
  "input_roots": ["/absolute/source-checkout/tests/desktop-perf", "/absolute/source-checkout/tools", "/external/complete-v-root"]
}
```

```sh
/external/foreground-supervise run /external/new-supervisor-state /external/profile.json
```

Input inventories bind modes, literal symlinks, resolved referents and file
digests before and after execution. The wrapper derives the adapter argv
from the validated profile. It does not execute an arbitrary profile command.
Keep the supervisor state outside all declared input trees.

`selfcheck NEW-STATE COMPLETE-V` exercises real spawn/reap behavior for
success, nonzero exit, timeout, output refusal, SIGTERM and a same-group
descendant that keeps the pipe open. It also checks ten prepared-profile and
completion-receipt cases without executing an adapter or QEMU. Each process
case checks the log bound and retirement; the nonzero case checks exact
stderr retention. The descendant case must time out because its inherited
pipe prevents EOF after the leader exits.
Eight additional preparation admission controls check the fixed argv and
fresh charged outputs, with six refusals; these use fixture documents and
paths and never execute an adapter.
Twenty-one observation controls check exact timing boundaries, backward clocks,
journal/row and dual-size boundaries, malformed du output, a 65 MiB sparse
file against a 64 MiB size helper and synthetic full-budget reserved-tail
refusal, actual one-second cadence with reconstructed completed
sample windows, and cleanup after a live journal failure. These do not run a VM.

`qualify NEW-STATE COMPLETE-V` rebuilds normal and production binaries and
runs all eighty-six controls on each. These comprise the forty-five historical
owner controls, sixteen x86 closure controls and twenty-five fixed audit
controls. It clears inherited tool selection,
uses private temp/module/cache directories and `-nocache`, selects the
inventoried absolute clang with an explicit SDKROOT, and charges the whole
qualification state throughout. It retains source copies, generated C,
binaries, argv, environments, logs, budgets and receipts. Its complete V
root and recorded host compiler/SDK metadata maps must stay unchanged.
The installed loader and SDK dependency closure are not claimed hermetic.

`qualify-adapter NEW-STATE COMPLETE-V` uses the same bounded compiler and
input-inventory policy to build maintained `run-x86.v` in normal and
production modes. Each build must pass its 37 selfcheck cases and
18 clone controls; their receipts and executable hashes are retained. This
mode does not stage a guest or run QEMU. The current x86 adapter must pass 37
selfchecks and 18 clone controls; the older 32-check result qualifies only its
historical source. `limitcheck NEW-STATE` checks actual
budget admission at the minimum, historical 2 GiB ceiling, its successor and
the 4.5 GiB ceiling, and refusal just outside the accepted range. These are
admission controls at actual low usage; they do not allocate to those limits.

Host qualification results and checksums are recorded in
`foreground-supervise-report.md`. No guest performance measurement is
implied by the host controls.

ARM preparation uses `arch: "aarch64"` and the separate `run-arm.v` adapter.
It retains a pinned base archive and a small ordered overlay instead of an
APFS clone. Additional typed fields are `firmware_vars`, `sysroot`, `gcc`,
`linker`, `mformat`, `mmd` and `mcopy`; `xorriso` is empty. The `linker` path
must name an absolute `ld.lld` driver alias: its literal link and canonical
referent are both inventoried because lld selects its driver from argv[0].
Other tools remain canonical. The whole selected guest sysroot is hashed
in place with literal symlinks, and excluded from the ordinary host-resolving
input roots. ARM admission scans the base archive and full sysroot before
creating its output. The approved base pin is the archive's SHA256; its
retained `base-before.tsv` separately binds the absolute path and lstat mode.

The ARM owner admits only the exact fixed QEMU command, including a read-only
PCI FAT boot disk, one MMIO ext2 workload disk, private firmware variables,
2048x1536 geometry and foreground serial monitor. Only `root.ext2` and
`vars.fd` may change during an ARM run. Preparation and run input maps bind
the complete selected sysroot before and after execution. The adapter also
compares its literal sysroot manifest. Preparation retains its final input
map or inventory error. A run failure attempts a final input map; if that
inventory also fails, the receipt has an empty map and does not retain the
inventory error text. An adapter drive error does not manufacture a
successful local completion receipt.

`armcheck NEW-STATE COMPLETE-V` adds sixteen document, fixed-argv, disk and
literal-sysroot controls without executing an adapter. `qualify-arm-owner`
builds normal and production owners and runs the eighty-six owner controls
plus these sixteen on each. `qualify-arm-adapter` builds normal
and production ARM adapters and runs their eighteen controls on each. Both
use the existing bounded qualifier; neither stages a guest nor runs QEMU.
Normal and production ARM owner and adapter controls passed in the separate
host-only qualification recorded in `foreground-supervise-report.md`.
Guest cross-compilation, preparation, boot and measurements remain pending.
See `run-arm.md` for the selected inputs and remaining validation.

## Fixed original audits

`audit frame|atomic NEW-STATE PROFILE.json` runs only the original full checker
against the retained fresh frame or atomic bundle. Checker, checker source,
bundle paths and complete manifest checksums are fixed in the maintained
source. An absent or changed complete original refuses admission. The profile
is canonical typed JSON with only `format` (1), `charged_limit_kib` and
`charged_roots`. The fresh state must be covered by its declared roots and
outside both repositories and fixed audit inputs. This mode never writes a
failure file into an existing caller directory.

The mode reuses the foreground owner with a 2 MiB combined child-log limit and
zero retirement grace. Its first sample starts from entry before admission and
pinning; successful postflight pin comparisons receive a final appended
sample. Actual start gaps, complete probe/journal windows and the final receipt
tail remain bounded to five seconds, and entry through final PASS to 300
seconds. Before/after receipts bind checker/source/manifest bytes and modes,
root identity, owner and profile. The original output must be exactly
`FRAME-PAGE COMPLETE STATE CHECK PASS` followed by a newline.

Qualification requires actual outer exit 0 and the exact final
`PERF ORIGINAL AUDIT PASS frame` or `PERF ORIGINAL AUDIT PASS atomic` line.
`audit.json` is provisional until the final time guards and stdout marker have
completed. A refused run retains its observed state and stderr; cleanup after
a refusal may exceed the deadline and remains refused. No arbitrary command,
replacement checker, alternate manifest or missing-evidence exception is
accepted.

After the child's `supervisor.json` is written, the audit mode appends one
post-pin sample to `budgets.jsonl`. The child receipt retains its count and
timing at cleanup. The extended journal's final count and completion are in
`audit.json`, which governs the complete phase together with actual outer 0
and the final stdout marker. The child receipt need not have the extended
journal's row count.
