@[has_globals]
module proc

import klock
import katomic
import memory
import event.eventstruct

// Match the conventional Linux soft RLIMIT_NOFILE. Large compatibility
// processes such as Wine's server keep a descriptor for every translated
// process, message queue, and X11 connection; 256 slots can be exhausted while
// a complex application is still creating its UI threads.
pub const max_fds = 1024

pub const max_events = 32

pub const max_pid = 65536

// Linux resource numbers.  Keeping the complete table matters even for limits
// which are only advisory in Vinix today: prlimit64/getrlimit must preserve a
// value instead of rejecting a perfectly ordinary libc probe.
pub const rlimit_cpu = 0
pub const rlimit_fsize = 1
pub const rlimit_data = 2
pub const rlimit_stack = 3
pub const rlimit_core = 4
pub const rlimit_rss = 5
pub const rlimit_nproc = 6
pub const rlimit_nofile = 7
pub const rlimit_memlock = 8
pub const rlimit_as = 9
pub const rlimit_locks = 10
pub const rlimit_sigpending = 11
pub const rlimit_msgqueue = 12
pub const rlimit_nice = 13
pub const rlimit_rtprio = 14
pub const rlimit_rttime = 15
pub const rlimit_nlimits = 16
pub const rlim_infinity = u64(-1)

pub struct RLimit {
pub mut:
	cur u64
	max u64
}

pub fn default_rlimits() [rlimit_nlimits]RLimit {
	mut limits := [rlimit_nlimits]RLimit{}
	for i := 0; i < rlimit_nlimits; i++ {
		limits[i] = RLimit{
			cur: rlim_infinity
			max: rlim_infinity
		}
	}
	limits[rlimit_nofile] = RLimit{
		cur: u64(max_fds)
		max: u64(max_fds)
	}
	limits[rlimit_stack] = RLimit{
		cur: 8 * 1024 * 1024
		max: rlim_infinity
	}
	limits[rlimit_nproc] = RLimit{
		cur: max_pid - 1
		max: max_pid - 1
	}
	return limits
}

pub struct Process {
pub mut:
	pid                      int
	ppid                     int
	pgid                     int
	sid                      int
	pagemap                  &memory.Pagemap = unsafe { nil }
	thread_stack_top         u64
	threads                  []&Thread
	threads_lock             klock.Lock
	fds_lock                 klock.Lock
	rlimits_lock             klock.Lock
	fds                      [max_fds]voidptr
	children                 []&Process
	children_lock            klock.Lock
	mmap_anon_non_fixed_base u64
	// Program break. It gets its own arena so that growing it can never run
	// into the anonymous mmap region or the thread stacks.
	brk_base          u64
	brk_current       u64
	current_directory voidptr
	event             eventstruct.Event
	status            int
	// Set once exit_group() (or a fatal fault) has started tearing the
	// process down, so late-arriving threads do not try to do it again.
	exiting bool
	name    string
	// Resolved program path used by the Linux /proc/self/exe compatibility
	// link. Keep it separate from name, which prctl(PR_SET_NAME) may change.
	executable_path string
	// amd64 supports both the original Vinix/mlibc syscall convention and the
	// Linux convention used by unmodified Alpine binaries. exec sets this from
	// the ELF interpreter; fork inherits it with the rest of the process ABI.
	linux_abi bool

	// Credentials: the real, effective and saved sets POSIX names, plus the
	// supplementary groups. Everything starts as root and is inherited across
	// fork, which is what a system with no login path and no setuid bits gets.
	uid     u32
	euid    u32
	suid    u32
	gid     u32
	egid    u32
	sgid    u32
	groups  []u32
	rlimits [rlimit_nlimits]RLimit
	// Creation mask inherited across fork and preserved by exec.
	umask u32 = 0o22

	// The controlling terminal's session, from setsid(2). A process is a
	// session leader when sid == pid.
	tty_session int

	// Nanoseconds this process' threads have spent on a CPU, summed over the
	// life of the process and over every thread it has ever had — a thread
	// pays in what it owes before it is torn down, so an exited thread's time
	// stays counted. It only ever grows, so a reader that wants a rate takes
	// two samples and divides the difference by the wall clock between them.
	cpu_time_ns u64
	// CPU time from children this process has successfully waited for.
	children_cpu_time_ns u64
	// POSIX nice value. The scheduler scales this process' timeslices from
	// -20 (highest normal priority) through 19 (lowest).
	nice int
}

// Read-mostly limits are naturally aligned u64s.  Writers serialize complete
// {cur,max} replacements with rlimits_lock; enforcement paths only need the
// current soft value and may take a slightly older value during a concurrent
// prlimit64, which is also permitted by the syscall's process-wide semantics.
pub fn soft_limit(process &Process, which int) u64 {
	if which < 0 || which >= rlimit_nlimits {
		return 0
	}
	return process.rlimits[which].cur
}

pub fn limit_allows(process &Process, which int, amount u64) bool {
	limit := soft_limit(process, which)
	return limit == rlim_infinity || amount <= limit
}

// RLIMIT_NPROC is charged to the real uid, like Linux.  The check and the PID
// allocation are individually protected; a pair of simultaneous forks may
// both observe the last slot.  max_pid remains the hard backstop, while this
// helper provides the expected deterministic limit for normal callers.
pub fn may_create_process(process &Process) bool {
	limit := soft_limit(process, rlimit_nproc)
	if limit == rlim_infinity {
		return true
	}
	pid_lock.acquire()
	defer { pid_lock.release() }
	mut count := u64(0)
	for i := 1; i < max_pid; i++ {
		candidate := processes[i]
		if candidate != unsafe { nil } && candidate.uid == process.uid {
			count++
		}
	}
	return count < limit
}

pub struct SigAction {
pub mut:
	sa_sigaction voidptr
	sa_mask      u64
	sa_flags     int
	sa_restorer  voidptr // SA_RESTORER trampoline (musl: __restore_rt)
}

// PIDs and TIDs live in a single namespace, as on Linux: the main thread of a
// process has tid == pid, and every other thread holds an id that no process
// can be given while it is alive.
__global (
	processes      [max_pid]&Process
	threads_by_tid [max_pid]&Thread
	pid_lock       klock.Lock
)

fn find_free_id() ?int {
	for i := int(1); i < max_pid; i++ {
		if processes[i] == unsafe { nil } && threads_by_tid[i] == unsafe { nil } {
			return i
		}
	}
	return none
}

pub fn allocate_pid(process &Process) ?int {
	pid_lock.acquire()
	defer {
		pid_lock.release()
	}

	i := find_free_id()?
	processes[i] = unsafe { process }
	return i
}

pub fn free_pid(pid int) {
	if pid <= 0 || pid >= max_pid {
		return
	}

	pid_lock.acquire()
	defer {
		pid_lock.release()
	}

	processes[pid] = unsafe { nil }
	// The main thread's tid aliases the pid, so it is released together.
	threads_by_tid[pid] = unsafe { nil }
}

// ── CPU time accounting ────────────────────────────────────────────
// A thread's time is charged to its process at the moment the scheduler takes
// it off a CPU, so the total is only ever moved forward by a span that has
// already finished. Both calls sit on the one path every context switch goes
// through. Neither takes a lock: `scheduled_at_ns` is touched only by the CPU
// the thread is running on, and the running total is added to atomically —
// see charge_cpu_time.

// begin_cpu_time marks a thread as having started a turn on a CPU.
pub fn begin_cpu_time(mut t Thread, now_ns u64) {
	t.scheduled_at_ns = now_ns
}

// charge_cpu_time bills the turn that has just ended to the thread's process
// and clears the mark, so a thread that is switched away twice without running
// in between is charged once. A clock that has not moved, or has moved
// backwards because the reading raced a tick, is charged nothing rather than a
// nonsense span.
//
// The addition is a compare-and-swap rather than a `+=`. Two threads of one
// process can come off two CPUs at the same moment, each holding only its own
// thread's lock, and a lost update there would undercount exactly the
// multi-threaded processes worth measuring. Taking the process' lock instead
// would put it underneath the scheduler, which is not somewhere it can go.
pub fn charge_cpu_time(mut t Thread, now_ns u64) {
	started := t.scheduled_at_ns
	t.scheduled_at_ns = 0
	if started == 0 || now_ns <= started {
		return
	}
	if unsafe { t.process == nil } {
		return
	}
	span := now_ns - started
	for {
		total := katomic.load(&t.cpu_time_ns)
		if katomic.cas(mut &t.cpu_time_ns, total, total + span) {
			break
		}
	}
	mut process := t.process
	for {
		total := katomic.load(&process.cpu_time_ns)
		if katomic.cas(mut &process.cpu_time_ns, total, total + span) {
			return
		}
	}
}

pub fn thread_cpu_time(t &Thread, now_ns u64) u64 {
	mut total := katomic.load(&t.cpu_time_ns)
	started := t.scheduled_at_ns
	if started != 0 && now_ns > started {
		total += now_ns - started
	}
	return total
}

pub fn process_cpu_time(process &Process, now_ns u64) u64 {
	mut total := katomic.load(&process.cpu_time_ns)
	current := current_thread()
	if unsafe { current != nil } && voidptr(current.process) == voidptr(process) {
		started := current.scheduled_at_ns
		if started != 0 && now_ns > started {
			total += now_ns - started
		}
	}
	return total
}

pub fn account_reaped_child(mut parent Process, child &Process) {
	child_time := katomic.load(&child.cpu_time_ns)
	for {
		total := katomic.load(&parent.children_cpu_time_ns)
		if katomic.cas(mut &parent.children_cpu_time_ns, total, total + child_time) {
			return
		}
	}
}

pub fn process_count() u16 {
	lock_table()
	defer { unlock_table() }
	mut count := u32(0)
	for i := 1; i < max_pid; i++ {
		if processes[i] != unsafe { nil } { count++ }
	}
	if count > 0xffff {
		return 0xffff
	}
	return u16(count)
}

// ── Reading the process table ──────────────────────────────────────
// The table is a bare array behind a spinlock, and a `&Process` taken out of
// it is only good for as long as that lock is held — a process that exits has
// its entry cleared and its memory freed. A reader therefore brackets its
// whole walk with these rather than collecting pointers to look at later.

pub fn lock_table() {
	pid_lock.acquire()
}

pub fn unlock_table() {
	pid_lock.release()
}

// process_at answers with the process holding `pid`, or nil. The caller must
// hold the table lock.
pub fn process_at(pid int) &Process {
	if pid <= 0 || pid >= max_pid {
		return unsafe { nil }
	}
	return processes[pid]
}

pub fn allocate_tid(thrd &Thread) ?int {
	pid_lock.acquire()
	defer {
		pid_lock.release()
	}

	i := find_free_id()?
	threads_by_tid[i] = unsafe { thrd }
	return i
}

// Claim an already-reserved id for a thread. Used to give a process' main
// thread the tid that matches its pid.
pub fn bind_tid(tid int, thrd &Thread) {
	if tid <= 0 || tid >= max_pid {
		return
	}

	pid_lock.acquire()
	defer {
		pid_lock.release()
	}

	threads_by_tid[tid] = unsafe { thrd }
}

pub fn free_tid(tid int) {
	if tid <= 0 || tid >= max_pid {
		return
	}

	pid_lock.acquire()
	defer {
		pid_lock.release()
	}

	threads_by_tid[tid] = unsafe { nil }
}

pub fn thread_by_tid(tid int) &Thread {
	if tid <= 0 || tid >= max_pid {
		return unsafe { nil }
	}

	pid_lock.acquire()
	defer {
		pid_lock.release()
	}

	return threads_by_tid[tid]
}

pub fn thread_affinity(tid int) ?u64 {
	if tid <= 0 || tid >= max_pid {
		return none
	}
	pid_lock.acquire()
	defer { pid_lock.release() }
	t := threads_by_tid[tid]
	if t == unsafe { nil } {
		return none
	}
	return t.affinity_mask
}

pub fn set_thread_affinity(tid int, mask u64) bool {
	if tid <= 0 || tid >= max_pid {
		return false
	}
	pid_lock.acquire()
	defer { pid_lock.release() }
	mut t := threads_by_tid[tid]
	if t == unsafe { nil } {
		return false
	}
	t.affinity_mask = mask
	return true
}
