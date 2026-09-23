@[has_globals]
module sched

import aarch64.cpu
import aarch64.cpu.local as cpulocal
import aarch64.timer
import aarch64.uart
import aarch64.virtio_input
import katomic
import klock
import proc
import memory
import memory.mmap
import elf
import lib
import errno
import time
import krandom

fn C.sched_switch_context(gpr_state voidptr, kernel_stack u64)

fn C.vinix_enter_idle(stack_top u64, entry voidptr, thread voidptr)

// The outgoing thread's lock protects its kernel stack. Release it only after
// the CPU has switched to its private idle stack; another CPU may otherwise
// resume that thread and overwrite the scheduler's still-active return frames.
@[noreturn]
fn finish_eviction(_thread voidptr) {
	mut thread := unsafe { &proc.Thread(_thread) }
	thread.l.release()
	// A replacement was often already runnable. Dispatch it now instead of
	// adding an idle-timer tick to every ordinary context switch.
	scheduler_timer_handler(unsafe { nil })
	await()
	for {}
}

// Go idle on this CPU's own stack instead of returning.
//
// The scheduler normally parks a CPU by returning from the timer handler, which
// lands back in await()'s polling loop -- correct while the caller's stack still
// belongs to this CPU. It does not when the CPU has just let go of a runnable
// thread: that thread's saved context points into this very stack, and another
// CPU is free to resume it, so returning would put two CPUs on one stack. Leave
// for a stack nobody else can be using.
@[noreturn]
fn evict_to_idle(cpu_number u64, thread &proc.Thread) {
	mut index := cpu_number
	if index >= max_idle_stacks {
		index = max_idle_stacks - 1
	}
	mut top := u64(voidptr(&idle_stacks[index][0])) + u64(idle_stack_size)
	top &= ~u64(0xf)
	C.vinix_enter_idle(top, voidptr(finish_eviction), voidptr(thread))
	for {}
}

fn C.vinix_call_void_fn(f voidptr)

fn C.yield_dispatch(handler voidptr)

const max_reap_slots = 256

// The same count as the per-CPU exception stacks. A CPU past the end shares the
// last stack, which is only reached when that CPU is idling anyway.
const max_idle_stacks = 8

const idle_stack_size = 32768

__global (
	// Per-CPU parking slot for the thread that most recently died there.
	reap_slots [max_reap_slots]&proc.Thread
	// One idle stack per CPU, for the case where a CPU has to leave a thread's
	// stack behind rather than return onto it: see evict_to_idle(). 32 KiB is
	// what await() and one pass of the scheduler need.
	idle_stacks [max_idle_stacks][idle_stack_size]u8
	// Held by whichever CPU is running the platform's input poll. Every caller
	// of poll_platform_input() competes for it, including the syscall fallback
	// below: the drivers behind that callback expect one poller, and the idle
	// loop, a blocking yield and a timeslice can be on three different CPUs.
	input_poll_lock            klock.Lock
	last_syscall_input_poll_ns u64
	// The first context switch into vinix-desktop-gpu is the boundary which
	// differs between QEMU and the M1. Point at that thread's saved register
	// state so the assembly restore can emit checkpoints without flooding every
	// ordinary context switch on the machine.
	gpu_exec_switch_state u64
	gpu_exec_switch_cpu   = u64(-1)
	// Interrupt-side continuation of the same one-shot trace. The first
	// lower-EL IRQ/FIQ transfers ownership here so the context-switch marker
	// does not recursively trace later switches while the interrupt dispatcher
	// can still identify exactly where that first exception stops.
	gpu_exec_interrupt_active = u64(0)
	gpu_exec_interrupt_cpu    = u64(-1)
	gpu_exec_interrupt_kind   u64
	gpu_exec_interrupt_state  u64
	// Printing to the framebuffer is slow enough to consume a short scheduler
	// slice. Hold the first GPU desktop slice here and arm it only after the
	// final traced checkpoint immediately before eret.
	gpu_exec_deferred_timeslice u64
)

fn gpu_exec_interrupt_trace_active(cpu_number u64) bool {
	return katomic.load(&gpu_exec_interrupt_active) != 0
		&& katomic.load(&gpu_exec_interrupt_cpu) == cpu_number
}

fn clear_gpu_exec_interrupt_trace() {
	katomic.store(mut &gpu_exec_interrupt_active, u64(0))
	katomic.store(mut &gpu_exec_interrupt_cpu, u64(-1))
	katomic.store(mut &gpu_exec_interrupt_kind, u64(0))
	katomic.store(mut &gpu_exec_interrupt_state, u64(0))
}

@[export: 'scheduler_gpu_context_trace']
fn scheduler_gpu_context_trace(gpr_state voidptr, phase u64) {
	if katomic.load(&gpu_exec_switch_state) != u64(gpr_state) {
		return
	}
	state := unsafe { &cpulocal.GPRState(gpr_state) }

	match phase {
		0 { println('exec[gpu]/switch: entered sched_switch_context assembly') }
		1 { println('exec[gpu]/switch: ELR and SPSR programmed') }
		2 {
			println('exec[gpu]/switch: eret readback ELR=0x${cpu.read_elr_el1():x} SPSR=0x${cpu.read_spsr_el1():x} CurrentEL=0x${cpu.read_currentel():x}')
			println('exec[gpu]/switch: saved target pc=0x${state.pc:x} sp=0x${state.sp:x} pstate=0x${state.pstate:x} tls=0x${state.tpidr_el0:x}')
			deferred_slice := katomic.load(&gpu_exec_deferred_timeslice)
			println('exec[gpu]/switch: target stack and TPIDR ready; arming deferred ${deferred_slice} us timeslice')
			// Nothing may print after this arm: on the M1 each production log also
			// redraws the framebuffer, and the old diagnostic path could expire the
			// new thread's entire slice before assembly reached eret.
			katomic.store(mut &gpu_exec_deferred_timeslice, u64(0))
			if deferred_slice != 0 {
				timer.oneshot(deferred_slice)
			}
			// Keep the trace armed across eret. The first lower-EL exception
			// vector clears it after saving the exception frame, which lets the
			// M1 distinguish an eret which never completes from an immediate
			// instruction abort, interrupt, FIQ, or SError.
		}
		else { println('exec[gpu]/switch: unknown assembly phase ${phase}') }
	}
}

// Record the very first exception after the initial context switch into the
// GPU desktop. This hook is called directly by the lower-EL vector stubs after
// SAVE_REGS has made the interrupted user register state safe. It intentionally
// runs before the ordinary syscall, page-fault, and IRQ dispatchers: if one of
// those paths stalls, the last visible line still identifies the exception
// which successfully crossed eret.
@[export: 'scheduler_gpu_lower_exception_trace']
fn scheduler_gpu_lower_exception_trace(esr u64, far u64, raw_state voidptr, kind u64) {
	if katomic.load(&gpu_exec_switch_state) == 0 {
		return
	}
	cpu_number := cpu.read_tpidr_el1()
	if katomic.load(&gpu_exec_switch_cpu) != cpu_number {
		return
	}

	// IRQ and FIQ dispatch have several important stages after vector entry.
	// Transfer those two kinds to a separate one-shot state before disarming
	// the context-switch trace. Synchronous faults and SError already have
	// dedicated dispatch diagnostics and end the handoff trace here.
	if kind == 1 || kind == 2 {
		katomic.store(mut &gpu_exec_interrupt_cpu, cpu_number)
		katomic.store(mut &gpu_exec_interrupt_kind, kind)
		katomic.store(mut &gpu_exec_interrupt_state, u64(raw_state))
		katomic.store(mut &gpu_exec_interrupt_active, u64(1))
	}
	katomic.store(mut &gpu_exec_switch_state, u64(0))
	katomic.store(mut &gpu_exec_switch_cpu, u64(-1))
	state := unsafe { &cpulocal.GPRState(raw_state) }
	name := match kind {
		0 { 'synchronous' }
		1 { 'IRQ' }
		2 { 'FIQ' }
		3 { 'SError' }
		else { 'unknown' }
	}
	println('exec[gpu]/eret: crossed into EL0; first lower-EL ${name} vector entered on CPU ${cpu_number}')
	println('exec[gpu]/eret: ESR=0x${esr:x} EC=0x${esr >> 26:x} FAR=0x${far:x}')
	println('exec[gpu]/eret: exception frame pc=0x${state.pc:x} sp=0x${state.sp:x} pstate=0x${state.pstate:x} x0=0x${state.x0:x} x8=0x${state.x8:x}')
}

// Mark the boundaries around the common IRQ dispatcher from the lower-EL
// vector. Phase 2 is the final operation before restoring the saved EL0 frame;
// if the scheduler retained this thread, arm its deferred fresh timeslice only
// after every slow diagnostic print is finished.
@[export: 'scheduler_gpu_interrupt_trace']
pub fn scheduler_gpu_interrupt_trace(raw_state voidptr, phase u64) {
	cpu_number := cpu.read_tpidr_el1()
	if !gpu_exec_interrupt_trace_active(cpu_number)
		|| katomic.load(&gpu_exec_interrupt_state) != u64(raw_state) {
		return
	}

	kind := if katomic.load(&gpu_exec_interrupt_kind) == 2 { 'FIQ' } else { 'IRQ' }
	match phase {
		0 { println('exec[gpu]/${kind}: entering common interrupt dispatcher') }
		1 { println('exec[gpu]/${kind}: common interrupt dispatcher returned; running exit barrier') }
		2 {
			deferred_slice := katomic.load(&gpu_exec_deferred_timeslice)
			if deferred_slice != 0 {
				println('exec[gpu]/${kind}: exit barrier complete; arming deferred ${deferred_slice} us timeslice and restoring EL0')
			} else {
				println('exec[gpu]/${kind}: exit barrier complete; restoring saved EL0 frame')
			}
			clear_gpu_exec_interrupt_trace()
			katomic.store(mut &gpu_exec_deferred_timeslice, u64(0))
			if deferred_slice != 0 {
				timer.oneshot(deferred_slice)
			}
		}
		else { println('exec[gpu]/${kind}: unknown vector phase ${phase}') }
	}
}

// The Apple architectural timer arrives through the FIQ callback ahead of the
// AIC event drain. These markers distinguish a timer-status read, scheduler
// stall, and AIC_EVENT stall without tracing every interrupt after startup.
pub fn gpu_exec_fiq_trace(phase u64, cntv_ctl u64) {
	cpu_number := cpu.read_tpidr_el1()
	if !gpu_exec_interrupt_trace_active(cpu_number) {
		return
	}
	match phase {
		0 { println('exec[gpu]/FIQ: platform FIQ callback entered') }
		1 { println('exec[gpu]/FIQ: CNTV_CTL=0x${cntv_ctl:x} pending=${cntv_ctl & 4 != 0}') }
		2 { println('exec[gpu]/FIQ: virtual timer pending; entering scheduler timer handler') }
		3 { println('exec[gpu]/FIQ: scheduler timer handler returned; CNTV_CTL=0x${cntv_ctl:x}') }
		4 { println('exec[gpu]/FIQ: virtual timer not pending; continuing with AIC event drain') }
		else { println('exec[gpu]/FIQ: unknown callback phase ${phase}') }
	}
}

pub fn initialise() {
	kernel_process = &proc.Process{
		pagemap: &kernel_pagemap
	}

	// Release the secondary CPUs into the scheduler.
	katomic.store(mut &scheduler_ready, true)

	println('sched: ARM64 scheduler initialised')
}

// Register a callback called from the scheduler's await() loop.
// Used by the console module to poll UART without a separate thread.
pub fn set_uart_poll_callback(cb voidptr) {
	uart_poll_callback = cb
}

// Run the platform's input poll, if this CPU can have it to itself.
//
// The callback drives lwIP, VirtIO networking, VirtIO input and the console's
// own byte buffer, none of which is reentrant, and it is called from three
// places that can each be on a different CPU at the same time: the idle loop,
// a blocking yield, and the boot CPU's timeslice. A try-lock rather than a
// wait: a CPU which finds another one already polling has nothing to contribute
// and should carry on with whatever else its loop does, and a poll skipped here
// is picked up microseconds later by whichever loop comes round next.
fn poll_platform_input() {
	if uart_poll_callback == voidptr(0) {
		return
	}
	if !input_poll_lock.test_and_acquire() {
		return
	}
	defer {
		input_poll_lock.release()
	}
	C.vinix_call_void_fn(uart_poll_callback)
}

// Keep the syscall fallback narrower than the scheduler's normal platform
// callback. Polling networking or the console from an arbitrary syscall can
// recurse into facilities that syscall is about to use; VirtIO input has no
// such dependency and is all a CPU-bound translated GUI needs here.
pub fn poll_syscall_input() {
	ints := cpu.interrupt_toggle(false)
	defer {
		cpu.interrupt_toggle(ints)
	}
	if !input_poll_lock.test_and_acquire() {
		return
	}
	defer {
		input_poll_lock.release()
	}
	now_ns := timer.get_ns()
	if now_ns - last_syscall_input_poll_ns < 1_000_000 {
		return
	}
	last_syscall_input_poll_ns = now_ns
	virtio_input.poll()
}

// Returns the scheduler's timer interrupt handler for use by the
// interrupt controller (GIC or AIC).
pub fn get_timer_handler() fn (voidptr) {
	return scheduler_timer_handler
}

// May this thread run on this CPU at all? Asked by the run-queue scan before it
// picks a thread up, and by the timer handler about the thread already on the
// CPU: an affinity change while a thread is running has to take effect, so a CPU
// it may no longer use puts it down even with nothing to replace it.
//
// Putting it down is the part that needs care on this architecture -- see
// evict_to_idle().
fn may_run_here(t &proc.Thread, cpu_number u64) bool {
	if cpu_number >= 64 {
		return true
	}
	return t.affinity_mask & (u64(1) << cpu_number) != 0
}

// ── Real-time scheduling ─────────────────────────────────────────────────────

// How many laps the ranked scan makes before it gives up. A lap that loses the
// thread it settled on to another CPU looks again, where that thread's lock is
// now held and is skipped like any other; a CPU that still comes away with
// nothing simply idles until its next tick.
const pick_attempts = 4

// What an ordinary thread's timeslice is shortened to while anything on the
// machine is scheduled by policy. See effective_timeslice().
const realtime_preempt_slice_us = u64(1000)

// SCHED_IDLE only runs when no other thread will have the CPU, and hands it
// back quickly when it does get one.
const idle_policy_slice_us = u64(1000)

// How often a CPU with nothing to run looks for real-time work, rather than
// waiting for its next idle tick. See await(): this, and not the tick, is what
// bounds how long a real-time thread waits on a machine that has a CPU free.
const realtime_poll_interval_ns = u64(25000)

// The real-time bandwidth cap, at Linux's default of 950 ms in every second.
// Without one, a SCHED_FIFO loop at any priority takes a CPU and never gives
// it back, which on a single-processor machine means the whole machine --
// including the shell that would have to kill it.
//
// A throttled CPU does not stop running real-time threads. It demotes them
// behind every ordinary thread instead, so one that is holding a lock somebody
// else is waiting on still gets to finish with it.
const rt_period_ns = u64(1000000000)

const rt_runtime_ns = u64(950000000)

const max_rt_cpus = 64

__global (
	// When this CPU's bandwidth window opened and how much of it real-time
	// threads have spent. Written only by the CPU they belong to.
	rt_window_start_ns [max_rt_cpus]u64
	rt_window_used_ns  [max_rt_cpus]u64
	// The reading this CPU last billed for, so a turn spanning several trips
	// through the scheduler is charged once, in pieces.
	rt_account_last_ns [max_rt_cpus]u64
)

// Where a thread sits in the picking order as the queue stands now. A deadline
// thread with nothing left of this period's budget, and every real-time thread
// on a CPU that has spent its bandwidth, drops behind the ordinary threads
// rather than being passed over altogether.
fn runnable_rank(mut t proc.Thread, now_ns u64, throttled bool) int {
	rank := t.sched.rank()
	if rank < proc.rank_realtime_base {
		return rank
	}
	if throttled {
		return proc.rank_idle
	}
	if t.sched.policy == proc.sched_deadline && !replenish_deadline(mut t, now_ns) {
		return proc.rank_idle
	}
	return rank
}

// Open a deadline thread's next period if the last one has ended, and report
// whether it has runtime left in the one it is now in.
fn replenish_deadline(mut t proc.Thread, now_ns u64) bool {
	if t.sched.dl_period == 0 {
		return true
	}
	if now_ns >= t.sched.dl_period_end {
		t.sched.dl_period_end = now_ns + t.sched.dl_period
		t.sched.dl_abs_deadline = now_ns + t.sched.dl_deadline
		t.sched.dl_budget_ns = t.sched.dl_runtime
	}
	return t.sched.dl_budget_ns > 0
}

// What is left of this period's budget, capped at an ordinary timeslice. The
// cap is not a limit on the turn -- a deadline thread with budget left is not
// preempted, so it simply carries on after the tick -- it is there because the
// clocks, the interval timers and every sleeping thread's wakeup are driven by
// the timer coming round.
fn deadline_timeslice(t &proc.Thread) u64 {
	mut slice := t.sched.dl_budget_ns / 1000
	if slice == 0 {
		slice = 1
	}
	if slice > t.timeslice {
		slice = t.timeslice
	}
	return slice
}

fn realtime_throttled(cpu_number u64, now_ns u64) bool {
	if cpu_number >= max_rt_cpus {
		return false
	}
	start := rt_window_start_ns[cpu_number]
	if start == 0 || now_ns - start >= rt_period_ns {
		return false
	}
	return rt_window_used_ns[cpu_number] >= rt_runtime_ns
}

// Bill the span since this CPU last came through the scheduler to whatever was
// running on it. A deadline thread pays for it out of this period's budget;
// every real-time thread pays it into this CPU's bandwidth window.
fn account_realtime_time(cpu_number u64, current &proc.Thread, now_ns u64) {
	if cpu_number >= max_rt_cpus {
		return
	}

	last := rt_account_last_ns[cpu_number]
	rt_account_last_ns[cpu_number] = now_ns

	if unsafe { current == nil } || last == 0 || now_ns <= last {
		return
	}
	mut t := unsafe { current }
	if !t.sched.is_realtime() {
		return
	}
	span := now_ns - last

	if t.sched.policy == proc.sched_deadline {
		if t.sched.dl_budget_ns <= span {
			t.sched.dl_budget_ns = 0
		} else {
			t.sched.dl_budget_ns -= span
		}
	}

	start := rt_window_start_ns[cpu_number]
	if start == 0 || now_ns - start >= rt_period_ns {
		rt_window_start_ns[cpu_number] = now_ns
		rt_window_used_ns[cpu_number] = span
		return
	}
	rt_window_used_ns[cpu_number] += span
}

// Does the thread the scan came back with take the CPU, or does the one on it
// keep it? Rank decides. A tie goes to the thread already running, unless its
// policy hands the CPU on at the end of a turn, or it has just asked to give
// the rest of its turn away, or both are deadline threads and the waiting one
// has the earlier deadline to meet.
fn should_preempt(mut current proc.Thread, next &proc.Thread, now_ns u64, throttled bool) bool {
	if unsafe { next == nil } {
		return false
	}
	mut candidate := unsafe { next }

	current_rank := runnable_rank(mut current, now_ns, throttled)
	next_rank := runnable_rank(mut candidate, now_ns, throttled)
	if next_rank != current_rank {
		return next_rank > current_rank
	}
	if current.yield_requested {
		return true
	}
	if current_rank == proc.rank_deadline {
		return candidate.sched.dl_abs_deadline < current.sched.dl_abs_deadline
	}
	return !current.sched.runs_to_completion()
}

// What a new thread gets from the one that created it. Policy and priority are
// inherited -- a program that starts a worker to share the job it is doing
// expects it to be scheduled the same way -- unless the creator carries
// SCHED_RESET_ON_FORK, whose entire purpose is that it does not hand what it
// holds to anything it starts. The flag itself is not passed on either, so a
// child cannot be made to strip a grandchild it never asked to.
//
// The deadline bookkeeping is left behind in any case: a new thread is at the
// start of its first period, not part-way through its parent's.
fn inherited_sched_params(source &proc.Thread) proc.SchedParams {
	if source.sched.reset_on_fork {
		return proc.SchedParams{
			policy: proc.sched_other
		}
	}

	mut inherited := source.sched
	inherited.dl_budget_ns = 0
	inherited.dl_period_end = 0
	inherited.dl_abs_deadline = 0
	return inherited
}

// Is there a real-time thread waiting for a CPU that this one could give it?
// Asked by the idle loop, which would otherwise not look at the run queue again
// until its next tick. Answering it costs a lap of the queue, so it is only
// ever asked on a machine that has a real-time thread to answer it about.
fn realtime_work_pending(cpu_number u64) bool {
	now_ns := timer.get_ns()
	if realtime_throttled(cpu_number, now_ns) {
		return false
	}
	scheduler_queue_lock.acquire()
	defer {
		scheduler_queue_lock.release()
	}

	for i := 0; i < max_running_threads; i++ {
		mut t := scheduler_running_queue[i]
		if unsafe { t == nil } {
			continue
		}
		if katomic.load(&t.is_dead) {
			continue
		}
		if !t.sched.is_realtime() || t.l.is_held() {
			continue
		}
		if !may_run_here(t, cpu_number) {
			continue
		}
		if t.sched.policy == proc.sched_deadline && !replenish_deadline(mut t, now_ns) {
			continue
		}
		return true
	}

	return false
}

// Pick a thread for this CPU. On a machine with more than one memory node this
// runs twice: once accepting only threads already at home on this CPU's node,
// and then accepting anything. A thread therefore tends to keep running next to
// the memory it faulted in, while a node with nothing to do still takes work
// from a busy one rather than idling.
fn get_next_thread() &proc.Thread {
	scheduler_queue_lock.acquire()
	defer {
		scheduler_queue_lock.release()
	}
	mut cpu_local := cpulocal.current()

	if numa_multinode {
		local_thread := scan_run_queue(mut cpu_local, int(cpu_local.numa_node))
		if unsafe { local_thread != nil } {
			return local_thread
		}
	}
	return scan_run_queue(mut cpu_local, -1)
}

// `want_node` of -1 accepts every thread; otherwise only those whose home node
// matches, plus those no CPU has claimed yet.
//
// A machine where every thread is scheduled by turn takes the first runnable
// thread it finds; one where anything has asked for a policy weighs the whole
// queue instead. The two are the same lap, and the split exists so that the
// ordinary machine goes on paying exactly what it used to.
fn scan_run_queue(mut cpu_local cpulocal.Local, want_node int) &proc.Thread {
	if proc.scheduling_policies_in_use() {
		return scan_run_queue_ranked(mut cpu_local, want_node)
	}
	return scan_run_queue_in_turn(mut cpu_local, want_node)
}

// Exactly one lap of the queue, from wherever this CPU last stopped, so the
// order stays round-robin. The lap is counted rather than compared against a
// starting index: the skip cases used to `continue` straight past the
// wrap-around check, so a slot that this CPU could not take and that happened
// to sit at the start index sent the scan round the queue for ever. Nothing was
// skipped before affinity masks and memory nodes existed, which is why it took
// until a pinned thread on another node to find.
fn scan_run_queue_in_turn(mut cpu_local cpulocal.Local, want_node int) &proc.Thread {
	mut start := cpu_local.last_run_queue_index
	if start < 0 || start >= max_running_threads {
		start = 0
	}

	for step := 1; step <= max_running_threads; step++ {
		index := (start + step) % max_running_threads

		mut t := scheduler_running_queue[index]
		if unsafe { t == nil } {
			continue
		}
		if katomic.load(&t.is_dead) {
			continue
		}
		if !may_run_here(t, cpu_local.cpu_number) {
			continue
		}
		if want_node >= 0 && t.numa_node >= 0 && t.numa_node != want_node {
			continue
		}
		if t.l.test_and_acquire() == true {
			cpu_local.last_run_queue_index = index
			return t
		}
	}

	return unsafe { nil }
}

// The same lap, ending at the most urgent thread this CPU may run rather than
// at the first one it can have. Equal ranks keep the round-robin order: the lap
// starts where the last one stopped, and a thread found later has to beat the
// one already in hand rather than tie it. Deadline threads are the exception
// and are ordered by the deadline each of them is trying to meet.
//
// A thread running on another CPU is still in the queue, holding its own lock.
// The lap has to see past those rather than stop at them, so it peeks at each
// lock and only takes the one it has settled on. If another CPU takes that one
// first, it looks again -- and on that pass the lock it lost to is held, and
// skipped like any other.
fn scan_run_queue_ranked(mut cpu_local cpulocal.Local, want_node int) &proc.Thread {
	now_ns := timer.get_ns()
	throttled := realtime_throttled(cpu_local.cpu_number, now_ns)

	for attempt := 0; attempt < pick_attempts; attempt++ {
		mut start := cpu_local.last_run_queue_index
		if start < 0 || start >= max_running_threads {
			start = 0
		}

		mut best := &proc.Thread(unsafe { nil })
		mut best_index := -1
		mut best_rank := -1
		mut best_deadline := u64(0)

		for step := 1; step <= max_running_threads; step++ {
			index := (start + step) % max_running_threads

			mut t := scheduler_running_queue[index]
			if unsafe { t == nil } {
				continue
			}
			if katomic.load(&t.is_dead) {
				continue
			}
			if !may_run_here(t, cpu_local.cpu_number) {
				continue
			}
			if want_node >= 0 && t.numa_node >= 0 && t.numa_node != want_node {
				continue
			}
			if t.l.is_held() {
				continue
			}
			rank := runnable_rank(mut t, now_ns, throttled)
			if rank < best_rank {
				continue
			}
			if rank == best_rank {
				if rank != proc.rank_deadline || t.sched.dl_abs_deadline >= best_deadline {
					continue
				}
			}
			best = t
			best_index = index
			best_rank = rank
			best_deadline = t.sched.dl_abs_deadline
		}

		if best_index < 0 {
			return unsafe { nil }
		}
		if best.l.test_and_acquire() == true {
			cpu_local.last_run_queue_index = best_index
			return best
		}
	}

	return unsafe { nil }
}

fn effective_timeslice(t &proc.Thread) u64 {
	mut slice := u64(0)

	match t.sched.policy {
		proc.sched_fifo {
			// Nothing here ends a FIFO thread's turn. The timer only has to
			// come round often enough to notice something more urgent becoming
			// runnable, and to keep the clocks moving.
			slice = t.timeslice
		}
		proc.sched_rr {
			// A fixed quantum, and the one sched_rr_get_interval(2) reports.
			// Nice does not scale it: what a real-time thread is entitled to is
			// decided by its priority and by nothing else.
			slice = t.timeslice
		}
		proc.sched_deadline {
			slice = deadline_timeslice(t)
		}
		proc.sched_idle {
			slice = idle_policy_slice_us
		}
		else {
			weight := u64(20 - t.process.nice)
			slice = t.timeslice * weight / 20
		}
	}

	// An ordinary thread gives the CPU back promptly while anything on this
	// machine is scheduled by policy. Lacking a way to interrupt another CPU on
	// demand, the next time it comes through here is the soonest a real-time
	// thread that has just woken can be given the CPU it is sitting on -- so
	// this interval is the machine's worst-case dispatch latency under load.
	if !t.sched.is_special() && proc.scheduling_policies_in_use()
		&& slice > realtime_preempt_slice_us {
		slice = realtime_preempt_slice_us
	}

	if slice == 0 {
		slice = 1
	}
	return slice
}

fn scheduler_timer_handler(_gpr_state voidptr) {
	dispatch_cpu := cpu.read_tpidr_el1()
	trace_gpu_switch := katomic.load(&gpu_exec_switch_state) != 0
		&& katomic.load(&gpu_exec_switch_cpu) == dispatch_cpu
	trace_gpu_interrupt := gpu_exec_interrupt_trace_active(dispatch_cpu)
	trace_gpu_dispatch := trace_gpu_switch || trace_gpu_interrupt
	if trace_gpu_dispatch {
		println('exec[gpu]/sched: immediate scheduler handler entered on CPU ${dispatch_cpu}')
	}
	// The timer interrupt delivers this handler with interrupts already off,
	// but yield()'s polling loop also calls it directly through
	// C.yield_dispatch(), and that loop can have been resumed by
	// sched_switch_context -- which returns to a thread with interrupts
	// enabled. cpulocal.current() below panics outright when it is entered
	// that way, which is what a thread pool eventually produces:
	//
	//     V panic: Attempted to get current CPU struct without disabling ints
	//
	// Take them off for the handler and give the caller its own state back.
	// Holding them off for the whole of that loop instead would stop this CPU
	// taking device interrupts for as long as a thread stays blocked, and the
	// machine stalls with no output rather than panicking.
	//
	// The two paths that leave without returning -- evict_to_idle() and
	// C.sched_switch_context() -- skip the restore on purpose: neither comes
	// back here, and whatever resumes next sets its own interrupt state.
	ints := cpu.interrupt_toggle(false)
	defer {
		cpu.interrupt_toggle(ints)
	}

	gpr_state := unsafe { &cpulocal.GPRState(_gpr_state) }
	timer.stop()
	if trace_gpu_dispatch {
		println('exec[gpu]/sched: scheduler interrupts disabled and timer stopped')
	}

	// Tick the monotonic/realtime clocks. The interval is measured from the
	// generic timer's counter rather than assumed, because this handler fires
	// on a timeslice, not at a fixed frequency.
	//
	// The same reading bills the outgoing thread and starts the incoming one,
	// so a switch neither loses time between the two nor counts it twice.
	now_ns := timer.get_ns()
	time.advance_to_ns(now_ns)
	if trace_gpu_dispatch {
		println('exec[gpu]/sched: scheduler clock advanced to ${now_ns} ns')
	}

	// Tick per-process interval timers (SIGALRM)
	tick_itimers()
	if trace_gpu_dispatch {
		println('exec[gpu]/sched: interval timers ticked; reading CPU-local state')
	}

	mut cpu_local := cpulocal.current()
	// The idle loop normally polls UART, VirtIO input and networking. A busy
	// userspace workload can keep every CPU runnable indefinitely, so relying
	// on idle time alone strands keyboard and pointer reports in their VirtIO
	// queues. Poll once per CPU-0 timeslice as well; using one CPU preserves the
	// drivers' single-poller assumption while keeping the desktop interactive.
	if cpu_local.cpu_number == 0 {
		if trace_gpu_dispatch {
			println('exec[gpu]/sched: polling platform input before run-queue selection')
		}
		poll_platform_input()
		if trace_gpu_dispatch {
			println('exec[gpu]/sched: platform input poll complete')
		}
	}
	katomic.store(mut &cpu_local.is_idle, false)
	if trace_gpu_dispatch {
		println('exec[gpu]/sched: CPU marked non-idle; reading current thread')
	}

	mut current_thread := proc.current_thread()

	// Charge the turn that has just ended against the real-time entitlements it
	// was spending: this period's budget for a deadline thread, and this CPU's
	// bandwidth window for any real-time one. It is billed before the pick
	// below, so a thread that has just run out of budget is passed over on the
	// scan it has run out on rather than on the next.
	account_realtime_time(cpu_local.cpu_number, current_thread, now_ns)
	if trace_gpu_dispatch {
		println('exec[gpu]/sched: realtime accounting complete; selecting run-queue thread')
	}

	mut next_thread := get_next_thread()
	if trace_gpu_dispatch {
		println('exec[gpu]/sched: run-queue selection returned')
	}
	// Only the replacement thread whose first handoff was explicitly armed is
	// interesting here. Matching the executable path alone keeps tracing every
	// later desktop timeslice and quickly buries the one-shot eret diagnostic.
	trace_gpu_next := unsafe { next_thread != nil }
		&& katomic.load(&gpu_exec_switch_state) == u64(&next_thread.gpr_state)
	if trace_gpu_next {
		println('exec[gpu]/sched: CPU ${cpu_local.cpu_number} selected replacement thread from run queue')
		println('exec[gpu]/sched: target pc=0x${next_thread.gpr_state.pc:x} sp=0x${next_thread.gpr_state.sp:x} ttbr0=0x${next_thread.ttbr0:x}')
		next_thread.affinity_mask = u64(-1)
		println('exec[gpu]/sched: first-handoff CPU pin removed')
	}
	// Set once this CPU has let go of the thread it was running, which decides
	// whether the idle path below may return to its caller.
	mut released_current := false

	if unsafe { current_thread != 0 } {
		current_thread.yield_await.release()

		entitled := katomic.load(&current_thread.is_in_queue)
			&& may_run_here(current_thread, cpu_local.cpu_number)
		mut keeps_cpu := unsafe { next_thread == nil } && entitled
		if unsafe { next_thread != nil } && entitled {
			// Something else is runnable, but whether it takes the CPU is the
			// policies' business: a FIFO thread is not interrupted by an equal,
			// and no thread at all is interrupted by something ranked below it.
			throttled := realtime_throttled(cpu_local.cpu_number, now_ns)
			if !should_preempt(mut current_thread, next_thread, now_ns, throttled) {
				// Hand back the thread the scan took for us. Nothing else can
				// pick it up while this CPU holds its lock.
				next_thread.l.release()
				next_thread = unsafe { nil }
				keeps_cpu = true
			}
		}

		if keeps_cpu {
			// This thread is still entitled to the CPU and nothing is taking it
			// away, so it keeps it. The two exceptions fall through instead: a
			// blocked thread, or a later wakeup would select that same stale
			// current thread and charge its whole sleep as CPU time; and one
			// whose affinity no longer allows this CPU, which has to be put down
			// even with nothing to replace it.
			current_thread.yield_requested = false
			next_slice := effective_timeslice(current_thread)
			if trace_gpu_interrupt {
				println('exec[gpu]/sched: current thread keeps CPU; deferring ${next_slice} us timer rearm until vector exit')
				katomic.store(mut &gpu_exec_deferred_timeslice, next_slice)
			} else {
				timer.oneshot(next_slice)
			}
			return
		}
		current_thread.yield_requested = false
		// Past the early return above, this thread really is coming off the
		// CPU, so the turn it has just had is charged to its process.
		proc.charge_cpu_time(mut current_thread, now_ns)

		if unsafe { _gpr_state != nil } {
			unsafe {
				current_thread.gpr_state = *gpr_state
			}
			// Debug: check if x30 is corrupted when saving state for pid 3
			if current_thread.process.pid == 3 && current_thread.gpr_state.x30 == u64(0x220000) {
				print('\nSCHED SAVE: pid=3 x30=0x220000! pc=0x${current_thread.gpr_state.pc:x} sp=0x${current_thread.gpr_state.sp:x} pstate=0x${current_thread.gpr_state.pstate:x}\n')
			}
		} else {
			// gpr_state is nil: check if existing gpr_state has corruption
			if current_thread.process.pid == 3 && current_thread.gpr_state.x30 == u64(0x220000) {
				print('\nSCHED NIL-SAVE: pid=3 x30=0x220000! pc=0x${current_thread.gpr_state.pc:x} sp=0x${current_thread.gpr_state.sp:x}\n')
			}
		}
		current_thread.tpidr_el0 = cpu.read_tpidr_el0()
		current_thread.ttbr0 = cpu.read_ttbr0_el1()
		fpu_save(current_thread.fpu_storage)
		katomic.store(mut &current_thread.running_on, u64(-1))
		released_current = true
	}

	if released_current {
		// The run-queue candidate is still eligible for the idle loop's next
		// scan. Drop its lock before parking, but retain the outgoing thread's
		// lock until the assembly handoff has changed stacks.
		if unsafe { next_thread != nil } {
			next_thread.l.release()
		}
		if trace_gpu_interrupt {
			clear_gpu_exec_interrupt_trace()
		}
		cpu.write_tpidr_el1(cpu_local.cpu_number)
		proc.set_current_thread(cpu_local.cpu_number, unsafe { nil })
		katomic.store(mut &cpu_local.is_idle, true)
		kernel_pagemap.switch_to()
		evict_to_idle(cpu_local.cpu_number, current_thread)
	}

	if unsafe { next_thread == nil } {
		if trace_gpu_interrupt {
			println('exec[gpu]/sched: no runnable target after first GPU interrupt; ending interrupt trace before idle')
			clear_gpu_exec_interrupt_trace()
		}
		// Called from the idle loop (await): no current thread, no next
		// thread. Go idle and return to await()'s polling loop.
		cpu.write_tpidr_el1(cpu_local.cpu_number)
		proc.set_current_thread(cpu_local.cpu_number, unsafe { nil })
		katomic.store(mut &cpu_local.is_idle, true)
		kernel_pagemap.switch_to()
		// Nothing was running here: this is await()'s own poll asking for work
		// and finding none, so returning to its loop is exactly right.
		return
	}

	current_thread = next_thread
	trace_gpu_restore := trace_gpu_next || trace_gpu_interrupt
	if trace_gpu_restore {
		println('exec[gpu]/sched: publishing replacement as CPU current thread')
	}
	proc.set_current_thread(cpu_local.cpu_number, current_thread)
	if trace_gpu_restore {
		println('exec[gpu]/sched: replacement published; starting CPU-time accounting')
	}
	proc.begin_cpu_time(mut current_thread, now_ns)
	if trace_gpu_restore {
		println('exec[gpu]/sched: CPU-time accounting started')
	}

	// The first CPU to run a thread claims it for its node, so that the pages
	// the thread goes on to fault in and the CPU it keeps returning to are on
	// the same side of the machine.
	if current_thread.numa_node < 0 {
		current_thread.numa_node = int(cpu_local.numa_node)
	}
	if trace_gpu_restore {
		println('exec[gpu]/sched: NUMA home selected; restoring TPIDR_EL0')
	}

	cpu.write_tpidr_el0(current_thread.tpidr_el0)
	if trace_gpu_restore {
		println('exec[gpu]/sched: TPIDR_EL0 restored; reading current TTBR0')
	}

	old_ttbr0 := cpu.read_ttbr0_el1()
	if trace_gpu_restore {
		println('exec[gpu]/sched: current TTBR0=0x${old_ttbr0:x}')
	}
	if old_ttbr0 != current_thread.ttbr0 {
		if trace_gpu_restore {
			println('exec[gpu]/sched: writing replacement TTBR0')
		}
		cpu.write_ttbr0_el1(current_thread.ttbr0)
		if trace_gpu_restore {
			println('exec[gpu]/sched: replacement TTBR0 written; executing ISB')
		}
		cpu.isb()
		if trace_gpu_restore {
			println('exec[gpu]/sched: ISB complete; invalidating local TLB')
		}
		cpu.tlbi_vmalle1()
		if trace_gpu_restore {
			println('exec[gpu]/sched: local TLB invalidation complete')
		}
	} else if trace_gpu_restore {
		println('exec[gpu]/sched: replacement TTBR0 already active')
	}

	if trace_gpu_restore {
		println('exec[gpu]/sched: restoring FPU state')
	}
	fpu_restore(current_thread.fpu_storage)
	if trace_gpu_restore {
		println('exec[gpu]/sched: FPU state restored; publishing running CPU')
	}
	katomic.store(mut &current_thread.running_on, cpu_local.cpu_number)
	if trace_gpu_restore {
		println('exec[gpu]/sched: running CPU published; preparing timeslice')
	}

	// Debug: check if x30 is corrupted when restoring state for pid 3
	if current_thread.process.pid == 3 && current_thread.gpr_state.x30 == u64(0x220000) {
		print('\nSCHED RESTORE: pid=3 x30=0x220000! pc=0x${current_thread.gpr_state.pc:x} sp=0x${current_thread.gpr_state.sp:x} pstate=0x${current_thread.gpr_state.pstate:x}\n')
	}

	next_slice := effective_timeslice(current_thread)
	if trace_gpu_next {
		katomic.store(mut &gpu_exec_deferred_timeslice, next_slice)
		println('exec[gpu]/sched: deferring ${next_slice} us timeslice until final low-level checkpoint')
	} else {
		timer.oneshot(next_slice)
		if trace_gpu_restore {
			println('exec[gpu]/sched: timeslice armed; entering low-level context restore')
		}
	}

	if trace_gpu_interrupt {
		println('exec[gpu]/sched: selected another thread; first GPU interrupt frame saved, ending interrupt trace')
		clear_gpu_exec_interrupt_trace()
	}

	// Restore ARM64 GPR state and return via eret (does not return).
	C.sched_switch_context(voidptr(&current_thread.gpr_state), current_thread.kernel_stack)
}

pub fn enqueue_thread(_thread &proc.Thread, by_signal bool) bool {
	return enqueue_thread_impl(_thread, by_signal, false)
}

pub fn enqueue_thread_traced(_thread &proc.Thread, by_signal bool) bool {
	return enqueue_thread_impl(_thread, by_signal, true)
}

fn enqueue_thread_impl(_thread &proc.Thread, by_signal bool, trace bool) bool {
	mut t := unsafe { _thread }
	if trace {
		println('exec[gpu]/sched: entered enqueue_thread')
		first_cpu := cpu.read_tpidr_el1()
		if first_cpu < 64 {
			t.affinity_mask = u64(1) << first_cpu
		}
		katomic.store(mut &gpu_exec_switch_cpu, first_cpu)
		katomic.store(mut &gpu_exec_switch_state, u64(&t.gpr_state))
		println('exec[gpu]/sched: armed first-context-switch tracing on CPU ${first_cpu}')
	}

	// A signal can arrive while the target is running immediately before it
	// removes itself from the run queue in event.await(). Publish the reason
	// first so the waiter can observe it after dequeuing itself.
	if by_signal {
		katomic.store(mut &t.enqueued_by_signal, true)
	}

	if trace {
		println('exec[gpu]/sched: acquiring run-queue lock')
	}
	scheduler_queue_lock.acquire()

	// A torn-down thread may still be referenced by event listener slots it
	// never got to detach; never let it back onto the run queue.
	if katomic.load(&t.is_dead) == true {
		scheduler_queue_lock.release()
		if trace {
			println('exec[gpu]/sched: run-queue lock acquired; ERROR replacement thread already dead')
		}
		return false
	}

	if t.is_in_queue == true {
		scheduler_queue_lock.release()
		if trace {
			println('exec[gpu]/sched: run-queue lock acquired; replacement thread was already queued')
		}
		return true
	}

	for i := u64(0); i < max_running_threads; i++ {
		if katomic.cas[&proc.Thread](mut &scheduler_running_queue[i], unsafe { nil }, t) {
			katomic.store(mut &t.is_in_queue, true)

			// Wake an idle CPU for ordinary work. The traced exec handoff stays
			// pinned to its current CPU until that CPU has acquired the new
			// thread, avoiding a cross-CPU race while diagnosing the M1 path.
			if !trace {
				for cpu_entry in cpu_locals {
					if katomic.load(&cpu_entry.is_idle) == true {
						cpu.sev()
						break
					}
				}
			}

			scheduler_queue_lock.release()
			if trace {
				println('exec[gpu]/sched: run-queue lock acquired; installed thread in slot ${i}')
				println('exec[gpu]/sched: deferred wakeup for same-CPU exec handoff')
				println('exec[gpu]/sched: enqueue complete; run-queue lock released')
			}
			return true
		}
	}

	scheduler_queue_lock.release()
	if trace {
		println('exec[gpu]/sched: run-queue lock acquired; ERROR no free slot; lock released')
	}
	return false
}

pub fn dequeue_thread(_thread &proc.Thread) bool {
	mut t := unsafe { _thread }
	scheduler_queue_lock.acquire()
	defer {
		scheduler_queue_lock.release()
	}

	was_enqueued := t.is_in_queue
	mut removed := false
	for i := u64(0); i < max_running_threads; i++ {
		if katomic.cas[&proc.Thread](mut &scheduler_running_queue[i], t, unsafe { nil }) {
			// Remove every occurrence. This also repairs a queue corrupted by an
			// older kernel's concurrent-wakeup race instead of leaving a stale
			// pointer behind when the Thread is freed.
			removed = true
		}
	}
	katomic.store(mut &t.is_in_queue, false)

	return removed || !was_enqueued
}

pub fn intercept_thread(_thread &proc.Thread) ? {
	mut t := unsafe { _thread }

	if voidptr(t) == voidptr(proc.current_thread()) {
		return none
	}

	dequeue_thread(t)

	running_on := t.running_on
	if running_on == u64(-1) {
		return
	}

	// On ARM64, send an SGI (software-generated interrupt) to wake the target CPU.
	// For now, use SEV as a simple cross-CPU notification.
	cpu.sev()

	t.l.acquire()
	t.l.release()
}

@[noreturn]
fn idle_after_dying_thread(trace bool) {
	cpu.interrupt_toggle(false)
	if trace {
		println('exec[gpu]/sched: idle handoff disabled interrupts')
	}
	timer.stop()
	if trace {
		println('exec[gpu]/sched: idle handoff stopped old timeslice; arming immediate timer')
	}
	timer.oneshot(1)
	if trace {
		println('exec[gpu]/sched: immediate timer armed; enabling interrupts')
	}
	cpu.interrupt_toggle(true)
	if trace {
		println('exec[gpu]/sched: interrupts enabled; entering traced idle loop')
	}
	await_impl(trace)
	for {}
}

pub fn yield(save_ctx bool) {
	if save_ctx == false {
		// Dying thread path (dequeue_and_die). Enter idle scheduler loop.
		idle_after_dying_thread(false)
	}

	cpu.interrupt_toggle(false)
	timer.stop()
	mut current_thread := proc.current_thread()

	// Blocking yield: HVF workaround.
	// IRQ delivery to guest is broken, so we can't rely on preemptive context
	// switching. Instead, poll the timer and when it fires, dispatch the
	// scheduler via yield_dispatch(). This saves our kernel context into a
	// GPRState on the stack and switches to any runnable thread. When this
	// thread is later re-enqueued and re-scheduled, sched_switch_context
	// restores our kernel context and we resume here.
	// The same rate as the idle loop, and for the same reason: this poll is
	// what expires the timer a sleeping thread is waiting on, so its period is
	// the floor on how long any sleep can take.
	freq := cpu.read_cntfrq_el0()
	mut ticks := freq / idle_tick_hz
	if ticks == 0 {
		ticks = 1
	}
	cpu.write_cntv_tval_el0(ticks)
	cpu.write_cntv_ctl_el0(1)

	mut last_realtime_poll_ns := u64(0)

	for {
		// Process timer ticks — dispatch scheduler to run other threads
		vctl := cpu.read_cntv_ctl_el0()
		if vctl & 0x4 != 0 {
			cpu.write_cntv_ctl_el0(0x2) // Mask timer

			// Dispatch scheduler: saves kernel context, switches to next
			// runnable thread. Returns when we're re-scheduled OR if no
			// thread to switch to. Note: scheduler_timer_handler calls
			// timer.stop() internally, so we must re-arm AFTER it returns.
			C.yield_dispatch(voidptr(scheduler_timer_handler))

			// Re-arm timer for next polling tick
			cpu.write_cntv_tval_el0(ticks)
			cpu.write_cntv_ctl_el0(1)
		} else if proc.scheduling_policies_in_use() {
			// This CPU is parked on a blocked thread's stack and would not look
			// at the run queue again until its next tick. A real-time thread
			// waiting for a CPU should not have to wait for that, so look for
			// one between ticks, at the same rate and for the same reason as
			// the idle loop does. See await().
			now_ns := timer.get_ns()
			if now_ns - last_realtime_poll_ns >= realtime_poll_interval_ns {
				last_realtime_poll_ns = now_ns
				time.advance_to_ns(now_ns)
				if realtime_work_pending(cpu.read_tpidr_el1()) {
					cpu.write_cntv_ctl_el0(0x2)
					C.yield_dispatch(voidptr(scheduler_timer_handler))
					cpu.write_cntv_tval_el0(ticks)
					cpu.write_cntv_ctl_el0(1)
				}
			}
		}

		// Poll UART for console input. Another CPU may be in this same loop
		// for a thread of its own, so the poll itself is serialized.
		poll_platform_input()

		// Check if we've been re-enqueued by an event trigger
		if katomic.load(&current_thread.is_in_queue) {
			break
		}

		asm volatile aarch64 {
			yield
			; ; ; memory
		}
	}

	// Interrupts were disabled on the way in, but the loop above can lose the
	// CPU at C.yield_dispatch() and come back through sched_switch_context,
	// which resumes a thread with interrupts enabled. Everything below reads
	// and writes per-CPU state, so take them off again rather than assume
	// which way this was reached: cpulocal.current() panics outright if it is
	// called with interrupts on, which is what a thread that blocks often
	// enough — anything using a thread pool — eventually hits.
	cpu.interrupt_toggle(false)

	// A safety net rather than the normal path. A CPU that parks now leaves this
	// stack for one of its own instead of returning here (see evict_to_idle), so
	// every way out of the loop above either never lost the CPU or came back
	// through sched_switch_context, which restores the per-CPU state itself. Left
	// in place for the case where this thread's slot was cleared without that
	// round trip, since resuming a blocking syscall on a CPU that still thinks it
	// is idle would be much worse than an unnecessary check.
	if proc.current_thread() == unsafe { nil } {
		mut cpu_local := cpulocal.current()
		current_thread.l.acquire()
		proc.set_current_thread(cpu_local.cpu_number, current_thread)
		proc.begin_cpu_time(mut current_thread, timer.get_ns())
		cpu.write_tpidr_el0(current_thread.tpidr_el0)
		if cpu.read_ttbr0_el1() != current_thread.ttbr0 {
			cpu.write_ttbr0_el1(current_thread.ttbr0)
			cpu.isb()
			cpu.tlbi_vmalle1()
		}
		fpu_restore(current_thread.fpu_storage)
		katomic.store(mut &current_thread.running_on, cpu_local.cpu_number)
	}

	// Thread re-enqueued. Re-arm timer for normal scheduling.
	timer.oneshot(effective_timeslice(current_thread))
	cpu.interrupt_toggle(true)
}

pub fn dequeue_and_yield() {
	cpu.interrupt_toggle(false)
	dequeue_thread(proc.current_thread())
	yield(true)
}

@[noreturn]
pub fn dequeue_and_die() {
	dequeue_and_die_impl(false)
}

@[noreturn]
pub fn dequeue_and_die_traced() {
	dequeue_and_die_impl(true)
}

@[noreturn]
fn dequeue_and_die_impl(trace bool) {
	if trace {
		println('exec[gpu]/sched: entered dequeue_and_die')
	}
	cpu.interrupt_toggle(false)
	if trace {
		println('exec[gpu]/sched: old execve thread disabled interrupts')
	}
	mut t := proc.current_thread()
	// Publish death before removing the queue entry. A concurrent event wakeup
	// will then either lose the queue lock and be removed below, or observe the
	// dead flag and refuse to resurrect this Thread.
	katomic.store(mut &t.is_dead, true)
	if trace {
		println('exec[gpu]/sched: old execve thread marked dead; dequeuing')
	}
	dequeue_thread(t)
	if trace {
		println('exec[gpu]/sched: old execve thread dequeued; charging CPU time')
	}
	// This thread leaves the CPU here rather than through the switch in
	// scheduler_timer_handler, so its last turn is charged here or not at all.
	// A process that runs briefly and exits would otherwise report no CPU time
	// at all, which is exactly the process worth noticing.
	proc.charge_cpu_time(mut t, timer.get_ns())
	if trace {
		println('exec[gpu]/sched: CPU time charged; disarming interval timer')
	}
	// tick_itimers() keeps a raw pointer to every armed thread, so the entry
	// has to go before the Thread struct can be recycled.
	set_itimer_real(t, 0, 0)
	if trace {
		println('exec[gpu]/sched: interval timer disarmed; releasing thread lock')
	}
	// A running thread holds its own lock, taken by get_next_thread(). Nothing
	// will ever deschedule us to release it, and intercept_thread() would spin
	// on it forever, so hand it back here.
	katomic.store(mut &t.running_on, u64(-1))
	t.l.release()
	if trace {
		println('exec[gpu]/sched: old thread lock released; clearing CPU current thread')
	}
	// Clear current thread so the scheduler timer handler knows
	// there is no running thread to save state from.
	mut cpu_local := cpulocal.current()
	proc.set_current_thread(cpu_local.cpu_number, unsafe { nil })
	if trace {
		println('exec[gpu]/sched: CPU current thread cleared; handing old thread to reaper')
	}
	hand_over_to_reaper(cpu_local.cpu_number, t)
	if trace {
		println('exec[gpu]/sched: old thread handed to reaper; dispatching scheduler immediately')
		// The replacement is already runnable. Select it synchronously instead
		// of depending on the first post-AGX CNTV timer status becoming visible.
		scheduler_timer_handler(unsafe { nil })
		println('exec[gpu]/sched: immediate dispatch returned without a target; entering scheduler idle loop')
		idle_after_dying_thread(true)
	}
	yield(false)
	for {
	}
}

// Reclaiming a dying thread's kernel stack cannot happen while we are still
// executing on it, so each CPU parks its latest corpse in a slot and frees the
// previous occupant instead. By the time a CPU reaches this point again it has
// long since switched off that stack, and no other CPU can ever have run on it:
// the thread was dequeued before it died, so only the CPU it died on could
// still be idling there.
fn hand_over_to_reaper(cpu_number u64, t &proc.Thread) {
	if cpu_number >= u64(max_reap_slots) {
		return
	}

	mut previous := reap_slots[cpu_number]
	reap_slots[cpu_number] = unsafe { t }

	if unsafe { previous == nil } {
		return
	}

	if previous.kstack_phys != 0 {
		memory.pmm_free(voidptr(previous.kstack_phys), kernel_stack_size / page_size)
	}
	if previous.fpu_storage_phys != 0 {
		memory.pmm_free(voidptr(previous.fpu_storage_phys), lib.div_roundup(fpu_storage_size, page_size))
	}
	unsafe { free(voidptr(previous)) }
}

// Give up the rest of this thread's timeslice without leaving the run queue.
// The scheduler is dispatched once so another runnable thread can take the CPU;
// we resume right here when picked again.
pub fn reschedule() {
	cpu.interrupt_toggle(false)
	timer.stop()

	// Say so, rather than leave the scheduler to infer it from the timer. A
	// SCHED_FIFO thread is not taken off the CPU by an equal, and sched_yield(2)
	// asking for exactly that is the one case where it should be: the thread
	// goes behind the others of its priority instead of keeping the CPU.
	mut current_thread := proc.current_thread()
	if unsafe { current_thread != 0 } {
		current_thread.yield_requested = true
	}

	C.yield_dispatch(voidptr(scheduler_timer_handler))

	// Read again: this is the far side of a context switch, and the thread that
	// comes back here is not necessarily the one that left.
	current_thread = proc.current_thread()
	if unsafe { current_thread != 0 } {
		timer.oneshot(effective_timeslice(current_thread))
	}
	cpu.interrupt_toggle(true)
}

pub fn new_kernel_thread(pc voidptr, arg voidptr, autoenqueue bool) &proc.Thread {
	mut stacks := []voidptr{}

	stack_phys := memory.pmm_alloc(kernel_stack_size / page_size)
	stacks << stack_phys
	stack := u64(stack_phys) + kernel_stack_size + higher_half

	gpr_state := cpulocal.GPRState{
		pc: u64(pc) // elr_el1 = entry point
		x0: u64(arg) // first argument in x0
		sp: stack
		// Kernel-context marker plus masked DAIF. The assembly restore maps
		// EL1h to the current handler level (EL2h on Apple VHE).
		pstate: 0x3c5
	}

	fpu_storage_phys := memory.pmm_alloc(lib.div_roundup(fpu_storage_size, page_size))

	mut t := &proc.Thread{
		process: kernel_process
		ttbr0: u64(kernel_process.pagemap.top_level)
		gpr_state: gpr_state
		timeslice: 5000
		running_on: u64(-1)
		stacks: stacks
		kstack_phys: u64(stack_phys)
		fpu_storage: voidptr(u64(fpu_storage_phys) + higher_half)
		fpu_storage_phys: u64(fpu_storage_phys)
	}

	unsafe { stacks.free() }

	t.self = voidptr(t)

	if autoenqueue == true {
		enqueue_thread(t, false)
	}

	return t
}

pub fn syscall_new_thread(_ voidptr, pc voidptr, stack u64) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: new_thread(0x%llx, 0x%llx)\n', process.name.str, pc, stack)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut empty_string_array := []string{}
	defer {
		unsafe { empty_string_array.free() }
	}

	mut new_thread := new_user_thread(process, false, pc, unsafe { nil }, stack, empty_string_array, empty_string_array, unsafe { nil }, false) or { return errno.err, errno.get() }

	enqueue_thread(new_thread, false)

	return u64(new_thread.tid), 0
}

// The new address space is not necessarily active during exec. Write its
// initial stack through the direct map, one physical page at a time.
fn write_initial_stack(pagemap &memory.Pagemap, addr u64, src voidptr, length u64) bool {
	mut done := u64(0)
	for done < length {
		virt := addr + done
		phys := pagemap.virt2phys(virt) or { return false }
		offset := virt & (page_size - 1)
		chunk := if length - done < page_size - offset { length - done } else { page_size - offset }
		unsafe {
			C.memcpy(voidptr(phys + higher_half + offset), voidptr(u64(src) + done), chunk)
		}
		done += chunk
	}
	return true
}

fn push_initial_bytes(pagemap &memory.Pagemap, bottom u64, mut cursor u64, src voidptr, length u64) bool {
	if cursor < bottom || length > cursor - bottom {
		return false
	}
	cursor -= length
	return write_initial_stack(pagemap, cursor, src, length)
}

fn push_initial_word(pagemap &memory.Pagemap, bottom u64, mut cursor u64, value u64) bool {
	return push_initial_bytes(pagemap, bottom, mut cursor, voidptr(&value), sizeof(u64))
}

fn push_initial_pair(pagemap &memory.Pagemap, bottom u64, mut cursor u64, key u64, value u64) bool {
	return push_initial_word(pagemap, bottom, mut cursor, value)
		&& push_initial_word(pagemap, bottom, mut cursor, key)
}

pub fn new_user_thread(_process &proc.Process, want_elf bool, pc voidptr, arg voidptr, _stack u64, argv []string, envp []string, auxval &elf.Auxval, autoenqueue bool) ?&proc.Thread {
	mut process := unsafe { _process }
	trace_gpu_exec := process.executable_path == '/usr/bin/vinix-desktop-gpu'
	if trace_gpu_exec {
		println('exec[gpu]/thread: entered new_user_thread')
	}

	mut stacks := []voidptr{}
	defer {
		unsafe { stacks.free() }
	}

	mut stack_vma := u64(0)
	mut stack_bottom_vma := u64(0)

	if _stack == 0 {
		if trace_gpu_exec {
			println('exec[gpu]/thread: calculating user stack size')
		}
		mut user_stack_size := default_user_stack_size
		stack_limit := proc.soft_limit(process, proc.rlimit_stack)
		if stack_limit != proc.rlim_infinity && stack_limit < user_stack_size {
			user_stack_size = lib.align_down(stack_limit, page_size)
		}
		if user_stack_size < page_size {
			errno.set(errno.enomem)
			return none
		}
		if trace_gpu_exec {
			println('exec[gpu]/thread: allocating ${user_stack_size / page_size} physical stack pages')
		}
		mut stack_pages := []u64{cap: int(user_stack_size / page_size)}
		for _ in 0 .. int(user_stack_size / page_size) {
			stack_pages << u64(memory.pmm_alloc(1))
		}

		stack_vma = process.thread_stack_top
		process.thread_stack_top -= user_stack_size
		stack_bottom_vma = process.thread_stack_top
		process.thread_stack_top -= page_size

		if trace_gpu_exec {
			println('exec[gpu]/thread: mapping user stack at 0x${stack_bottom_vma:x} len=0x${user_stack_size:x}')
		}
		mmap.map_pages(mut process.pagemap, stack_bottom_vma, stack_pages, mmap.prot_read | mmap.prot_write, mmap.map_anonymous) or {
			unsafe { stack_pages.free() }
			return none
		}
		unsafe { stack_pages.free() }
		if trace_gpu_exec {
			println('exec[gpu]/thread: user stack mapped')
		}
	} else {
		stack_vma = _stack
	}

	if trace_gpu_exec {
		println('exec[gpu]/thread: allocating kernel stack')
	}
	kernel_stack_phys := memory.pmm_alloc(kernel_stack_size / page_size)
	stacks << kernel_stack_phys
	kernel_stack := u64(kernel_stack_phys) + kernel_stack_size + higher_half
	if trace_gpu_exec {
		println('exec[gpu]/thread: kernel stack allocated at 0x${u64(kernel_stack_phys):x}')
		println('exec[gpu]/thread: allocating FPU storage')
	}

	fpu_storage_phys := memory.pmm_alloc(lib.div_roundup(fpu_storage_size, page_size))
	if trace_gpu_exec {
		println('exec[gpu]/thread: FPU storage allocated at 0x${u64(fpu_storage_phys):x}')
	}

	gpr_state := cpulocal.GPRState{
		pc: u64(pc)
		x0: u64(arg)
		sp: u64(stack_vma)
		pstate: 0x000 // EL0t, no DAIF masking
	}

	mut t := &proc.Thread{
		process: process
		ttbr0: u64(process.pagemap.top_level)
		gpr_state: gpr_state
		timeslice: 5000
		running_on: u64(-1)
		kernel_stack: kernel_stack
		kstack_phys: u64(kernel_stack_phys)
		stacks: stacks
		fpu_storage: voidptr(u64(fpu_storage_phys) + higher_half)
		fpu_storage_phys: u64(fpu_storage_phys)
	}
	if trace_gpu_exec {
		println('exec[gpu]/thread: thread object initialized pc=0x${t.gpr_state.pc:x} sp=0x${t.gpr_state.sp:x}')
	}

	t.self = voidptr(t)
	t.tpidr_el0 = u64(0)

	// Set all sigactions to default (SIG_DFL = 0 on Linux, -2 on mlibc)
	for mut sa in t.sigactions {
		sa.sa_sigaction = voidptr(0)
	}

	if want_elf == true {
		if trace_gpu_exec {
			println('exec[gpu]/thread: building initial ELF stack')
		}
		if auxval != unsafe { nil } {
			uart.puts(c'ELF auxval: base=')
			uart.put_hex(auxval.at_base)
			uart.puts(c' phdr=')
			uart.put_hex(auxval.at_phdr)
			uart.puts(c' entry=')
			uart.put_hex(auxval.at_entry)
			uart.putc(`\n`)
		}
		mut cursor := stack_vma
		mut string_pointer := stack_vma
		for elem in envp {
			if !push_initial_bytes(process.pagemap, stack_bottom_vma, mut cursor,
				voidptr(elem.str), u64(elem.len) + 1) {
				errno.set(errno.e2big)
				return none
			}
		}
		for elem in argv {
			if !push_initial_bytes(process.pagemap, stack_bottom_vma, mut cursor,
				voidptr(elem.str), u64(elem.len) + 1) {
				errno.set(errno.e2big)
				return none
			}
		}
		cursor &= ~u64(0xf)
		if (argv.len + envp.len + 1) & 1 != 0 {
			cursor -= sizeof(u64)
		}
		mut random_bytes := [16]u8{}
		if !krandom.fill(voidptr(&random_bytes[0]), 16, true) {
			unsafe { C.memset(voidptr(&random_bytes[0]), 0, 16) }
		}
		if !push_initial_bytes(process.pagemap, stack_bottom_vma, mut cursor,
			voidptr(&random_bytes[0]), 16) {
			errno.set(errno.e2big)
			return none
		}
		random_vma := cursor

		// Auxiliary vector (NULL-terminated). ARM64 advertises the mandatory
		// FP/ASIMD baseline and no optional extensions yet.
		if !push_initial_pair(process.pagemap, stack_bottom_vma, mut cursor, 0, 0)
			|| !push_initial_pair(process.pagemap, stack_bottom_vma, mut cursor, elf.at_secure, 0)
			|| !push_initial_pair(process.pagemap, stack_bottom_vma, mut cursor, elf.at_hwcap2, 0)
			|| !push_initial_pair(process.pagemap, stack_bottom_vma, mut cursor, elf.at_hwcap, 0x3)
			|| !push_initial_pair(process.pagemap, stack_bottom_vma, mut cursor, elf.at_random, random_vma)
			|| !push_initial_pair(process.pagemap, stack_bottom_vma, mut cursor, elf.at_pagesz, page_size)
			|| !push_initial_pair(process.pagemap, stack_bottom_vma, mut cursor, elf.at_uid, u64(process.uid))
			|| !push_initial_pair(process.pagemap, stack_bottom_vma, mut cursor, elf.at_euid, u64(process.euid))
			|| !push_initial_pair(process.pagemap, stack_bottom_vma, mut cursor, elf.at_gid, u64(process.gid))
			|| !push_initial_pair(process.pagemap, stack_bottom_vma, mut cursor, elf.at_egid, u64(process.egid))
			|| !push_initial_pair(process.pagemap, stack_bottom_vma, mut cursor, elf.at_entry, auxval.at_entry)
			|| !push_initial_pair(process.pagemap, stack_bottom_vma, mut cursor, elf.at_phdr, auxval.at_phdr)
			|| !push_initial_pair(process.pagemap, stack_bottom_vma, mut cursor, elf.at_phent, auxval.at_phent)
			|| !push_initial_pair(process.pagemap, stack_bottom_vma, mut cursor, elf.at_phnum, auxval.at_phnum)
			|| !push_initial_pair(process.pagemap, stack_bottom_vma, mut cursor, elf.at_base, auxval.at_base)
			|| !push_initial_word(process.pagemap, stack_bottom_vma, mut cursor, 0) {
			errno.set(errno.e2big)
			return none
		}
		if cursor < stack_bottom_vma || u64(envp.len) * sizeof(u64) > cursor - stack_bottom_vma {
			errno.set(errno.e2big)
			return none
		}
		cursor -= u64(envp.len) * sizeof(u64)
		for i, elem in envp {
			string_pointer -= u64(elem.len) + 1
			pointer := string_pointer
			if !write_initial_stack(process.pagemap, cursor + u64(i) * sizeof(u64),
				voidptr(&pointer), sizeof(u64)) {
				return none
			}
		}
		if !push_initial_word(process.pagemap, stack_bottom_vma, mut cursor, 0) {
			errno.set(errno.e2big)
			return none
		}
		if cursor < stack_bottom_vma || u64(argv.len) * sizeof(u64) > cursor - stack_bottom_vma {
			errno.set(errno.e2big)
			return none
		}
		cursor -= u64(argv.len) * sizeof(u64)
		for i, elem in argv {
			string_pointer -= u64(elem.len) + 1
			pointer := string_pointer
			if !write_initial_stack(process.pagemap, cursor + u64(i) * sizeof(u64),
				voidptr(&pointer), sizeof(u64)) {
				return none
			}
		}
		if !push_initial_word(process.pagemap, stack_bottom_vma, mut cursor, u64(argv.len)) {
			errno.set(errno.e2big)
			return none
		}
		t.gpr_state.sp = cursor
		if trace_gpu_exec {
			println('exec[gpu]/thread: initial ELF stack complete sp=0x${t.gpr_state.sp:x}')
		}
	}

	if trace_gpu_exec {
		println('exec[gpu]/thread: attaching replacement thread to process')
	}
	attach_thread(mut process, mut t)?
	if trace_gpu_exec {
		println('exec[gpu]/thread: replacement thread attached tid=${t.tid}')
	}

	if autoenqueue == true {
		if trace_gpu_exec {
			println('exec[gpu]/thread: auto-enqueueing replacement thread')
		}
		enqueue_thread(t, false)
		if trace_gpu_exec {
			println('exec[gpu]/thread: auto-enqueue complete')
		}
	}

	if trace_gpu_exec {
		println('exec[gpu]/thread: leaving new_user_thread')
	}
	return t
}

// Give a thread its id and add it to its process. The first thread of a process
// is its main thread and, as on Linux, takes the tid that matches the pid;
// every other thread draws its own id out of the shared namespace.
fn attach_thread(mut process proc.Process, mut t proc.Thread) ?int {
	process.threads_lock.acquire()
	defer {
		process.threads_lock.release()
	}

	if process.threads.len == 0 && process.pid != 0 {
		t.tid = process.pid
		proc.bind_tid(t.tid, t)
	} else {
		t.tid = proc.allocate_tid(t)?
	}

	process.threads << t
	return t.tid
}

// Create an additional thread inside an existing process, cloning the caller's
// register state. This is what backs clone()/clone3() with CLONE_VM: the new
// thread shares the address space and only gets its own stack, TLS and tid.
pub fn new_cloned_thread(_process &proc.Process, _source &proc.Thread, state &cpulocal.GPRState, child_sp u64, tls u64, set_tls bool) ?&proc.Thread {
	mut process := unsafe { _process }
	mut source := unsafe { _source }

	stack_pages := kernel_stack_size / page_size
	fpu_pages := lib.div_roundup(fpu_storage_size, page_size)

	kernel_stack_phys := memory.pmm_alloc_fallible(stack_pages)
	if kernel_stack_phys == unsafe { nil } {
		return none
	}
	fpu_storage_phys := memory.pmm_alloc_fallible(fpu_pages)
	if fpu_storage_phys == unsafe { nil } {
		memory.pmm_free(kernel_stack_phys, stack_pages)
		return none
	}

	mut t := &proc.Thread{
		process: process
		ttbr0: u64(process.pagemap.top_level)
		gpr_state: state
		timeslice: source.timeslice
		running_on: u64(-1)
		kernel_stack: u64(kernel_stack_phys) + kernel_stack_size + higher_half
		kstack_phys: u64(kernel_stack_phys)
		fpu_storage: voidptr(u64(fpu_storage_phys) + higher_half)
		fpu_storage_phys: u64(fpu_storage_phys)
		sigentry: source.sigentry
		sigactions: source.sigactions
		masked_signals: source.masked_signals
		affinity_mask: source.affinity_mask
		sched: inherited_sched_params(source)
	}

	t.self = voidptr(t)

	// The saved copy belongs to the last scheduler switch; clone/fork must copy
	// the caller's live SIMD state as it exists at this syscall boundary.
	fpu_save(source.fpu_storage)
	unsafe { C.memcpy(t.fpu_storage, source.fpu_storage, fpu_storage_size) }

	// The child resumes right after its svc, returning 0 on its own stack.
	t.gpr_state.x0 = u64(0)
	t.gpr_state.sp = child_sp
	t.tpidr_el0 = if set_tls { tls } else { cpu.read_tpidr_el0() }
	t.gpr_state.tpidr_el0 = t.tpidr_el0

	attach_thread(mut process, mut t) or {
		memory.pmm_free(kernel_stack_phys, stack_pages)
		memory.pmm_free(fpu_storage_phys, fpu_pages)
		return none
	}

	return t
}

pub fn new_process(old_process &proc.Process, pagemap &memory.Pagemap) ?&proc.Process {
	if unsafe { old_process != nil } && !proc.may_create_process(old_process) {
		errno.set(errno.eagain)
		return none
	}
	mut new_proc := &proc.Process{
		pagemap: unsafe { nil }
	}

	new_proc.pid = proc.allocate_pid(new_proc) or { return none }

	if unsafe { old_process != 0 } {
		new_proc.ppid = old_process.pid
		new_proc.pgid = old_process.pgid
		new_proc.sid = old_process.sid
		new_proc.uid = old_process.uid
		new_proc.euid = old_process.euid
		new_proc.suid = old_process.suid
		new_proc.gid = old_process.gid
		new_proc.egid = old_process.egid
		new_proc.sgid = old_process.sgid
		new_proc.groups = old_process.groups.clone()
		new_proc.umask = old_process.umask
		new_proc.nice = old_process.nice
		new_proc.executable_path = old_process.executable_path.clone()
		new_proc.rlimits = old_process.rlimits
		new_proc.allow_wx = old_process.allow_wx
		// A NUMA memory policy is process state, like nice and the rlimits, so
		// a fork keeps the placement its parent asked for.
		new_proc.mempolicy_mode = old_process.mempolicy_mode
		new_proc.mempolicy_nodemask = old_process.mempolicy_nodemask
		new_proc.pagemap = mmap.fork_pagemap(old_process.pagemap) or { return none }
		new_proc.thread_stack_top = old_process.thread_stack_top
		new_proc.mmap_anon_non_fixed_base = old_process.mmap_anon_non_fixed_base
		new_proc.current_directory = proc.current_directory_of(old_process)
		proc.inherit_container_state(mut new_proc, old_process)
	} else {
		new_proc.ppid = 0
		new_proc.pgid = new_proc.pid
		new_proc.sid = new_proc.pid
		new_proc.pagemap = unsafe { pagemap }
		new_proc.thread_stack_top = elf.initial_stack_top()
		new_proc.mmap_anon_non_fixed_base = elf.initial_mmap_base()
		new_proc.current_directory = voidptr(vfs_root)
		new_proc.rlimits = proc.default_rlimits()
		proc.inherit_container_state(mut new_proc, unsafe { nil })
	}

	return new_proc
}

// idle_tick_hz is how often the idle loop dispatches the scheduler. It bounds
// the wakeup latency of every sleeping thread: nothing that is waiting on a
// timer can run again sooner than the next tick, so a 20 Hz idle tick made
// *every* nanosleep cost about 50 ms however short it asked for. The loop
// already polls rather than waiting on an interrupt, so ticking a thousand
// times a second costs it nothing it was not already spending.
const idle_tick_hz = u64(1000)

pub fn await() {
	await_impl(false)
}

fn await_impl(trace_gpu_handoff bool) {
	if trace_gpu_handoff {
		println('exec[gpu]/sched: traced idle loop entered; reading timer frequency')
	}
	freq := cpu.read_cntfrq_el0()
	mut ticks := freq / idle_tick_hz
	if ticks == 0 {
		ticks = 1
	}
	cpu.write_cntv_tval_el0(ticks)
	cpu.write_cntv_ctl_el0(1)
	if trace_gpu_handoff {
		println('exec[gpu]/sched: idle timer programmed for ${ticks} ticks; disabling interrupts')
	}

	// Polling idle loop used on both QEMU/HVF and early Apple bring-up.
	// Keep interrupts disabled, poll CNTV_CTL ISTATUS, and dispatch the
	// scheduler timer handler directly when the timer fires.
	cpu.interrupt_toggle(false)
	if trace_gpu_handoff {
		println('exec[gpu]/sched: idle interrupts disabled; polling timer')
	}

	mut last_realtime_poll_ns := u64(0)
	mut first_poll := true

	for {
		vctl := cpu.read_cntv_ctl_el0()
		if trace_gpu_handoff && first_poll {
			println('exec[gpu]/sched: first idle timer status=0x${vctl:x}')
			first_poll = false
		}
		if vctl & 0x4 != 0 {
			if trace_gpu_handoff {
				println('exec[gpu]/sched: idle timer fired; dispatching scheduler')
			}
			// Timer fired. Dispatch scheduler in polling mode.
			scheduler_timer_handler(unsafe { nil })
			if trace_gpu_handoff {
				println('exec[gpu]/sched: idle scheduler dispatch returned without a target; rearming timer')
			}

			// Re-arm timer for next tick
			cpu.write_cntv_tval_el0(ticks)
			cpu.write_cntv_ctl_el0(1)
		} else if proc.scheduling_policies_in_use() {
			// A real-time thread must not wait for the idle tick. This loop
			// runs at a thousand ticks a second, which is the granularity a
			// sleeping thread's wakeup is noticed at and the granularity the
			// run queue is looked at again -- a millisecond of dispatch latency
			// on a CPU that has nothing else to do.
			//
			// So look more often than that, at a rate set by how long a real-
			// time thread should have to wait rather than by how often the
			// clocks need moving. Bringing the clocks up to date is what
			// expires the timer such a thread is sleeping on, and the check
			// after it is what hands it the CPU.
			now_ns := timer.get_ns()
			if now_ns - last_realtime_poll_ns >= realtime_poll_interval_ns {
				last_realtime_poll_ns = now_ns
				time.advance_to_ns(now_ns)
				if realtime_work_pending(cpu.read_tpidr_el1()) {
					scheduler_timer_handler(unsafe { nil })
					cpu.write_cntv_tval_el0(ticks)
					cpu.write_cntv_ctl_el0(1)
				}
			}
		}

		// Poll UART input while idle (no separate thread — HVF workaround).
		// Uses a callback set by the console module to avoid circular imports.
		poll_platform_input()

		asm volatile aarch64 {
			yield
			; ; ; memory
		}
	}
}

// ── ITIMER_REAL (per-process interval timer → SIGALRM) ──

const max_itimer_real = 32

struct ItimerRealEntry {
mut:
	thrd        &proc.Thread = unsafe { nil }
	value_us    i64 // microseconds remaining (0 = inactive)
	interval_us i64 // microseconds to reload after firing
	active      bool
}

__global (
	itimer_real_entries [max_itimer_real]ItimerRealEntry
	itimer_real_lock    klock.Lock
	itimer_last_cntpct  = u64(0)
	itimer_cntfrq       = u64(0)
)

fn tick_itimers() {
	// Read hardware counter for accurate elapsed time
	mut counter := u64(0)
	asm volatile aarch64 {
		mrs counter, CNTVCT_EL0
		; =r (counter)
	}

	if itimer_cntfrq == 0 {
		itimer_cntfrq = cpu.read_cntfrq_el0()
	}

	if itimer_last_cntpct == 0 {
		itimer_last_cntpct = counter
		return
	}

	elapsed_ticks := counter - itimer_last_cntpct
	itimer_last_cntpct = counter

	// Convert to microseconds: elapsed_ticks * 1000000 / freq
	elapsed_us := i64(elapsed_ticks * 1000000 / itimer_cntfrq)
	if elapsed_us <= 0 {
		return
	}

	if !itimer_real_lock.test_and_acquire() {
		return
	}

	for i := 0; i < max_itimer_real; i++ {
		mut e := unsafe { &itimer_real_entries[i] }
		if !e.active || e.value_us <= 0 {
			continue
		}
		e.value_us -= elapsed_us
		if e.value_us <= 0 {
			// Fire SIGALRM (signal 14, which is bit 13)
			katomic.bts(mut &e.thrd.pending_signals, u8(13))
			enqueue_thread(e.thrd, true)
			if e.interval_us > 0 {
				e.value_us = e.interval_us
			} else {
				e.active = false
			}
		}
	}

	itimer_real_lock.release()
}

// set_itimer_real arms or disarms a per-thread ITIMER_REAL timer.
// Returns the previous (value_us, interval_us).
pub fn set_itimer_real(thrd &proc.Thread, value_us i64, interval_us i64) (i64, i64) {
	itimer_real_lock.acquire()
	defer {
		itimer_real_lock.release()
	}

	// Find existing entry for this thread
	for i := 0; i < max_itimer_real; i++ {
		mut e := unsafe { &itimer_real_entries[i] }
		if e.active && e.thrd == thrd {
			old_value := e.value_us
			old_interval := e.interval_us
			if value_us <= 0 && interval_us <= 0 {
				e.active = false
			} else {
				e.value_us = value_us
				e.interval_us = interval_us
			}
			return old_value, old_interval
		}
	}

	// Not found — add new entry if arming
	if value_us > 0 || interval_us > 0 {
		for i := 0; i < max_itimer_real; i++ {
			mut e := unsafe { &itimer_real_entries[i] }
			if !e.active {
				e.thrd = unsafe { thrd }
				e.value_us = value_us
				e.interval_us = interval_us
				e.active = true
				break
			}
		}
	}

	return 0, 0
}

// get_itimer_real returns the current (value_us, interval_us) for a thread.
pub fn get_itimer_real(thrd &proc.Thread) (i64, i64) {
	itimer_real_lock.acquire()
	defer {
		itimer_real_lock.release()
	}

	for i := 0; i < max_itimer_real; i++ {
		e := itimer_real_entries[i]
		if e.active && e.thrd == thrd {
			return e.value_us, e.interval_us
		}
	}

	return 0, 0
}
