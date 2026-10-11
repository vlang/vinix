# Native filesystem power-cut tooling

Three Python runners are replaced with direct V commands:

```sh
tests/resource-accounting/run [--arch aarch64|amd64] [--retention-only]
tests/pagecache/run-guest [--arch aarch64|amd64]
tests/ext2-sparse/run [--arch aarch64|amd64] [--blocks 1024,4096]
```

All three also accept `--kernel DIR|ELF`, `--state-dir FRESH-DIR`,
`--prebuilt-init ELF` and `--build-only`. Default private workspaces retire on
success, interruption and failure; explicit fresh evidence remains available.
Existing directories are refused before their contents can be overwritten.
Kernel inputs retain `VINIX_KERNEL_DIR` on ARM and `VINIX_AMD64_KERNEL` on x86.
The commands snapshot an already-built kernel and never rebuild the checkout.
This replaces the older ARM launcher's implicit build/package-server path.
`VINIX_VM_RUNNER_ROOT` still selects the boot dependencies.

The unchanged accounting C guest keeps its exact strict static/pthread recipe
and retention-only define. Both maintained V fixtures use the native module
compiler with their original strict flags and static linker recipes. A supplied
ELF must match the requested architecture; permissions and timestamps follow
the original file-copy policy. Receipts record compiler arguments, fixture
source hashes, executable/kernel/archive hashes, RAM, deadline and launch
arguments. The 300-second environment budget, ARM 2,048 MiB and x86 1,024 MiB
settings remain. The native x86 paths also replace the two old calls to the
undefined `mapped.amd64_boot` entry.
Each guest uses its declared START/DONE prefix; the older imported report
policy had retained disk-no-sync's literal markers.

Every disk is a private, physically formatted sparse 64 MiB image. ARM mounts
it as ext2 `/root`, reusing the same file across restart epochs; x86 seeds a
bootable root with the exact ISO archive identity. The original 128-byte inode
size, ext2 feature masks and block sizes remain. Sparse disks start with
`large_file` disabled. Create, shrink and cleanup use one disk and one guest
image, with no reformat between phases. After create, debugfs must report the
original addressing capacity, the strict sparse block-count bound and the
persisted `large_file` feature. Every successful phase still requires
`e2fsck -f -n` to exit zero.

`guesthost/powercut.v` directly owns QEMU through a private PTY. Completion
matches the original byte regex: a word phase, an entire decimal inode number,
optional carriage returns and a newline. The first complete match determines
the phase; missing starts, wrong phases and declared failures still fail.
ARM checks the original last 8,192 bytes and prints after retirement; x86
streams raw bytes and requires a newline before stopping on a failure. Neither
path uses decoded replacement characters to decide the verdict. QEMU receives
SIGKILL before disk inspection. Monitor/QMP quit and graceful shutdown cannot
flush data before inspection. The writer is reaped and its descriptor closed
on every exit; SIGINT retires the writer and returns 130 from the command.

`check-filesystem.v CONTROLLER PROFILE CACHE` checks eight actual target
profiles, exact compiler/linker arguments, byte-identical recipe replays,
kernel snapshots, genuine disk geometry, initial e2fsck and x86 image identity.
`--owners CONTROLLER PROFILE CACHE` checks twelve failed private workspace
retirements and three existing-directory guards. `--fronts` cold-builds all
three public fronts outside the checkout. The units cover complete and partial
verdicts, wrong phases, failure precedence, large inode values, addressing
capacities and strict sparse bounds. `check-powercut.v` checks raw binary/large
PTY data, both capture policies, partial lines, deadlines, direct SIGKILL,
SIGINT and 60 FD/PID retirements per host.

Fresh ARM, Rosetta x86 and ARM ASan/UBSan hosts pass the builds, units,
workspace guards and supervisor checks. macOS uses `detect_leaks=0`; no
LeakSanitizer claim is made. Original C controls come directly from their
recorded Git revisions, with no Python interpreter involved.

Real ARM accounting retention passes with slab KiB unchanged at 2,256. Both
original C and maintained V read-ahead guests pass their original data/policy
assertions and disk checks. ARM sparse create/shrink/cleanup passes on both
1 KiB and 4 KiB disks, including persisted high sizes, sparse bounds and six
clean post-cut e2fsck checks. The final runs use the original 2 GiB ARM setting.

Prepared-kernel failures remain failures. Full ARM accounting passes every
guest assertion, including bounded scratch, but e2fsck reports stale block and
inode bitmap bits after the hard stop. The prepared x86 accounting retention
guest exceeds the unchanged 16 KiB allowance (904 to 1,000 KiB). Original C
and maintained V x86 read-ahead both fail at line 69 with the same zero
automatic read-ahead result. Both original C and maintained V x86 sparse first
1 KiB create boots time out within the unchanged 300-second budget; later
phases do not run.
No fixture assertion, disk check or deadline is relaxed, and no kernel source
was changed or rebuilt.

Evidence is retained under
`/Users/alex/.cache/vinix-python-zero-process-20261011`. Prepared kernel SHA-256
values remain ARM
`8866c72f19cba5f95ff22070e193b25cbe0cf57ae89e306067b16a82dba7289f`
and x86 `38fb88ad76e81bb26f9d84267678cf98cd0ccc0aae10573b9b83ddd5ca0b3f0a`.
The three originals total 19,639 bytes / 339 lines. Other Python callers still
use the older disk-no-sync and mapped-writeback import interfaces; those files
remain until their callers are ported. No source is hidden or language
classification changed.
