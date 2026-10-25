# Native signal-action output-copy ordering

Vinix rt_sigaction commits a valid disposition update before copying the old
action to userspace. Output EFAULT leaves the update in place; input faults
and invalid sigset sizes preserve state and output. A stack fixed array
snapshots the old record before the update, including aliased input/output.
This follows rt_sigaction and do_sigaction in
[Linux v6.12 kernel/signal.c](https://github.com/torvalds/linux/blob/v6.12/kernel/signal.c).

Identical static musl ELF64 probes run as root and UID 1000/GID 2000. Three
signals, four starting/incoming records, six bad output pointer classes,
aligned/unaligned/aliased/null output, exact page boundaries and guard bytes
are covered. Input faults and invalid sizes preserve state/output; masks
strip SIGKILL/SIGSTOP. Dispositions use default/ignore handlers, zero or
SA_RESTART|SA_SIGINFO flags and zero restorers. No signals are delivered by
this fixture.

| Result on each architecture | Checks | Failures |
| --- | ---: | ---: |
| Linux 6.12.51 reference | 4,440 | 0 |
| Original Vinix production kernel | 4,440 | 432 |
| Corrected Vinix production kernel | 4,440 | 0 |

Native AArch64 uses 16 KiB pages. Native x86-64 and both Linux references use
4 KiB pages. Both production builds pass with unchanged before/after source
inventories. All thirteen maintained suites pass per architecture: sigactioncopy,
sigmaskcopy, altstackcopy, sigwaitorder, sigwaitcopy, sigpending, randomsignal,
clonesignal, cloneclear, seccomp, runtime, futex and jit.

The first x86-64 maintained attempt failed randomsignal interruption checks; two ordinary 8 MiB requests completed with a zero saved result in the handler. The second attempt failed futex with a truncated diagnostic. The third attempt and the first AArch64 attempt returned success. Their complete guest directories subsequently disappeared during concurrent work; only controller logs, commands and statuses survived. The cause of the deletion is unknown. No missing receipt is reconstructed. Fresh persistent runs retain complete artifacts for all thirteen suites on both architectures with unchanged fixtures and kernels. The intermittent failures remain unresolved; passing replays do not establish their cause.

The complete external audit passes. The bundle at
`/Users/alex/.cache/vinix-linux-compat/sigactioncopy-20261025/evidence-final`
retains 18117 files with zero omitted selected inputs. Its manifest
SHA-256 is `25c7e44005775f8798ca2e948ef0a807c50fafdf74819034016431680749743d`.
Historical complete bundles remain required by their original checkers.

The isolated candidate is `ffaff4f7f5c9be4e82c9d769f16431083e1a9b6c`, based on
`6cbe5ba3a455cb02c72cbc6224aa7e6b8af071d1`. Only signal.v changes, with SHA-256
`604a9e44a0b43544f3492ec25cda5794fa19832ed20a80b363199e898f760ab5`.

| Production kernel | SHA-256 |
| --- | --- |
| AArch64 | `984c50eec4244e7f26d549bd0a8c5e2b9dc54c24d023f0f42a17bf43fe07c52f` |
| x86-64 | `29f063aecf99e5a3ea4f96719da100ed92bfea5bcf71e8f2c4e35c61e7d5f8ee` |

Generated C review compares 395 AArch64 and 434 x86-64 userland, syscall-table
and timer bodies. Only syscall_rt_sigaction changes: its old-record stack
array moves outside the output condition and the copy follows the unchanged
process-wide update under the existing thread lock. No allocation, release
or new object lifetime is introduced. The exact comparison preserves all
other bodies, usercopy and mapping/exit functions. No measured allocation-leak
qualification is claimed.

The first private x86-64 fixture compilation failed during concurrent
temporary-directory creation. Its second compilation uses the same fixture
bytes as the first AArch64 compilation. Original, corrected and Linux runs
use the same ELF per architecture. A helper compilation initially used a
reserved identifier; the corrected helper passes. First control invocations
used invalid CLI arguments; corrected invocations pass. Diagnostic attempts
and frozen inputs are retained.

Compile checkers without `-prod` to preserve assertions:

```sh
v run tests/linux-compat/sigactioncopy-reference.v --self-test
v run tests/linux-compat/sigactioncopy-evidence.v self-test
v run tests/linux-compat/sigactioncopy-evidence.v check /Users/alex/.cache/vinix-linux-compat/sigactioncopy-20261025/evidence-final
```

The reference parser passes two positive and rejects nine negative controls.
The evidence checker passes five positive and rejects 23 negative controls.

Handler delivery, pending-signal flushing, arbitrary flags/restorers,
SIGKILL/SIGSTOP query semantics, invalid-signum versus input-fault precedence
and asynchronous races remain unqualified. GNU libc, translated/ELF32 paths
and installation, service, sandbox and portal acceptance remain separate
qualifications. Three broad section 15 gates remain open.
