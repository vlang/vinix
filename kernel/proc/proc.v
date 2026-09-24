@[has_globals]
module proc

import klock
import lib
import katomic
import memory
import event.eventstruct
import time

// Match the conventional Linux soft RLIMIT_NOFILE. Large compatibility
// processes such as Wine's server keep a descriptor for every translated
// process, message queue, and X11 connection; 256 slots can be exhausted while
// a complex application is still creating its UI threads.
pub const max_fds = 1024

pub const max_events = 32

pub const max_pid = 65536

// ── Scheduling policies ─────────────────────────────────────────────────────
//
// Linux's numbers, because the syscalls that carry them are Linux's. Policy
// and priority belong to the thread, not the process: sched_setscheduler(2)
// takes a tid, and a program that gives one thread a deadline to keep leaves
// the rest of itself alone.
pub const sched_other = 0
pub const sched_fifo = 1
pub const sched_rr = 2
pub const sched_batch = 3
pub const sched_idle = 5
pub const sched_deadline = 6

// SCHED_RESET_ON_FORK, as ORed into the policy argument. It is state rather
// than a policy of its own: a thread carrying it hands its children an
// ordinary SCHED_OTHER slot instead of the real-time one it holds, so a
// privileged program cannot leak its priority into everything it starts.
pub const sched_reset_on_fork = 0x40000000

// The real-time band. 1 is the lowest urgency that still outranks every
// ordinary thread; 99 outranks everything else.
pub const rt_priority_min = 1
pub const rt_priority_max = 99

// Where a thread sits in the order the scheduler picks in. Higher wins.
// Deadline threads come first, then the real-time band by priority, then
// ordinary threads, then SCHED_IDLE, which only runs when a CPU would
// otherwise have nothing to do.
pub const rank_deadline = 200
pub const rank_realtime_base = 100
pub const rank_normal = 1
pub const rank_idle = 0

// A thread's scheduling parameters: what it is entitled to and, for a deadline
// thread, how much of that entitlement is left.
pub struct SchedParams {
pub mut:
	policy        int = sched_other
	priority      int // 1..99 under SCHED_FIFO/RR, 0 under every other policy
	reset_on_fork bool
	// SCHED_DEADLINE, all in nanoseconds: at most `dl_runtime` of CPU every
	// `dl_period`, to be finished `dl_deadline` after the period opens.
	dl_runtime  u64
	dl_deadline u64
	dl_period   u64
	// Where the current instance is up to, on the monotonic clock the
	// scheduler bills CPU time with. `dl_budget_ns` is what is left of this
	// period's runtime; a thread that spends it all waits for `dl_period_end`
	// rather than running on.
	dl_budget_ns    u64
	dl_period_end   u64
	dl_abs_deadline u64
}

pub fn (s &SchedParams) is_realtime() bool {
	return s.policy == sched_fifo || s.policy == sched_rr || s.policy == sched_deadline
}

// Is this thread scheduled by something other than its turn? SCHED_BATCH is
// not: it ranks with SCHED_OTHER and differs only in the timeslice it is
// given, so a machine running nothing but those two is the uniform machine the
// scheduler's cheapest path is written for.
pub fn (s &SchedParams) is_special() bool {
	return s.policy != sched_other && s.policy != sched_batch
}

// Ties are broken round-robin by the run-queue scan, except between deadline
// threads, where the earlier absolute deadline wins.
pub fn (s &SchedParams) rank() int {
	return match s.policy {
		sched_deadline { rank_deadline }
		sched_fifo, sched_rr { rank_realtime_base + s.priority }
		sched_idle { rank_idle }
		else { rank_normal }
	}
}

// Does a thread of this policy keep the CPU when an equally ranked thread is
// waiting for it? SCHED_FIFO is the policy that does: it runs until it blocks,
// yields, or something more urgent than it turns up. A deadline thread keeps
// the CPU for the same reason, until its budget for this period runs out.
pub fn (s &SchedParams) runs_to_completion() bool {
	return s.policy == sched_fifo || s.policy == sched_deadline
}

// How many threads on this machine are scheduled by policy rather than by
// turn. Everything the real-time support costs is conditional on this being
// non-zero: a machine where nobody has asked for a policy keeps the run-queue
// scan, the timeslices and the idle poll it had before any of this existed.
//
// It is a hint, and deliberately so. Every use of it trades latency against
// throughput; none of them decides whether a thread may run.
__global (
	special_policy_threads = int(0)
)

pub fn scheduling_policies_in_use() bool {
	return katomic.load(&special_policy_threads) > 0
}

fn adjust_policy_count(was_special bool, now_special bool) {
	if was_special == now_special {
		return
	}
	if now_special {
		katomic.inc(mut &special_policy_threads)
	} else {
		katomic.dec(mut &special_policy_threads)
	}
}

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
	// In a pid namespace other than the initial one, the process's pid, group
	// and session as that namespace numbers them (0 for a group or session
	// whose leader is outside it), and the namespace itself. Kept until the
	// process is reaped: its parent still asks for it by number.
	ns_pid                   int
	ns_pgid                  int
	ns_sid                   int
	numbered_in              &Namespace = unsafe { nil }
	// Field 22 of /proc/<pid>/stat: start time in clock ticks. Linux runtimes
	// (runc) use (pid, start_time) as a process's identity; a constant zero
	// makes a just-created process indistinguishable from the zero value a
	// caller compares against, which breaks runc's hasInit() check.
	start_time_ticks         u64
	pagemap                  &memory.Pagemap = unsafe { nil }
	thread_stack_top         u64
	threads                  []&Thread
	threads_lock             klock.Lock
	fds_lock                 klock.Lock
	rlimits_lock             klock.Lock
	// The descriptor table, max_fds entries allocated with the process and
	// freed when it is reaped. Held inline it made every process 10 KiB, which
	// the allocator rounds up to four pages.
	fds                      []voidptr
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
	// Some compatibility runtimes require an RWX probe even when their generated
	// code runs interpreted. Exec replaces this opt-in; fork preserves it.
	allow_wx bool

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
	// NUMA memory policy, from set_mempolicy(2) and mbind(2). Zero is
	// MPOL_DEFAULT: an anonymous page comes from the node the faulting thread
	// is running on. Inherited across fork and preserved by exec, as on Linux.
	mempolicy_mode     int
	mempolicy_nodemask u64
	// Where MPOL_INTERLEAVE is up to. It lives on the process so that its
	// threads interleave together instead of each starting from node zero.
	mempolicy_interleave u64

	// Container state; see container.v. The directory absolute paths start
	// from (nil means the system root), the namespaces this process is in,
	// its capability sets and its cgroup.
	root_directory  voidptr
	ns              NamespaceSet
	caps            Capabilities
	no_new_privs    bool
	child_subreaper bool
	pdeathsig       int
	cgroup          voidptr
	// The controller state of that cgroup, nil for the root. See
	// cgroup_account.v.
	cgroup_account &CGroupAccount = unsafe { nil }
	// Pages faulted in since memory.max was last checked for this process.
	faults_since_memory_check u32
	oom_score_adj   int
	// The file the process is running. /proc/<pid>/exe leads here when
	// followed, which is what makes an exec from a memfd resolvable.
	exe_node voidptr
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
	// Where the search for the next free id starts. Called with pid_lock held.
	next_id_cursor = int(1)
)

// A process group or a session outlives the process that named it: the leader
// can exit while its members keep running, and the number stays theirs. Handing
// that number to an unrelated new process makes that process a group leader by
// accident, and a program which then asks for a session of its own is told it
// cannot have one. Chromium's crash handler, four processes below the browser,
// treats that refusal as fatal and takes the browser down with it.
fn id_is_a_live_group(id int) bool {
	for i := int(1); i < max_pid; i++ {
		process := processes[i]
		if process == unsafe { nil } {
			continue
		}
		if process.pgid == id || process.sid == id {
			return true
		}
	}
	return false
}

// Ids are handed out in increasing order and wrap at max_pid, as on Linux, so
// one is not reused until the others have had their turn. Taking the lowest
// free id instead gave a process that had just died's pid to the next one
// started, within moments. Whatever still watches the old pid then acts on the
// new process: busybox timeout's watcher polls kill(parent, 0) to see whether
// the command it guards has finished, kept seeing the recycled pid alive, and
// at the deadline sent its SIGTERM to an unrelated process -- a container
// shim, runc, the docker client.
fn find_free_id() ?int {
	for n := 0; n < max_pid - 1; n++ {
		i := (next_id_cursor - 1 + n) % (max_pid - 1) + 1
		if processes[i] != unsafe { nil } || threads_by_tid[i] != unsafe { nil } {
			continue
		}
		if id_is_a_live_group(i) {
			continue
		}
		next_id_cursor = if i + 1 >= max_pid { 1 } else { i + 1 }
		return i
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
	mut p := unsafe { process }
	if p.start_time_ticks == 0 {
		// USER_HZ is 100 on aarch64 Linux, so a tick is 10 ms. The value only
		// has to be non-zero and stable per process; tick-granularity
		// collisions between processes are what Linux has too.
		mut ticks := time.monotonic_ns() / 10000000
		if ticks == 0 {
			ticks = 1
		}
		p.start_time_ticks = ticks
	}
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

	mut reaped := processes[pid]
	release_process_number(reaped)
	processes[pid] = unsafe { nil }
	// Nothing can find the process now, and every descriptor it had was closed
	// when it exited.
	if reaped != unsafe { nil } && reaped.fds.len != 0 {
		unsafe { reaped.fds.free() }
		reaped.fds = []voidptr{}
	}
	// The main thread's tid aliases the pid, so it is released together.
	release_thread_slot(pid)
}

// Drop a thread out of the tid table, taking its real-time entitlement with
// it. Called with pid_lock held.
fn release_thread_slot(tid int) {
	t := threads_by_tid[tid]
	if t != unsafe { nil } {
		adjust_policy_count(t.sched.is_special(), false)
		release_thread_number(t)
	}
	threads_by_tid[tid] = unsafe { nil }
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
	t.cgroup_charged_ns = now_ns
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
	charge_cgroup_cpu(mut t, now_ns)
	t.cgroup_charged_ns = 0
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
	adjust_policy_count(false, thrd.sched.is_special())
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
	adjust_policy_count(false, thrd.sched.is_special())
}

pub fn free_tid(tid int) {
	if tid <= 0 || tid >= max_pid {
		return
	}

	pid_lock.acquire()
	defer {
		pid_lock.release()
	}

	release_thread_slot(tid)
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
	// Forget which memory node this thread was at home on. The scheduler looks
	// for threads whose home node matches the CPU it is picking for before it
	// will take any thread at all, so a thread pinned to the CPUs of a
	// different node than the one it last ran on would be passed over on every
	// scan by any thread already at home there -- for ever. The next CPU to run
	// it claims it again, which is the right answer anyway: a thread told to run
	// somewhere else does not belong where it used to be.
	t.numa_node = -1
	return true
}

pub fn thread_sched_params(tid int) ?SchedParams {
	if tid <= 0 || tid >= max_pid {
		return none
	}
	pid_lock.acquire()
	defer { pid_lock.release() }
	t := threads_by_tid[tid]
	if t == unsafe { nil } {
		return none
	}
	return t.sched
}

// Install a thread's scheduling parameters. The deadline bookkeeping is reset
// rather than carried over: a thread that has just been given a period has not
// started one yet, and one leaving SCHED_DEADLINE owes nothing to a period it
// is no longer in.
pub fn set_thread_sched_params(tid int, params SchedParams) bool {
	if tid <= 0 || tid >= max_pid {
		return false
	}
	pid_lock.acquire()
	defer { pid_lock.release() }
	mut t := threads_by_tid[tid]
	if t == unsafe { nil } {
		return false
	}
	was_special := t.sched.is_special()
	mut next := params
	next.dl_budget_ns = 0
	next.dl_period_end = 0
	next.dl_abs_deadline = 0
	t.sched = next
	adjust_policy_count(was_special, next.is_special())
	return true
}

// The share of one CPU that the deadline threads already admitted have been
// promised, in parts per million, ignoring `except_tid` so that a thread
// changing its own parameters is measured against everyone else.
//
// Admission control is what makes SCHED_DEADLINE a promise rather than a
// priority: a thread is only given a deadline the machine can still meet
// alongside every deadline it has already agreed to.
pub fn deadline_bandwidth_ppm(except_tid int) u64 {
	pid_lock.acquire()
	defer { pid_lock.release() }
	mut total := u64(0)
	for i := 1; i < max_pid; i++ {
		t := threads_by_tid[i]
		if t == unsafe { nil } || i == except_tid {
			continue
		}
		if t.sched.policy != sched_deadline || t.sched.dl_period == 0 {
			continue
		}
		total += t.sched.dl_runtime * 1000000 / t.sched.dl_period
	}
	return total
}

// ── What /proc reports about a process ──────────────────────────────────────
// procfs rebuilds its tree from the process table on access, so each of these
// takes the table lock, reads what it needs and lets go before its caller does
// anything with the answer. A `&Process` never leaves this file.

// The command name Linux puts in comm and in the parenthesised field of stat.
// A Vinix process is named for the path it was executed from with its pid
// appended; the part that corresponds to comm is the basename without that.
fn command_name(name string) string {
	start, end := command_name_bounds(name)
	if start >= end {
		return name
	}
	return name[start..end]
}

// Where the command name is in a process name.
fn command_name_bounds(name string) (int, int) {
	mut end := name.len
	if end > 0 && name[end - 1] == `]` {
		mut open := end - 1
		for open > 0 && name[open] != `[` {
			open--
		}
		if name[open] == `[` {
			end = open
		}
	}
	mut start := 0
	for i := 0; i < end; i++ {
		if name[i] == `/` {
			start = i + 1
		}
	}
	if start >= end {
		return 0, name.len
	}
	return start, end
}

// The real, effective, saved and filesystem ids of a status Uid: or Gid: line;
// the filesystem id is the effective one here.
fn add_id_fields(mut text lib.Text, real u32, effective u32, saved u32) {
	text.add_unsigned(u64(real))
	text.add_byte(`\t`)
	text.add_unsigned(u64(effective))
	text.add_byte(`\t`)
	text.add_unsigned(u64(saved))
	text.add_byte(`\t`)
	text.add_unsigned(u64(effective))
}

fn add_command_name(mut text lib.Text, name string) {
	start, end := command_name_bounds(name)
	for i in start .. end {
		text.add_byte(name[i])
	}
}

// The program a process is running, as an absolute path. Empty when the kernel
// started the process itself and there is no file behind it.
pub fn process_program(pid int) string {
	lock_table()
	defer { unlock_table() }
	process := process_at(pid)
	if process == unsafe { nil } {
		return ''
	}
	return process.executable_path.clone()
}

pub fn process_command(pid int) string {
	lock_table()
	defer { unlock_table() }
	process := process_at(pid)
	if process == unsafe { nil } {
		return ''
	}
	mut text := lib.new_text(32)
	add_command_name(mut text, process.name)
	return text.str()
}

// The thread ids of a process, in the order the process holds them.
pub fn thread_ids(pid int) []int {
	mut ids := []int{}
	lock_table()
	defer { unlock_table() }
	mut process := process_at(pid)
	if process == unsafe { nil } {
		return ids
	}
	// Taken without blocking: this runs under the table lock, and a thread in
	// the middle of exiting holds its process' thread list while it goes on to
	// take locks the rest of the kernel takes first. A process that is busy
	// changing its thread set reports its main thread for one lookup instead.
	if !process.threads_lock.test_and_acquire() {
		ids << pid
		return ids
	}
	for i := 0; i < process.threads.len; i++ {
		member := process.threads[i]
		if member != unsafe { nil } {
			ids << member.tid
		}
	}
	process.threads_lock.release()
	if ids.len == 0 {
		ids << pid
	}
	return ids
}

// Whether some process or thread stands in `directory`: has it as its working
// directory or its root. Neither holds a reference on it, so removing the
// directory has to ask. A process whose thread list is busy counts as one.
pub fn directory_in_use(directory voidptr) bool {
	lock_table()
	defer { unlock_table() }
	for pid := 1; pid < max_pid; pid++ {
		process := process_at(pid)
		if process == unsafe { nil } {
			continue
		}
		if process.current_directory == directory || process.root_directory == directory {
			return true
		}
		mut owner := unsafe { process }
		if !owner.threads_lock.test_and_acquire() {
			return true
		}
		mut inside := false
		for t in process.threads {
			if t.fs != unsafe { nil } && (t.fs.current_directory == directory
				|| t.fs.root_directory == directory) {
				inside = true
				break
			}
		}
		owner.threads_lock.release()
		if inside {
			return true
		}
	}
	return false
}

// sysrq 't': every thread on the console, with the syscall it is in and that
// call's first argument, which is how a hang in userspace is told apart from
// one in the kernel and pinned to the call that never returned.
pub fn dump_tasks() {
	lock_table()
	defer { unlock_table() }
	for pid := 1; pid < max_pid; pid++ {
		process := process_at(pid)
		if process == unsafe { nil } {
			continue
		}
		state := if process.exiting { 'Z' } else { 'R' }
		// The list is only safe to walk under its lock: a thread leaving takes
		// itself out and can be freed right after. Taken without blocking, for
		// the same reason as in the tid listing above.
		mut owner := unsafe { process }
		if !owner.threads_lock.test_and_acquire() {
			print('sysrq: pid=${pid} ppid=${process.ppid} ${state} ${command_name(process.name)} (thread list busy)\n')
			continue
		}
		for t in process.threads {
			nr, arg0 := t.current_syscall()
			print('sysrq: pid=${pid} ppid=${process.ppid} tid=${t.tid} ${state} ${command_name(process.name)} syscall=${nr} arg0=0x${arg0:x} ${t.syscall_args_text()}\n')
		}
		owner.threads_lock.release()
	}
}

// The first fields of /proc/<pid>/stat. Everything Vinix does not account for
// is reported as zero rather than invented; readers take the fields they know.
// Ids are shown as `viewer` numbers them.
pub fn process_stat_line(pid int, viewer &Namespace) string {
	lock_table()
	defer { unlock_table() }
	process := process_at(pid)
	if process == unsafe { nil } {
		return ''
	}
	threads := if process.threads.len > 0 { process.threads.len } else { 1 }

	// The main thread's policy is what `ps -c` and `top` report for the
	// process. Under a real-time policy Linux puts -1 - rt_priority in the
	// priority field, which is how those tools tell the two bands apart.
	params := threads_by_tid[pid].sched_or_default()
	mut priority := 20 + process.nice
	if params.policy == sched_fifo || params.policy == sched_rr {
		priority = -1 - params.priority
	}

	// Fields 21 to 39, which nothing here keeps, and then rt_priority and
	// policy in 40 and 41.
	state := if process.exiting { 'Z' } else { 'R' }
	shown_pid := pid_in(process, viewer)
	shown_ppid := pid_in(process_at(process.ppid), viewer)
	shown_pgid := pgid_in(process, viewer)
	shown_sid := sid_in(process, viewer)
	mut text := lib.new_text(256)
	text.add_decimal(shown_pid)
	text.add(' (')
	add_command_name(mut text, process.name)
	text.add(') ')
	text.add(state)
	text.add_byte(` `)
	text.add_decimal(shown_ppid)
	text.add_byte(` `)
	text.add_decimal(shown_pgid)
	text.add_byte(` `)
	text.add_decimal(shown_sid)
	text.add(' 0 -1 0 0 0 0 0 0 0 0 0 ')
	text.add_decimal(priority)
	text.add_byte(` `)
	text.add_decimal(process.nice)
	text.add_byte(` `)
	text.add_decimal(threads)
	text.add(' 0 ')
	text.add_unsigned(process.start_time_ticks)
	text.add(' 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 ')
	text.add_decimal(params.priority)
	text.add_byte(` `)
	text.add_decimal(params.policy)
	text.add_byte(`\n`)
	return text.str()
}

// The scheduling parameters of a thread that may not be there. Called with the
// table locked, where the tid-keyed lookups cannot be.
fn (t &Thread) sched_or_default() SchedParams {
	if t == unsafe { nil } {
		return SchedParams{}
	}
	return t.sched
}

pub fn process_status_text(pid int, viewer &Namespace) string {
	lock_table()
	defer { unlock_table() }
	process := process_at(pid)
	if process == unsafe { nil } {
		return ''
	}
	threads := if process.threads.len > 0 { process.threads.len } else { 1 }
	caps := process.caps
	no_new_privs := if process.no_new_privs { 1 } else { 0 }
	// Seccomp is reported as absent altogether: without the field a runtime
	// knows the kernel has no seccomp, which is the truth here.
	state := if process.exiting { 'Z (zombie)' } else { 'R (running)' }
	shown_pid := pid_in(process, viewer)
	shown_ppid := pid_in(process_at(process.ppid), viewer)
	mut text := lib.new_text(512)
	text.add('Name:\t')
	add_command_name(mut text, process.name)
	text.add('\nUmask:\t0')
	text.add_radix(u64(process.umask), 8, 0)
	text.add('\nState:\t')
	text.add(state)
	text.add('\nTgid:\t')
	text.add_decimal(shown_pid)
	text.add('\nNgid:\t0\nPid:\t')
	text.add_decimal(shown_pid)
	text.add('\nPPid:\t')
	text.add_decimal(shown_ppid)
	text.add('\nTracerPid:\t0\nUid:\t')
	add_id_fields(mut text, process.uid, process.euid, process.suid)
	text.add('\nGid:\t')
	add_id_fields(mut text, process.gid, process.egid, process.sgid)
	// NSpid lists the process's number in every namespace from the reader's
	// down to its own.
	text.add('\nNSpid:\t')
	if !numbers_own(viewer) && numbers_own(process.numbered_in) {
		text.add_decimal(pid)
		text.add_byte(`\t`)
		text.add_decimal(process.ns_pid)
	} else {
		text.add_decimal(shown_pid)
	}
	text.add('\nThreads:\t')
	text.add_decimal(threads)
	text.add('\nCapInh:\t')
	text.add_radix(caps.inheritable, 16, 16)
	text.add('\nCapPrm:\t')
	text.add_radix(caps.permitted, 16, 16)
	text.add('\nCapEff:\t')
	text.add_radix(caps.effective, 16, 16)
	text.add('\nCapBnd:\t')
	text.add_radix(caps.bounding, 16, 16)
	text.add('\nCapAmb:\t')
	text.add_radix(caps.ambient, 16, 16)
	text.add('\nNoNewPrivs:\t')
	text.add_decimal(no_new_privs)
	text.add_byte(`\n`)
	return text.str()
}

