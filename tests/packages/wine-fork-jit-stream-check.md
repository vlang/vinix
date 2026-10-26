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
