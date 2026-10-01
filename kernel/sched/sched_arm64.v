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
	mut thr := unsafe { &proc.Thread(_thread) }
	thr.l.release()
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
fn evict_to_idle(cpu_number u64, thr &proc.Thread) {
	mut index := cpu_number
	if index >= max_idle_stacks {
		index = max_idle_stacks - 1
	}
	mut top := u64(voidptr(&idle_stacks[index][0])) + u64(idle_stack_size)
	top &= ~u64(0xf)
	C.vinix_enter_idle(top, voidptr(finish_eviction), voidptr(thr))
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
	// A synchronous exception is the normal first event after exec: the ELF
	// entry point is demand-paged. Keep the initial quantum stopped until that
	// exception has installed its PTE and is ready to return to EL0. This avoids
	// racing a timer FIQ against the first page-in on physical Apple hardware,
	// and gives the one-shot trace a post-page-in checkpoint.
	gpu_exec_sync_active = u64(0)
	gpu_exec_sync_cpu    = u64(-1)
	gpu_exec_sync_state  u64
	// Printing to the framebuffer is slow enough to consume a short scheduler
	// slice. Hold the first GPU desktop slice here and arm it only when the
	// first lower-EL exception has completed.
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

fn clear_gpu_exec_sync_trace() {
	katomic.store(mut &gpu_exec_sync_active, u64(0))
	katomic.store(mut &gpu_exec_sync_cpu, u64(-1))
	katomic.store(mut &gpu_exec_sync_state, u64(0))
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
			C.kprintf(c'exec[gpu]/switch: eret readback ELR=0x%llx SPSR=0x%llx CurrentEL=0x%llx\n',
				u64(cpu.read_elr_el1()), u64(cpu.read_spsr_el1()), u64(cpu.read_currentel()))
			C.kprintf(c'exec[gpu]/switch: saved target pc=0x%llx sp=0x%llx pstate=0x%llx tls=0x%llx\n',
				u64(state.pc), u64(state.sp), u64(state.pstate), u64(state.tpidr_el0))
			deferred_slice := katomic.load(&gpu_exec_deferred_timeslice)
			C.kprintf(c'exec[gpu]/switch: target stack and TPIDR ready; deferring %llu us timeslice until first lower-EL return\n',
				u64(deferred_slice))
			// The new ELF entry point is demand-paged. Enter EL0 with the timer
			// stopped, resolve that first exception as one transaction, then arm a
			// fresh slice from scheduler_gpu_sync_exit_trace().
			// Keep the trace armed across eret. The first lower-EL exception
			// vector clears it after saving the exception frame, which lets the
			// M1 distinguish an eret which never completes from an immediate
			// instruction abort, interrupt, FIQ, or SError.
		}
		else { C.kprintf(c'exec[gpu]/switch: unknown assembly phase %llu\n', u64(phase)) }
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

	// The first synchronous exception is normally the instruction translation
	// fault which demand-pages the new executable's entry point. Transfer the
	// trace to its exit hook without printing on entry: the framebuffer console
	// is slow, and the useful boundary is whether page-in actually completed.
	if kind == 0 {
		katomic.store(mut &gpu_exec_sync_cpu, cpu_number)
		katomic.store(mut &gpu_exec_sync_state, u64(raw_state))
		katomic.store(mut &gpu_exec_sync_active, u64(1))
		katomic.store(mut &gpu_exec_switch_state, u64(0))
		katomic.store(mut &gpu_exec_switch_cpu, u64(-1))
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
	C.kprintf(c'exec[gpu]/eret: crossed into EL0; first lower-EL %.*s vector entered on CPU %llu\n',
		i32(name.len), name.str, u64(cpu_number))
	C.kprintf(c'exec[gpu]/eret: ESR=0x%llx EC=0x%llx FAR=0x%llx\n', u64(esr), u64(esr >> 26),
		u64(far))
	C.kprintf(c'exec[gpu]/eret: exception frame pc=0x%llx sp=0x%llx pstate=0x%llx x0=0x%llx x8=0x%llx\n',
		u64(state.pc), u64(state.sp), u64(state.pstate), u64(state.x0), u64(state.x8))
}

// Finish the first synchronous exception after its handler and signal work
// have completed, but before the saved EL0 frame is restored. A demand-fault
// handler normally arms its own fresh slice; stop that timer while printing so
// the checkpoint itself cannot consume the quantum, then arm the exec slice.
@[export: 'scheduler_gpu_sync_exit_trace']
fn scheduler_gpu_sync_exit_trace(raw_state voidptr) {
	if katomic.load(&gpu_exec_sync_active) == 0
		|| katomic.load(&gpu_exec_sync_cpu) != cpu.read_tpidr_el1()
		|| katomic.load(&gpu_exec_sync_state) != u64(raw_state) {
		return
	}

	deferred_slice := katomic.load(&gpu_exec_deferred_timeslice)
	timer.stop()
	C.kprintf(c'exec[gpu]/eret: first lower-EL synchronous exception completed; arming deferred %llu us timeslice\n',
		u64(deferred_slice))
	clear_gpu_exec_sync_trace()
	katomic.store(mut &gpu_exec_deferred_timeslice, u64(0))
	if deferred_slice != 0 {
		timer.oneshot(deferred_slice)
	}
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
		0 {
			C.kprintf(c'exec[gpu]/%.*s: entering common interrupt dispatcher\n', i32(kind.len),
				kind.str)
		}
		1 {
			C.kprintf(c'exec[gpu]/%.*s: common interrupt dispatcher returned; running exit barrier\n',
				i32(kind.len), kind.str)
		}
		2 {
			deferred_slice := katomic.load(&gpu_exec_deferred_timeslice)
			if deferred_slice != 0 {
				C.kprintf(c'exec[gpu]/%.*s: exit barrier complete; arming deferred %llu us timeslice and restoring EL0\n',
					i32(kind.len), kind.str, u64(deferred_slice))
			} else {
				C.kprintf(c'exec[gpu]/%.*s: exit barrier complete; restoring saved EL0 frame\n',
					i32(kind.len), kind.str)
			}
			clear_gpu_exec_interrupt_trace()
			katomic.store(mut &gpu_exec_deferred_timeslice, u64(0))
			if deferred_slice != 0 {
				timer.oneshot(deferred_slice)
			}
		}
		else {
			C.kprintf(c'exec[gpu]/%.*s: unknown vector phase %llu\n', i32(kind.len), kind.str,
				u64(phase))
		}
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
		1 {
			pending := if cntv_ctl & 4 != 0 { c'true' } else { c'false' }
			C.kprintf(c'exec[gpu]/FIQ: CNTV_CTL=0x%llx pending=%s\n', u64(cntv_ctl), pending)
		}
		2 { println('exec[gpu]/FIQ: virtual timer pending; entering scheduler timer handler') }
		3 {
			C.kprintf(c'exec[gpu]/FIQ: scheduler timer handler returned; CNTV_CTL=0x%llx\n',
				u64(cntv_ctl))
		}
		4 { println('exec[gpu]/FIQ: virtual timer not pending; continuing with AIC event drain') }
		else { C.kprintf(c'exec[gpu]/FIQ: unknown callback phase %llu\n', u64(phase)) }
	}
}

pub fn initialise() {
	// The kernel acts with every capability: file permissions are lifted by
	// capabilities, not by a uid of zero, and kernel threads create files
	// wherever the initramfs puts them.
	kernel_process = &proc.Process{
		pagemap: &kernel_pagemap
		caps:    proc.full_capabilities()
		fds:     unsafe { []voidptr{len: proc.initial_fds} }
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

__global (
	user_signal_hook voidptr
)

type UserSignalHook = fn (&cpulocal.GPRState)

// userland registers its fatal-signal dispatch here; it cannot be imported.
pub fn register_user_signal_hook(hook voidptr) {
	user_signal_hook = hook
}

// A thread that never makes a syscall -- a loop that only computes -- would
// otherwise never take a signal, since the syscall exit and the fault handlers
// are the only places one is delivered: kill -9 could not stop it, and a
// container spinning like that could never be removed. So a tick that
// interrupts a thread in userspace ends it if it has a fatal signal pending.
// `state` is the frame the thread was interrupted in.
fn deliver_signal_on_tick(t &proc.Thread, state &cpulocal.GPRState) {
	if user_signal_hook == unsafe { nil } || state.pstate & 0xf != 0 {
		return
	}
	// SIGKILL gets through whatever the mask says.
	deliverable := ~t.masked_signals | (u64(1) << 8)
	if katomic.load(&t.pending_signals) & deliverable == 0 {
		return
	}
	hook := unsafe { UserSignalHook(user_signal_hook) }
	hook(state)
}

// The scheduler's clock: the generic timer's counter.
@[inline]
fn clock_ns() u64 {
	return timer.get_ns()
}

@[inline]
fn interrupts_off() {
	cpu.interrupt_toggle(false)
}

// See cgroup_holds_thread_back(). `state` is where the thread would resume.
fn cgroup_parks(t &proc.Thread, state &cpulocal.GPRState) bool {
	return cgroup_holds_thread_back(t, state.pstate & 0xf != 0)
}

fn get_next_thread() &proc.Thread {
	scheduler_queue_lock.acquire()
	defer {
		scheduler_queue_lock.release()
	}
	mut cpu_local := cpulocal.current()
	return pick_next_thread(cpu_local.cpu_number, int(cpu_local.numa_node), &cpu_local.last_run_queue_index)
}

fn scheduler_timer_handler(_gpr_state voidptr) {
	dispatch_cpu := cpu.read_tpidr_el1()
	trace_gpu_switch := katomic.load(&gpu_exec_switch_state) != 0
		&& katomic.load(&gpu_exec_switch_cpu) == dispatch_cpu
	trace_gpu_interrupt := gpu_exec_interrupt_trace_active(dispatch_cpu)
	trace_gpu_dispatch := trace_gpu_switch || trace_gpu_interrupt
	if trace_gpu_dispatch {
		C.kprintf(c'exec[gpu]/sched: immediate scheduler handler entered on CPU %llu\n',
			u64(dispatch_cpu))
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
	// When each tick lands, to the cycle, is what the generator reseeds from.
	krandom.add_event(now_ns)
	if trace_gpu_dispatch {
		C.kprintf(c'exec[gpu]/sched: scheduler clock advanced to %llu ns\n', u64(now_ns))
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
	// And the cgroup's cpu.max: a thread that keeps the CPU is charged as it
	// goes, not only when it gives the CPU up.
	if unsafe { current_thread != 0 } {
		proc.charge_cgroup_cpu(mut current_thread, now_ns)
		if unsafe { _gpr_state != nil } {
			deliver_signal_on_tick(current_thread, gpr_state)
		}
	}
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
		C.kprintf(c'exec[gpu]/sched: CPU %llu selected replacement thread from run queue\n',
			u64(cpu_local.cpu_number))
		C.kprintf(c'exec[gpu]/sched: target pc=0x%llx sp=0x%llx ttbr0=0x%llx\n', u64(next_thread.gpr_state.pc),
			u64(next_thread.gpr_state.sp), u64(next_thread.ttbr0))
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
			&& !(unsafe { _gpr_state != nil } && cgroup_parks(current_thread, gpr_state))
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
				C.kprintf(c'exec[gpu]/sched: current thread keeps CPU; deferring %llu us timer rearm until vector exit\n',
					u64(next_slice))
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
				C.kprintf(c'\nSCHED SAVE: pid=3 x30=0x220000! pc=0x%llx sp=0x%llx pstate=0x%llx\n',
					u64(current_thread.gpr_state.pc), u64(current_thread.gpr_state.sp),
					u64(current_thread.gpr_state.pstate))
			}
		} else {
			// gpr_state is nil: check if existing gpr_state has corruption
			if current_thread.process.pid == 3 && current_thread.gpr_state.x30 == u64(0x220000) {
				C.kprintf(c'\nSCHED NIL-SAVE: pid=3 x30=0x220000! pc=0x%llx sp=0x%llx\n',
					u64(current_thread.gpr_state.pc), u64(current_thread.gpr_state.sp))
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
		//
		// That scan must come to the candidate first. The one that found it
		// left this CPU's place in the queue on it, so the next lap started
		// just past it and reached it last -- after the thread being put
		// down, which is runnable again by then. A thread that gave the CPU
		// up with sched_yield(2) took it straight back, every time, and one
		// waiting for a CPU with every CPU busy never got one: with a worker
		// pinned to each, qemu-core's concurrent-wakeups coordinator ran only
		// when something else happened to wake, and took minutes.
		if unsafe { next_thread != nil } {
			next_thread.l.release()
			cpu_local.last_run_queue_index = (cpu_local.last_run_queue_index + max_running_threads - 1) % max_running_threads
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
		C.kprintf(c'exec[gpu]/sched: current TTBR0=0x%llx\n', u64(old_ttbr0))
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
		C.kprintf(c'\nSCHED RESTORE: pid=3 x30=0x220000! pc=0x%llx sp=0x%llx pstate=0x%llx\n',
			u64(current_thread.gpr_state.pc), u64(current_thread.gpr_state.sp), u64(current_thread.gpr_state.pstate))
	}

	next_slice := effective_timeslice(current_thread)
	if trace_gpu_next {
		katomic.store(mut &gpu_exec_deferred_timeslice, next_slice)
		C.kprintf(c'exec[gpu]/sched: deferring %llu us timeslice until final low-level checkpoint\n',
			u64(next_slice))
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
		C.kprintf(c'exec[gpu]/sched: armed first-context-switch tracing on CPU %llu\n', u64(first_cpu))
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
				C.kprintf(c'exec[gpu]/sched: run-queue lock acquired; installed thread in slot %lld\n',
					i64(i))
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
	// The thread's turn ends here. What this CPU does until the thread runs
	// again -- the polling below, which is the idle loop's work done on this
	// thread's stack, or another thread -- is not the thread's time. Charged
	// to it, the tick-long poll made every process that sleeps look busy: a
	// program that did nothing but sleep 16 ms at a time read 10% of a CPU,
	// and the compositor's frame pacing alone most of a window drag's cost.
	if unsafe { current_thread != nil } {
		proc.charge_cpu_time(mut current_thread, timer.get_ns())
	}

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

	// Woken before this CPU gave the thread up: nothing else has started its
	// turn again. One that was switched away was started when it came back.
	if current_thread.scheduled_at_ns == 0 {
		proc.begin_cpu_time(mut current_thread, timer.get_ns())
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

// Leave the CPU for good without going to the reaper. For a thread whose exit a
// sibling tearing the process down has already taken charge of (see
// proc.claim_thread_exit): that sibling is waiting for this thread to be off
// the CPU, and releases what it holds once it is. Its memory stays allocated,
// as for every thread a sibling has to stop.
@[noreturn]
pub fn park_stopped_thread() {
	cpu.interrupt_toggle(false)
	mut t := proc.current_thread()
	katomic.store(mut &t.is_dead, true)
	dequeue_thread(t)
	proc.charge_cpu_time(mut t, timer.get_ns())
	katomic.store(mut &t.running_on, u64(-1))
	t.l.release()
	mut cpu_local := cpulocal.current()
	proc.set_current_thread(cpu_local.cpu_number, unsafe { nil })
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

	if unsafe { previous != nil } {
		reap_thread(previous)
	} else {
		reap_deferred()
	}
}

fn free_thread_memory(t &proc.Thread) {
	if t.kstack_phys != 0 {
		memory.pmm_free(voidptr(t.kstack_phys), kernel_stack_size / page_size)
	}
	if t.fpu_storage_phys != 0 {
		memory.pmm_free(voidptr(t.fpu_storage_phys), lib.div_roundup(fpu_storage_size, page_size))
	}
	unsafe {
		t.comm.free()
		free(voidptr(t))
	}
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
		// PAN, where it is on, from the thread's first instruction: it takes no
		// exception that would set it on the way in.
		pstate: u64(0x3c5) | kernel_pstate_pan
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
			println('exec[gpu]/thread: reserving user stack')
		}
		stack_vma, stack_bottom_vma = reserve_main_stack(mut process, want_elf)?
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
		C.kprintf(c'exec[gpu]/thread: kernel stack allocated at 0x%llx\n', u64(kernel_stack_phys))
		println('exec[gpu]/thread: allocating FPU storage')
	}

	fpu_storage_phys := memory.pmm_alloc(lib.div_roundup(fpu_storage_size, page_size))
	if trace_gpu_exec {
		C.kprintf(c'exec[gpu]/thread: FPU storage allocated at 0x%llx\n', u64(fpu_storage_phys))
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
		C.kprintf(c'exec[gpu]/thread: thread object initialized pc=0x%llx sp=0x%llx\n', u64(t.gpr_state.pc),
			u64(t.gpr_state.sp))
	}

	t.self = voidptr(t)
	t.tpidr_el0 = u64(0)

	// Every signal starts at SIG_DFL, which Linux spells as zero.
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
		t.gpr_state.sp = build_initial_stack(mut process, stack_vma, stack_bottom_vma, argv, envp,
			auxval)?
		if trace_gpu_exec {
			C.kprintf(c'exec[gpu]/thread: initial ELF stack complete sp=0x%llx\n', u64(t.gpr_state.sp))
		}
	}

	if trace_gpu_exec {
		println('exec[gpu]/thread: attaching replacement thread to process')
	}
	attach_thread(mut process, mut t)?
	if trace_gpu_exec {
		C.kprintf(c'exec[gpu]/thread: replacement thread attached tid=%lld\n', i64(t.tid))
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
		comm: source.comm.clone()
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
		C.kprintf(c'exec[gpu]/sched: idle timer programmed for %llu ticks; disabling interrupts\n',
			u64(ticks))
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
			C.kprintf(c'exec[gpu]/sched: first idle timer status=0x%llx\n', u64(vctl))
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

// ITIMER_REAL is counted down by every scheduler tick here: see
// sched/itimer.v.
fn itimer_armed() {}

// The CPU features a program is told of in AT_HWCAP and AT_HWCAP2; see
// build_initial_stack().
fn user_hwcaps() (u64, u64) {
	return cpu.user_hwcaps()
}
