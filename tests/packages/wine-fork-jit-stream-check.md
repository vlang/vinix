# Supplemental translated fork stream diagnostic

This diagnostic separates the translator's emitted AArch64 instruction log by
process after one fork. It leaves the canonical 32-fork workload unchanged.
It does not qualify ARM, Wine, fork, shared JIT backing or a failure cause.
The existing translated ARM fork failure remains open.

## Logging contract

The contract follows the exact upstream QEMU 9.1.2 paths:

- Without `-D` or `-d tid`, the logger stores `stderr` as its global stream:
  [`util/log.c:319-327`](https://github.com/qemu/qemu/blob/v9.1.2/util/log.c#L319-L327).
  The earlier `dup(2)` path is for daemonized logging with a filename.
- A guest `dup2` calls host `dup2` before updating descriptor translation:
  [`linux-user/syscall.c:9242-9248`](https://github.com/qemu/qemu/blob/v9.1.2/linux-user/syscall.c#L9242-L9248).
- Log unlocking flushes the stream:
  [`util/log.c:129-138`](https://github.com/qemu/qemu/blob/v9.1.2/util/log.c#L129-L138).
- `QEMU_LOG_FILENAME` supplies `-D`:
  [`linux-user/main.c:475-476`](https://github.com/qemu/qemu/blob/v9.1.2/linux-user/main.c#L475-L476).
  The supervisor removes it, `QEMU_LOG`, `QEMU_STRACE` and `VINIX_ALLOW_WX`.
- `-d tid` caches a thread-local stream, and the fork hooks do not reset it:
  [`util/log.c:42-103`](https://github.com/qemu/qemu/blob/v9.1.2/util/log.c#L42-L103),
  [`linux-user/main.c:143-169`](https://github.com/qemu/qemu/blob/v9.1.2/linux-user/main.c#L143-L169).
  It is not used for fork attribution here.

These anchors explain upstream descriptor plumbing. They do not establish a
complete corresponding-source build for the existing patched Alpine binary.

The V probe preopens separate child and parent files before fork. Both branches
then select their descriptor arithmetically and enter the same prewarmed `dup2`
helper before role-specific work. Each writes a PID-bearing ready marker and
runs its own fixed arithmetic workload. The parent checks the child's status.
Code on the path to redirection can still be translated before attribution.

The native guest fixture is capture-only. It requires PID 1 and root, then the
supervisor drops real/effective/saved UID and GID to 1000, clears supplementary
groups, and executes `/qemu-x86_64 -B 0x100000000 -d out_asm` with the probe.
It emits one JSON capture record after cleanup. It does not print a workload
pass marker or install/build/stage a target image.

The supervisor bounds execution to ten seconds, limits each log to 256 KiB with
hard `RLIMIT_FSIZE`, and kills the entire process group even after early leader
failure. It admits logs only after reaping the leader and confirming group
disappearance. A size limit, timeout, missing marker or cleanup failure makes
the capture incomplete or unavailable; increasing limits requires review.

## Offline comparison and host controls

Build from the repository root with V, `-prod -gc none -manualfree`, and module
path `@vlib|.|@vmodules`. The maintained entry points are:

| Source | Purpose / arguments |
| --- | --- |
| `wine-fork-jit-stream-probe/main.v` | Native or future translated probe: `PARENT_LOG CHILD_LOG` |
| `wine-fork-jit-stream-controls.v` | `NATIVE_PROBE OFFLINE_CHECKER NEW_OUTPUT` |
| `wine-fork-jit-stream-check.v` | `PARENT_LOG CHILD_LOG NEW_REPORT`, or `--serial SERIAL_LOG NEW_REPORT` |
| `tools/packages/winejitstream/parse_test.v` | Compile as a test executable and run it |

The checker requires both exact ready markers, distinct positive PIDs, and
emitted instruction rows after each marker. Serial captures additionally need
confirmed cleanup, the ordinary identity marker, and a parent PID matching the
recorded leader. It hashes the inputs and preserves arithmetic flags and raw
wait status. Direct logs have unknown completion status. Existing reports are
refused.

Comparison counts overlapping RX virtual addresses and addresses with differing
observed instruction words, retaining at most eight address examples. Multiple
words at one address are retained. Neither matching nor differing observations
establish shared physical backing, simultaneous writes or the cause of a fault.

## Host-only evidence, 2026-10-26

Source base: `e23154560116456b3314c333c9cfdb4ba48080af`, plus the seven new V
files hashed in the observation receipt. External artifacts:

`/Users/alex/Library/Caches/vinix-codex/section14/wine-jit-stream-host-01`

- `observations.json` SHA-256:
  `542e4852eaadef6d0fdc19b58e3b898864b56f4fbed6269233afde828480f8b9`.
  It records post-run source/tool/artifact hashes, compiler flags/environment,
  and observed commands. This is not a reproducible-build proof.
- `results-02/results.json`: all twelve native/offline controls passed. They
  exercise branch PIDs, fd2 redirection, arithmetic, absent-instruction refusal,
  timeout cleanup of a forked descendant, the hard file-size limit, exec failure,
  existing-log preservation, valid direct/serial inputs, and four serial refusal
  cases (missing readiness, identical PIDs, unconfirmed cleanup, wrong leader).
- The nine parser test functions passed, including malformed PID/instruction
  input, readiness scoping, repeated addresses, deterministic comparison and
  exact byte-limit controls.
- Linux/arm64 V source checking of the guest fixture passed. It was not linked
  for the target. No target staging, full QEMU build or VM run occurred.
- Observed artifact bytes before the receipt: 1,349,600, below 20 MiB. Completed
  `/bin/df -k` readings exceeded 500 MiB before every compile/run. The controls
  use completed `df` readings because V's macOS `disk_usage` currently uses an
  incorrect block-size multiplier.

No target observation has been collected by this diagnostic. The next target
run needs separately reviewed input pins and resource bounds; it must preserve
the canonical workload result independently of these supplemental streams.

## Standalone ARM controller and host guard

The maintained controller is `wine-fork-jit-stream-native.v`. Build it with
`-prod -gc none -manualfree` and module path
`@vlib|.|tests/hardware-platform|@vmodules`. Its arguments are:

```text
ROOT PATCHED_TRANSLATOR KERNEL KERNEL_RECEIPT V ARM_SYSROOT ARM_GCC AMD_SYSROOT AMD_GCC NEW_OUTPUT
```

It builds only the small static ARM init fixture and x86-64 probe. The image
contains `/sbin/init`, `/qemu-x86_64`, `/fork-jit-stream-probe`, the scenario file
and empty mount directories. Existing `hwhost/boot.v:70` composes that initramfs;
`boot.v:97` sizes the FAT volume and `vm.v:110` selects the ARM machine. No full
Wine root, DLL set, full QEMU rebuild, network or GUI is needed. The canonical
32-fork probe and its earlier failure evidence remain independent.

The selected retained translator is the ARM static ELF at
`build/package-wine-translation-fork-qualified-1/extras/qemu-x86_64`, SHA-256
`93f1e83fbb7cedcfe2813f6b65775685a8dbc46943c1280ad3da650567985475`.
It is admitted by exact bytes, not by a claim of complete corresponding source.
The selected kernel candidate is:

```text
/Users/alex/.cache/vinix-linux-compat/altstackclone-20261026/states/kernel-first-arm-prod/kernel/bin/vinix
SHA256 98bfeb6bbfb247ef476e462cd89f055d7b9ec92c2452f5a550cdf277ef394999
candidate commit c6b5455ee837f44b843d03255294c8b610ad7635
```

Its preserved build receipt is
`section14/wine-arm-fork-reclamation-01/kernel-receipt.json`, SHA-256
`724884d18e429c89ba4f2ac3e25f8128109dc2db0c43c2e0db9d9240337a3500`
under `/Users/alex/Library/Caches/vinix-codex`. The controller requires a
successful ARM prod build receipt binding the exact kernel output bytes.

Before any separately authorized target run, selected source and tool paths
are inventoried: V and its libraries, Clang/resource directory, LLD, both musl
sysroots/GCC libraries, host QEMU, firmware, Limine, image tools and fixture
sources. Captured paths are rechecked before and after the VM. New directory
entries, the host SDK, transitive dynamic libraries and external tool behavior
are outside this binding. Exact selected environment and argv are retained.

The native resource plan is:

| Resource | Bound or budget |
| --- | --- |
| Each of four target compilation steps | 60 s plus at most 2 s group cleanup |
| Complete boot worker, including image tools | 90 s plus at most 2 s group cleanup |
| Inner `hwhost` VM timeout | 60 s |
| Trusted host child groups | Leader reaped and group disappearance confirmed after success, failure, cancellation or timeout; children must retain their inherited host group |
| Hard file ceiling inherited by worker | 128 MiB per file, core output disabled |
| Sampled thresholds, checked every 10 ms | State 256 MiB; ordinary logs 256 KiB; serial log 6 MiB; at most 512 state entries |
| Actual free space | Checked `statvfs.f_frsize * f_bavail`: at least 1100 MiB initially and immediately before the VM, 550 MiB before each child and once per second during it |
| Expected ordinary retained state | Approximately 160–180 MiB, including a 64 MiB FAT volume and a private 64 MiB UEFI variable file |

Sampled thresholds may overshoot; 256 MiB is an admission threshold, not a hard
aggregate disk ceiling. A worker can reach its larger per-file ceiling between
polls. The 1100 MiB admission reserve is intentionally larger than the expected
image state. Input hashing and host file operations outside a child guard do
not have a claimed whole-controller deadline. Capture completion still needs
the offline checker and both PID-ready streams before any RX comparison.

Host-only validation uses `wine-fork-jit-stream-native-host.v` with
`ROOT EXISTING_STATE V_COMPILER [PREVIOUS_STATE]`. It maintains source/tool and
executable hashes, argv, selected environment, completed actual `df -k`
readings and raw wait results. Its builds and unit executable have hard outer
group deadlines. Controls deliberately use cooperative cancellation: the
wrapper forwards INT/TERM/HUP to the controls leader and waits for its inner
fixture-group cleanup; a 60 s overrun requests cancellation and is recorded,
without a hard outer-deadline claim. A cancellation control signals the wrapper
after a descendant starts, verifies forwarding and disappearance of the nested
leader/group/descendant, and requires the sequence to stop before case four.

Host source base: `b9e739333ee5bc7c2d34db36ebd3c240adc4031b`, plus the five V
sources hashed in the receipt. Final external evidence is under
`/Users/alex/Library/Caches/vinix-codex/section14/wine-jit-stream-native-host-02`:

- `receipt.json` SHA-256:
  `8228bab632d856f26b3ddb76ac36f44ad84117abdfdfec17aa70263d981b293a`.
  It binds the maintained observer, selected source/tool paths, host outputs,
  environment, argv, completed `df` readings and raw results.
- Three host builds and all four unit functions passed. The native controls
  passed ten entries, including sixteen pre-cancelled guard repetitions with
  confirmed leader/group disappearance. Each build and the unit executable
  completed within its hard guard deadline with confirmed cleanup.
- The cooperative cancellation control signalled the wrapper after the third
  case's descendant marker, forwarded SIGTERM to the controls leader and
  observed raw controls status 256 (exit 1). The interrupted fixture retained
  raw status 9, reason `native guard interrupted` and confirmed cleanup. The
  nested leader/group/descendant were absent, and case four did not start.
  The normal wrapper completed in 841 ms and cancellation in 57 ms, with no
  60 s overrun. This does not establish a hard cooperative-wrapper deadline.
- Combined current and preserved `wine-jit-stream-native-host-01` state was
  4,891,551 bytes after the small V summary helper, including failures and
  compiler scratch. The maintained runner reserved final receipt bytes before
  writing and rechecked the combined 20 MiB budget afterward. All recorded
  build/run `df -k` readings exceeded 550 MiB; the final receipt recorded
  15,737,800 KiB available. These are observations, not reserved disk space.

The first host attempt is preserved in `wine-jit-stream-native-host-01`: the
guard refused a compiler-created scratch symlink, killed/reaped the compiler
and retained raw status 9. Qualification then isolated compiler scratch from
the guarded operation-log directory and counted the complete host state
without following links before/after each step; link refusal in the maintained
guard remains enforced. That directory also retains an earlier nine-control
run; the `host-02` receipt qualifies the source bytes at that stage. The input
inventory change below has a separate receipt.

No target compilation, staging, image creation or VM run is included in this
source and host-controls change. The translated ARM fork failure remains open.

## Compiler directory-link preflight refusal

The first authorized standalone launch used controller SHA-256
`d0de81c794776d80d74bf214c9ae4cf7f149577707ef5bb1368e0b7b0e4a3fb9`
from source commit `e5aab57def36deaee945eb396346697c1e8d78d6`. All five selected
controller/translator/kernel/receipt/V pins matched before launch, and completed
`df -k` reported 45,257,236 KiB available. Input inventory then exited 1 with:

```text
unsupported input entry: /Users/alex/code/v/thirdparty/tcc/tcc
```

That entry is a directory symlink to `/Users/alex/code/v/thirdparty/tcc`, its
own parent. Refusal happened before output-directory creation, target builds
or any VM child. The external posthoc tool-trace transcription is
`section14/wine-jit-stream-native-arm-01.launch-refusal.json`, SHA-256
`53052e3ed96d98fc51014baab4af757bc21c7b4a432f955ec99966edf80925be`.
It preserves argv, explicit environment overrides/unset, observed raw output,
exit code and input pins; it explicitly does not reconstruct the uncaptured
inherited environment. There is no serial or offline-parser target result.

`tools/packages/winejitstream/native_inputs.v` now binds each input's kind,
literal link and canonical path. File bytes remain hashed. A directory link
is recorded without traversal only if its canonical target is inside the
same explicitly walked tree; ordinary traversal covers the target's files.
This admits the finite TCC self-cycle, rejects escaping directory links,
dangling links and special entries, and rechecks kinds, links, paths and
covered file bytes.
The output-state guard's link refusal is unchanged.

Source base is `e5aab57def36deaee945eb396346697c1e8d78d6`, with these V hashes:

- `wine-fork-jit-stream-native.v`:
  `0764644fed666ebefdff2526f0becdd291119ad7457d2fa4e45b48e2743db1a9`.
- `native_inputs.v`:
  `c120a301f8688156a3edf5c63995a210276a67109f644fd96ade509fbb5b6fda`.
- `native_guard_test.v`:
  `30f7aea5c859d3b45fae05a3f8154b226431097386a36d92c14d5a032948aaca`.

Host-only evidence is in `section14/wine-jit-stream-native-host-03` under the
same external cache root. Its `receipt.json` SHA-256 is
`0b1fb961fcb6491ab08fa263ec9dd7bae6e89ddf011e14842bc6b8d63d7509c1`.
The unchanged maintained observer's executable/source pins are retained in
that receipt; it inventories the complete diagnostic module before and after
the run. Those two inventories were identical. Three host builds and all eight
unit functions passed, including four new functions covering internal cycles,
covered byte mutation, literal retargeting, sibling-prefix escapes, uncovered
directory-link admission, dangling links, FIFO refusal and file-link type
replacement. The new controller executable SHA-256 is
`3694fc5d84bb676c712b0e47f9bb92d21673bd6298f59b2d36763445b4947799`.

The ten guard-control entries passed again, including sixteen pre-cancelled
repetitions. Normal cooperative controls completed in 940 ms; injected SIGTERM
cancellation completed in 65 ms with raw controls status 256. Its interrupted
fixture retained raw status 9, `native guard interrupted`, and cleanup confirmed
in 24 ms. Case four did not start; the nested leader/group/descendant were
absent. All hard build/unit guards completed successfully with confirmed
cleanup. Combined
`host-01`, `host-02`, `host-03` and refusal-receipt state was 6,260,180 bytes,
including failure and compiler scratch. Recorded build/run free-space checks
exceeded 550 MiB. This followup contains no target build, image or VM result;
the translated ARM fork failure remains open.

## Standalone input-inventory refusal with private compiler

A second authorized launch used the unchanged `host-03` controller from source
commit `682f6fbe796bd8e82f567b059b07498429d1dcd1`. The shared V executable had
changed, so this launch selected the existing copied compiler at
`build/package-https-runtime-work/toolchain/v`, SHA-256
`ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`,
beside its `vlib` and `thirdparty` trees. This is a selected binary binding,
not a compiler rebuild or exact binary/source provenance claim. `VFLAGS` and
`VINIX_HWTEST_TCG` were explicitly unset. The other selected controller,
translator, kernel and kernel-receipt hashes matched the earlier bindings;
completed `df -k` reported 47,009,988 KiB available before launch.

The controller exited 1 during input inventory with the exact output
`No such file or directory; code: 2`. The proposed `wine-jit-stream-native-arm-01`
output directory remained absent. No input inventory, target build, image,
child process group, VM, serial capture or offline comparison was produced.
The missing entry is not identified by this bare error. Subsequent read-only
inspection found dangling `usr/lib/libRusticlOpenCL.so` links in both selected
X11 sysroots, each naming absent `libRusticlOpenCL.so.1`; this does not prove
which entry first stopped inventory. Dangling-input refusal remains enforced.

The preserved external posthoc tool-trace transcription is
`section14/wine-jit-stream-native-arm-01.launch-02.json`, SHA-256
`c1002c7e5cf45cc904b689587192b6d719e025520e6ba94ff676a40631f9b525`.
It records exact argv, explicit environment changes, observed output/exit,
selected pins and before/after free-space readings. It explicitly does not
reconstruct the full inherited environment or claim a completed input binding.
The 3,481-byte receipt is the only new retained state from this attempt. The
translated ARM fork failure remains open.

## Contextual input refusal and host controls

The followup to `682f6fbe796bd8e82f567b059b07498429d1dcd1` adds operation,
literal path and underlying error to failed input open/read/lstat/readlink/stat
and directory-list operations. Admission rules are unchanged. Missing paths,
dangling links, special entries, uncovered directory links and changed captured
inputs still fail closed. The focused negative control checks the missing
add/root/open paths, deleted captured input and dangling target diagnostics;
it also checks that refused inputs are not admitted and retained ordinary
content is unchanged. Qualified source SHA-256 values are:

- `native_inputs.v`:
  `005bb652e8a893afe77caec23a5012286e287d51ddfab314da8f9ad2889a30ad`.
- `native_guard_test.v`:
  `857c768eb883ba4c9efb42c2a57f431327cbf97d8b94356e569a3ee6002baad5`.

Host-only evidence is retained in `section14/wine-jit-stream-native-host-05`
under the same external cache root. Its `receipt.json` SHA-256 is
`f76b3abc22ec0f4725fbd12245b967016a25a63f9771146c26e3e70d321bc16f`.
The unchanged maintained observer and selected private compiler are bound in
the receipt. It records explicit V caller-selection/no-fallback environment
fields; launch additionally unset `VFLAGS`. All three host builds completed
with raw status 0 and confirmed cleanup, in 48,795, 25,031 and 15,376 ms.
All nine unit functions passed in 542 ms. The controller executable SHA-256 is
`11afa70a12a21c34e58f30203319202e9cef13f2da88e96bb40a7c40f2d50f0a`.
Selected before/after inventories are identical. This selected-input host
observation does not freeze the host SDK or transitive libraries.

All ten normal guard-control entries passed, including sixteen pre-cancelled
process groups. Normal controls took 962 ms. Wrapper SIGTERM forwarding took
71 ms and retained raw status 256; its interrupted fixture took 34 ms with raw
status 9 and confirmed cleanup. The cancellation checker confirmed no later
case and no surviving nested leader, process group or descendant.

The preceding `wine-jit-stream-native-host-04` failure is preserved. Its raw
build status was 256 after 11,706 ms, with confirmed cleanup and no controller
output. Clang could not create an embedded-object temporary file because the
observer-selected private `TMPDIR` did not exist. The successful fresh
`host-05` invocation precreated that directory. The failed `steps.json` SHA-256
is `83aeed9c788ccd9869ca1337f1b630b8e8aa1a0681544a7a8f4c8d26cfed4bc5`;
its build-log SHA-256 is
`c27047a1908cc1222be87fcd9689d53f1c65b619ffaa7087b76b8f5730e9452f`.
Both states, their scratch and receipt add 1,374,667 bytes; all retained host
and launch-refusal state totals 7,638,328 bytes. Completed free-space checks
exceeded 550 MiB before every build/run; final available space was
37,768,404 KiB. No target build, staging, image or VM ran in this followup.
The canonical probe and translated ARM fork result are unchanged.

## Retained static C inputs and host qualification

The maintained static-input composer follows source revision
`a9f0dba16a317590e145fe05ed07d8f18feef75f`. It copies only ordinary C headers,
six fixed musl startup/library files and five fixed GCC runtime files from
`/opt/homebrew/Cellar/musl-cross/0.9.11/libexec` into the standard relative
layout at `section14/wine-jit-stream-native-inputs-01`. The root C++ header
branch is excluded. Missing files, links, special files, destination collisions,
source changes and unselected destination entries are refused. Sources are
inventoried before copying and checked again after complete destination
readback and after both driver queries. The shared source installation and
its dangling links remain unchanged. These checks assume stopped trusted
inputs; they do not provide a hostile ancestor-rename sandbox.

The final four source SHA-256 values are:

- `tools/packages/winejitstream/static_inputs.v`:
  `a9d2d2275e98ca8c8fad244681866bccd90a252a194a5db858fdab97f0ae95e0`.
- `tools/packages/winejitstream/static_inputs_test.v`:
  `8abc7dc56d7b2b83707de9490d12960a3248a3a666dfcde1567a786eec2ca1e4`.
- `tests/packages/wine-fork-jit-stream-inputs.v`:
  `0a6ce4ea204f4cc840fe0830b6a6ae530b1823b8cf7571d3fbf63affbfe5e9eb`.
- `tests/packages/wine-fork-jit-stream-inputs-host.v`:
  `a943d758a96279a5c9a60a77ef955e55e55328535444b0ea4937798e02507ee8`.

Evidence is retained outside Git under
`/Users/alex/Library/Caches/vinix-codex/section14/`, in
`wine-jit-stream-static-inputs-host-01` through `host-05`. Final qualification
is in `wine-jit-stream-static-inputs-host-05`; `host-receipt.json` has SHA-256
`d413d0281bb44205e70b636acf27643415b515f759b7e48d8151d70dec7953f2`.
It binds the selected private V binary `ff75a301...` described above, its full
selected adjacent compiler library trees and the maintained source paths.
The 3,741-entry sorted binding digest was unchanged before/after:
`c555e8339260d5babac7079afe6b4fe2160702cd26176e388256b5a2109a0471`.
Explicit caller-selection/no-fallback markers, cleared caller overrides,
compiler argv and private scratch paths are recorded. The first small host
observer build was an observed bootstrap outside its own guard; the final
bootstrap exited 0 in 23.42 seconds. Subsequent three builds used hard
60-second process-group guards and all exited 0 with confirmed cleanup.
The final composer executable SHA-256 is
`e85d063d9653786ee608b008e75cc71bd1409985f1b688e787e8303bbcf55b6e`.

All eight unit functions passed in both normal and production builds, in
1,759 and 2,376 ms. Checks use explicit `if`/`panic`, with filesystem side
effects evaluated separately. The same executables' intentional-failure
sentinels each retained raw wait status 256 and the exact expected diagnostic,
in 85 and 106 ms. Coverage includes ordinary copy/readback, link/special and
missing-input refusal, changed sources/outputs, collision/overlap, budget and
receipt bounds, and split/joined compiler search-path escape refusal. Every
guarded build/run confirmed process-group cleanup.

The admitted 32 MiB inclusive limit covers all selected prior retained failure,
receipt and compiler-scratch state, plus a 2 MiB reserve. Projection includes
both plan/compose-before envelopes, complete source/readback inventories,
the exact environment and bounded final receipt before admission; actual
encoded lengths and cumulative state are rechecked before copying, before
driver queries and after the final receipt. Host-05 planned 28,601,132 bytes
including reserve. The final copy retained 1,113 files totaling 9,915,649
bytes. Whole composition exited 0 in 5.36 seconds. Final inclusive logical
state was 26,509,811 bytes; with the reserve it was 28,606,963 bytes, below
33,554,432. Completed free-space checks exceeded 2 GiB before builds/runs;
the enforced floor was 1 GiB. Final available space was 8,415,928 KiB.

Both guarded Clang queries, `-###` and `-print-search-dirs`, exited 0 with
confirmed cleanup in 64 and 38 ms. Their recorded argv uses the retained
sysroot and GCC-relative layout, explicit resource/linker paths and
`--no-default-config`; ambient search/configuration variables are cleared and
recorded. The recipe selected retained C headers, library directories and
all five startup objects. Its selected external include directory was the
pinned Clang resource include tree. Original cross-installation paths and
existing search paths outside these roots are refused. The selected Clang,
linker and resource tree are bound before/after. This observes dry-run path
selection; it does not compile or link, freeze the host SDK/transitive host
libraries, or establish exact private-compiler source provenance.

Final host-05 evidence SHA-256 values are:

- `composition.json`:
  `f9ede94dcfa974b992d5768ce93e9c1b16d2e607d363dac3cd7d524929665450`.
- `drivers.json`:
  `2c187985a65cdafb11a73c194b7d19183cf49527714c59946619c5ad3eea4372`.
- `output-readback.json` and `source-after.json`:
  `9a28c8bd5edd84abda9c71443e2800a2beb9685f68db6274c1232b9dbcb9929a`.

Earlier failed controls and refusals are preserved. Host-01/02 unit attempts
are unqualified: filesystem cleanup failed, including an `assert` side effect
omitted by production compilation. Host-03 passed the then-seven explicit
normal/production controls and refused the original 20 MiB budget. Host-04
passed those controls but refused before destination creation when its
compose-before receipt exceeded the 24 MiB cumulative limit by 32,490 bytes;
this led to the final advance receipt projection. Its initial bootstrap's
mistyped posthoc elapsed field is preserved separately as
`bootstrap.log.incorrect-elapsed.json`; the corrected receipt records 10.06
seconds from unchanged raw timing output. No earlier evidence was removed.
This followup ran no target build, staging, image or VM. The canonical probe
and translated ARM fork result remain unchanged.

## Standalone compiler policy and host controls

Following source revision `7bd0390a20ff979ae9a198c88f949c8a6f1e8d38`, the
standalone controller now preserves Clang warnings, passes
`--no-default-config`, and clears and records 18 inherited compiler, search,
configuration and test-selection variables. This includes `CFLAGS`, `LDFLAGS`,
`VTEST_ONLY_FN` and `V3CACHE`. V invocations use `-nocache`; both `TMPDIR` and
`VTMP` select retained private scratch. Initial and pre-VM free-space admission
is 2 GiB, with a 1 GiB floor for guarded children. The existing 60-second
compile guards, 90-second VM-worker guard, 60-second inner VM limit,
128 MiB file limit and sampled 256 MiB state/256 KiB log/6 MiB serial limits
remain. Inventory, parent copies and final receipts are outside a whole-run
hard deadline; sampled thresholds can overshoot. No warning-suppression
option is added by the maintained target Clang argument builder.

The four implementation/control source SHA-256 values are:

- `tests/packages/wine-fork-jit-stream-native.v`:
  `f376189ee03517d5bdc0b39a4a8276ced57906b18427536326e89808cdd2760b`.
- `tools/packages/winejitstream/native_policy.v`:
  `9588d9a91b8bcb5ab276d261e2a9ccd3d7b9b3f59073df12996d595164f8daae`.
- `tools/packages/winejitstream/native_policy_test.v`:
  `bb90e8f9652cfa20721718a351702a4fafc0b047418ca4a33f2356a4bd069b0c`.
- `tests/packages/wine-fork-jit-stream-native-host.v`:
  `5f8bca9522adc1eb440c6c7153ce0f6213c6b09bc53b1c526fad8920f5540bc7`.

Host-only evidence is retained at
`/Users/alex/Library/Caches/vinix-codex/section14/wine-jit-stream-native-host-07`.
`policy-receipt.json` SHA-256 is
`dd2a164e558421234b3ee74920a49e82e6d5fe1e4d153e2f2f713f2056434849`;
`steps.json` is
`42431dc0928ea5a229e89b6c1d8836a5b30590bb92126322a82f36e98560631f`.
The selected private V binary remains `ff75a301...` described above. Full
selected private compiler libraries and maintained source trees were
re-enumerated and hashed before/after: all 3,770 entries matched binding
digest `fa69dda5c8c5047b3540a37062506986e1c97d6a0710caa166e99d76a980319c`.
The observer also refuses a changed embedded policy-helper source. This binds
selected binary/library bytes; it does not establish exact compiler source
provenance or freeze the host SDK, dynamic libraries or ambient module search.
Before a target run, a private empty `VMODULES` directory must be selected,
charged and inventoried rather than relying on the default home module path.

The final observed bootstrap used `-nocache`, exited 0 in 6.12 seconds and
retained empty compiler output. It was outside its own guard, observed with a
300-second stop policy. `host-02` SHA-256 is
`304ce4e15f51479c2666f0ce9a447ecc8cbb453f7e462d748f8694d613b7d564`;
`bootstrap-02.json` is
`6b0b3f38043e4c584213cbe5df4814c2e89e41a5ca68346b578f33340da24135`.
The earlier host-07 bootstrap and its receipt remain beside it. Three
subsequent builds used hard 60-second process-group guards and exited 0 in
9,303, 1,079 and 1,777 ms with confirmed cleanup. The host-built controller
SHA-256 is
`bf1a920e392f43176876562757dd71478686fee94f117b1b3739d6eb25d5bb44`.

All five explicit `if`/`panic` unit functions passed in normal and production
builds, in 263 and 242 ms. They verify both target architectures' exact
warning-preserving argv, unsupported targets and every invalid path position,
all 18 independently enumerated inherited environment keys and exact presence
restoration, and the shared admission/output limits. Both intentional-failure
sentinels retained raw wait status 256 and the expected diagnostic, in 15 ms
each. Every guarded build/run confirmed process-group cleanup. No target
controller was invoked.

The separate host-policy profile allows 64 MiB inclusive logical retained
state, counts all selected earlier native/static host attempts, both ARM
launch refusals, the immutable composition, host-06 and host-07, and retains
a 2 MiB reserve. Its exact no-follow count after the final 7,794-byte receipt
was 58,415,543 bytes including reserve, below 67,108,864. Host-07 remained
below its separate 20 MiB bound. This profile does not change the static
composer's 32 MiB contract. Completed free-space checks exceeded 2 GiB before
every build/run; final actual `df -k` available space was 5,861,228 KiB.

The preceding host-06 bootstrap is preserved without deletion. Its compiler
exited 0 in 13.50 seconds, but retained compiler-cache state made the subsequent
posthoc recorder exit 1 with `static composition would exceed cumulative
32 MiB`; no guarded qualification ran there. Its empty `bootstrap.log`, raw
`bootstrap.time`, binary and scratch remain at
`section14/wine-jit-stream-native-host-06`. The binary SHA-256 is
`a1a60f9ad7f0dd231f815b2b1e627752c58285313737710e9525deb5e946c338`;
its then-observer source was
`4c1313f8cc2b581421ec23d66460e2c86a3ff589d0777619fc30a796755dc707`.
The first host-07 `-nocache` bootstrap exited 0 in 7.49 seconds; the final
rebuild followed the test-filter/environment review. These are retained
attempts, not target qualifications. Project-local wait-status width repair
and strict target compilation remain separate work. No target build, staging,
image or VM ran in this policy followup; canonical results are unchanged.

## Local wait ABI and private module search

Following source revision `2477eb6eb687c81f7c167729851e88e236c86805`, the
supplemental probe and its host/guest supervisors declare POSIX `waitpid`
with explicit `i32` arguments, return value and status storage. The shared
`raw_waitpid` path casts PID/options at the C boundary; leader and descendant
status stays four bytes through polling and cleanup. Only public result
fields widen status to V `int`. The older maintained host observer receives
the same local declaration/storage correction. This change does not modify
the shared `hwhost` implementation or the canonical 32-fork probe.

The standalone controller creates and records a private empty `VMODULES`
directory under its charged state. It refuses noncanonical paths, symlinks,
files, missing or nonempty roots and module path lists. Selection and empty
contents are checked before and after each guarded child and before the
final receipt. This replaces reliance on an inherited or default home
module directory. The controls use explicit `if`/`panic` checks so production
compilation cannot remove their assertions or cleanup side effects.

The fixed-scope `wine-fork-jit-stream-width-host.v` observer permits only
host controls, a host controller build and strict relocatable C objects. It
cannot invoke the target controller. All retained host-08 through host-16 attempts
share a 32 MiB allowance; the selected prior evidence plus these attempts
and a 2 MiB reserve must remain below the separate 128 MiB host profile.
It preserves failures, records raw guarded results before checking success,
and admits the final receipt using its actual encoded length. The static
composer's 32 MiB contract remains unchanged.

The earlier 7 MiB width allowance could not accommodate preserved host-08
and host-09 failures plus the complete host-10 C/object checks. Before any
host-10 execution, its fixed profile was raised to 16 MiB and the separate
128 MiB host profile. Preserved attempts through host-12 totaled 12,722,831
bytes; a 4 MiB host-13 projection exceeded the remaining 16 MiB allowance.
Before host-13, the collective allowance was raised to 24 MiB. Each guarded
child retains its 16 MiB file/subtree bounds, 256 KiB sampled log threshold
and 60-second timeout, with 2 GiB admission and a 1 GiB free-space floor. The
retained attempts remain charged; the historical 64 MiB policy qualification
and the static composer's limit are unchanged. The new width profile's
maximum charged prior bytes, 32 MiB attempts and 2 MiB reserve sum to
91,969,975 bytes, below its 134,217,728-byte ceiling.

The strict object controls retain `-Werror=incompatible-pointer-types` and
never use `-w`. Only `-Wno-pointer-sign` suppresses the generated V string
literal `char *`/`u8 *` flood. The qualified overlay's unrelated rune table
initializes `i32 *` from `const i32 *`; the exact
`-Wno-error=incompatible-pointer-types-discards-qualifiers` exception keeps
that diagnostic visible as a warning. A negative control changes only the
actual generated `capture` body's unique status declaration from `i32` to
`i64` and compiles under identical flags. It must retain raw status 256, the
hard incompatible `i64 *`/`i32 *` error, and no object output. These flags are
local to this object fixture; the standalone target link policy is unchanged.

The live guard now tolerates only `ENOENT` for a vanished child entry or
nested directory between enumeration and inspection. A missing selected root,
`ENOTDIR`, other errors, links and unsupported file types remain refusals.
Vanished entries still consume the 512-entry budget. A deterministic sixth
control covers those exact paths and retained-file byte accounting.

All preceding attempts remain intact. Host-08's controller log contains
the old shared `hwhost` `i64 *` wait-status error; its guard also observed
`ENOENT` and retained raw status 9. Host-09 refused an incorrect generated
symbol prefix; host-10 refused a checker body match that selected an earlier
call site. Host-11 retained raw status 9 when the signed-char warning flood
crossed its 256 KiB sampled log threshold. Host-12 retained raw status 256
for the rune-table qualifier error. Host-13 retained raw status 9 after a
compiler temporary disappeared during scanning (`No such file or directory`),
despite its controller binary and empty compiler log being present. This
last refusal motivated the narrow scan repair and deterministic control.

Host-14 passed all six controls in normal and production builds, both sentinel
failures, the host controller build and the strict ARM relocatable object.
Its actual-capture `i64` mutation failed with raw status 256 and no object,
but the observer required `[-Werror,-Wincompatible-pointer-types]` instead of
Clang's actual `[-Wincompatible-pointer-types]` suffix. The corrected anchor
still requires the hard `error:` diagnostic, exact incompatible pointer types,
raw status 256 and absent object under identical flags. All host-08 through
host-14 state totaled 19,709,648 bytes before the fresh host-15 attempt; its
4 MiB projection fit the unchanged 24 MiB allowance.

Host-15 also passed the ARM wrong-width refusal, then refused an assumed
`void main__main` symbol. The qualified compiler instead places the probe
inside `int main(int argc, char** argv)`; retained generated C has the exact
`i32` storage and raw `waitpid` call. The corrected anchor checks that actual
entry signature. All host-08 through host-15 state totaled 23,684,897 bytes;
the fresh host-16 4.5 MiB projection required raising only the collective
attempt allowance to 32 MiB. The inclusive 128 MiB and per-child limits stay
unchanged. No prior attempt is removed or recast as a pass.

Fresh `section14/wine-jit-stream-native-host-16` passed with the qualified
compiler at `/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain/v`
(SHA-256 `ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`).
The external bootstrap exited 0 in 16.19 seconds and its posthoc recorder
exited 0. The maintained observer then exited 0. All six explicit controls
passed in normal and production builds: adjacent four-byte status canaries,
pending `WNOHANG` sentinel preservation, exact exit/signal statuses 9472/9,
already-reaped `ECHILD`, real supervisor zero-status replacement and cleanup,
private module refusals and deterministic vanished-entry scan behavior.
Both intentional-failure sentinels retained raw status 256. All guarded
children confirmed cleanup, with no timeout or size-limit result.

The controller build took 36,521 ms, normal/production control runs 336/899 ms,
ARM shared-unit object compilation 2,974 ms and AMD probe object compilation
819 ms. Both positive objects have ELF64 little-endian `ET_REL` headers and
the matching machine IDs 183/62. The actual ARM capture mutation retained
raw status 256, the required hard incompatible-pointer errors and no object
in 491 ms. No target executable was linked or run.

The 7,258 selected bindings were equal before and after qualification, digest
`b030e72f7157983cbf59a36a95ae83065fd4237366d95c695d7751aaf5345be6`.
The complete qualified compiler-root inventory matched before and after.
`width-receipt.json` SHA-256 is
`5042ad2aa5d233292af086256c167e5f31c4322dc913fe826294cf090e5547c9`;
`bootstrap.json` is
`502e93e6684127c41864b0455f3ef6673eb8c58f240e6ba0530e95ff17f21afa`.
The host controller SHA-256 is
`ad4b3a2c0cdc3f71906459143670702d7443f5258cab5c0c2291d1a77016e525`.
Its shared host dependency was the exact `hwhost/process.v` from main revision
`8f7d7ccca1097a94b5f38e4c8713f493b014c675`, SHA-256
`1cefdf1ce196bbe4f05813969107144dd2c123662c56815124da56c92dc5e5d5`;
that previously committed dependency is excluded from this Wine change.

All complete attempt bundles remain under
`/Users/alex/Library/Caches/vinix-codex/section14/wine-jit-stream-native-host-08`
through `wine-jit-stream-native-host-16`. Their complete inventories and
checksums are in `wine-jit-stream-native-width-seal-01/08` through `/16` under
the same cache root; all nine full inventory rechecks passed. Host-16's
inventory SHA-256 is
`39ea33238ea141f3c21e810aa3fcea783ff9c57813ee7af84e519a251fd5c0f8`.
The metadata bundle's complete inventory is in
`wine-jit-stream-native-width-seal-01-complete/inventory.json`, SHA-256
`b156b6870ab0072c94388a46ee0f978ca8a6f0bd0caf773b0cea48f96f532aca`.
Final no-follow attempt bytes were 27,828,945; prior evidence plus attempts
and the 2 MiB reserve were 86,244,488 bytes. Metadata and its complete seal
used 331,727 bytes within that reserve. Recorded child admission readings
exceeded 2 GiB; final actual `df -k` showed 55,608,168 KiB available.

These are host and relocatable-object checks. Bootstrap and before/after
inventories sit outside each child's 60-second guard. Namespace/log limits
are sampled, rather than filesystem quotas; trusted tools must not detach
or write elsewhere. Host SDK and transitive dynamic dependencies are not
frozen. No staging, image or VM ran, and the translated ARM fork failure
remains open. Source base is the revision above with these changed V bytes:

```text
ffba1cb35c74b11d035661dd7e66108dea5bee7200195ca57a11508191cd5290  tools/packages/winejitstream/supervisor.v
22d86f7348caa05bd14211b57845b885df3d5a94a68d21da9f9fab2aee3a1110  tools/packages/winejitstream/native_guard.v
15851702a1c2b0ffc6baa393bf1fb52563a4faff210e1e28ffd593f9d21ec581  tools/packages/winejitstream/native_policy.v
83847d4794eb4ff281ab4463a2f08bd4265c7bd0902669829f52d5cf48cee9c6  tests/packages/wine-fork-jit-stream-native.v
8a38f3691df4c38b922435b8304e8c737ce097dd532c256c5a2e638e3d8f3815  tests/packages/wine-fork-jit-stream-native-host.v
72213ec18bec6a6935fee7cccbdbee30ef5e550abe7771f0ad470c238b54b0ab  tests/packages/wine-fork-jit-stream-probe/main.v
57665ad238efda0166fa0a00fb2c861b4988a82ba7bd94ac665ec6fe10777e01  tools/packages/winejitstream/native_wait_test.v
a09498d71da51f11d3beee34992a601767b5d5b5b51d41fa7e1a1a4246a618be  tests/packages/wine-fork-jit-stream-width-host.v
```

## Standalone caller marker followup

After `4ebaeda2220327bf512f50a0cb0b2c57dfc61cfd`, source review found that
the controller itself selected `V_MACOS_V3_NO_FALLBACK=1` but recorded its
caller value as absent. The qualified overlay's `vlib/v/pref/pref.v`
restores delegated child environments from those caller markers, so absence
could remove the child prohibition. Direct compiler checks still observed
the actual value `1`; no fallback is established by this source defect.
The controller now selects both `V_MACOS_V3_CALLER_NO_FALLBACK` and
`V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT` as `1`, matching the host-16 observer.
The child compiler marker remains absent with its presence marker `0`.
Independent source review checked this narrow fix against the qualified
overlay. Host-16 and its complete evidence above remain unchanged.

The first followup in external `wine-jit-stream-native-host-17` timed out
the production controller build at 60,031 ms: raw wait status `9`,
`timed_out=true`, leader reaped and group absent. Its complete failed state
is preserved. Fresh `wine-jit-stream-native-host-18` used a reviewed
120-second bound and completed that one host production build in 62,529 ms,
raw wait status `0`, without timeout or size limit. Its external bootstrap
completed with status `0` in 36,770 ms. The coherent caller environment,
private empty modules and all 7,258 selected static inputs matched before
and after; their binding digest was
`df06b7a1a5d8290684062a037e8c611473bc12ac39684be3a7840e03e6bebfe4`.
The rebuilt controller SHA-256 is
`d7239ec811f723c1c93d82871f618e40af3154605584948d372cbc631b1ca820`;
its source SHA-256 is
`73d2faeed2d0184c6d237d37048b490e5dfa9c2c1a9c75bb33e9c8d1f6fe48d1`.
No controller execution, target compilation, staging or VM ran.

Under `/Users/alex/Library/Caches/vinix-codex/section14`, the original
complete checker passed both retained states. The manifests are
`wine-jit-stream-native-caller-seal-01/17/complete/inventory.json`
(`095e76d14c08e5a0714d5cba00a9e2bbe8b1d2fbeb854a5b6391d02164297337`)
and `wine-jit-stream-native-caller-seal-01/18/complete/inventory.json`
(`f65f6db35abfdcc833cf4e9fb74c6c173708327a663edd68f6b1b1003a44893e`).
Host-08 through host-18 and both width/caller seals total 34,483,736 logical
bytes within the collective 40 MiB cap; with the prior 56,318,391-byte
profile and 2 MiB reserve, the inclusive charge is 92,899,279 bytes within
128 MiB. Final actual `df -k` showed 37,701,152 KiB available. Bootstrap
and input inventories remain outside the guarded compiler child; host SDK
and transitive dynamic dependencies remain unfrozen. Prepared target
execution is still required.

The old fault kernel's private source revision
`c6b5455ee837f44b843d03255294c8b610ad7635` and matched build-05's baseline
`9acefa77bee69247c837e97987a2377536aa41cc` have identical signal, clone and
process source. Their complete kernel source diff changes only `elf/elf.v`,
`memory/aligned.v` and `memory/heap_selftest.v`. The later process-wide
one-shot handler, Linux action-flag and automatic alternate-stack disarming
changes on main are absent from that matched baseline. A retest using it
must preserve this distinction when interpreting the result.

## Matched kernel receipt adapter

The maintained production-only `wine-fork-jit-stream-kernel-bind.v` adapts
the actual matched build-05 ARM status and its original complete audit to
the standalone controller's receipt format. It pins the checker, manifest,
build status, qualification, baseline, production patch and kernel; verifies
the original complete audit; and retains equal full selected per-path input
maps before and after. It preserves the actual successful 207,711 ms build
and its `leader reaped; group absent` cleanup. It does not build a kernel.

From source base `a0cca255efd1246f85d7ea1b8c1c652a2172f0b2`, the external
bootstrap completed with actual status `0` in 37,700 ms, and the adapter
completed with actual status `0` in 76,430 ms. The checker was a leaf in
the adapter's inherited process group with a 300-second bound; subsequent
inventory found the adapter, checker and observed group absent. Adapter
source SHA-256 is
`e94d8580ab678a406e5560324919cca6bf44232c8b536a479c29f9d1592ce77d`;
the generated `kernel-binding.json` SHA-256 is
`cdee03dabbcd5af40f5e1b7dc0eed94994042fac48c37f23bd630b8edcdd80dd`.

Under the external section14 cache, both original complete seal checks
passed: `wine-jit-stream-native-kernel-bind-seal-01/bootstrap/complete/inventory.json`
SHA-256 `cc297e31f82899d4c40611921da69a29dadcd6987a85d089db11513e94b22801`,
and `wine-jit-stream-native-kernel-bind-seal-01/receipt/complete/inventory.json`
SHA-256 `438766088e9d82534dcd9b8e2943083f4f35477cdb24690f4f46aaf589dfe2ca`.
They preserve `wine-jit-stream-native-kernel-bind-host-01` and
`wine-jit-stream-native-kernel-bind-01`; the original complete matched
kernel audit remains mandatory. New retained state, including both seals,
is 464,048 bytes within the reviewed 8 MiB reserve. The Wine evidence
profile, prior retained states and 2 MiB reserve total 93,363,327 bytes
within 128 MiB. Final actual free space was 32,546,264 KiB. Bootstrap and
whole-adapter stop policies were externally observed; host SDK and
transitive dynamic dependencies remain unfrozen. No target program or VM
ran. The receipt names the unchanged-signal matched baseline, rather than
qualifying later main signal changes or any Wine workload.
