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

The `dupabi` case qualifies native dup/dup3 descriptor and flag words, x86
dup2 words/self calls and ordinary musl dup/dup2/dup3 controls. Unknown dup3
flags must return EINVAL before replacing a distinct seeded target; negative
libc targets retain EBADF. Six source classes check alias metadata/status,
descriptor CLOEXEC, shared cursor movement and preservation of source/target
state on errors, plus unchanged bytes/queued pipe data and two allocation
cohorts. Concurrent publication has its own `duppublish` qualification below;
see [the dated dupabi limits](../../docs/linux-posix-qualification.md#native-descriptor-duplication-errors-and-words).

```sh
tests/linux-compat/run --arch aarch64 --kernel-dir ARM-KERNEL --state-dir FRESH-NATIVE --cases dupabi,statabi,open,runtime
v -enable-globals -nocache -gc none -cc cc run tests/linux-compat/dupabi-reference.v --arch aarch64 --kernel LINUX-KERNEL --init FRESH-NATIVE/dupabi/init --state-dir FRESH-LINUX
```

Use matching x86 kernel/probe inputs and `--arch x86_64` for x86. The reference
controller freezes the same native probe ELF and Linux kernel, builds a V
wrapper/initramfs and retains exact hashes and serial output, including on
failure. ARM uses macOS HVF; x86 uses TCG. `--reference` omits Vinix allocator
reporting while running the identical semantic matrix. The native audit
requires the allocation cohorts and refuses reference-only qualification.

The `duppublish` case checks flag visibility and real fork snapshots while a
worker duplicates a descriptor with opposing source flags. Both root and
UID/GID1000 run six methods with 128 calls and 16 fork checks per method, then
200 close/reuse rounds. A completed worker is synchronized before the final
metadata sample. Sequential storage cohorts require flat slab objects and
large pages after 200 cycles; they measure retention separately from the
concurrent controls.

```sh
tests/linux-compat/run --arch aarch64 --kernel-dir ARM-KERNEL --state-dir FRESH-NATIVE --cases duppublish,dupabi,open,runtime --timeout 1300
v -enable-globals -nocache -gc none -cc cc run tests/linux-compat/duppublish-reference.v --arch aarch64 --kernel LINUX-KERNEL --init FRESH-NATIVE/duppublish/init --state-dir FRESH-LINUX
v run tests/linux-compat/duppublish-instrument.v INPUT-FILE FRESH-OUTPUT-FILE
```

Use matching x86 inputs and `--arch x86_64` for x86. The instrumenter creates
a private copy of `kernel/file/file.v` that yields 32 times immediately after
inserting target 63. Apply that copy only in an isolated qualification build,
to both baseline and candidate. Production kernels contain no scheduling
hook. A known-bad baseline stops after visibility controls, avoiding the
deliberate close/reuse exercise on a freed descriptor. The audit requires
complete baseline failures, candidate and Linux passes, unchanged probe ELFs,
and an observed unfinished producer before close in each instrumented cohort.
See [the publication receipts and limits](../../docs/linux-posix-qualification.md#descriptor-flags-before-publication).

The `fcntlabi` case runs 8,928 raw/musl calls per architecture across root and
UID/GID1000. It varies descriptor, command and scalar upper words independently,
checks getters and descriptor/status/signal setters, duplicates six source
classes, and distinguishes invalid minima from actual descriptor exhaustion.
Zero-soft-limit controls preserve native dup's EMFILE behavior. Real high
stack flock pointers and surrounding canaries check transport; NULL remains
EFAULT. Pipe identity-size queries use each kernel's actual capacity. Shared
offsets, source/seed metadata and flags, file bytes and queued AB remain exact.
Two native 200-cycle cohorts measure valid and refused duplication retention.

```sh
tests/linux-compat/run --arch aarch64 --kernel-dir ARM-KERNEL --state-dir FRESH-NATIVE --cases fcntlabi,dupabi,duppublish,open,runtime --timeout 1300
v -enable-globals -nocache -gc none -cc cc run tests/linux-compat/fcntlabi-reference.v --arch aarch64 --kernel LINUX-KERNEL --init FRESH-NATIVE/fcntlabi/init --state-dir FRESH-LINUX
```

Use matching x86 inputs and `--arch x86_64` for x86. Set `V` to the selected
compiler for both controllers and their generated guest modules when collecting
reproducible receipts. Reference boots run the identical frozen native ELF and
omit only Vinix allocator reporting. See [the fcntl receipts and limits](../../docs/linux-posix-qualification.md#native-fcntl-words-and-duplicate-minima).

The `fcntlpath` case checks 10,812 native raw/musl calls per architecture across
root and UID/GID1000. Six O_PATH classes cover readable/private regular files,
a directory, FIFO, unfollowed symlink and unlinked file. Original/ordinary/
CLOEXEC aliases reject 24 non-pathname commands with EBADF before copying real,
NULL or invalid user pointers, preserving packet canaries, metadata and flags.
Allowed flag/duplication controls and ordinary file errors/data/permissions
remain usable. Two 200-cycle cohorts measure refusal and alias retention.

```sh
tests/linux-compat/run --arch aarch64 --kernel-dir ARM-KERNEL --state-dir FRESH-NATIVE --cases fcntlpath,fcntlabi,open,runtime --timeout 1300
v -enable-globals -nocache -gc none -cc cc run tests/linux-compat/fcntlpath-reference.v --arch aarch64 --kernel LINUX-KERNEL --init FRESH-NATIVE/fcntlpath/init --state-dir FRESH-LINUX
```

Repeat with matching x86 inputs and `--arch x86_64`. Set `V` to the selected
compiler for both controllers and guest modules. Linux boots run the frozen
native ELF and skip only Vinix allocator reporting. See [receipts and limits](../../docs/linux-posix-qualification.md#o_path-fcntl-command-refusals).

The `fcntlquery` case runs 9080 F_DUPFD_QUERY controls per architecture across
root and UID/GID1000. Eight classes each have original/ordinary/CLOEXEC aliases;
separate opens of six same-inode objects must compare different. Native word,
libc, invalid-source/target, held-descriptor zero/eight soft-limit and real
close/replacement tests preserve all metadata, flags, cursors, bytes and two
pipe queues. A directory control balances live references and flags while
retaining separate descriptions. Two 200-cycle query cohorts measure retention.

```sh
tests/linux-compat/run --arch aarch64 --kernel-dir ARM-KERNEL --state-dir FRESH-NATIVE --cases fcntlquery,fcntlpath,open,runtime --timeout 1300
v -enable-globals -nocache -gc none -cc cc run tests/linux-compat/fcntlquery-reference.v --arch aarch64 --kernel LINUX-KERNEL --init FRESH-NATIVE/fcntlquery/init --state-dir FRESH-LINUX
```

Use matching x86 inputs with `--arch x86_64`, and set `V` for both controllers
and their guest modules. The pinned Linux 6.12.51 reference returns EBADF for
either invalid descriptor; the original Linux 6.12 implementation differed
for an invalid comparison descriptor. See [receipts and limits](../../docs/linux-posix-qualification.md#fcntl-duplicate-description-queries).

The `fcntlcreated` case runs 3808 F_CREATED_QUERY controls per architecture for
root and UID/GID 1000. Sixteen description classes and ordinary/CLOEXEC aliases
cover inherited and child-owned creation, existing-file reopens and truncation,
ignored O_PATH creation flags, existing/dangling symlink targets, O_PATH links
and directories, unlink/recreation and pipe endpoints. Eight ignored full-width
arguments, native descriptor/command words, exact errors, zero/eight soft limits
and descriptor replacement must preserve metadata, flags, cursors, bytes and
queued data. Two 200-cycle cohorts measure retained kernel storage.

```sh
tests/linux-compat/run --arch aarch64 --kernel-dir ARM-KERNEL --state-dir FRESH-NATIVE --cases fcntlcreated,fcntlquery,fcntlpath,open,runtime --timeout 1300
v -enable-globals -nocache -gc none -cc cc run tests/linux-compat/fcntlcreated-reference.v --arch aarch64 --kernel LINUX-KERNEL --init FRESH-NATIVE/fcntlcreated/init --state-dir FRESH-LINUX
```

Repeat with matching x86 inputs and `--arch x86_64`. Set `V` for both controllers
and guest modules. Linux runs the same frozen native musl ELF and omits only
Vinix allocator observations. See [receipts and limits](../../docs/linux-posix-qualification.md#fcntl-file-creation-queries).

The `fcntlsync` case runs 3472 F_SETFL controls per architecture for root and
UID/GID 1000. Nine regular/directory/unlinked/pipe description classes and
ordinary/CLOEXEC aliases must retain the O_SYNC/O_DSYNC and access modes chosen
at open. Append/nonblocking changes share across aliases while separate opens
keep their own state. Six O_PATH aliases require EBADF. Native argument words,
musl setters, held descriptors above zero/eight soft limits and replacement 66
preserve metadata, descriptor flags, cursors, file bytes and queued AB. Two
200-cycle cohorts measure retained kernel storage.

```sh
tests/linux-compat/run --arch aarch64 --kernel-dir ARM-KERNEL --state-dir FRESH-NATIVE --cases fcntlsync,fcntlabi,fcntlpath,open,runtime --timeout 1300
v -enable-globals -nocache -gc none -cc cc run tests/linux-compat/fcntlsync-reference.v --arch aarch64 --kernel LINUX-KERNEL --init FRESH-NATIVE/fcntlsync/init --state-dir FRESH-LINUX
```

Repeat with matching x86 inputs and `--arch x86_64`. Set `V` for both controllers
and their guest modules. Linux boots the same native musl ELF. The dated
qualification composes successful unchanged-kernel cases with recorded original
receipts, excluding provisional sync probes and failed ISO setup. See
[receipts and limits](../../docs/linux-posix-qualification.md#fcntl-synchronization-status-preservation).

The `ofdlocks` case qualifies native regular-file open-description record
locks as root and UID/GID1000. Its 464 checks per architecture cover aliases and
separate opens, POSIX/OFD conflicts, query records and PID values, splitting/
coalescing/conversion, selected errors, flock independence and final-close/
fork inheritance. F_OFD_GETLK with F_UNLCK queries this description's own
locks; F_GETLK with F_UNLCK returns EINVAL. Three child waiters per credential
are observed sleeping in procfs before unlock, downgrade or non-restarting
SIGUSR1; returns must be success or EINTR as appropriate. Two 200-cycle cohorts
measure every slab class and large-page count after repeated lock/alias cleanup.
The reference controller boots the identical musl ELF on Linux 6.12.51 and
mounts procfs for the same wait checkpoints. Sources and executed C/ELF must
match across baseline, candidate and reference. See the
[qualification receipts and limits](../../docs/linux-posix-qualification.md#native-open-description-record-locks).

The `lockrange` case checks signed record-lock endpoints and validation order
for all six native POSIX/OFD commands. It runs 2,096 libc/raw controls per
architecture as root and UID/GID1000: sixteen accepted ranges, ten refusals,
compound type/access/PID errors, complete flock records and retained seed locks.
Finite ranges ending at INT64_MAX return the same zero-length endpoint as
Linux; the preceding byte remains finite. Boundary splits/bridges/conversion
and alias/final-close behavior preserve file bytes, metadata, flags and shared
cursors. Two 200-cycle cohorts measure maximum-byte lock and cleanup retention.
The Linux reference runs the identical musl ELF and skips allocator accounting.
The dated x86 qualification combines three original successful cases with
recovered open/runtime cases after host setup/log-write failure, with exact
source/kernel/ISO/capture provenance. See the
[range receipts and limits](../../docs/linux-posix-qualification.md#native-signed-record-lock-ranges).

The `lockaccess` case qualifies native advisory-lock access and operation
errors with 12,720 controls per architecture as root and UID/GID1000. All six
record commands cover five access modes, three aliases, three lock types,
five range/kind/PID variants and libc/raw calls. Sixteen flock operations
check exact SH/EX/UN forms with optional NB, mode3/O_PATH refusals and low32
descriptor/operation imports. Full headers, observed locks, bytes, metadata,
flags and real shared cursors are checked; two 200-cycle cohorts measure
refused calls plus actual OFD/flock alias cleanup. The same native musl ELF
passes actual Linux 6.12.51; both unchanged kernels reproduce 1,458 failures.
See the [access receipts and limits](../../docs/linux-posix-qualification.md#native-advisory-lock-access-and-words).

The `flocksame` case checks same-kind open-description ownership with 1,936
controls per architecture/run as root and UID/GID1000. Regular files and
directories, SH/EX, three alias forms and libc/raw high argument words retain
their locks while independent queued children stay asleep until explicit
unlock. Blocking/NB repetition, both actual conversions and final-close
release are positive controls. Private scheduling copies alone yield 32 times
after real release: baselines expose 792 ARM/790 x86 failures; ordinary and
window candidates plus actual same-ELF Linux references pass. Two 200-cycle
cohorts measure mixed file/directory repetition/conversion/close storage in
both candidate profiles. The uninstrumented baseline is not claimed to fail
deterministically. See the [repetition receipts and limits](../../docs/linux-posix-qualification.md#same-kind-flock-ownership).

The `fcntlsig` case qualifies existing F_SETSIG/F_GETSIG configuration with
4,720 native controls per architecture as root and UID/GID 1000. Six ordinary
source classes and three alias forms exercise signal boundaries, native
upper words, musl setters, ignored getter arguments, O_PATH/missing sources,
zero/eight descriptor limits and replacement 66. Independent opens retain
their own setting; metadata/flags/owners/cursors/bytes/AB queues stay intact.
Two 200-cycle setter/refusal/alias-close cohorts remain flat. Identical native
probe C/ELFs pass actual Linux 6.12.51. The dispatch wrapper already imports
low32 scalar words, so this qualification adds no kernel change or bug claim.
Actual SIGIO/queued-signal delivery and asynchronous readiness remain
unqualified. See the [receipts and limits](../../docs/linux-posix-qualification.md#native-fcntl-signal-configuration).

The `fcntlowner` case checks Linux owner command numbers and target errors
with 7,190 native controls per architecture as root and UID/GID1000. Scalar
and extended updates verify zero/live self targets, ESRCH for missing targets,
INT_MIN EINVAL, kind/pointer/descriptor precedence, shared alias state and
raw/libc getters. Upper words, O_PATH, reduced limits, replacement and real
file/queue/cursor state are covered. Both baselines fail 2,736 controls; patched
Vinix and the identical native ELF on actual Linux 6.12.51 pass. Two 200-cycle
cohorts keep storage flat. Actual SIGIO and retained target identity are
unqualified. See [receipts and limits](../../docs/linux-posix-qualification.md#native-fcntl-owner-commands-and-target-errors).

The `ownerquery` case checks attached owner kinds and caller PID namespaces
with 2,430 controls per architecture as root and UID/GID1000. Regular files,
pipe readers and UNIX stream endpoints have original/dup/CLOEXEC aliases.
Main PIDs, non-main TIDs, child reaping, joined workers, surviving leaderless
groups and shared descriptions across a one-level PID namespace exercise
zero, visible IDs and ESRCH without disturbing bytes, metadata, flags,
signals, cursors or queued AB. Raw/libc scalar and extended getters cover
native upper words and negative raw group-number decoding. Fresh bounded
task-directory snapshots establish observed worker removal after join;
cached task-path invalidation and exact exit races remain unqualified.
Two 200-cycle cohorts measure alias/update/refusal cleanup with a live worker.
Both baselines fail 1,290 controls; candidate Vinix and actual same-ELF Linux
6.12.51 pass. Earlier join-timing and cached-path setup failures are preserved.
See [receipts and limits](../../docs/linux-posix-qualification.md#native-fcntl-owner-task-kinds-and-namespaces).

The `proctask` case qualifies cached procfs task lookup with 3,384 native
controls per architecture as root and UID/GID1000 in initial/one-level PID
namespaces. Three mounts, self/numeric parents, stat/status/directory leaves
and five libc/raw open/openat forms include high words and original/dup/CLOEXEC
parent handles. Joined workers return ESRCH to independent tgkill signal-zero
queries before removal checks, without procfs polling; paths return ENOENT while main
and surviving sibling paths remain visible. An unrelated child belongs to its
own task directory; WNOWAIT zombie paths remain until reap. Retained stat and
directory aliases preserve dev/ino/mode and descriptor flags. Both baselines
fail 792 controls; candidates and actual same-ELF Linux 6.12.51 pass. Four
200-cycle cohorts keep lookup/alias cleanup storage flat. Task/mount churn,
tree reclamation, number reuse and exact concurrent detach remain unqualified.
Run `tests/linux-compat/run` with `--arch ARCH --kernel-dir DIR --state-dir FRESH`
and `--cases proctask,ownerquery,procself,open,runtime`; use
`tests/linux-compat/proctask-reference.v` with `--kernel`, `--init`, `--arch`
and a fresh `--state-dir` to run the identical probe on Linux. See
[receipts and limits](../../docs/linux-posix-qualification.md#cached-procfs-task-path-invalidation).

The `procpid` case qualifies cached numeric procfs process-root opens with
2,592 native controls per architecture as root and UID/GID1000 in initial and
one-level PID namespaces. Three mounts, stat/status/directory leaves and five
libc/raw open/openat forms cover high argument words and original/dup/CLOEXEC
root handles. Live and WNOWAIT zombie children remain visible; after waitpid
and an independent kill-zero ESRCH observation, repeated cached paths return
ENOENT without procfs polling. Surviving children, self and static/dot entries
remain reachable. Twenty-seven retained root/child aliases preserve metadata
and descriptor flags. Both baselines fail 360 controls; fixed Vinix and actual
same-ELF Linux 6.12.51 pass. Four 200-cycle lookup/alias cohorts keep storage
flat; this does not measure process/mount churn or tree reclamation. PID reuse,
concurrent reap after a positive check, inherited retired-directory lookup and
retired file contents require separate qualification.
Run `tests/linux-compat/run` with `--arch ARCH --kernel-dir DIR --state-dir FRESH`
and `--cases procpid,proctask,procself,open,runtime`; use
`tests/linux-compat/procpid-reference.v` with `--kernel`, `--init`, `--arch`
and a fresh `--state-dir` for the identical Linux probe. Superseded host build
failures have empty probe/ISO hashes and are published separately from the
actual semantic baselines. See
[receipts and limits](../../docs/linux-posix-qualification.md#cached-procfs-process-root-invalidation).

The `accessflags` case checks native faccessat2 flag words and pipe inode
owners with 6,430 controls per architecture. Root/UID1000 cohorts exercise
known/unknown lower flags, five upper-word patterns, real permissions and
path/pointer/descriptor errors, original/dup/CLOEXEC aliases, unlinked O_PATH
handles and retained metadata/owners/flags/data/cursors/queued AB. Baselines
fail 3,623 controls; final Vinix and actual same-ELF Linux 6.12.51 pass. Two
200-cycle stable-resource/alias cohorts retain flat storage. The existing
`access` case also checks low-word pipe owners and real/effective permission
differences. Run `tests/linux-compat/run` with `--arch ARCH --kernel-dir DIR`
and compact fresh `--state-dir` paths and `--cases accessflags,access,procpid,open,runtime`.
Use `tests/linux-compat/accessflags-reference.v` with `--arch`, `--kernel`,
`--init` and a fresh `--state-dir` for the identical Linux probe. Early QMP
launch failures and word-only pipe permission failures are preserved as
diagnostics. See
[receipts and limits](../../docs/linux-posix-qualification.md#native-faccessat2-flag-words-and-pipe-owners).

The `pipeabi` case checks native pipe2 flag words and real errors as root and
UID/GID1000. Four ordinary flag combinations, ten invalid lower words, five
upper register patterns and eight output-pointer forms cover aligned and
unaligned results, nil, inaccessible, readonly and page-crossing memory.
Original/dup/CLOEXEC aliases check raw 64-bit F_GETFL, inode owners/identity,
FD flags, nonblocking EAGAIN, byte transfers and EOF. Retained regular data,
cursor, queued AB and the original 64 descriptor slots stay unchanged.
Both baselines fail 3,904 of 4,186 native controls; fixed Vinix passes.
The same musl ELF passes 3,546 ordinary-pipe/error controls on Linux6.12.51.
The 640 extra native controls separately verify EOPNOTSUPP for unimplemented
packet O_DIRECT and ENOPKG for notification O_EXCL. Linux deliberately skips
that row; these errors do not establish packet/watch-queue support.
Two 200-cycle finite pipe creation/alias/transfer/close and refusal cohorts
keep all slabs and large pages flat. Run `tests/linux-compat/run` with
`--arch ARCH --kernel-dir DIR --state-dir FRESH` and
`--cases pipeabi,accessflags,access,open,runtime`; keep the state path compact
for the QMP socket limit. Use `tests/linux-compat/pipeabi-reference.v` with
`--arch`, `--kernel`, `--init` and a fresh `--state-dir` for the identical ELF
on Linux. Descriptor exhaustion cleanup, concurrent publication/closure,
limit/pointer precedence and F_SETFL packet mode require separate work. See
[receipts and limits](../../docs/linux-posix-qualification.md#native-pipe2-flag-words-and-errors).

The `pipepair` case qualifies native pipe construction under descriptor
pressure. Root/UID1000 cohorts lower the soft limit to 48/64, fill available
slots, and reopen zero through three nonadjacent holes. Four ordinary flags,
five upper-register patterns and seven aligned/unaligned/fault outputs check
actual return/error behavior, immediate descriptor state, output canaries and
filler restoration. Successful pairs select the two lowest holes, retain
original/dup/CLOEXEC aliases and pass inode/owner/status/FD flags, EAGAIN,
ABC transfers and EOF. Original regular data/cursor, nine aliases, queued AB
and 64 descriptor slots survive. Baselines leak a reader on each one-slot
refusal, failing 560 of 8,986 controls per architecture; corrected Vinix and
the identical ELF on actual Linux6.12.51 pass all rows. Two 200-cycle pressure,
copy-fault and success/alias cohorts retain exactly flat storage.
Run `tests/linux-compat/run` with `--arch ARCH --kernel-dir DIR --state-dir FRESH`
and `--cases pipepair,pipeabi,access,open,runtime`. Use
`tests/linux-compat/pipepair-reference.v` with `--arch`, `--kernel`, `--init`
and a fresh `--state-dir` for Linux. These limits are below the initial 1,024
table slots; growth, allocation-budget refusal and concurrent limit changes
remain unqualified. User-copy publication/rollback races and nil-versus-limit
precedence are separate. See
[receipts and limits](../../docs/linux-posix-qualification.md#native-pipe-construction-under-descriptor-pressure).

The `pipenull` case extends the pressure matrix with nil output pointers.
Root/UID1000 cohorts at limits 48/64 check zero through three free slots,
four ordinary flags, five upper words and eight destinations. Exact error
precedence, immediate descriptor state, canaries/refill, real pair transfers
and retained bank state pass 10,266 checks per architecture on corrected
Vinix and same-ELF Linux 6.12.51. Baselines fail 160 nil-output errno checks.
Two 200-cycle cohorts include nil EMFILE before slot installation and nil EFAULT
cleanup after both slots are installed, plus successful pairs and cross-page
faults; all slab/large-page storage remains flat. Run the suite with
`--cases pipenull,pipepair,pipeabi,access,open,runtime` and use
`pipenull-reference.v` for the matching native ELF on actual Linux.
Growth/budget injection, concurrent limit/close and output-copy rollback
races, legacy x86 pipe and GNU/foreign paths remain separate. See
[receipts and limits](../../docs/linux-posix-qualification.md#native-pipe2-null-output-error-precedence).

The `pipecmd` case qualifies F_GETPIPE_SZ/F_SETPIPE_SZ nonpipe EBADF and
real anonymous pipe/FIFO capacities. Root/UID1000 cohorts check nine source
classes, original/dup/CLOEXEC/fixed aliases, native words, ignored arguments,
libc, invalid descriptors, reduced limits and reuse. All 3,172 controls pass
per architecture on corrected Vinix and the identical ELF on Linux6.12.51;
original baselines fail 1,724 wrong-error checks. Final metadata, flags,
regular XYZ/cursor1, queued AB/CD/GH and 80 slots remain intact. Same-capacity
setters preserve occupied buffers. Two 200-cycle alias/query/close cohorts
keep every slab and large-page count flat after removing measured per-call
interface boxes. The separate errno-only kernel's storage failures and
allocation-tracked call chains remain visible in the report.
Run `--cases pipecmd,fcntlabi,fcntlpath,open,runtime` and use
`pipecmd-reference.v --arch ARCH --kernel LINUX --init NATIVE-PROBE-ELF
--state-dir FRESH-DIR` for Linux. The reference CPIO supplies `/dev/null`.
Actual resizing, occupancy/ceiling/budget behavior, concurrent close/reuse,
GNU and foreign paths remain separate. See
[receipts and limits](../../docs/linux-posix-qualification.md#native-pipe-only-fcntl-type-errors).

The `pipesize` case qualifies native-page rounding and the effective
CAP_SYS_RESOURCE pipe-growth ceiling on both architectures. Four independent
root/UID1000 capability cohorts run8,060 total checks per architecture,
covering real anonymous/FIFO resizing, aliases, overflow/type errors,
upper-register arguments, low limits/reuse, metadata/flags/cursors, queued
bytes and wrapped/full-ring data. The original kernels fail 3,144 ARM/1,404 x86
checks, the separately committed rounding fix leaves 376 capability failures
on each, and corrected Vinix plus the exact same ELF on Linux 6.12.51 pass.
Each final 200-cycle resizing cohort keeps every slab class and large-page
count flat. Run `--cases pipesize,pipecmd,fcntlabi,keepcaps,capset,open,runtime`;
`pipesize-reference.v --arch ARCH --kernel LINUX --init NATIVE-PROBE-ELF
--state-dir FRESH-DIR` runs the Linux oracle. The qualification report binds
the V audit, preparation diagnostics, six builds, source/C/ELF identities,
independent lifetime review and fresh memory/desktop controls. Fragmented
page-slot occupancy, page quotas/sysctls, concurrent resizing, budget
injection, larger privileged allocations and GNU/foreign paths remain open.

The `schedabi` case checks signed32 native PID/policy words and legacy
scheduler parameter errors on both architectures. Two root/UID1000
cohorts run 5,476 checks, including 4,600 kernel-facing/state controls and
876 deliberate ENOSYS refusals from the bundled musl's legacy process
wrappers. The raw setup uses actual syscalls. Six PID classes, five word
patterns, nine parameter destinations, invalid policy 8, BATCH/OTHER
transitions, real priority bounds and guards check exact errors and retained
policy/priority. Original kernels fail 2,460 checks, the separately committed
error fix leaves 1,308 word failures, and decoded kernels plus identical
Linux 6.12.51 ELFs pass. Both 200-cycle credential cohorts retain flat storage.
Run `--cases schedabi,runtime,capabi,open,fcntlabi` with a fresh state directory.
`schedabi-reference.v --arch ARCH --kernel LINUX --init NATIVE-PROBE-ELF
--state-dir FRESH-DIR` runs the Linux oracle. Compile `schedabi-check.v`
without `-prod` and pass the retained evidence directory to audit the
captured original/error-only/decoded/reference artifacts and negative
controls. [The report](../../docs/linux-posix-qualification.md#native-scheduler-scalar-words-and-error-precedence)
publishes setup/oracle diagnostics, independent lifetime review and the
existing AArch64 small-QoS CPU-affinity blocker. Realtime/deadline, capability/
limit/reset rules, SCHED_EXT, target races, namespaces/pledge, RR/attribute/
affinity argument ABIs and GNU/foreign paths remain separate.

The `schext` case qualifies Linux SCHED_EXT priority metadata separately
from class availability. Root/UID1000 children check sixteen policies,
both priority bounds, six raw words and actual musl wrappers: 450 controls
per architecture. Only 28 EXT queries fail on the original kernels;
corrected Vinix and identical probe ELFs on Linux 6.12.51 pass all rows.
Reserved/unknown/negative/reset-flagged policies retain EINVAL, FIFO/RR
retain 1/99 bounds, and queries retain observed policy/priority. Two warmed
200-cycle cohorts keep every slab/large-page count flat. Run
`--cases schext,runtime,schedabi,open,fcntlabi` with fresh state directories.
`schext-reference.v --arch ARCH --kernel LINUX --init NATIVE-PROBE-ELF
--state-dir FRESH-DIR` executes the Linux oracle; compile `schext-check.v`
without `-prod` and pass the retained evidence directory to audit the
captured artifacts and negative controls. [The report](../../docs/linux-posix-qualification.md#native-sched_ext-priority-metadata)
binds four builds, exact C scope, compiler/source/ELF pins, lifetime review
and the failed standalone-helper preparation. Installing or running a
SCHED_EXT/BPF scheduler, permission rules, GNU/foreign paths and the
AArch64 multi-CPU QoS blocker remain open.

The `rrabi` case qualifies native `sched_rr_get_interval` PID decoding and
task-before-output error precedence. Root/UID1000 children make 998 controls
per architecture: six PID targets, seven raw register-word forms, ten guarded
output forms and genuine musl wrapper calls. Both cohorts query a real RR
task at priority1 before returning to OTHER. Vinix retains its 5ms RR quantum
and zero OTHER interval; Linux references validate normalized timespecs and
positive RR intervals without requiring configuration-dependent durations
to match. Original kernels fail 520 checks; corrected kernels and identical
ELFs on Linux 6.12.51 pass every row. Two warmed 200-cycle query cohorts keep
all slab/large-page counts flat. Run
`--cases rrabi,runtime,schedabi,schext,open,fcntlabi` in a fresh state directory.
`rrabi-reference.v --arch ARCH --kernel LINUX --init NATIVE-PROBE-ELF
--state-dir FRESH-DIR` executes the Linux oracle. Compile `rrabi-check.v`
without `-prod` and pass the retained evidence directory to audit original,
corrected and reference artifacts, compiler/source/C/ELF pins and executing
negative controls. [The report](../../docs/linux-posix-qualification.md#native-rr-interval-pid-words-and-output-errors)
publishes the independent lifetime review and retained dependency limits.
Scheduling-class timing, cross-task policy/permissions/races, attribute and
affinity ABIs, GNU/foreign paths and the broad compatibility gates remain open.

The `attrquery` case qualifies native `sched_getattr` PID/size/flag handling,
exact 48–57-byte prefixes, native page caps and full advertised user ranges.
Separate root/UID1000 children cover six targets, sixteen sizes, ten buffers,
flags 0/1, upper-word controls, real RR/BATCH state and user-half boundaries:
15,406 checks per architecture. Originals fail 3,040; corrected kernels and
identical probe ELFs on Linux 6.12.51 pass all rows. Both 200-cycle cohorts
retain flat storage. Run `--cases attrquery,runtime,schedabi,rrabi,open,fcntlabi`
with a fresh state directory. `attrquery-reference.v --arch ARCH --kernel
LINUX --init NATIVE-PROBE-ELF --state-dir FRESH-DIR` runs the Linux oracle;
compile `attrquery-check.v` without `-prod` and pass the retained evidence
directory to audit counts, ranges, source/C/ELF pins and actual negative
controls. [The report](../../docs/linux-posix-qualification.md#native-scheduling-attribute-query-prefixes-and-errors)
publishes the initial x86 reserved-top-page setup failure, final receipts,
storage measurements and independent lifetime review. Setter semantics,
other state/permission/race controls, GNU/foreign paths and broad gates remain open.

The `attrimport` case qualifies the native `sched_setattr` input contract:
signed32 PIDs, entry errors, zero-size compatibility, exact short imports,
page bounds, best-effort size writebacks and zero-only extensions. Root and
UID1000 cohorts combine six targets, sixteen sizes, twelve input forms,
flags and upper words, plus negative policy/short clamp/unknown flag controls:
18,510 checks per architecture. BATCH/OTHER state and input guards are checked
after every call. Original kernels fail 5,324; corrected kernels and identical
ELFs on Linux 6.12.51 pass. Both 200-cycle cohorts retain flat storage.
Run `--cases attrimport,runtime,schedabi,rrabi,attrquery,open,fcntlabi` with
a fresh state directory. `attrimport-reference.v` accepts the same arguments
as the preceding reference controller; compile `attrimport-check.v` without
`-prod` and pass the retained evidence directory. [The report](../../docs/linux-posix-qualification.md#native-scheduling-attribute-import-contract)
publishes the initial disk-full builds and corrected read-only page-crossing
oracle as preparation, final receipts and independent lifetime review.
Nice clamping, full scheduling flags/classes/permissions and GNU/foreign
paths remain separate; the three broad compatibility gates stay open.

The `affabi` case qualifies native affinity PID/length words, short masks,
getter bit-count overflow and stable-peer owner/CAP_SYS_NICE permissions.
Root/UID1000 cohorts exercise real worker TIDs, a UID1001 peer, eight target
classes, nineteen lengths, ten buffers, upper words and genuine musl wrappers:
49,416 checks per architecture. Original kernels fail 27,868; corrected kernels
and identical probe ELFs on Linux 6.12.51 pass. Exact native eight-byte masks
are distinguished from measured Linux bitmap widths, including the x86
reference's 32 bytes. Each cohort restores masks/capabilities and retains flat
storage through 200 cycles. Run `--cases affabi,runtime,schedabi,rrabi,attrquery,attrimport,open,fcntlabi`
in a fresh state directory. `affabi-reference.v`
accepts the same arguments as preceding reference controllers; compile
`affabi-check.v` without `-prod` and pass the retained evidence directory.
[The report](../../docs/linux-posix-qualification.md#native-affinity-masks-argument-words-and-stable-peer-permissions)
publishes width-oracle/compile/disk-space preparations, final receipts and
independent lifetime review. Target/credential races, namespaces/security,
hotplug/cpusets/large masks, actual migration/fairness and GNU/foreign paths
remain separate; the three broad compatibility gates remain open.

The `attrnice` case qualifies native `sched_setattr` nice normalization and
admission for single-thread process leaders. OTHER/BATCH apply clamped nice
values using target RLIMIT_NICE and effective CAP_SYS_NICE; UID0 alone has
no privilege bypass, default limits are 0/0 and IDLE/FIFO/RR ignore nice.
Root/UID1000 cohorts use six target classes, twelve nice values, four input
forms, three self limits, capability off/on and upper-word controls, plus
nonfair/legacy/layout/error-ordering/state checks: 29,310 per architecture.
Original kernels fail 9,366; corrected kernels and identical ELFs on Linux
6.12.51 pass. Genuine musl getpriority observes each live operation. A
privileged broker restores every live target after either success or error;
peer processes, pipes and guarded mappings have explicit cleanup. Both
warmed 200-cycle cohorts retain flat storage. Run
`--cases attrnice,runtime,schedabi,rrabi,attrquery,attrimport,affabi,fcntlabi`
with a fresh state directory. `attrnice-reference.v` accepts the preceding
reference controller arguments; compile `attrnice-check.v` without `-prod`
and pass the retained evidence directory. [The report](../../docs/linux-posix-qualification.md#native-scheduling-attribute-nice-normalization-and-admission)
binds exact cohort failures, source/C/ELF/compiler pins, production builds,
storage, executing negative controls and independent lifetime review. Eight
cases pass across primary/completion/recovery receipts; missing initial aggregates
and the failed x86 descriptor ISO build remain explicit. Nice remains process-wide in Vinix; pthread nice, races, complete realtime/deadline/
reset/clamp behavior and GNU/foreign paths remain separate. The three broad
compatibility gates remain open.

The `rtadmit` case qualifies realtime admission through native
`sched_setscheduler`, `sched_setparam` and `sched_setattr` for single-thread
process leaders. The target's `RLIMIT_RTPRIO` controls admission; retaining or
lowering its current priority remains allowed above the limit, and changing RT
policy with a zero target limit needs effective `CAP_SYS_NICE`. Root and UID1000
each execute `5400/1440/7680/1039` controls, or 31,118 per architecture. Same-owner
and cross-owner peers have different limits, five real initial policy/priority
states are set by a privileged broker, and every live call checks and restores
actual state. Guarded inputs, negative/absent/reaped PIDs, upper syscall words,
real errors, untouched buffers and genuine musl getpriority observations are
included. Originals fail 1,312; corrected Vinix and identical ELFs on Linux
6.12.51 pass, with two flat warmed 200-cycle storage cohorts. Run
`--cases rtadmit,runtime,schedabi,rrabi,attrquery,attrimport,attrnice,fcntlabi`
with a fresh state directory. `rtadmit-reference.v` accepts the preceding
reference controller arguments; compile `rtadmit-check.v` without `-prod` and
pass the retained evidence directory. [The report](../../docs/linux-posix-qualification.md#native-realtime-scheduling-admission)
binds receipts, source/C/ELF/compiler pins, actual auditor negative controls and
independent lifetime review. Thread/credential/limit races, idle-exit/reset/
deadline/timing, security configurations and GNU/foreign paths remain separate.
The three broad compatibility gates remain open.

The `idleexit` case qualifies stable single-thread leader exits from IDLE using
target current nice and RLIMIT_NICE, independently of caller limits/requested
nice. Effective CAP_SYS_NICE and owner admission remain real; setparam on IDLE
stays allowed, and RT destinations also require target RTPRIO admission.
Root/UID1000 each perform `3780/896/3584/4244` controls (25,008 per architecture),
with guarded inputs, upper words, peer limits, imported nice and real state.
Originals fail 632; corrected Vinix and identical ELFs on Linux 6.12.51 pass.
Two warmed 200-cycle cohorts retain flat storage. Run
`--cases idleexit,runtime,schedabi,rrabi,rtadmit,attrimport,attrnice,fcntlabi`
with a fresh state directory. `idleexit-reference.v` accepts the preceding
reference arguments; compile `idleexit-check.v` without `-prod` and pass the
retained evidence area. [The report](../../docs/linux-posix-qualification.md#native-idle-scheduling-exit-permissions)
binds first compile/native setup failures separately from final identities.
Broker setup uses canonical signed64 setpriority words; setpriority signed32/
permission/group semantics and RT getattr nice remain separate gaps. Worker
threads, races, security/reset/deadline/timing and GNU/foreign paths remain
unqualified, and the three broad compatibility gates remain open.

The `attrclass` case qualifies class-specific scheduling queries for stable
single-thread leaders. FIFO/RR priorities 1/99 report sched_attr nice 0 despite
retained actual nice -20/-1/0/1/19; OTHER/BATCH/IDLE report the actual nice.
Root/UID1000 cohorts query without effective CAP_SYS_NICE, including same/cross-
owner peers, guarded short/full/unaligned/page-tail outputs, upper argument words
and real EINVAL/ESRCH/EFAULT behavior. Each architecture runs 24,016 controls;
originals fail 9,248 and corrected Vinix plus identical ELFs on Linux 6.12.51 pass.
Two warmed 200-cycle query cohorts retain flat slabs/pages. Run
`--cases attrclass,runtime,schedabi,rrabi,attrquery,attrnice,rtadmit,idleexit`
with a fresh state directory. `attrclass-reference.v` uses the preceding reference
arguments; compile `attrclass-check.v` without `-prod` and supply the retained
evidence area. [The report](../../docs/linux-posix-qualification.md#native-realtime-scheduling-attribute-queries)
binds exact fields/errors/state, compiler/source/C/ELF/receipt hashes and independent
lifetime review. Reference fair slice/clamp defaults remain configuration fields.
Canonical signed64 broker setup is explicit; setpriority signed32/admission/group
semantics, worker nice/races, deadline/reset/utilization/security and GNU/foreign
paths remain separate. The three broad compatibility gates remain open.

The `niceabi` case qualifies PRIO_PROCESS getpriority/setpriority signed32
selector/target/nice words and negative-target ESRCH for stable process leaders.
Root/CAP_SYS_NICE and UID1000/no-capability zero-limit cohorts cover seven word
forms, eight target kinds, three policies, clamped nice boundaries, genuine musl
calls, exact errors and retained raw/musl nice and scheduling state. Each
architecture runs 13,214 controls; originals fail 2,898, corrected Vinix and
identical ELFs on Linux 6.12.51 pass. Two warmed 200-cycle cohorts stay flat.
Run `--cases niceabi,runtime,attrclass,attrnice --timeout 900` with a fresh state
directory. `niceabi-reference.v` uses the preceding reference arguments; compile
`niceabi-check.v` without `-prod` and supply the retained evidence area.
[The report](../../docs/linux-posix-qualification.md#native-priority-argument-words-and-missing-target-errors)
binds one actual failed ARM C preparation separately from final four-alloca
probe identities, real Linux references, storage, receipts and independent review.
The first ARM runtime ISO preparation also fails for disk space; its real failure
receipt and initial watcher assertion remain bound alongside a fresh runtime-only
completion with unchanged kernel/source/C/ELF. Passing cases are retained.
PRIO_PGRP/PRIO_USER, full capability/limit admission, worker nice/races/security,
GNU/translated/ELF32 priority paths and the three broad gates remain open.

The `niceadmit` case qualifies PRIO_PROCESS setpriority effective CAP_SYS_NICE
and target RLIMIT_NICE admission for stable process leaders. Root and UID1000
cohorts exercise both capability states, six target limits, opposite caller
limits, four live target forms, three policies and raw/upper-word/genuine musl
setters. Each architecture runs 40,196 controls; originals fail 10,692, corrected
Vinix and identical ELFs on Linux 6.12.51 pass. Two warmed 200-cycle cohorts stay
flat. Run `--cases niceadmit,runtime,niceabi,attrnice --timeout 900` with a fresh
state directory. `niceadmit-reference.v` uses the preceding reference arguments;
compile `niceadmit-check.v` without `-prod` and supply the retained evidence area.
[The report](../../docs/linux-posix-qualification.md#native-priority-capability-and-target-limit-admission)
binds the actual failed initial preflight separately from final five-alloca
probe identities, fresh builds, both Linux references and independent review.
Nice remains process-wide; group/user selectors, worker nice, concurrent
credential/limit/target races, namespace/security configurations and GNU/foreign
priority paths remain separate. The three broad gates remain open.

The `randomflags` case qualifies seeded native getrandom flag rejection and
buffer/error precedence. Root/UID1000 each exercise canonical/upper-word/raw
and genuine musl requests, six destination forms, zero/huge invalid counts and
accepted bounded requests with preserved guards. Each architecture runs 7,056
controls; originals fail exactly 864, corrected kernels and identical ELFs on
Linux 6.12.51 pass. Two warmed 200-cycle invalid/zero paths remain flat. Run
`--cases randomflags,runtime,niceadmit --timeout 900` in a fresh state directory.
`randomflags-reference.v` uses the preceding reference arguments; compile
`randomflags-check.v` without `-prod` and supply the retained evidence area.
[The report](../../docs/linux-posix-qualification.md#native-getrandom-flag-validation)
binds complete source/C scope, real errno/data guards, four-alloca probe identity,
Linux references and exact retained inputs. Entropy quality, unseeded blocking,
interruption, partial faults, large valid requests and GNU/foreign paths remain
separate; the three broad section 15 gates stay open.

The `randomcopy` case qualifies seeded getrandom partial-copy accounting across
PROT_NONE/read-only/unmapped suffixes, root/UID1000, six valid flags and raw/musl
calls. The common native/Linux oracle requires a positive short count bounded
by the accessible prefix and intact guards outside that prefix. ARM Linux may
stop copying early or modify additional accessible bytes beyond its conservative
return after a faulting store. The native storage cycle requires exact
complete-prefix returns. `randomcopy-reference.v` boots the unchanged probe ELF
on supplied Linux kernels. Compile `randomcopy-check.v` without `-prod` and
pass the retained evidence area to audit compiler/build/source/C/input identities,
real receipts, original failures, guarded transfers, flat storage and executing
negative controls. Both stricter exploratory ARM reference failures and a
controller restart recovery remain published. See the [partial-copy report](../../docs/linux-posix-qualification.md#native-getrandom-partial-copy-faults).

The `randomrange` case qualifies seeded getrandom request capping and complete
range errors before output, including invalid zero-count addresses. It uses
fixed 4GiB and discovered-ceiling guarded arenas, six accepted flags, raw/musl
calls, positive bounded partial results and unchanged canaries. The same ELF
runs through `randomrange-reference.v` on supplied Linux kernels. Compile
`randomrange-check.v` without `-prod` and pass its retained evidence area to
verify actual original failures, native/reference outcomes, source/C/build and
compiler identities, seven primary source pins, flat storage, exact retained
inputs and executing audit controls. The initial compile refusal remains
separate from guest evidence. See the [request-range report](../../docs/linux-posix-qualification.md#native-getrandom-request-ranges).

The `randomsignal` case checks large seeded getrandom calls interrupted by a
one-shot timer, the syscall result saved in its signal frame, complete small
requests, already pending blocked signals, SA_RESTART, six flags and raw/musl
calls. Output after a short result must remain untouched. Native repeated
page+1 calls check flat slab/page storage. The same ELF runs through
`randomsignal-reference.v` on supplied Linux kernels. Compile
`randomsignal-check.v` without `-prod` and supply the retained evidence area to
verify original failures, native/reference outcomes, complete C scope, compiler
and dispatch pins, executing audit controls and real diagnostic refusals.
The final ARM run explicitly reuses byte-verified frozen objects/ELFs after
shared SDK loss; it does not claim a fresh C compilation. See the
[signal-interruption report](../../docs/linux-posix-qualification.md#native-getrandom-signal-interruption).

The `groupabi` case checks getpgid/getsid/setpgid signed 32-bit argument words,
negative-ID errors and precedence, successful child group changes, retained
caller/child/outside-session identities and zombie/reaped queries. It runs
5,760 controls per architecture as root and UID/GID1000, plus two warmed
200-cycle mutation/query/error storage cohorts. `groupabi-reference.v` boots
the unchanged probe ELF on supplied Linux kernels. Build `groupabi-check.v`
without `-prod` and give it the evidence directory to verify actual original
failures, native/reference results, whole-C scope, compiler/SDK/inventory pins,
real diagnostic refusals and executing audit controls. The initial Linux setup
refusal is retained; a PID1 group/session of zero is valid. See the
[group/session report](../../docs/linux-posix-qualification.md#native-process-group-and-session-argument-words).

The `grouptid` case qualifies live/retired worker getpgid/getsid lookup, exact
setpgid nonleader EINVAL, real child group changes and worker callers. Root
and UID/GID1000 in initial and one-level PID namespaces run 14,464 controls
per architecture plus four warmed 200-cycle storage cohorts. Seven raw word
forms and genuine musl calls share the same oracle as Linux. Supply the native
ELF to `grouptid-reference.v`; build `grouptid-check.v` without `-prod` and
pass the retained evidence area to verify original failures, native/reference
results, exact whole-C scope, SDK/compiler/input pins, independent lifetime
review and executing audit controls. See the
[worker lookup report](../../docs/linux-posix-qualification.md#native-worker-process-group-and-session-lookup).

The `grouporder` case checks setpgid child-session eligibility before the
executed-child refusal, preserving same-session EACCES, non-child ESRCH and
negative-group EINVAL. Six held child/grandchild targets include actual exec;
11,520 controls per architecture run as root/UID1000 in initial and one-level
PID namespaces, with real group changes, retained state and flat 200-cycle
refusal paths. `grouporder-reference.v` boots the unchanged native ELF on Linux.
Compile `grouporder-check.v` without `-prod` and pass its evidence area to verify
original failures, native/reference results, exact one-function C scope,
compiler/SDK/input pins, initial compile refusals and executing audit controls.
See the [session/exec report](../../docs/linux-posix-qualification.md#native-process-group-session-and-exec-error-precedence).

The `groupzombie` case qualifies completed zombie setpgid targets and groups
whose only member is a zombie. Root/UID1000 cohorts in initial and one-level
PID namespaces run 17,152 controls per architecture. WNOWAIT and pidfd POLLIN
establish completed exit; real mutations affect wait-group selection, live
children join/leave the zombie-only group, and reaped identities get exact
errors. Four warmed 200-cycle cohorts alternate upper-word/raw and real musl
mutations, joins and refusals. `groupzombie-reference.v` boots the unchanged
native ELF on Linux. Compile `groupzombie-check.v` without `-prod` and supply
its evidence area to verify original failures, native/reference results,
whole-C scope, compiler/SDK/input pins, lifetime review and executing audit
controls. Incomplete teardown and lifecycle races remain outside this stable
contract. See the [zombie-group report](../../docs/linux-posix-qualification.md#native-completed-zombie-process-groups).

The `waitabi` case qualifies native wait4/waitid low32 scalar imports,
INT_MIN ESRCH after option validation, live/zombie group selection, WNOWAIT
and exact errors. Root/UID1000 in initial and one-level PID namespaces run
118,272 controls per architecture with independently varied raw register
forms and genuine musl calls, plus four flat 200-cycle storage cohorts.
`waitabi-reference.v` boots the unchanged native ELF on Linux. Compile
`waitabi-check.v` without `-prod` and supply its evidence area to verify
original failures, final native/reference results, whole-C scope, compiler/SDK/
input pins, preserved failed exploratory copyout oracles and executing audit
controls. Empty/error siginfo copyout has separate `waitempty` qualification;
consuming wait4 copy faults remain open.
See the [wait ABI report](../../docs/linux-posix-qualification.md#native-wait-selectors-and-scalar-argument-words).

The `waitempty` case qualifies waitid no-event/error output: six cleared fields,
preserved padding/tail, EFAULT priority, NULL and unused rusage, read-only and
inaccessible pointers, every guard cut0..32 plus64/127/128, real WNOWAIT/reaped
controls and flat storage. Four root/UID1000 initial/one-level PID namespace
cohorts run 38,400 controls per architecture. `waitempty-reference.v` boots
the unchanged native ELF on Linux. Compile `waitempty-check.v` without `-prod`
and supply its evidence area to verify guest failures/results, whole-C scope,
compiler/SDK/inventory pins, retained hidden-allocation compile refusals and
executing audit controls. Successful-event output and consuming faults retain
separate limits. See the [empty/error output report](../../docs/linux-posix-qualification.md#native-waitid-empty-and-error-siginfo-output).

The `waituid` case qualifies child real UIDs for stopped, continued, exit37
and SIGKILL events. Four credential profiles per root/UID1000 cohort in
initial/one-level PID namespaces include different real/effective/saved IDs
and UID4294967294. Its 13,952 controls per architecture cover three selectors,
eight raw/musl forms, unaligned output, NULL/valid rusage, WNOWAIT, consuming
waits, cleared no-event/ECHILD and NULL infop, plus four flat200-cycle cohorts.
`waituid-reference.v` boots the unchanged native ELF on Linux. Compile
`waituid-check.v` without `-prod` and supply its evidence area to verify
original failures, native/reference results, whole-C scope, compiler/SDK/input
pins, initial host-helper refusal and executing audit controls. Mapped user
IDs, credential races, siginfo padding, accounting and consuming copyout faults
retain separate limits. See the [child real-UID report](../../docs/linux-posix-qualification.md#native-waitid-child-real-uid).

The `waitevent` case qualifies successful child-event siginfo fields and
preserved padding/tail, plus stable ordered copyout faults. Four root/UID1000
initial/one-level PID namespace cohorts run 156,800 controls per architecture
across four credential profiles and stop/continuation/exit37/SIGKILL, three
selectors, eight raw/musl forms, WNOWAIT with/without WNOHANG, mapped offsets,
NULL/valid rusage, all guard cuts 0..32 plus 64/127/128, invalid pointers and
consuming/cleared controls. Four warmed 200-cycle storage cohorts stay flat.
`waitevent-reference.v` boots the unchanged native ELF on Linux. Compile
`waitevent-check.v` without `-prod` and supply its evidence area to verify
original failures, native/reference results, whole-C scope, compiler/SDK/input
pins and executing audit controls. Consuming copyout faults, rusage-fault
ordering/aliasing/accounting and mapping/credential races retain separate
limits. See the [event-field report](../../docs/linux-posix-qualification.md#native-waitid-child-event-siginfo-writes).

The `waitusage` case qualifies rusage-before-siginfo output ordering: failed
rusage skips siginfo stores, earlier rusage survives later siginfo faults,
and siginfo fields win in seven overlapping layouts plus an adjacent control.
Four root/UID1000 initial/one-level PID namespace cohorts and four credential
profiles run 310,400 controls per architecture across stop/continuation/exit37/
SIGKILL, three selectors, eight raw/musl forms, WNOWAIT with/without WNOHANG,
mapped offsets, thirteen partial-rusage cuts, all siginfo cuts0..32 plus64/127/
128, invalid pointers and consuming/cleared unused-rusage controls. Four warmed
200-cycle storage cohorts stay flat. `waitusage-reference.v` boots the unchanged
native ELF on Linux. Compile `waitusage-check.v` without `-prod` and supply its
evidence area to verify original failures, native/reference results, whole-C
scope, compiler/SDK/input pins and executing audit controls. Consuming faults,
exact partial-rusage counts/accounting and arbitrary aliases remain separate.
See the [copyout-order report](../../docs/linux-posix-qualification.md#native-waitid-rusage-and-siginfo-copyout-order).

The `waitconsume` case qualifies wait4/waitid event consumption after status,
siginfo or rusage copyout faults and waitid WNOWAIT retention. It creates one
child/event per trial, observes readiness without consuming it, and requires
pidfd POLLIN for exit/SIGKILL events. Four root/UID1000 initial/one-level PID
namespace cohorts run 2,880 controls per architecture across stopped/continued/
exit37/SIGKILL, three selectors, raw upper-word/musl forms, WNOHANG variation
and wrapping/unmapped/read-only/PROT_NONE/partial-guard outputs. Subsequent
nonblocking waits must report cleared events/ECHILD or the retained identity;
cleanup also works on original kernels. Four warmed 200-cycle storage cohorts
include fork, faulting wait, normal cleanup and pidfd close. The unchanged ELF
runs on Linux with `waitconsume-reference.v`. Compile `waitconsume-check.v`
without `-prod` to verify original failures, native/reference identity, exact
source/whole-C scope, independent lifetime review, retained preboot compiler
refusals, compiler/SDK pins and executing audit negatives. Exact partial-copy
counts/accounting, incomplete exit teardown and concurrent waits stay separate.
See the [event-consumption report](../../docs/linux-posix-qualification.md#native-wait-copyout-fault-event-consumption).

The `waitstatus` case qualifies wait4 scalar status copies: stable guards with
only one/two/three writable bytes must return EFAULT without changing that
prefix, while mapped/unaligned and valid cross-page stores write exactly four
status bytes. It runs 2,496 controls per architecture across four child states,
three selectors, raw upper-word/musl calls, NULL/valid rusage, NULL/invalid
status and ignored bad outputs on no-event/EINVAL/ESRCH/ECHILD. Four root/UID1000
initial/one-level PID namespace cohorts validate child topology, pidfd readiness
for exits and event consumption after each selected wait. Four warmed 200-cycle
measurements include fork, COW preparation, status store/fault, reap and close.
`waitstatus-reference.v` boots the unchanged native ELF on Linux. Compile
`waitstatus-check.v` without `-prod` to verify native/reference results, original
failures, exact source/C scope, input/compiler/SDK pins, preserved prior evidence
clones and executing audit negatives. Concurrent stores/mapping changes and
exact accounting or partial-rusage counts remain separate. See the
[scalar-status report](../../docs/linux-posix-qualification.md#native-wait4-scalar-status-copyout).

The `robustquery` case qualifies native get_robust_list signed32 PID imports
and length-before-head scalar copyout. It checks 6,048 controls per architecture:
self/leader/pipe-blocked worker queries, distinct stored registrations, upper
register words, aligned/unaligned/cross-page outputs, 15 overlap positions, NULL
and guarded faults in either/both outputs, retired/missing targets and exact
canaries. Four root/UID1000 initial/one-level PID namespace cohorts restore
both original musl heads before join, then close every pipe/mapping. Four
warmed 200-call query cohorts measure all slab classes and big-heap pages.
`robustquery-reference.v` boots the unchanged native ELF against Linux. Compile
`robustquery-check.v` without `-prod`: it validates actual original failures,
source/C/ELF identity, final native/reference/regression verdicts, exact whole-C
scope, compiler/SDK/inventory pins, earlier refused/diagnostic profiles and
executing audit negatives. Concurrent mappings/list registration/teardown,
inspection-policy changes, robust owner death and GNU/foreign paths remain
separate. See [the robust-list query report](../../docs/linux-posix-qualification.md#native-robust-list-query-pid-words-and-ordered-scalar-output).

The `robustwake` case qualifies native pending robust-unlock and selective exit
wakes with 608 controls per architecture. Positive CMP_REQUEUE counts establish
three shared waiters, one private waiter and one neighboring waiter before
completed owner exit; exact remaining queues and a 256-byte canary model verify
wake1, ownerless word preservation and PI queue separation. Four root/UID1000
initial/one-level PID namespace cohorts rotate flags, offsets and list/pending
layouts, then require real musl robust-mutex payload recovery. Four warmed
200-cycle one-waiter cohorts measure fork/requeue/exit/drain/reap/join/close.
`robustwake-reference.v` boots the unchanged native ELF on Linux. Compile
`robustwake-check.v` without `-prod` to verify original failures, native/Linux
results, exact whole production-C scope, input/SDK/compiler pins, retained
pre-ELF refusals and executing audit negatives. Concurrent owner-word CAS,
mapping/list mutation, malformed lists, actual PI-state handover, forced sibling
exit and GNU/foreign paths remain separate. See [the robust-exit report](../../docs/linux-posix-qualification.md#native-robust-futex-pending-unlock-and-selective-exit-wakes).

The `robustcreds` case checks native robust-list READ_REALCREDS and active
CAP_SYS_PTRACE overrides, including process_vm read/write permission checks.
It runs 5,120 controls per architecture with 32 caller/target credential profiles
in each root/ordinary and initial/one-level PID namespace view. Distinct live
leader/worker heads, verified real/effective/saved IDs and capability sets,
dumpability, upper PID words, output/payload faults, canaries, target write echoes,
self-access and missing targets are checked. Four warmed 200-cycle cohorts
include whole caller/target/worker setup and cleanup. `robustcreds-reference.v`
boots the unchanged ELF on Linux; compile `robustcreds-check.v` without `-prod`
to check actual original failures, final results, exact whole-C scope, retained
refusals, SDK/compiler/inventory pins and executing negative controls. Concurrent
credentials/mappings/targets, new MAC/LSM/user-namespace policy and GNU/foreign
paths remain separate. See [the inspection report](../../docs/linux-posix-qualification.md#native-robust-list-and-process-memory-inspection-credentials).

The `tidwake` case checks native clear-child-tid notification with one shared
futex wake. It runs 384 controls across root/UID1000 and both PID namespace
views: five registration modes, four initial words, two offsets, admitted
one/three shared waiters, private/abandoned queue isolation, complete two-page
canaries and real musl joins. A raw owner worker exits while its leader stays
alive; worker ESRCH and leader liveness precede exact queue drains, then the
leader exits and is reaped. Four warmed 200-cycle cohorts measure complete
owner/worker/observer cleanup with one shared waiter per trial.
`tidwake-reference.v` boots the unchanged ELF on Linux; compile
`tidwake-check.v` without `-prod` to verify original failures, final results,
whole-C scope, retained refusals, SDK/compiler/inventory pins and executing
negative controls. See [the TID exit report](../../docs/linux-posix-qualification.md#native-clear-child-tid-selective-exit-wakes) for the raw-exit workflow and qualification limits.

The `tidfault` case checks clear-child-tid notification after a failed zero
store: readable MAP_SHARED direct/alias addresses still wake one waiter;
PROT_NONE, unmapped and read-only private anonymous addresses retain their
queues. Its 384 controls per architecture establish one/three shared waiters
before changing access, verify actual process_vm read/write results, retire
the raw worker while its leader lives, restore access and count every remaining
waiter. Private/neighbor queues and complete two-page parent/conductor canaries
must survive. Four warmed 200-trial cleanup cohorts keep three shared waiters
per trial. Use `--cases tidfault --timeout 1500` with a fresh state directory.
`tidfault-reference.v` boots the unchanged ELF on Linux; compile
`tidfault-check.v` without `-prod` to audit original failures, final results,
exact whole-C scope, SDK/compiler/inventory pins and executing negative controls.
See [the fault-notification report](../../docs/linux-posix-qualification.md#native-clear-child-tid-store-fault-notifications)
for the raw-exit workflow and remaining limits.

The supplementary `tidfault-perf-check.v` auditor checks completed operation,
churn/cache and idle/apps/drag logs from the desktop performance harness against
its saved JSON and the same corrected ARM kernel. Compile without `-prod`,
adding `tests/desktop-perf` to V's module path. It retains the strict auditor's
actual refusal and explicitly reports the single observed EXT2 rename retention
finding; its evidence-integrity pass leaves general retention qualification
open. Desktop/application lifecycle qualification remains separate.

The `tidlast` case checks clear-child-tid suppression for the last address-space
user. Four sole-user paths (exit, exit_group, exit after a joined thread, exit
after a reaped CLONE_VM peer) preserve the shared word and all three admitted
shared waiters. Surviving-thread and surviving-CLONE_VM-process controls still
wake exactly one, including through a read-only alias. Its 384 controls per
architecture cover root/UID1000, both PID namespace views, four initial words,
two native-page offsets, replaced registrations, private/abandoned queues and
complete two-page alias canaries. Four warmed 200-trial cohorts measure complete
cleanup. Use `--cases tidlast --timeout 1200` with a fresh state directory.
`tidlast-reference.v` boots the unchanged ELF on Linux; compile `tidlast-check.v`
without `-prod` to check original failures, corrected results, whole-C scope,
storage, retained setup/compiler refusals and executing negative controls.
See [the last-user report](../../docs/linux-posix-qualification.md#native-clear-child-tid-last-address-space-user).

The `clonesignal` case checks native clone3 exit-signal validation. Signals
outside 0–64 and nonzero signals with CLONE_THREAD/CLONE_PARENT return EINVAL
before cgroup-FD lookup. All 65 valid signal values reach an EBADF control;
successful fork/reap controls use SIGCHLD. Protected, unaligned and page-tail
inputs check import-fault precedence and complete two-page canaries. Four
credential/PID-namespace cohorts run 2,652 controls per architecture. Both
original and corrected kernels measure four warmed 200-cycle cleanup cohorts
using the same six valid-signal FD refusals and one real fork/reap per cycle.
Use `--cases clonesignal --timeout 1200` with a fresh state directory.
`clonesignal-reference.v` boots the unchanged ELF on Linux; compile
`clonesignal-check.v` without `-prod` to audit baseline failures, corrected
results, exact whole-C scope, flat storage, pins and executing negative controls.
See [the clone3 signal report](../../docs/linux-posix-qualification.md#native-clone3-exit-signal-validation).

The `clonecgroup` case checks the clone3 cgroup descriptor ABI: values above
INT_MAX return EINVAL when CLONE_INTO_CGROUP is present, in-range missing FDs
retain EBADF, and the field is ignored when the flag is absent. Four
credential/PID-namespace cohorts run 684 controls per architecture through
aligned, unaligned and page-tail protected input layouts. Version sizes,
input faults, complete two-page canaries, empty-child checks and actual
SIGCHLD fork/reap are included. Original and corrected kernels each measure
four warmed 200-cycle cleanup cohorts with the same descriptor inputs and
fork/reap workload. Only the retention loop accepts either original EBADF or
corrected EINVAL; conformance checks require the exact Linux error.
Use `--cases clonecgroup --timeout 1200` with a fresh state directory.
`clonecgroup-reference.v` runs the identical ELF on Linux; compile
`clonecgroup-check.v` without `-prod` to audit exact source/C scope, baseline
failures, corrected results, flat storage, pins and executing negative controls.
See [the cgroup descriptor report](../../docs/linux-posix-qualification.md#native-clone3-cgroup-descriptor-range).

The `clonestack` case checks clone3 stack range admission. Wrapping and
out-of-userspace intervals return EINVAL; valid intervals reach a later EBADF
control without requiring mapped or writable pages. Four credential/PID
namespace cohorts run 768 controls per architecture through three protected
input layouts. Null/size mismatches, input-fault precedence, complete canaries,
empty-child checks and inherited-stack SIGCHLD fork/reap are included.
Original and corrected kernels each measure four warmed 200-cycle cleanup
cohorts on identical inputs. Only this retention loop accepts either original
EBADF or corrected EINVAL; conformance checks require the exact Linux error.
Use `--cases clonestack --timeout 1200` with a fresh state directory.
`clonestack-reference.v` runs the identical ELF on Linux; compile
`clonestack-check.v` without `-prod` to audit original failures, corrected
results, exact source/C scope, storage, pins and executing negative controls.
See [the stack range report](../../docs/linux-posix-qualification.md#native-clone3-stack-range-admission).

The `cloneflags` case checks native clone3 flag validation: unknown high bits,
reserved former CSIGNAL/CLONE_DETACHED bits and conflicting
CLONE_SIGHAND/CLONE_CLEAR_SIGHAND requests return EINVAL after argument import.
Four credential/PID namespace cohorts run 1,056 controls per architecture
through three protected layouts. Recognized flags reach an EBADF admission
control; direct invalid calls must create no children. Original kernels create
nine unrequested children per cohort, which the probe validates and reaps;
corrected kernels and identical Linux ELFs create none. Valid SIGCHLD fork/reap
controls, input faults, canaries and empty-child checks are included.
Original and corrected kernels measure identical warmed 200-cycle cleanup
workloads. Only this retention loop accepts original EBADF or corrected
EINVAL; semantic cases require exact errors. Use `--cases cloneflags --timeout
1200` with a fresh state directory. `cloneflags-reference.v` runs the unchanged
ELF on Linux; compile `cloneflags-check.v` without `-prod` for the executing
evidence audit. Recognized-flag admission does not qualify each flag's effects.
See [the flag report](../../docs/linux-posix-qualification.md#native-clone3-flag-word-validation).

The `cloneclear` case checks actual CLONE_CLEAR_SIGHAND effects. Each child
queries all 62 changeable dispositions; caught handlers become SIG_DFL,
SIG_IGN survives, and all action flags, restorers and masks are cleared.
Ordinary clones retain mixed dispositions. Parent dispositions and the blocked
mask stay unchanged. Real SIGUSR1 delivery distinguishes caught, default and
ignored behavior. Four credential/PID namespace cohorts run 576 controls per
architecture through sizes 64/72/80/88 and three protected input layouts,
including conflict refusals, input canaries and complete child reaping.
Original and corrected kernels also measure identical warmed 200-cycle
fork/query/reap/refusal workloads; only cleanup measurements tolerate the
original child table. Use `--cases cloneclear --timeout 1200` with a fresh state
directory. `cloneclear-reference.v` runs the unchanged ELF on Linux; compile
`cloneclear-check.v` without `-prod` to audit the original failures, corrected
results, exact source/C scope, retention and executing negative controls.
See [the disposition report](../../docs/linux-posix-qualification.md#native-clone3-cleared-signal-dispositions).
