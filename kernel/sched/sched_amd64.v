@[has_globals]
module sched

import x86.cpu
import x86.cpu.local as cpulocal
import x86.idt
import x86.apic
import katomic
import proc
import memory
import memory.mmap
import elf
import lib
import errno
import time
import krandom
import klock

fn C.vinix_call_void_fn(f voidptr)

__global (
	// Hardware that this kernel drives without interrupts -- a network card --
	// polled from the scheduler. See set_device_poll_callback().
	device_poll_callback voidptr
	device_poll_lock     klock.Lock
)

// How long an idle CPU sleeps before it looks at the run queue again, and how
// long CPU 0 does when there is a device to poll: a received frame waits in its
// ring until a CPU comes round, and every round trip on the network pays for
// that twice. Any CPU can run the poll, so one waking often is enough; the rest
// keep the slow tick rather than all costing their host a thousand wakeups a
// second.
const idle_wakeup_us = u64(20000)
const idle_poll_wakeup_us = u64(1000)

// Have the scheduler call `cb` on every pass it makes, on whichever CPU makes
// it, and wake an idle CPU often enough that it keeps being called. This is
// the counterpart of arm64's platform poll, which drives VirtIO networking
// from that scheduler's idle loop and timer tick.
pub fn set_device_poll_callback(cb voidptr) {
	device_poll_callback = cb
}

// One CPU at a time runs the poll: what it drives is not reentrant. A CPU that
// finds another already polling has nothing to add and goes on scheduling.
fn poll_devices() {
	if device_poll_callback == voidptr(0) {
		return
	}
	if !device_poll_lock.test_and_acquire() {
		return
	}
	C.vinix_call_void_fn(device_poll_callback)
	device_poll_lock.release()
}

pub fn initialise() {
	scheduler_vector = idt.allocate_vector()
	C.kprintf(c'sched: Scheduler interrupt vector is 0x%llx\n', u64(scheduler_vector))

	interrupt_table[scheduler_vector] = voidptr(scheduler_isr)
	idt.set_ist(scheduler_vector, 1)

	initialise_tlb_shootdown()

	// The kernel acts with every capability: file permissions are lifted by
	// capabilities, not by a uid of zero, and kernel threads create files
	// wherever the initramfs puts them.
	kernel_process = &proc.Process{
		pagemap: &kernel_pagemap
		caps:    proc.full_capabilities()
		fds:     unsafe { []voidptr{len: proc.initial_fds} }
	}
}

// The scheduler's clock: the monotonic clock, which the timer tick advances.
@[inline]
fn clock_ns() u64 {
	return time.monotonic_ns()
}

@[inline]
fn interrupts_off() {
	asm volatile amd64 {
		cli
	}
}

// See cgroup_holds_thread_back(). `state` is where the thread would resume.
fn cgroup_parks(t &proc.Thread, state &cpulocal.GPRState) bool {
	return cgroup_holds_thread_back(t, !in_userspace(state))
}

// Whether `state` resumes userspace: a code segment of privilege 3, which an
// LDT's can be as well as the GDT's.
@[inline]
fn in_userspace(state &cpulocal.GPRState) bool {
	return state.cs & 3 == 3
}

fn get_next_thread() &proc.Thread {
	scheduler_queue_lock.acquire()
	defer {
		scheduler_queue_lock.release()
	}
	mut cpu_local := cpulocal.current()
	return pick_next_thread(cpu_local.cpu_number, int(cpu_local.numa_node), &cpu_local.last_run_queue_index)
}

__global (
	user_signal_hook voidptr
	preemption_guard voidptr
)

type UserSignalHook = fn (&proc.Thread, &cpulocal.GPRState)
type PreemptionGuard = fn () bool

// A compatibility subsystem can defer a timer switch while holding a Linux
// spinlock. Registered at boot; the callback runs with interrupts disabled.
pub fn register_preemption_guard(guard voidptr) {
	preemption_guard = guard
}

// userland registers what an interrupt returning to userspace has to do for
// the thread; it cannot be imported. As on arm64.
pub fn register_user_signal_hook(hook voidptr) {
	user_signal_hook = hook
}

fn scheduler_isr(_ u32, gpr_state &cpulocal.GPRState) {
	apic.lapic_timer_stop()

	mut cpu_local := cpulocal.current()

	katomic.store(mut &cpu_local.is_idle, false)
	if preemption_guard != unsafe { nil } {
		guard := unsafe { PreemptionGuard(preemption_guard) }
		if !guard() {
			apic.lapic_eoi()
			apic.lapic_timer_oneshot(mut cpu_local, scheduler_vector, 1000)
			return
		}
	}

	// Before the run queue is read, so a thread that the poll wakes -- one
	// waiting on a socket -- can be picked straight away.
	poll_devices()

	// The same reading bills the outgoing thread and starts the incoming one,
	// so a switch neither loses time between the two nor counts it twice.
	now_ns := clock_ns()
	// When each tick lands, to the cycle, is what the generator reseeds from.
	krandom.add_event(now_ns)

	mut current_thread := proc.current_thread()

	// Charge the turn that has just ended against the real-time entitlements it
	// was spending, and against its cgroup's cpu.max, before the pick below: a
	// thread that has just run out is passed over on the scan it ran out on.
	account_realtime_time(cpu_local.cpu_number, current_thread, now_ns)
	if unsafe { current_thread != 0 } {
		proc.charge_cgroup_cpu(mut current_thread, now_ns)
	}

	mut next_thread := get_next_thread()

	if unsafe { current_thread != 0 } {
		// Let a yield() waiting on this lock go on, with a plain store rather
		// than release(): release() puts back the interrupt flag of whoever
		// took the lock last, and that was yield() itself, with interrupts on
		// -- or, when the thread was not yielding at all, an earlier yield().
		// Interrupts turned on here, on the scheduler's IST stack, let the next
		// scheduler interrupt land on the same stack and write its frame over
		// this one: the thread interrupted here was later resumed with another
		// context's registers, or the CPU kept returning to its own iretq.
		katomic.store(mut &current_thread.yield_await.l, false)

		// A thread whose context resume_saved_context() preset is not resumed
		// where it was interrupted, but from that context.
		preset := current_thread.context_preset
		entitled := katomic.load(&current_thread.is_in_queue)
			&& may_run_here(current_thread, cpu_local.cpu_number)
			&& !cgroup_parks(current_thread, gpr_state)
		mut keeps_cpu := unsafe { next_thread == nil } && entitled
		if unsafe { next_thread != nil } && entitled {
			// Something else is runnable, but whether it takes the CPU is the
			// policies' business: a FIFO thread is not interrupted by an equal,
			// and no thread at all is interrupted by something ranked below it.
			throttled := realtime_throttled(cpu_local.cpu_number, now_ns)
			if !should_preempt(mut current_thread, next_thread, now_ns, throttled) {
				// Hand back the thread the scan took for us. Taken here, its
				// lock gives interrupts back off.
				next_thread.l.release()
				next_thread = unsafe { nil }
				keeps_cpu = true
			}
		}
		if keeps_cpu && !preset {
			current_thread.yield_requested = false
			// An LDT another thread of the process has made since, which
			// set_ldt_entry() may be waiting for this CPU to take up.
			load_process_ldt(mut cpu_local, current_thread.process)
			apic.lapic_eoi()
			apic.lapic_timer_oneshot(mut cpu_local, scheduler_vector, effective_timeslice(current_thread))
			return
		}
		current_thread.yield_requested = false
		// Past the early return above this thread really is coming off the
		// CPU, so the turn it has just had is charged to its process. The
		// monotonic clock is the tick source here rather than a counter read,
		// which puts the resolution at one timer tick.
		proc.charge_cpu_time(mut current_thread, now_ns)
		if preset {
			current_thread.context_preset = false
		} else {
			unsafe {
				current_thread.gpr_state = *gpr_state
			}
		}
		current_thread.gs_base = cpu.get_kernel_gs_base()
		current_thread.fs_base = cpu.get_fs_base()
		save_fs_gs(mut current_thread)
		current_thread.cr3 = cpu.read_cr3()
		fpu_save(current_thread.fpu_storage)
		katomic.store(mut &current_thread.running_on, u64(-1))
		current_thread.l.release()
	}

	if unsafe { next_thread == nil } {
		apic.lapic_eoi()
		cpu.set_gs_base(u64(&cpu_local.cpu_number))
		cpu.set_kernel_gs_base(u64(&cpu_local.cpu_number))
		katomic.store(mut &cpu_local.is_idle, true)
		kernel_pagemap.switch_to()
		memory.note_active_pagemap(cpu_local.cpu_number, u64(kernel_pagemap.top_level))
		cpu_local.tss.ist3 = cpu_local.idle_pf_stack
		// No LDT for an idle CPU, so that one being freed is not held up
		// waiting for this CPU to run something.
		load_process_ldt(mut cpu_local, unsafe { nil })
		reap_dead_threads(mut cpu_local)
		await()
	}

	current_thread = next_thread
	proc.begin_cpu_time(mut current_thread, now_ns)

	// The first CPU to run a thread claims it for its node, so that the pages
	// the thread goes on to fault in and the CPU it keeps returning to are on
	// the same side of the machine.
	if current_thread.numa_node < 0 {
		current_thread.numa_node = int(cpu_local.numa_node)
	}

	// Its TLS descriptors and LDT, before anything checks a segment of its
	// frame against them.
	load_segment_tables(mut cpu_local, mut current_thread)

	// A thread going back to userspace with a signal it has to take, or an exit
	// a sibling asked for, is sent to take care of it first; the hook points
	// the frame into the kernel. So is one whose code or stack segment is gone.
	// See userland.interrupt_return().
	if in_userspace(&current_thread.gpr_state) && user_signal_hook != unsafe { nil } {
		hook := unsafe { UserSignalHook(user_signal_hook) }
		// The thread is named: GS still finds the one leaving, or none.
		hook(current_thread, &current_thread.gpr_state)
	}

	cpu_local.tss.ist3 = current_thread.pf_stack
	reap_dead_threads(mut cpu_local)

	// Recorded before it is loaded; see memory.note_active_pagemap().
	memory.note_active_pagemap(cpu_local.cpu_number, current_thread.cr3)
	if cpu.read_cr3() != current_thread.cr3 {
		cpu.write_cr3(current_thread.cr3)
	}

	fpu_restore(current_thread.fpu_storage)

	katomic.store(mut &current_thread.running_on, cpu_local.cpu_number)

	apic.lapic_eoi()
	apic.lapic_timer_oneshot(mut cpu_local, scheduler_vector, effective_timeslice(current_thread))

	// The SWAPGS below leaves GS on the thread for the kernel, and the
	// thread's own base parked in KERNEL_GS_BASE, whichever mode it returns
	// to; in userspace the two are the other way round. A user thread resumed
	// inside a syscall used to lose the GS base it had set with arch_prctl.
	//
	// Last, as nothing past this point may use GS: for a thread resumed in
	// the kernel it holds the thread's own base until the SWAPGS. Freeing the
	// thread that died here used to come after it, and anything on the way
	// that looked at GS -- a lock answering a TLB shootdown asks which CPU it
	// is on -- read address 0, and its fault handler faulted for good.
	fs_base, user_gs_base := load_fs_gs(current_thread)
	if in_userspace(&current_thread.gpr_state) {
		cpu.set_gs_base(u64(current_thread))
		cpu.set_kernel_gs_base(user_gs_base)
	} else {
		cpu.set_gs_base(user_gs_base)
		cpu.set_kernel_gs_base(u64(current_thread))
	}
	cpu.set_fs_base(fs_base)

	new_gpr_state := &current_thread.gpr_state

	asm volatile amd64 {
		mov rsp, new_gpr_state
		pop rax
		mov ds, eax
		pop rax
		mov es, eax
		pop rax
		pop rbx
		pop rcx
		pop rdx
		pop rsi
		pop rdi
		pop rbp
		pop r8
		pop r9
		pop r10
		pop r11
		pop r12
		pop r13
		pop r14
		pop r15
		add rsp, 8
		swapgs
		iretq
		; ; rm (new_gpr_state)
		; memory
	}

	for {
	}
}

pub fn enqueue_thread(_thread &proc.Thread, by_signal bool) bool {
	mut t := unsafe { _thread }

	if by_signal {
		katomic.store(mut &t.enqueued_by_signal, true)
	}

	scheduler_queue_lock.acquire()
	defer {
		scheduler_queue_lock.release()
	}

	// A thread that has died -- by its own exit, or torn down by a sibling's
	// exit_group() or execve() -- is still reachable through the events it
	// was listening on and the timers it had armed. It has no context left to
	// resume, so it must never be picked again. Checked under the queue lock,
	// which dequeue_and_die() takes after marking the thread.
	if t.is_dead {
		return false
	}

	if t.is_in_queue == true {
		return true
	}

	for i := u64(0); i < max_running_threads; i++ {
		if katomic.cas[&proc.Thread](mut &scheduler_running_queue[i], unsafe { nil }, t) {
			katomic.store(mut &t.is_in_queue, true)

			// Check if any CPU is idle and wake it up
			for cpu_entry in cpu_locals {
				if katomic.load(&cpu_entry.is_idle) == true {
					apic.lapic_send_ipi(u8(cpu_entry.lapic_id), scheduler_vector)
					break
				}
			}

			return true
		}
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
			removed = true
		}
	}
	katomic.store(mut &t.is_in_queue, false)

	return removed || !was_enqueued
}

// Who gives back a dead thread's stacks: the thread itself, from its own CPU
// once it is off them, or the sibling that stopped it for good.
const reap_claim_self = 1
const reap_claim_stopped = 2

// Take a thread of another CPU for good, for exit_group() or execve() in one
// of its siblings: it is off every CPU when this returns, and never runs
// again. The caller has marked it dead, so no wakeup can put it back. A thread
// that is already on its way out through dequeue_and_die() is left to go by
// itself: its own CPU has claimed reaping after the final switch. Otherwise
// its stacks are buried here.
pub fn stop_thread_for_good(_thread &proc.Thread) {
	mut t := unsafe { _thread }
	if voidptr(t) == voidptr(proc.current_thread()) {
		return
	}
	mut kicked_cpu := u64(-1)
	for {
		if katomic.load(&t.reap_claim) == u32(reap_claim_self) {
			return
		}
		dequeue_thread(t)
		on := katomic.load(&t.running_on)
		if on == u64(-1) {
			// Off every CPU, unless one is just picking it up: it takes the
			// lock before it says where the thread runs.
			if !t.l.is_held() {
				break
			}
		} else if on != kicked_cpu {
			// Send that CPU to the scheduler, once per CPU it is found on.
			apic.lapic_send_ipi(u8(cpu_locals[on].lapic_id), scheduler_vector)
			kicked_cpu = on
		}
		answer_tlb_shootdown()
		asm volatile amd64 {
			pause
			; ; ; memory
		}
	}
	set_itimer_real(t, 0, 0)
	if katomic.cas(mut &t.reap_claim, u32(0), u32(reap_claim_stopped)) {
		proc.linuxkpi_mark_task_dead(mut t)
		bury_thread(t)
	}
}

// Like dequeue_thread(), but it stops it immediately
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

	apic.lapic_send_ipi(u8(cpu_locals[running_on].lapic_id), scheduler_vector)

	t.l.acquire()
	t.l.release()
}

pub fn yield(save_ctx bool) {
	asm volatile amd64 {
		cli
	}

	apic.lapic_timer_stop()

	mut cpu_local := cpulocal.current()

	mut current_thread := proc.current_thread()

	if save_ctx == true {
		current_thread.yield_await.acquire()
	} else {
		cpu.set_gs_base(u64(&cpu_local.cpu_number))
		cpu.set_kernel_gs_base(u64(&cpu_local.cpu_number))
	}

	apic.lapic_send_ipi(u8(cpu_local.lapic_id), scheduler_vector)

	asm volatile amd64 {
		sti
	}

	if save_ctx == true {
		current_thread.yield_await.acquire()
		current_thread.yield_await.release()
	} else {
		for {
			asm volatile amd64 {
				hlt
			}
		}
	}
}

pub fn dequeue_and_yield() {
	asm volatile amd64 {
		cli
	}
	dequeue_thread(proc.current_thread())
	yield(true)
}

// Leave the CPU for good, as a thread whose exit a sibling tearing the process
// down has already taken charge of (see proc.claim_thread_exit). That sibling's
// stop_thread_for_good() and dequeue_and_die() settle between them, through
// reap_claim, which gives back the stacks.
@[noreturn]
pub fn park_stopped_thread() {
	dequeue_and_die()
}

@[noreturn]
pub fn dequeue_and_die() {
	asm volatile amd64 {
		cli
	}
	mut t := proc.current_thread()
	t.is_dead = true
	proc.linuxkpi_mark_task_dead(mut t)
	// A sibling's exit_group() may be stopping this thread at the same time.
	// Whichever of the two claims it gives back its stacks.
	claimed := katomic.cas(mut &t.reap_claim, u32(0), u32(reap_claim_self))
	dequeue_thread(t)
	// ITIMER_REAL keeps a pointer to the thread that armed it.
	set_itimer_real(t, 0, 0)
	// This thread leaves the CPU here rather than through the switch in
	// scheduler_isr, so its last turn is charged here or not at all.
	proc.charge_cpu_time(mut t, time.monotonic_ns())
	// Its stacks are still in use until the switch; the scheduler gives them
	// back once it is past it.
	if claimed {
		mut cpu_local := cpulocal.current()
		cpu_local.dying_thread = voidptr(t)
	}
	yield(false)
	for {
	}
}

// Give up the CPU, leaving the current thread to resume from the context in
// its gpr_state, which the caller has just rewritten: a signal handler's entry,
// or what a sigreturn restores. The registers of the syscall in progress are
// not the thread's to keep, which is the difference from a timer switch;
// scheduler_isr saves everything else a switch saves and leaves the registers
// alone. It is also what lets go of the thread's lock, once this CPU is on the
// scheduler's own stack. Letting go here, while still running on the thread's
// kernel stack, let another CPU pick the thread up, run its handler and take
// its next syscall on that same stack underneath this CPU, whose interrupts
// then landed in the middle of the other's frames.
pub fn resume_saved_context() {
	asm volatile amd64 {
		cli
	}
	mut t := proc.current_thread()
	t.context_preset = true
	yield(true)
	// scheduler_isr never comes back to a thread whose context was preset.
	for {
	}
}

// Give up the rest of this thread's timeslice without leaving the run queue.
// This mirrors the ARM scheduler helper used by shared kernel wait loops.
pub fn reschedule() {
	yield(true)
}

pub fn new_kernel_thread(pc voidptr, arg voidptr, autoenqueue bool) &proc.Thread {
	stack_phys := memory.pmm_alloc(stack_size / page_size)
	stack := u64(stack_phys) + stack_size + higher_half
	pf_stack_phys := memory.pmm_alloc(stack_size / page_size)
	// IRET enters the function without CALL pushing a return address. The
	// SysV ABI still requires (RSP + 8) to be 16-byte aligned at entry, so
	// reserve that word within the owned stack rather than starting at its top.
	entry_stack := stack - 8
	C.memset(voidptr(entry_stack), 0, 8)

	gpr_state := cpulocal.GPRState{
		cs: kernel_code_seg
		ds: kernel_data_seg
		es: kernel_data_seg
		ss: kernel_data_seg
		rflags: 0x202
		rip: u64(pc)
		rdi: u64(arg)
		rbp: u64(0)
		rsp: entry_stack
	}

	mut t := &proc.Thread{
		process: kernel_process
		cr3: u64(kernel_process.pagemap.top_level)
		gpr_state: gpr_state
		timeslice: 5000
		running_on: u64(-1)
		kernel_stack: stack
		pf_stack: u64(pf_stack_phys) + stack_size + higher_half
		fpu_storage: voidptr(u64(memory.pmm_alloc(lib.div_roundup(fpu_storage_size, page_size))) + higher_half)
	}

	t.self = voidptr(t)
	t.gs_base = u64(voidptr(t))
	proc.linuxkpi_init_task(mut t, unsafe { nil })

	if autoenqueue == true {
		enqueue_thread(t, false)
	}

	return t
}

pub fn new_user_thread(_process &proc.Process, want_elf bool, pc voidptr, arg voidptr, _stack u64, argv []string, envp []string, auxval &elf.Auxval, autoenqueue bool) ?&proc.Thread {
	mut process := unsafe { _process }

	mut stacks := []voidptr{}
	defer {
		unsafe { stacks.free() }
	}

	mut stack_vma := u64(0)
	mut stack_bottom_vma := u64(0)

	if _stack == 0 {
		stack_vma, stack_bottom_vma = reserve_main_stack(mut process, want_elf)?
	} else {
		stack_vma = _stack
	}

	kernel_stack_phys := memory.pmm_alloc(stack_size / page_size)
	stacks << kernel_stack_phys
	kernel_stack := u64(kernel_stack_phys) + stack_size + higher_half

	pf_stack_phys := memory.pmm_alloc(stack_size / page_size)
	stacks << pf_stack_phys
	pf_stack := u64(pf_stack_phys) + stack_size + higher_half

	gpr_state := cpulocal.GPRState{
		cs: user_code_seg
		ds: user_data_seg
		es: user_data_seg
		ss: user_data_seg
		rflags: 0x202
		rip: u64(pc)
		rdi: u64(arg)
		rsp: u64(stack_vma)
	}

	mut t := &proc.Thread{
		process: process
		cr3: u64(process.pagemap.top_level)
		gpr_state: gpr_state
		timeslice: 5000
		running_on: u64(-1)
		kernel_stack: kernel_stack
		pf_stack: pf_stack
		stacks: stacks
		fpu_storage: voidptr(u64(memory.pmm_alloc(lib.div_roundup(fpu_storage_size, page_size))) + higher_half)
	}

	t.self = voidptr(t)
	t.gs_base = u64(0)
	t.fs_base = u64(0)

	// Set up FPU control word and MXCSR as defined in the sysv ABI
	fpu_restore(t.fpu_storage)

	default_fcw := u16(0b1100111111)

	asm volatile amd64 {
		fldcw default_fcw
		; ; m (default_fcw)
		; memory
	}

	default_mxcsr := u32(0b1111110000000)

	asm volatile amd64 {
		ldmxcsr default_mxcsr
		; ; m (default_mxcsr)
		; memory
	}

	fpu_save(t.fpu_storage)

	// SIG_DFL, which Linux spells as zero.
	for mut sa in t.sigactions {
		sa.sa_sigaction = voidptr(0)
	}

	if want_elf == true {
		t.gpr_state.rsp = build_initial_stack(mut process, stack_vma, stack_bottom_vma, argv, envp,
			auxval)?
	}

	// Published processes (proc.allocate_pid()/new_process()) can be visible
	// to another CPU -- e.g. syscall_kill's kill(-1, sig) broadcast, which
	// reads process.threads directly -- before their first thread lands
	// here, and start_program()'s exec path replaces this same slice under
	// the identical lock; attach_thread() holds it across the append. The
	// thread is numbered before it can run, so gettid() never sees it bare.
	attach_thread(mut process, mut t) or {
		errno.set(errno.eagain)
		return none
	}
	proc.linuxkpi_init_task(mut t, unsafe { nil })

	if autoenqueue == true {
		enqueue_thread(t, false)
	}

	return t
}

// Number a thread and add it to its process. Threads are numbered from the
// pid space, as on Linux and on arm64: the first thread of a process takes the
// pid as its tid, every other one an id no process can have while it lives.
// gettid(), tgkill() and the scheduling calls find a thread by that number.
// A thread for clone(CLONE_THREAD), or the one thread of a process
// clone()/fork() makes: it resumes where `source` made the syscall, from the
// registers in `state`, with 0 as the syscall's result and `child_sp` as its
// stack pointer. `tls`, when `set_tls` asks for it, is its FS base -- where
// musl keeps the thread pointer. The caller enqueues it.
pub fn new_cloned_thread(_process &proc.Process, _source &proc.Thread, state &cpulocal.GPRState, child_sp u64, tls u64, set_tls bool) ?&proc.Thread {
	mut process := unsafe { _process }
	mut source := unsafe { _source }

	kernel_stack_phys := memory.pmm_alloc(stack_size / page_size)
	pf_stack_phys := memory.pmm_alloc(stack_size / page_size)
	fpu_phys := memory.pmm_alloc(lib.div_roundup(fpu_storage_size, page_size))
	if kernel_stack_phys == unsafe { nil } || pf_stack_phys == unsafe { nil }
		|| fpu_phys == unsafe { nil } {
		errno.set(errno.eagain)
		return none
	}

	mut t := &proc.Thread{
		process:        process
		cr3:            u64(process.pagemap.top_level)
		gpr_state:      *state
		timeslice:      source.timeslice
		running_on:     u64(-1)
		kernel_stack:   u64(kernel_stack_phys) + stack_size + higher_half
		pf_stack:       u64(pf_stack_phys) + stack_size + higher_half
		fpu_storage:    voidptr(u64(fpu_phys) + higher_half)
		sigactions:     source.sigactions
		masked_signals: source.masked_signals
		affinity_mask:  source.affinity_mask
		sched:          inherited_sched_params(source)
		comm:           source.comm.clone()
	}

	t.self = voidptr(t)
	// In a syscall the user's GS base is the one swapgs put aside.
	t.gs_base = cpu.get_kernel_gs_base()
	t.fs_base = if set_tls { tls } else { cpu.get_fs_base() }
	// Its selectors and TLS descriptors too, as Linux copies them. A TLS
	// pointer is a 64-bit FS base, which a selector would replace.
	t.fs_selector = if set_tls { u16(0) } else { cpu.fs_selector() }
	t.gs_selector = cpu.gs_selector()
	t.tls = source.tls

	// The saved copy is from the last switch; the child has to start with
	// the FPU state the caller has at this syscall.
	fpu_save(source.fpu_storage)
	unsafe { C.memcpy(t.fpu_storage, source.fpu_storage, fpu_storage_size) }

	t.gpr_state.rax = 0
	t.gpr_state.rsp = child_sp

	attach_thread(mut process, mut t) or {
		errno.set(errno.eagain)
		return none
	}
	proc.linuxkpi_init_task(mut t, source)

	return t
}

pub fn await() {
	asm volatile amd64 {
		cli
	}
	mut cpu_local := cpulocal.current()
	wakeup := if device_poll_callback != voidptr(0) && cpu_local.cpu_number == 0 {
		idle_poll_wakeup_us
	} else {
		idle_wakeup_us
	}
	apic.lapic_timer_oneshot(mut cpu_local, scheduler_vector, wakeup)
	asm volatile amd64 {
		sti
		1:
		hlt
		jmp b1
		; ; ; memory
	}
}

// ITIMER_REAL is counted down by the clock tick here: see sched/itimer.v.
fn itimer_armed() {
	if katomic.cas(mut &itimer_hook_claimed, u32(0), u32(1)) {
		if !time.register_tick_hook(tick_itimers) {
			katomic.store(mut &itimer_hook_claimed, u32(0))
		}
	}
}

__global (
	// Set once by whichever set_itimer_real() gets to register the tick hook.
	// A word, as katomic.cas needs 4 or 8 bytes.
	itimer_hook_claimed u32
)

// ── giving back the stacks of dead threads ──────────────────────────────────

// Every thread has a 2 MiB kernel stack, a 2 MiB page fault stack and its FPU
// area. They used to be kept forever, so every process and thread a program
// started cost 4 MiB for the rest of the machine's life: a session of shell
// prompts, compiles and git clones ran a 4 GiB machine out of memory.

__global (
	// Threads a sibling's exit_group() or execve() stopped. Their stacks go
	// when that sibling's own do.
	graveyard      []&proc.Thread
	graveyard_lock klock.Lock
)

// Hand over a thread that will never run again: one exit_group() or execve()
// took off the CPU for good.
pub fn bury_thread(t &proc.Thread) {
	graveyard_lock.acquire()
	graveyard << unsafe { t }
	graveyard_lock.release()
}

// The stacks are found from their tops, which the thread keeps; its `stacks`
// array cannot be used for this, as the functions that make threads free it
// once they have copied it in.
fn free_thread_stacks(mut t proc.Thread) {
	if t.kernel_stack != 0 {
		memory.pmm_free(voidptr(t.kernel_stack - stack_size - higher_half), stack_size / page_size)
		t.kernel_stack = 0
	}
	if t.pf_stack != 0 {
		memory.pmm_free(voidptr(t.pf_stack - stack_size - higher_half), stack_size / page_size)
		t.pf_stack = 0
	}
	if t.fpu_storage != unsafe { nil } {
		memory.pmm_free(voidptr(u64(t.fpu_storage) - higher_half), lib.div_roundup(fpu_storage_size,
			page_size))
		t.fpu_storage = unsafe { nil }
	}
}

// The stacks, and then the Thread, of a thread that died by itself: it left
// the tid table, its process and every event it waited on before it died.
fn free_thread_memory(t &proc.Thread) {
	mut thr := unsafe { t }
	free_thread_stacks(mut thr)
	unsafe {
		thr.comm.free()
		free(voidptr(thr))
	}
}

// Called by scheduler_isr once this CPU is on its own stacks and its IST3
// points at the thread it is about to run, or at its idle stack: the thread
// that died on this CPU is off its stacks by then, and goes, as on arm64. One
// a sibling stopped keeps its Thread, as events it was waiting on may still
// point at it, and only gives its stacks back.
fn reap_dead_threads(mut cpu_local cpulocal.Local) {
	if cpu_local.dying_thread == unsafe { nil } {
		return
	}
	mut dead := unsafe { &proc.Thread(cpu_local.dying_thread) }
	cpu_local.dying_thread = unsafe { nil }
	// yield(false) clears GS before the interrupt, so the outgoing-thread
	// branch cannot release this lock. We are now on the scheduler's stack.
	katomic.store(mut &dead.running_on, u64(-1))
	katomic.store(mut &dead.l.l, false)
	reap_thread(dead)

	// The threads it stopped on its way out were taken off their CPUs before
	// it went on to die itself, so by now nothing can be on their stacks.
	if !graveyard_lock.test_and_acquire() {
		return
	}
	mut i := 0
	for i < graveyard.len {
		mut buried := graveyard[i]
		if katomic.load(&buried.running_on) == u64(-1) && !buried.l.is_held() {
			free_thread_stacks(mut buried)
			graveyard.delete(i)
		} else {
			i++
		}
	}
	graveyard_lock.release()
}

// The CPU features a program is told of in AT_HWCAP and AT_HWCAP2; see
// build_initial_stack().
fn user_hwcaps() (u64, u64) {
	return cpu.user_hwcaps()
}
