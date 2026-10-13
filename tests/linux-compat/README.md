# Linux compatibility qualification

The maintained V controller snapshots a matching, already built ELF64 kernel
and each V fixture before compiling or booting. Both architectures use the
existing native guest supervisor and disposable images. Every requested marker
must pass; bad pointers, errno, compiler failure, panic, timeout and late failure
remain failures. Sources, init/ISO/kernel hashes, receipts and raw serial logs
stay in the required fresh artifact directory, including on failure.

Receipt audit sources use V assertions. Build them without `-prod`, which
removes assertions in the current V3 compiler. `-nocache -cflags -O2` retains
the checks while optimizing hashing. Confirm a deliberate failing assertion
exits nonzero before using a compiler for an audit. Application catalog
validation uses explicit errors and retains its checks in production builds.

```sh
tests/linux-compat/run --arch aarch64 --kernel-dir /path/to/arm/kernel --state-dir /path/to/fresh-arm
tests/linux-compat/run --arch x86_64 --kernel-dir /path/to/x86/kernel --state-dir /path/to/fresh-x86
```

`--cases bpf,access,open,mmap,runtime,namespace,sharedmem,seccomp,futex,futexkeys,futexbits,futexop,futexerror,futexqueue,sparsefork,seccompquery,budget,mapstorage,sysrq,jit,nnp,nnpthread,keepcaps,securebits,ambient,capbset,capset,cappid,capabi,seccompthread,seccompkill,seccompinstall,seccompalloc,sysnr,pipezero,readerror,pathio,iovpin,iovimport,iovrange,iovoffset,iovposition,iovflags,iovfd` selects the tests; `--timeout` sets each guest's
deadline. The kernel is never rebuilt implicitly. Build in separate worktrees
and supply the ARM musl sysroot through `VINIX_AARCH64_SYSROOT` when necessary.

- `bpf` verifies ENOSYS for unavailable program operations and untouched query
  buffers; loading or attaching a policy cannot return a dummy success.
- `access` checks empty paths, exact errors, execute permission, O_PATH/deleted
  files, pipes, real/effective UID differences and nonempty AT_EMPTY_PATH paths.
- `open` checks open_how size/extensions, flags, invalid pointers, O_PATH,
  link inode descriptors for regular, dangling and procfs links with
  O_PATH|O_NOFOLLOW, and EBADF on reads through those descriptors,
  mutually exclusive/unknown constraints, NO_SYMLINKS and NO_MAGICLINKS on
  intermediate/final/nested/procfs links and creation, and final link handles.
  Trailing slashes require directory resolution even with O_PATH|O_NOFOLLOW;
  failed O_CREAT requests cannot leave regular files behind.
  Exclusive creation returns EEXIST for existing final symlinks, including
  dangling targets and supported link constraints, without creating a target.
  Plain O_CREAT follows dangling final links, including relative chains, and
  verifies target contents/mode. Link restrictions and mount boundaries still
  apply, and failed requests leave no target.
  Plain open/openat ignore creation, truncation and access flags with O_PATH;
  data stays intact and descriptor flags remain correct. openat2 rejects them.
  NO_XDEV checks tmpfs and same-filesystem bind mounts, alias-relative opens,
  '..', absolute symlink targets, creation and procfs descriptor jumps.
  BENEATH, IN_ROOT, CACHED and combinations requesting them return EOPNOTSUPP;
  this does not qualify containment or cache-only lookup.
- `runtime` checks four concurrent pthreads, isolated libc errno/TLS and keys,
  64-bit atomic increments, SSE2/NEON across scheduling, auxv/sysconf page sizes
  and an actual RW-to-RX JIT function. It prints pointer width and page size.
  It also verifies file offsets past 8 GiB, normalized CLOCK_REALTIME and a
  nonblocking timerfd deadline 2^32 seconds into the future, including through
  the i386 libc's time64 wrappers.
  `--once` makes a staged runtime fixture exit after testing instead of waiting
  as PID 1. It is a native musl test until run through a foreign runtime.
- `mmap` checks that MAP_ANONYMOUS ignores every descriptor, including an
  invalid positive value and a zero-extended -1, and that file-backed mappings
  consume only the low signed C-int descriptor. Invalid file descriptors still
  return EBADF. The test writes anonymous pages and verifies mapped file data.
- Namespace feature discovery checks user/network/time requests through
  clone/clone3/unshare/setns and verifies EINVAL without identity changes,
  including mixed supported/unsupported flags. Writes to uid_map, gid_map and
  setgroups must return EPERM and retain the initial namespace's contents.
  This rejects identity-only or ignored-write success; it does not qualify
  those namespace kinds as implemented isolation.

The [coverage matrix](../../docs/linux-posix-compatibility.md) separates missing
interfaces from implemented behavior and lists unsupported dependencies.

The `iovpin` case checks 32 blocked readv and 24 multi-chunk writev calls per
architecture in root and UID/GID 1000 children. Another pthread closes the
descriptor or replaces it with a pipe, regular file or wrong-access handle;
all bytes must still use the original open description. Pipe readiness/queued
bytes verify that the call entered the original pipe before replacement, and
EOF verifies final writer-reference release. Two 200-cycle pipe/vector cohorts
exercise successful, empty, invalid-header, invalid-payload and wrong-access
returns, comparing every live slab class and big-page count after warmup.
Shared-offset atomicity, stream short reads and foreign
ABIs require separate qualification.

The `iovimport` case checks 40 readv and 40 multi-chunk writev calls per
architecture as root and UID/GID 1000, with readonly 2/8/9/513/1024-entry
header arrays. After the call has imported the headers, a peer changes a
later destination/source address or protects the header mapping with PROT_NONE.
All I/O must use the original addresses and complete lengths. A preopened
scratch-reservation observer establishes the read import checkpoint; queued
pipe bytes establish the write checkpoint. Both checks work on the unchanged
kernel too. Two 200-cycle cohorts check stack/heap import cleanup on valid,
empty, bad-header, bad-payload and invalid-range errors. This does not
qualify positioned vectors, Linux's MAX_RW_COUNT/range handling, shared-offset
atomicity, stream message behavior, memory exhaustion or foreign ABIs.

The `iovrange` case checks 215 native range/length/count cases in each root and
UID/GID 1000 child. Later invalid ranges must return EFAULT before changing
regular-file contents/offsets, pipe bytes or UNIX stream/datagram messages,
including invalid bases on zero-length entries. Later signed-invalid lengths
require EINVAL before earlier range errors. Fixed mmap probes measure the
active user limit and verify its last and next pages; the qualified QEMU runs
use 47-bit ARM and 56-bit x86 ranges. EOF boundary tests distinguish a single
segment's page-size MAX_RW_COUNT clamp before range validation from multiple
segments' original-range checks, including tails beyond the cap. In-range
PROT_NONE destinations still fail at copy time and retain a regular read's
completed prefix. Two 200-cycle error/count cohorts compare every live slab
class and big-page count after warmup. No 2 GiB payload is allocated or
transferred. Positioned vectors, tagged ARM pointers, four-level x86 runs,
shared-offset atomicity, stream message conformance and foreign ABIs remain
separate work. See the [qualification and receipts](../../docs/linux-posix-qualification.md#native-vector-ranges-and-transfer-counts).

The `iovoffset` case checks 348 native positioned-vector cases in each root and
UID/GID 1000 child. Raw preadv/pwritev/preadv2/pwritev2 calls vary pos_h while
preserving full pos_l at 4 GiB + 123, 8 GiB - 1 and 8 GiB + 17. Scalar I/O
verifies original sparse bytes, lower 32-bit aliases, file size/blocks and
unchanged explicit-I/O cursors; public musl wrappers are preservation controls.
Negative offsets require EINVAL before malformed headers/counts/descriptors.
Only v2 -1 uses and updates the current position, including nonblocking pipes.
Two 200-cycle valid/error/sentinel cohorts require flat slab and big-page
counts while reusing the sparse file. GNU wrappers, ELF32/translated paths,
positioned header/descriptor lifetime, other flags/errors, count limits and
shared-offset atomicity remain separate. See the [qualification and receipts](../../docs/linux-posix-qualification.md#native-positioned-vector-offsets).

The `iovposition` case checks 396 native positioned-vector cases in each root
and UID/GID 1000 child. Descriptor/access and pipe/socket seek errors precede
header faults/count errors, including empty vectors and v2's current-position
access refusals. All signed lengths and original ranges are checked before
I/O; failed imports retain data, cursors and pipe/socket queues. Read-only
2/8/9/513/1024-entry headers cover both storage paths. Whole-vector signed
offset overflow returns EINVAL before EOF or file-size-limit behavior. The
fixture bounds the unchanged write-overflow control with RLIMIT_FSIZE=1024.
In-range PROT_NONE payloads retain completed prefixes. Fourteen EOF boundary
checks per version cover MAX_RW_COUNT without allocating a 2 GiB payload.
Two 200-cycle cohorts require flat slab classes and big-page counts. Emitted
code verifies one descriptor lookup/import and scoped ownership; deterministic
positioned close/dup2/header races require separate qualification. Flags,
character devices, GNU wrappers, foreign ABIs, actual cap-sized transfers,
disk-backed vectors and shared-offset atomicity remain open. See the
[qualification and receipts](../../docs/linux-posix-qualification.md#native-positioned-vector-imports-and-errors).

The `procself` case checks 1,620 native raw/musl calls per architecture as
root/UID1000, with a main reader and two pthread readers in each forked child.
Three procfs mounts, directory-relative/pathname calls and inherited O_PATH
empty-path handles return the reading process's relative PID for `self` and
PID/task/TID for `thread-self`. One/three/full-byte copies preserve exact
prefixes, no terminating NUL and buffer canaries; null/inaccessible buffers
return EFAULT. Resolution selects the same inode/device/mode as an explicit
numeric path, with the correct Tgid. A root child resolves both links inside a
chroot containing `/view` but no `/proc`. Thirty-two warmups and 200 cycles of
120 target probes plus six status checks keep all live slab counts and large
pages flat. Failed pthread joins terminate the process before stack state or
shared descriptions can unwind. The independent `procfs-mount --case reuse`
suite checks PID-view numbering, inactive views and retargeted aliases.

Status controls now require the selected Pid/NSpid and process Tgid. A root
cohort also checks leader/worker IDs through inherited root-view and fresh
PID-namespace proc mounts, including exact two/one-column NSpid values. The
original wider assertions exposed this field bug; their failure artifacts remain
published. See [the task-status receipts](../../docs/linux-posix-qualification.md#selected-task-status-identities). The full procfs mount suite fails its unchanged 16 KiB
retention bound on both baseline and candidate; those failures remain visible.
See [the relative-link receipts and limits](../../docs/linux-posix-qualification.md#relative-procfs-self-and-thread-self-links).

Stat controls additionally check fields 1/18/40/41 (selected PID, effective
priority, real-time priority and policy) through both named and numeric paths.
Workers use musl pthread scheduling APIs with FIFO17/RR33; the namespace worker
uses FIFO23, while leader/process paths retain ordinary scheduling. Raw targeted
queries independently provide expected policies. The fixture requires the stock
musl process-level sched wrappers to retain their actual ENOSYS refusal. There
are 84 initial stat reads per architecture and 12 more per retention cycle.
Both baselines fail 28 worker records; both candidates pass all fields with flat
63 ARM/160 x86 large pages. Initial setup failures caused by musl wrappers remain
published. See [the task-stat receipts](../../docs/linux-posix-qualification.md#selected-task-stat-identity-and-scheduling).
Per-thread state/name/nice/start-time reporting remains separate. CPU/fault
controls are extended below.

Stat fields 10/12/14/15 now compare against before/read/after `getrusage` brackets
using RUSAGE_THREAD for task paths and RUSAGE_SELF for process paths at 100 Hz.
Leader/worker workloads reserve 64 MiB, touch 256/32/64 native-sized pages,
unmap and require positive minor-fault deltas, then do 200/50/100 ms of measured
CPU work. Worker samples must show fewer faults and CPU ticks than the process.
Both baselines fail 28 task records; both candidates pass the 84 initial reads,
namespace/chroot controls and all retention cycles, preserving previous
identity/scheduling checks. Original small-map baselines remain published;
AArch64's eager small mappings did not prove positive demand faults. Major
faults are zero controls here; disk fault production and child-time fields need
separate qualification. See [the accounting receipts](../../docs/linux-posix-qualification.md#selected-task-stat-cpu-and-fault-accounting).

State controls now require the selected task in stat field 3 and the full status
State description. A leader and pipe-backed worker alternate real blocking
reads: 120 initial R/S records cover self/thread-self, numeric process and
leader/worker task paths across three mounts and both credential groups.
SIGSTOP/WUNTRACED adds 24 stopped process/task records; SIGKILL/WNOWAIT adds 12
zombie process records. Baselines fail 48 sleeping records as R; candidates pass
all 156. A worker and two pipe pairs remain held during the 200-cycle samples,
adding 30 state reads per cycle with flat live slabs and 75 ARM/198 x86 pages.
Zombie task directories and stop/retirement transitions remain separate.
The bare draft's promoted worker record was corrected to explicit stack storage;
failed builds remain published. Related cases missing after disk exhaustion pass
through fresh same-kernel recovery receipts. A private compiler reproduces all
four kernel C captures after a shared executable changed; fixture C differs
only by an exact unused stderr-print prelude.
See [the state receipts and limits](../../docs/linux-posix-qualification.md#selected-procfs-task-states).

Name controls require exact selected comm/stat/status bytes, including empty
names, slash/brackets/parentheses and escaped status newline/backslash. The
four reader phases produce 360 records; empty-worker fork inheritance and
actual exec reset add 144. Twenty prctl controls require bounded page-edge
copies, truncation, real EFAULT without mutation and exact GET padding/canaries.
Baselines fail 378 records plus boundary/GET controls; candidates pass all 524
record/API checks. Each storage cycle adds 90 name reads and two SET/GET
roundtrips, retaining flat slabs and 75 ARM/198 x86 pages. Explicit kernel
scratch buffers and thread-command Text remove three allocation sites. Related
x86 cases blocked by host disk exhaustion pass through same-input recovery
receipts; original failures remain visible. See [the name receipts and limits](../../docs/linux-posix-qualification.md#selected-procfs-task-names).

The `execnames` case observes comm/stat/status/exe through three procfs mounts
while a child performs 200 real execs, as root and UID/GID1000. Each record
must match the exact initial or replacement name/path; files need not show
one atomic generation. Dumpability is established before the first gate.
Both candidates pass, with x86 baseline invalid-name evidence and an ARM
baseline that does not expose the timing race. A final gate keeps the child
alive after exec while 200 observer cycles retain flat slabs and 79 ARM/205
x86 pages. This measures observer retention after exec, not whole-exec
allocation retention. Procself/runtime regressions pass across final and
completion captures; host disk failures and partial receipts remain visible.
See [the exec receipts and limits](../../docs/linux-posix-qualification.md#procfs-metadata-publication-during-exec).

The `statx` case checks 6214 raw/musl calls per architecture as root/UID1000,
covering low-32-bit descriptor/flag/mask words, real file/link/unlinked/pipe
metadata, exact invalid flag/mask/sync and lookup/output errors, unchanged
output canaries/bytes/cursors and descriptor-only NULL paths. Each 200-cycle
retention cohort makes 18 successful/refused calls per cycle, keeping every
live slab class and 63 ARM/160 x86 large pages exact. Baselines fail 4592
calls; both candidates and Linux 6.12.51 references pass using unchanged ELFs.
See [the statx receipts and limits](../../docs/linux-posix-qualification.md#native-statx-requests-and-error-precedence).

On macOS, boot the same native probe ELF against a supplied Linux kernel:

```sh
build-support/run-v-tool.sh tests/linux-compat/statx-reference.v \
  --arch aarch64 --kernel /path/to/pinned/linux-vmlinuz \
  --init /path/to/native/statx/init --state-dir /path/to/fresh-linux-reference
```

The reference controller generates a newc archive in V and uses an exec
wrapper to select `--reference`. This mode runs the same semantics, omitting
Vinix-specific allocator observations; native receipt audits still require
them. ARM uses HVF; `--arch x86_64` uses TCG and a matching kernel/ELF.
Reference receipts bind kernel, unchanged probe, wrapper/source/C/ELF,
archive, QEMU binary/command and raw capture; failed outcomes remain failures.

The `readlinkempty` case checks 3,648 raw/musl calls per root/UID1000 child
on both architectures. Empty paths name the retained symlink description,
including O_PATH handles after unlink or private-directory search denial.
Named/dangling/deleted links and dynamic procfs self/exe aliases retain exact
target prefixes without NUL or canary damage. Invalid FDs return EBADF and
nonlinks/FDCWD ENOENT; native signed32 sizes reject nonpositive values first,
while musl exact-zero scratch lookup retains its path result. Descriptor
upper words, metadata/flags/shared cursors, real AB queues and private/missing
pathname refusals remain checked. Thirty-eight child descriptors survive 32
warm-ups and 200 cycles of 56 probes plus three transient dup/copy controls
with flat live slabs and big pages. Each child closes its inherited references
and three private exe aliases; the parent keeps 35 descriptors while paused.
Concurrent close/unlink/exec, restrictive policy and partial-copy boundaries
remain separate qualification.

The `readlinkabi` case checks 2,160 AArch64 or 2,880 x86-64 calls in each
root/UID1000 child. Raw readlinkat, x86 readlink and both musl wrappers cover
sixteen path classes, fifteen size words and valid/null/inaccessible buffers.
The native ABI consumes a signed32 size: nonpositive values return EINVAL
before path, directory FD, permission or destination access; positive values
ignore upper bits and copy exact target prefixes without a NUL. Musl's exact
zero uses a scratch lookup and returns zero or the real path error, leaving
the caller's buffer untouched. Missing/empty/private/nonlink/loop paths,
relative/absolute FD behavior and procfs links retain their errors or bytes.
The supervisor stages the executable at `/sbin/init`; `/proc/self` retains
Vinix's existing absolute spelling, whose Linux conformance is separate.
Six stable descriptors retain metadata/types/sizes, file bytes/shared cursors
and descriptor flags. After 32 warm-ups, 200 cycles of 52 probes and a transient
directory alias retain flat slab live objects and large pages. Original
fixture expectation failures remain published alongside corrected runs.
Empty-path symlink descriptors are covered by `readlinkempty`; atime,
restrictive policy, concurrency and partial-copy boundaries remain separate.

The `truncatepath` case checks 384 raw/musl pathname truncate calls in each
root and UID/GID1000 child. Twenty-four classes cover regular/private files,
directories, FIFOs, UNIX sockets, devices, direct/symlink targets and lookup
faults. Negative lengths retain EINVAL before lookup; resolved directories
require EISDIR and other nonregular targets EINVAL before policy/copy-up/growth.
A verified failed-open ENOENT seed prevents stale kernel errno from accidentally
satisfying the oracle; original unseeded baseline runs remain published.
Actual resizing checks prefixes/zero tails, metadata/blocks/flags, shared
cursors and private permissions. Ten inherited descriptors retain queued AB
bytes/readiness; both children drain and replenish queues. Two 200-cycle
cohorts measure eighty-eight raw probes plus three transient-alias controls,
requiring flat storage. Symlink loops and inaccessible pointers are outcome
checks outside that repeated loop. Disk/overlays/readonly mounts, timestamps,
privilege-bit clearing, restrictive policies, huge growth, concurrency and
GNU/foreign ABIs remain separate. See
[the pathname receipts](../../docs/linux-posix-qualification.md#native-pathname-truncate-type-errors).

The `truncateabi` case checks 2,784 native ftruncate calls in each root and
UID/GID1000 child. Five raw upper-descriptor patterns and one libc control
combine twenty descriptor classes, aliases and eight signed64 lengths.
Lower-32-bit FD decoding must preserve real resizing/zero-fill/metadata/flags,
shared cursors, private permissions, queued bytes/readiness and negative/
access/type errors. Sixty stable cohort descriptors plus temporary aliases
require flat storage through 200 high-word cycles. The emitted adapter changes
only the descriptor cast, preserving the signed64 length and existing callee
ownership. Other FD APIs, huge growth, concurrent truncation, disk and
GNU/foreign ABIs remain separate. See
[the descriptor-word receipts](../../docs/linux-posix-qualification.md#native-ftruncate-descriptor-words).

The `truncateaccess` case checks 928 native raw/musl ftruncate calls in each
root and UID/GID1000 child. Twenty descriptor classes, original/dup/
F_DUPFD_CLOEXEC aliases and eight signed64 lengths require negative-length
EINVAL before lookup, O_PATH EBADF before policy/type, and nonregular,
readonly or mode3 EINVAL before MAC. Writable regular files shrink and grow
with preserved prefixes, zero-filled tails and unchanged shared cursors.
Every probe checks metadata/flags, private-file permissions and real queued
pipe/socket/FIFO bytes and readiness. Sixty stable cohort descriptors plus
temporary aliases warm 32 and measure 200 cycles of eighty probes and three
duplicate controls, requiring flat slab objects and big pages. Initial strict-C
compile rejections remain published alongside corrected native baselines and
candidates. Upper descriptor words are qualified by `truncateabi` above.
GNU/foreign ABIs, protected attributes,
privilege-bit clearing, readonly mounts, disk, concurrent close/truncate and
huge growth remain separate. See
[the ftruncate receipts](../../docs/linux-posix-qualification.md#native-ftruncate-descriptor-eligibility).

The `seekextent` case checks 9,000 raw/musl SEEK_DATA/SEEK_HOLE calls in each
root and UID/GID1000 child. Generic reporting treats every in-file byte as
data and EOF as the final hole. Five sizes cover empty, small, page-crossing
and sparse files above 4GiB/across 8GiB. Three access modes and original/dup/
F_DUPFD_CLOEXEC aliases check signed64 boundaries, upper FD/selector words,
shared cursors, ENXIO outside the file and retained metadata/blocks/bytes.
Invalid/O_PATH and pipe/socket errors remain controls. Forty-five stable
descriptors warm 32 and measure 200 cycles of 900 raw/libc seeks plus three
temporary aliases, requiring flat slab objects and big pages. A bounded
backup-style walker copies empty/small/page-crossing contents byte for byte.
Its copy directory is explicitly writable for ordinary users; initial failed
copy-setup runs remain published alongside fresh corrected baseline/candidate
runs. Physical extent discovery, concurrent truncation, disk-backed paths and
GNU/foreign ABIs remain separate. See
[the DATA/HOLE receipts](../../docs/linux-posix-qualification.md#generic-native-data-and-hole-seeks).

The `seekerror` case checks 3,888 native lseek refusals in each root and
UID/GID1000 child. Twelve descriptor classes, original/dup/F_DUPFD_CLOEXEC
handles, three FD/selector upper-word patterns and four signed64 offsets
require EINVAL for invalid selectors after descriptor validation, before
pipe/socket/device type errors. Invalid/O_PATH handles retain EBADF. Valid
stream selectors, ordinary file/directory cursors, sparse file seeks, alias
flags/metadata and real queued bytes/FIONREAD/poll/EAGAIN stay valid. Sixteen
stable descriptors warm 32 and measure 200 cycles of 1,296 invalid seeks plus
valid controls and three transient dup/seek/close operations, with flat slab
objects and big pages. Physical extent discovery, valid character-device seeks,
overflow/concurrency, GNU/foreign ABIs and disk-backed handles remain separate.
See [the selector-error receipts](../../docs/linux-posix-qualification.md#native-seek-selector-error-precedence).

The `scalarabi` case checks 2,795 native read/write/pread64/pwrite64/lseek/close
probes in each root and UID/GID1000 child. Five upper-word patterns must use
the lower 32 bits of descriptors and whence, while counts and signed offsets
stay 64-bit. Seven descriptor classes cover files, invalid/O_PATH/wrong-mode
handles, both pipe directions and UNIX streams. Checks require actual bytes,
cursor/queue disposition, access/seek/copy/count errors, closure and surviving
aliases, and sparse contents above 4GiB/across 8GiB. Two 200-cycle cohorts
exercise 70 probes per cycle after 32 warm-ups, requiring flat slab objects
and big pages. Other FD APIs, GNU/foreign ABIs, regular copy-fault cursor
behavior, cap-sized transfers and shared-offset concurrency remain separate.
See [the scalar ABI receipts](../../docs/linux-posix-qualification.md#native-scalar-syscall-argument-words).

The `opathseek` case checks 3,024 native lseek refusals in each root and
UID/GID1000 child. O_PATH handles for readable/private files, directories,
FIFOs, unfollowed links and devices must return EBADF before policy, type,
offset or whence errors. Four requested flag variants and original/dup/
F_DUPFD_CLOEXEC aliases retain metadata and descriptor flags. Ordinary sparse,
relative, negative and invalid seeks, saved file bytes and private-file access
remain valid controls. Two 200-cycle cohorts reuse twelve descriptors and
exercise 510 refusals per cycle, including six temporary dup/close operations,
requiring flat slab and big-page storage. GNU wrappers, upper-word argument
decoding, foreign ABIs, ordinary SEEK_DATA/SEEK_HOLE and shared-position races
remain separate. See [the seek receipts](../../docs/linux-posix-qualification.md#native-o_path-seek-access).

The `iovstream` case checks 220 pipe/UNIX stream/datagram/seqpacket probes in
each root and UID/GID1000 child, using native readv and preadv2 at -1 with
2/8/9/513/1024-entry imports. It checks full/truncated records, untouched next
messages, available data returning while the writer stays open, empty vectors,
first-destination errors and complete 1MiB records. The
blocking probe joins its worker after a late delivery if the call waits for
another record; it never unwinds borrowed storage before the join. Two
200-cycle cohorts reuse endpoint pairs and a payload mapping, checking valid,
empty, invalid-count and EAGAIN callback cleanup with flat slab/big-page counts.
An earlier resource-churn stress hit the separate 4096-socket object limit
before grace retirement; those diagnostic failures remain published. The
`iovimport` checkpoint now counts active receive/vector reservations and passes
both old and fixed stream kernels. Byte streams retain their initial
destination precheck; UNIX record copy faults now consume the selected packet,
as qualified separately by `iovpacket`. Later byte-stream faults, partial-copy
counts, Internet/netlink/character-device paths, allocator exhaustion and
foreign ABIs remain separate qualification. See
[the report](../../docs/linux-posix-qualification.md#native-stream-vector-receives).

The `iovpacket` case checks 350 UNIX datagram/seqpacket native readv and
current-position preadv2 probes in each root and UID/GID1000 child. Headers
with 2/8/9/513/1024 entries cover stack and heap imports. Unmapped, PROT_NONE,
read-only, later-entry and page-crossing copy faults must return EFAULT and
retire only the selected record, including after a copied prefix. Empty queues
return EAGAIN before copying; an empty queued record returns zero and retires
without touching an inaccessible destination. Empty/malformed/count/length
and flag-import controls preserve queued data, and short records never touch
later invalid destinations. Two stable socket pairs and one two-page mapping
warm 32 cycles and measure 200 cycles of 210 transfers each, requiring flat
slab objects and big pages. Scalar reads/recvmsg, other socket families, GNU
wrappers, foreign ABIs and later byte-stream faults remain separate. See
[the record-fault receipts](../../docs/linux-posix-qualification.md#native-unix-record-vector-copy-faults).

The `iovflags` case checks 1,540 native preadv2/pwritev2 cases in each root
and UID/GID 1000 child. Unknown low flag bits must follow negative-offset,
descriptor/access/seek, header/count/range and explicit-position overflow
errors. Valid empty vectors succeed without I/O; malformed zero tails still
fail import. Refusals retain regular-file data/cursors and pipe/socket queues.
High-only flag patterns perform real I/O, verifying the native low-32-bit
flag argument. Two 200-cycle cohorts cover empty 0/8/9/1024-entry imports,
error cleanup, unsupported nonempty requests and flags0 I/O, comparing every
slab class and big-page count. Recognized nonzero RWF modes remain unsupported;
MAC denials, current-position overflow, character devices, GNU/foreign ABIs,
disk-backed vectors and shared-offset atomicity need separate qualification.
See the [qualification and receipts](../../docs/linux-posix-qualification.md#native-vector-flags-and-error-precedence).

The `iovfd` case checks 3,080 native descriptor-word cases in each root and
UID/GID 1000 child across all six vector syscalls and v2's current-position
path. Five upper-word patterns must resolve the same low-32-bit descriptor,
preserve real file/pipe/socket I/O and retain access/seek/import/negative-offset
errors. Invalid low descriptors still fail. Counts of 2^32+1 remain invalid;
they cannot become a one-entry transfer. Data, cursors and queues are checked
after refusals. Two 200-cycle fast/heap/error cohorts require flat slab and
big-page counts. Emitted kernel bodies may differ only by the three lookup
casts; all wrappers and ownership remain identical. The `scalarabi` case
separately qualifies six scalar FD APIs; other FD APIs,
GNU/foreign ABIs, positioned races and shared-offset atomicity remain separate.
See the [qualification and receipts](../../docs/linux-posix-qualification.md#native-vector-descriptor-words).

The `sharedmem` case drops to UID 1000/GID 2000 and checks memfd creator
ownership, mode 0777 independent of umask, zero links, owner chmod and a
read-only `/proc/self/fd` reopen with exact data. A write reopen after mode 0400
must fail with EACCES. It also checks mounted `/dev/shm` mode 1777, ordinary-user
file creation/ownership, and EPERM when removing a root-owned file there.

The `seccomp` case installs a real classic-BPF filter, checks twenty trapped
getpid calls, SYS_SECCOMP siginfo with exact filter data, syscall/architecture
and call address, original return registers, and handler-supplied return values.
Ordinary SIGSYS delivery before and after must carry no stale trap metadata.
Separate children must die from SIGSYS when the synchronous trap is blocked
or ignored. This qualifies trap delivery; filter thread ownership and complete
application sandbox isolation remain separate checks.
It also rejects uninitialized scratch loads, stores to another word and skipped
stores on conditional/unconditional paths with EINVAL. Valid A/X stores, both
branch stores and a maximum-length filter must install successfully.

The `futex` case checks actual waiter returns and exact wake counts across eight
rounds of twelve timed pthread waiters, including overflow event storage.
It checks Linux's original futex ABI zero/negative-count behavior and both
queues of WAKE_OP with true and false comparisons. Requeue semantics have
their own `futexqueue` case.

The `futexkeys` case maps one memfd at two shared addresses and one private
address. Twenty timed pthread waits check that private queues ignore another
virtual alias, shared queues wake through an alias, and private/shared flags
identify separate queues on both mapping kinds. Priority-inheritance futex
keys and cross-process shared-file page eviction remain separate checks.

The `futexbits` case checks twelve waiters with three distinct masks, including
overflow listener storage, across three selective-wake rounds. Requests must
wake only intersecting masks up to the requested count; other waiters remain
blocked. Zero masks, including values whose low u32 is zero, return EINVAL for
both WAIT_BITSET and WAKE_BITSET. A plain WAIT round matches the highest wake
bit too. The fixture checks 36 timed and twelve untimed waits.

The `futexop` case checks all six signed WAKE_OP comparisons with 24 actual
waiters, including a negative comparison operand. SET/ADD/OR/ANDN/XOR must
change the target word correctly. Shift operands follow Linux's masking, and
unsupported atomic operations/comparisons return ENOSYS with the appropriate
word side effects and without waking a queue.

The `futexerror` case checks 38 exact results for alignment, unknown command
bits, unsupported clock flags, private versus shared unmapped addresses,
timeout copy/validation precedence and expired deadlines. A mismatching word
returns EAGAIN before expiration; a matching word returns ETIMEDOUT. WAKE_OP
validates both keys before decoding or modifying its target.

The `futexqueue` case checks REQUEUE and CMP_REQUEUE with exact comparison,
count and address errors, including an empty queue and a read-only comparison
word. Transfers respect wake/move limits, leave existing target waiters
blocked and preserve masks. Shared aliases distinguish neighboring words
within one page. Same-key counting, multiple transfers and timeout/signal
cleanup exercise the transferred queue's lifetime. It runs 164 raw waits and
240 musl condition-variable waits across repeated broadcasts.

The `sparsefork` case reserves 512 private 64 MiB mappings, touching one page
in every sixteenth mapping. It holds the child after fork and measures physical
memory use before further faults: untouched reservations must keep empty shadow
page tables. The page-size-dependent bound allows metadata, resident COW tables
and stacks. The child checks initial zero pages, COW writes, WIPEONFORK zeros and
unmapping; the parent then checks its original bytes and independently faults
the untouched pages. This memory bound applies to the isolated native guest.

The `seccompquery` case runs as UID/GID 1000 and queries every recognized
seccomp action. Nonzero flags return EINVAL before the action pointer is read;
unsupported actions return EOPNOTSUPP and inaccessible arguments return
EFAULT. It checks Linux's unsigned-int narrowing, untouched input/guard words,
and that queries leave seccomp disabled.

The `budget` case preopens `/proc/kernel-resources`, exhausts the ordinary
user's allowance with small shared anonymous mappings and requires ENOMEM with the matching owner-limit
reason, resource kind and rejected byte request. Fixed diagnostic buffers
avoid user allocations; one mapping is released for the kernel's read scratch
reservation before inspecting its retained failure evidence. Unmapping restores
the reservations, keeps the failure evidence, and permits another mapping.
Retained page-map vector capacity and empty table pages remain charged.

The `mapstorage` case runs as UID/GID 1000 and reserves 1024 private 64 MiB
spans without touching data pages. It measures metadata reservations rather
than virtual size or physical RSS, splits 512 mappings with mprotect, forks,
and checks independent zero pages and protection changes in the child. After
unmapping it repeats the cycle to check bounded retained capacity. Prior
fixed 8 KiB alias reservations fail the metadata bound on both architectures.
The [host helper checks](../mmap-budget/README.md) separately cover allocator
geometry, refused growth, retry and surviving creator accounts.

The `sysrq` case checks that an ordinary user receives EACCES when opening
`/proc/sysrq-trigger` for writing, then issues two root task-dump requests.
The controller requires both the fixture verdict and an actual serial task
row. Production kernels retain the graphical console report and also send
these explicit requests to serial. A busy thread list is reported without
waiting for its lock; broader deadlock recovery remains a separate concern.

The `jit` case self-binds one runtime directory read-only with
`nosuid,nodev,wxallowed`. UID/GID 1000 must retain ordinary effective credentials
even when the executable has setuid/setgid bits; writes return EROFS and user
remounts return EPERM. An explicit W^X request through an unapproved path fails
exec with EPERM. Approved exec permits RWX mmap/mprotect, while exec without
the request retains EOPNOTSUPP. Administrator revocation rejects future
requests and preserves the default behavior.

The `nnp` case runs as UID/GID 1000 and checks 34 exact EINVAL results for
PR_GET_NO_NEW_PRIVS and PR_SET_NO_NEW_PRIVS, before and after a valid set.
Reserved arguments retain their full native unsigned-long width; invalid
requests cannot set or clear the state. The C-int option selector ignores
upper register bits. Valid setting remains idempotent and sticky.

The `nnpthread` case runs as UID/GID 1000. A worker sets no_new_privs without
changing its leader, then the leader sets it without changing an existing worker.
Each state must survive new pthreads, fork and exec. Two direct execs from a
nonleader whose flag differs from its leader require the caller's state in the
replacement leader. Seccomp authorization must use the calling thread:
an unreadable header returns EFAULT in both states; a readable valid-length
header with unreadable instructions returns EACCES for state 0 and EFAULT for
state 1, through both the seccomp syscall and prctl.
No filter is installed by that authorization probe. `/proc/self/status`,
`/proc/thread-self/status` and another task's status must report the selected
thread's flag. WNOWAIT permits checking status after child exit before reaping.
The capability-exec suite separately checks retained privilege ceilings.
The `seccompthread` case qualifies filter ownership and TSYNC separately.
Setuid/file-capability execution and complete sandbox isolation remain separate.

The `keepcaps` case checks PR_SET_KEEPCAPS values 0 and 1 as root and UID/GID
1000. Six invalid unsigned-long values, including high bits and all bits set,
must return EINVAL in both flag states without changing them: 24 exact errors.
Valid requests remain reversible and idempotent. Fork inherits the flag, exec
clears it, and the parent's state remains unchanged. The `securebits` case
qualifies locking; per-thread capability credentials remain separate.

The `securebits` case checks all four Linux behavior/lock pairs, locked-clear
and locked-set states, EPERM on changes or unlocking, and exact EINVAL before
the KEEP_CAPS lock check. Unknown mask bits and callers without CAP_SETPCAP
must receive EPERM without changing state, including uid 0 after dropping that
capability. Root exec obeys NOROOT, UID transitions obey NO_SETUID_FIXUP,
and ambient raises obey NO_CAP_AMBIENT_RAISE. KEEP_CAPS alone retains permitted
but clears effective and ambient sets on a complete root-to-user transition.
Exec clears only KEEP_CAPS and retains locks, including from a nonleader with
different flags from its leader. Existing siblings stay independent; clone and
fork inherit the caller's flags. Capability sets themselves remain process-wide;
file capabilities, fsuid-specific fixups and full isolation remain unqualified.

The disk-backed mount conformance controller creates its own fresh 128 MiB ext2
volume and owns QEMU directly. It checks exact missing/non-block/type errors,
source symlinks, a read-only alias, data readback and unmount/remount. The kernel,
fixture, init, ISO and before/after volume hashes accompany its serial log.
`mke2fs` is required; `VINIX_MKE2FS` can select it. Run it with:

```sh
build-support/run-v-tool.sh tests/linux-compat/run-mount.v --arch aarch64 --kernel-dir /path/to/kernel --state-dir /path/to/fresh-mount-state
```

Use `x86_64` for the other native architecture. The controller attaches only its
private volume and enables disk driver startup; the small preformatted volume
cannot trigger automatic system installation.

Run application workloads with:

```sh
build-support/run-v-tool.sh tools/linux-compat/workloads/main.v --host --work=/path/to/fresh-evidence --cases=sqlite,media
# Inside Vinix, installation can be included explicitly:
linux-compat-workloads --work=/tmp/compat-evidence --install
```

Build the workload command for the target userland and stage it as
`linux-compat-workloads`. It invokes applications with literal argument vectors,
bounded output/deadlines and process-group cleanup; it never runs Python.
SQLite tests a WAL transaction and integrity/reopen; FFmpeg checks actual encoded
frames; Gnumeric saves and reopens cell data; browsers render real local content;
existing Go/Java application sources and a V compile/file workload test runtimes;
BusyBox (or Alpine's BusyBox Extras) runs and retires an HTTP service with a
unique response, recording its response and termination. Missing
executables are `unsupported`, nonzero exits/timeouts are `failed`, and either
causes a failing suite exit. There is no sandbox-disable fallback.

Guest command receipts include a starting `/proc/meminfo` and
`/proc/kernel-resources` snapshot. Before terminating a command for a timeout
or output limit, the driver records those counters again, the child's
`status`/`maps`, and `slabinfo`. Nonzero exits retain the final global counters.
Each snapshot retains at most 64 KiB; truncation and read errors are explicit
and cannot turn a failing command into a pass. Host-only runs collect no proc
diagnostics. These counters help distinguish allocation limits from physical
memory pressure; they do not establish the cause of a failure by themselves.

The `serviceunits` case requires the cross-compiled native `vinix-desktop` broker
and BusyBox Extras. It imports a supported Linux HTTP service unit disabled,
starts it explicitly, checks its response and failure restart, restores its
saved definition across broker restarts, then stops and removes it. Unauthorized
imports, unsupported security directives and removal of active services must
fail without changing saved configuration. RPC replies are recorded separately
from command exit codes. The native Services tab exposes import/start/stop/remove;
see the [unit contract](../../docs/linux-posix-qualification.md#linux-service-unit-integration).
Build guest brokers with `desktop/tools/session_check.v cross`: production
compilation embeds VML assets instead of leaving host-path startup dependencies.

The application guest init supplies the usual login environment (HOME, user
names, UTF-8 locale and XDG_RUNTIME_DIR). Prepared office roots also need real
fonts; DejaVu and the Alpine Gnumeric dependency closure qualify the native
save/reopen workload. Archive and guest-input hashes accompany the dated
results, including the initial missing-font failure. Extraction remains
distinct from installed-system package transactions and desktop integration.

The Go case sets the installed `/usr/lib/go` root when present, a private build
cache and `CGO_ENABLED=0`, matching the existing pure-Go smoke workflow. Native
AArch64 and x86-64 select the matching architecture assertion while preserving
the existing application checks. The input generator rejects foreign paths
and unexpected assertions. Child
environment overrides and removed variable names are recorded per command and
cleared between workloads; inherited environment values are not serialized.

The Java case compiles the existing input and runs it from a class directory
and a newly created JAR, with a bounded heap. HotSpot requires writable
executable code pages: its children request VINIX_ALLOW_WX=1, which still
requires Vinix's [privileged launch or wxallowed mount policy](../../docs/mount-execution-policy.md).
All Java tools come from one complete JDK. PATH takes precedence; extracted
Alpine roots can use the actual `/usr/lib/jvm/*/bin` tools when post-install
alternatives have not been registered. This does not qualify package scripts
or installation. That launch requirement is recorded in command receipts;
ordinary unprivileged
launches without the administrator's policy are not qualified.

For ordinary-user Firefox or Java qualification, add `--uid 1000
--jit-runtimes firefox` (or `java`) to `run-apps.v` and select that workload.
The controller accepts distinct selected native Firefox/Java runtimes only;
it records the exact mount input and the guest init prepares read-only
`nosuid,nodev,wxallowed` self-binds before dropping credentials. The driver
remains outside those mounts. Firefox requests VINIX_ALLOW_WX only for its
children; every helper exec still receives the kernel's mount check. Reports
retain the requested names and actual most-specific mountinfo rows, whose
permissions are required before launching. No sandbox-disable environment
or command is added. Foreign execution chains and Chromium's setuid sandbox
require separate integration.

The Firefox 128.14.0esr workload passes on both native architectures in 4096 MiB
guests with this explicit approval, including AArch64's 16 KiB pages. It requires
a real nonce-bearing JavaScript callback
and a rendered PNG. The earlier 2048 MiB approved run reaches kernel resource
limits; approval alone does not increase those limits. These are extracted
runtime workloads, with installation scripts and persistent lifecycle checks
still separate. See the [dated qualification evidence](../../docs/linux-posix-qualification.md#administrator-approved-native-jit-runtimes).

`--host` labels host-only evidence and prohibits installation. `--path` chooses
native AArch64/x86-64 or AArch64's translated x86-64/i386 launcher. Native paths
must match the driver architecture. `--runtime-probe` chooses the corresponding
staged fixture. Go and Java compilation remain explicitly unsupported on
translated paths; translated HTTP service integration is also unqualified.
Portal discovery and games requiring licensed assets remain explicit unsupported
results until real chooser/save and title-specific GPU/input/audio/save tests
exist. The JSON report always keeps full lifecycle qualification false: these
workloads alone do not certify package updates, desktop integration, systemd,
Flatpak/Snap or every glibc software dependency.

Cross-build static musl executables with the maintained V builder. It generates
C through V, invokes the selected target compiler and verifies the ELF machine
and class. Production mode embeds the Go/Java application sources in the driver
so they are available inside the guest. The output directory must be fresh;
`build.json` records sources, generated C, command arguments and executable hashes.
Both modes currently name
their output `linux-compat-workloads`, so keep the driver and probe in different
directories:

```sh
build-support/run-v-tool.sh tools/linux-compat/build/main.v aarch64 /path/to/fresh-driver
build-support/run-v-tool.sh tools/linux-compat/build/main.v aarch64 /path/to/fresh-probe --runtime-probe
build-support/run-v-tool.sh tests/linux-compat/run-apps.v --arch aarch64 --kernel-dir /path/to/arm/kernel --state-dir /path/to/fresh-apps --rootfs /path/to/prepared-root --workloads /path/to/fresh-driver/linux-compat-workloads --runtime-probe /path/to/fresh-probe/linux-compat-workloads --cases sqlite,server,runtime
```

The controller's `--workload-timeout` sets each application command's deadline
(1..3600 seconds, default 120). `--timeout` separately bounds the entire guest.
The receipt records the command deadline and hashes the exact guest options;
increasing a deadline does not change or replace a previous failed receipt.

Repeat with `x86_64` and its matching kernel/root. The ARM builder uses
`VINIX_AARCH64_SYSROOT` and `CC_AARCH64` (default clang); x86 uses `CC_AMD64`
(default x86_64-linux-musl-gcc). `VINIX_V_COMPILER` selects V. The
`i386 --runtime-probe` path uses `CC_I386` (default i686-linux-musl-gcc), or a
clang-compatible compiler when `VINIX_I386_SYSROOT` names an i386 musl SDK and
`VINIX_I386_BUILTINS` names its compiler-rt builtins archive. In the latter mode
the receipt also hashes the SDK CRT, libc and builtins; host GCC libraries are
excluded. SSE2 intrinsics let this fixture build through V's i386 C backend.

Use `--uid 1000` for ordinary-user workloads. The guest clears supplementary
groups, drops GID/UID to 1000, and provides a private HOME and XDG runtime
directory; the report records the observed credentials. `--memory 4096` gives
large application dependency closures more RAM (1024..16384 MiB is supported).
SQLite, HTTP and runtime predicates pass as UID 1000 on both architectures.

The `firefox` and `chromium` cases require UID 1000 and invoke the real ELF
engines directly with fresh profiles. An inherited Mozilla sandbox-disable
environment fails the precondition. A private loopback page computes 6*7 in
JavaScript and returns a fresh nonce and 42 to the V HTTP server. Chromium must
also return the changed DOM; Firefox must render a PNG. Startup/version output,
a page fetch, a wrong nonce/result or an image without the callback cannot pass.
These are default-policy headless checks; failed sandbox setup and actual
timeouts stay failed. See the [current browser failures and pinned inputs](../../docs/linux-posix-qualification.md#ordinary-user-application-and-browser-regressions).

To qualify real CLI installation/update/removal, stage unchanged signed Alpine
v3.20/v3.21 SQLite dependency closures and APK tooling with the V stager:

```sh
build-support/run-v-tool.sh tools/linux-compat/packages/main.v aarch64 /path/to/prepared-base /path/to/fresh-package-inputs
```

Run `run-apps.v` with that output's `root`, the matching driver/probe, `--cases
packages` and `--data-disk /path/to/private-preformatted-ext2`. The controller
never formats an existing data disk. Use a dedicated test volume: the workload
creates its own root, repositories and database there. The first boot installs
SQLite through real APK and the existing `pkg` frontend, commits WAL data, syncs
and unmounts. Repeat in a fresh state directory with the same disk for the
reboot/upgrade/removal phase. It reopens saved data, performs an actual version
upgrade, removes the package, verifies base-runtime/data retention and unmounts.
Run the two phases sequentially. Both state receipts retain before/after disk
hashes, making the volume handoff verifiable. No untrusted-package opt-in or
placeholder installer is used. The stager only acquires inputs; guest APK
performs dependency resolution and validates repository/package signatures.
`packages` is restricted to native Vinix execution and an explicit disk;
`--host` rejects it. This workflow does not qualify desktop or service packaging.

```sh
VINIX_I386_SYSROOT=/path/to/i386-sdk VINIX_I386_BUILTINS=/path/to/libclang_rt.builtins-i386.a build-support/run-v-tool.sh tools/linux-compat/build/main.v i386 /path/to/fresh-i386-probe --runtime-probe
```

The application controller takes a prepared guest root with matching programs
and libraries, snapshots the kernel/driver/probe and init source, and preserves
guest symlinks literally. It boots without networking or implicit installation.
Root file/mode/link hashes, input receipts, serial output and extracted
`guest-report.json` stay in the state directory, including failed/unsupported
results. To test translation, select `--path translated-x86_64`, supply a
native ARM driver and an x86-64 probe, and stage the existing translator/private
runtime in the prepared root. The static probe uses `run-x86-64 --direct`;
dynamic applications use the normal private-loader path. A passing static probe
does not qualify glibc loaders or all translated applications.

Select `--path translated-i386` with an ELF32 probe to test 32-bit translation.
The static probe invokes `VINIX_I386_EMULATOR` (default `/usr/bin/qemu-i386`)
directly with the private runtime root and the launcher's W^X opt-in, because a
static ELF cannot be passed to the wrapper's dynamic musl loader. That environment
is confined to the child; ordinary i386 applications still use `run-x86-32`.
The dated [qualification report](../../docs/linux-posix-qualification.md) contains
passing native ELF64 and translated 32-bit runtime receipts. Native ELF32/x32 entry,
arbitrary glibc applications, the complete large-file/time ABI and debugger operations remain separate
checks beyond the qualified lseek/clock/timerfd predicates.

Unmodified GNU libc can be tested independently with the pinned Debian SDK:

```sh
build-support/run-v-tool.sh tools/linux-compat/sdk/main.v arm64 /path/to/fresh-sdk
VINIX_GLIBC_SYSROOT=/path/to/fresh-sdk/sysroot build-support/run-v-tool.sh tools/linux-compat/build/main.v aarch64 /path/to/fresh-gnu-probe --runtime-probe --libc=glibc
```

Use `amd64`/`x86_64` or `i386` for the other SDK/probe pairs. The SDK verifies
the checked-in archive hashes, then extracts headers, CRT and libraries without
executing package scripts. GNU builds use their own headers and dynamic loader;
i386 enables _FILE_OFFSET_BITS=64 and _TIME_BITS=64. Link receipts retain the
actual libc, loader, libm, libgcc and CRT hashes.

Stage those libraries in the prepared guest's
`/usr/libexec/vinix-glibc/ARCH/lib`. Native probes need the matching GNU
interpreter at `/lib/ld-linux-aarch64.so.1` or
`/lib64/ld-linux-x86-64.so.2`. For translation, each private `ARCH` root needs
its interpreter at the normal Linux path: `/lib64/ld-linux-x86-64.so.2` or
`/lib/ld-linux.so.2`. Pass `--runtime-libc glibc` to the application controller
(or `--runtime-libc=glibc` to the guest driver). Translated probes use QEMU-user
directly with this private root, scoped W^X opt-in and removed foreign library
environment variables. The driver requires the probe's GNU libc version marker
as well as every runtime predicate. Dated receipts cover both native and both
translated paths; these checks do not qualify every GNU application.

Select `--cases debugger` with either translated path and its matching runtime
probe to qualify the QEMU-user GDB remote stub. The V client verifies register
and instruction-memory reads, stack memory write/read/restore, a software
breakpoint, single stepping and successful continuation through every runtime
predicate. The report records the exact translator/probe hashes, addresses,
register-packet hash and child cleanup. The stub listens on guest loopback port
19016; packets and output are bounded, and socket operations have deadlines.
Native paths report unsupported because ptrace has no syscall dispatch.
Source-level symbols, unwinding, core dumps and JIT debugger registration need
their own qualification.

The `open` fixture also checks invalid O_CREAT|O_DIRECTORY combinations in
plain open/openat and openat2: EINVAL must precede path lookup and leave no new
file. Legacy O_PATH normalization remains valid. Dated before/after receipts
use identical fixture binaries on both architectures; the final kernels pass
all six native cases.

Select `--cases games` with a prepared native root containing `chocolate-doom`,
its SDL libraries and a locally licensed IWAD at
`/usr/share/games/doom/doom1.wad`. The workload runs `demo1` twice with SDL dummy
video and software rendering, and requires completed gameplay and a matching
tick count on replay. Chocolate Doom ends a successful timedemo with exit 255;
the driver requires that exact exit and the complete timing record. Crashes,
startup failures, timeouts and output limits remain failures. Assets are never
replaced or included in receipts: their SHA-256 identifies the external input.
Visible rendering, audio, input, saves and foreign runtime qualification are
separate requirements. See the dated game receipt and its limits.

The `ambient` case issues raw PR_CAP_AMBIENT requests with nonzero reserved
arguments, including bits above the C-int width. It checks all four commands,
including CLEAR_ALL's third argument, before and after a real ambient raise
and after dropping to UID/GID 1000. All 81 malformed requests must return
EINVAL and leave the ambient set unchanged. Valid raises, queries, lowers and
clears retain their behavior; an ordinary user without the required permitted
and inheritable capability gets EPERM for a valid raise. This case qualifies
argument validation, not per-thread capability credential isolation.

The `capbset` case checks PR_CAPBSET_READ/DROP with six invalid full-width
capability numbers. DROP must check effective CAP_SETPCAP before returning
EINVAL for a capability number; READ returns EINVAL independently of privilege.
Privileged root, root with that effective capability removed, and UID/GID 1000
must receive the exact 42 errors without changes to the bounding set. Valid,
repeated low/high drops leave current capability sets unchanged; fork inherits
the bounding set, a child's drop stays private, and exec retains the drops.
Per-thread capability credentials remain outside this case's qualification.

The `capset` case runs 13 isolated children covering low/high inheritable
bits and an ordinary user. New bits must belong to the bounding set, while
existing inheritable bits may survive a later bounding drop. Effective
CAP_SETPCAP allows bounded additions outside the old permitted set; without
it, additions must also come from old permitted. Authorization uses the old
effective set even if the same update drops CAP_SETPCAP. Rejected updates
leave capability sets unchanged, and dropping permitted clears ambient bits.
The parent verifies that child changes do not alter its state. Fixture helpers
use stack storage and compile without V allocation or indexing runtime calls.

The `cappid` case checks capset's caller-only PID contract: zero and gettid()
accept valid no-op data, while sibling, group-leader-from-sibling, negative and
missing IDs return EPERM before reading data. All three capability versions
are checked with readable, null and bad data pointers. Valid self IDs with bad
data and unreadable headers return EFAULT. Root and UID 1000 leader/sibling
rounds verify 236 exact errors and unchanged sets. This qualifies PID/error
validation; capability sets still belong to the process.

The `capabi` case checks null-data version discovery, preferred-version
writeback, unchanged PID words, readonly write faults and headers with only
their version word accessible. All three versions use exact data sizes at
protected page boundaries; version 1 clears the unrepresented high word in
isolated children. Reserved high bits are ignored for root and UID 1000 while
valid bits and capability state remain intact. Native page sizes are recorded.

The `seccompthread` case checks task-local filters, independent siblings and
caller-based clone/fork/exec inheritance, including nonleader exec while a
differently filtered leader spins in userspace. TSYNC must accept disabled or
ancestral siblings, refuse diverged or independently installed identical
programs with the offending TID or ESRCH, and preserve all state on failure.
Successful sync propagates the caller's no_new_privs without clearing an
existing sibling flag. Procfs reports each live task and retains zombie leader
scalars. A full 32768-instruction path is accepted; another filter gets ENOMEM.
Concurrent clone/sync and two storage cohorts check thread publication and
3200 filter installations with natural exits and 200 forced nonleader execs.
The 32/64/96/128-byte slab classes must remain flat after grace periods; this
includes the actual filter-header and instruction-buffer classes. Storage
cohorts use raw queries to keep the existing retained procfs trees out of the
filter measurement. Notifications and full sandbox support remain separate.
Allow at least 300 seconds for each native guest.

The `seccompkill` case runs eleven isolated UID/GID 1000 groups. KILL_THREAD
(with and without data bits) and strict-mode violations must terminate only
the triggering task; KILL_PROCESS and unknown actions must terminate the
group. Caught SIGSYS handlers must not intercept these actions, and the last
task must retain its SIGSYS/SIGKILL wait status. Strict mode permits raw
read/write/exit and actual signal return, forbids exit_group, and blocks TSYNC
from a filtered sibling with the offending TID or ESRCH. CHILD_CLEARTID and
ESRCH confirm task retirement. The V fixture uses musl's unchanged raw
`__clone` architecture trampoline because its public clone wrapper refuses
these CLONE_THREAD flags. Success waits for retirement before unmapping the
child stack; failure after cloning exits the group while its borrowed Task
frame remains live. Core dumps and foreign/ELF32 runtimes remain separate.

The `seccompinstall` case compares syscall/prctl installation errors in five
isolated groups: root with CAP_SYS_ADMIN, root without it, UID 1000 without
no_new_privs, UID 1000 with it, and root without CAP_SYS_ADMIN with no_new_privs.
Unreadable headers must return EFAULT and invalid lengths EINVAL before the
permission check. Valid lengths require permission before reading/verifying
instructions. Null, bad and partial-page pointers, readonly headers, exact
instruction boundaries, unaligned headers and ignored ABI padding are tested.
Repeated rejection preserves mode and no_new_privs; valid ALLOW filters prove
the capability/NNP authorization paths. Each group performs 446 checked calls.

The `seccompalloc` case records four root/UID 1000 syscall/prctl cohorts. A
valid 4095-instruction ALLOW program succeeds in production; a separate kernel
built with `VFLAGS='-d seccomp_alloc_selftest'` injects a nil instruction
allocation and must return ENOMEM before copying the instruction pointer.
The dated auditor independently requires these distinct outcomes and refuses
to label ordinary success as a tested allocation failure. Header, length and
permission errors retain their precedence; rejection preserves mode/NNP and a
subsequent small filter must work. After warmup, 256 rejected large-copy calls
per cohort retain flat `/proc/slabinfo` large-allocation page counts. A
32760-byte raw buffer uses the big allocator, including its metadata: three
pages on AArch64 and nine on x86-64. It does not belong to a 32768-byte slab
class. The separate `seccompthread` case measures published small-buffer
retirement. Allow 300 seconds per case. Physical OOM recovery is a separate
qualification; the injection is absent from production kernels.

The `sysnr` case runs seven isolated UID/GID 1000 groups. Four full-register
prefixes check the low-32-bit C-int selector: getpid/gettid/getuid/getgid retain
their results; unknown, negative and x32-tagged numbers return ENOSYS. User
number 511 cannot select the kernel's private verdict handler, including after
an earlier errno verdict. Filters still see that number and may intentionally
return ERRNO(0), EACCES or TRAP. Eight SIGSYS traps check signed syscall
metadata, architecture, call address and the original return register; the
handler changes the result. Strict read/write/exit calls with high bits pass
using a primed pipe. A caught SA_RESTART signal restarts a blocked read while
its signal frame preserves the full original selector. These are native ELF64
checks; native ELF32/x32 and translated syscall entry remain separate.

The `pipezero` case runs seven isolated UID/GID 1000 groups. Zero-byte reads
must return immediately on blocking and nonblocking empty anonymous pipes and
named FIFOs, populated/full pipes and after writer close. Zero-byte writes
also succeed on full pipes and after reader close, without SIGPIPE. Null,
unmapped and PROT_NONE buffers are accepted because no byte is transferred.
Repeated calls preserve FIONREAD and poll readiness; real reads retain data,
empty nonblocking reads and full writes retain EAGAIN, EOF returns zero, and
invalid/closed/wrong-access descriptors retain EBADF. A non-restarting alarm
bounds each child and must never fire in a passing group. Root only prepares
a writable test directory before the fixture drops credentials. Directory
read type errors are a separate regression.

The `readerror` case performs 64 checks each as root and UID/GID 1000. Scalar
read(2) must return EISDIR for root, tmpfs, procfs and sysfs directories at zero,
one and 4096 bytes without touching valid, unmapped or PROT_NONE destinations.
An out-of-userspace nonzero range returns EFAULT. Failed directory reads leave
the offset intact; invalid and wrong-access descriptors retain EBADF. Regular
zero-byte reads leave the offset intact, and valid data/EOF reads still work.
These checks do not qualify vectored, O_PATH or later-copy-fault behavior.

The `pathio` case performs 240 checks each in isolated root and UID/GID 1000
children. O_PATH handles to a regular file, directory, FIFO and unfollowed
symlink, plus their duplicates, refuse scalar/positioned reads and writes and
empty/nonempty vectors with EBADF. Metadata, duplication and status flags
remain usable. Vector descriptor/access errors precede malformed iovec faults,
including zero vectors and wrong read/write modes. Valid two-iovec regular
read/write and zero vectors retain their results. The ordinary child first
requires EACCES for an ordinary open of the root-owned mode-0600 file. This
retains the existing scalar-read refusal. Concurrent close/reuse during a
complete vector operation and other O_PATH operations require separate
qualification.

Host verification of the report generator and timeout/nonzero-exit handling:

```sh
v -cc cc test tools/linux-compat
```

If the local V compiler reports missing cached `_v3_lit_*` literals after edits,
use a fresh `V3CACHE` directory or `v -nocache -cc cc run` for the host tool.

The `statabi` case checks native fstat/newfstatat argument words, unknown flags,
NULL/empty descriptor queries, actual metadata and exact lookup/output errors
as root and UID/GID1000. It includes x86 legacy stat/lstat and ordinary musl
wrappers, output canaries/sentinels, unchanged file bytes/cursor and two
200-cycle allocation cohorts. Native statx/open/runtime regressions accompany
the [dated stat qualification](../../docs/linux-posix-qualification.md#native-stat-descriptor-words-and-flag-errors).

The same native probe ELF can run against a Linux kernel through the V
reference controller. Its fresh artifact directory retains frozen kernel/probe
inputs, wrapper source/C/ELF, V-generated initramfs, QEMU command and receipt,
including when qualification fails. The macOS ARM path uses HVF; x86 uses TCG.

```sh
tests/linux-compat/run --arch aarch64 --kernel-dir ARM-KERNEL --state-dir FRESH-NATIVE --cases statabi,statx,open,runtime
v -enable-globals -nocache -gc none -cc cc run tests/linux-compat/statabi-reference.v --arch aarch64 --kernel LINUX-KERNEL --init FRESH-NATIVE/statabi/init --state-dir FRESH-LINUX
```

Use matching `--arch x86_64` and kernel/probe inputs for x86. `--reference`
selects the same semantic matrix while skipping Vinix-specific slab reporting;
the native audit still requires the allocation cohorts. NULL is tested through
raw syscalls because musl's fstatat wrapper requires a non-NULL pathname.
