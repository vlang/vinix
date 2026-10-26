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
