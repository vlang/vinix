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

	// The kernel acts with every capability: file permissions are lifted by
	// capabilities, not by a uid of zero, and kernel threads create files
	// wherever the initramfs puts them.
	kernel_process = &proc.Process{
		pagemap: &kernel_pagemap
		caps:    proc.full_capabilities()
		fds:     []voidptr{len: proc.initial_fds}
	}
}

// May this thread run on this CPU at all? Asked by the run-queue scan before it
// picks a thread up, and by the timer handler about the thread already on the
// CPU: an affinity change while a thread is running has to take effect, so a CPU
// it may no longer use puts it down even with nothing to replace it. Safe to do
// here because this scheduler's idle path never returns to the caller -- it ends
// in await(), on the per-CPU interrupt stack.
fn may_run_here(t &proc.Thread, cpu_number u64) bool {
	if cpu_number >= 64 {
		return true
	}
	return t.affinity_mask & (u64(1) << cpu_number) != 0
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
// Exactly one lap of the queue, from wherever this CPU last stopped, so the
// order stays round-robin. The lap is counted rather than compared against a
// starting index: the skip cases used to `continue` straight past the
// wrap-around check, so a slot that this CPU could not take and that happened
// to sit at the start index sent the scan round the queue for ever. Nothing was
// skipped before affinity masks and memory nodes existed, which is why it took
// until a pinned thread on another node to find.
fn scan_run_queue(mut cpu_local cpulocal.Local, want_node int) &proc.Thread {
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

fn effective_timeslice(t &proc.Thread) u64 {
	weight := u64(20 - t.process.nice)
	mut slice := t.timeslice * weight / 20
	if slice == 0 {
		slice = 1
	}
	return slice
}

__global (
	user_signal_hook voidptr
)

type UserSignalHook = fn (&cpulocal.GPRState)

// userland registers what an interrupt returning to userspace has to do for
// the thread; it cannot be imported. As on arm64.
pub fn register_user_signal_hook(hook voidptr) {
	user_signal_hook = hook
}

fn scheduler_isr(_ u32, gpr_state &cpulocal.GPRState) {
	apic.lapic_timer_stop()

	mut cpu_local := cpulocal.current()

	katomic.store(mut &cpu_local.is_idle, false)

	// Before the run queue is read, so a thread that the poll wakes -- one
	// waiting on a socket -- can be picked straight away.
	poll_devices()

	mut current_thread := proc.current_thread()

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
		if unsafe { next_thread == nil } && katomic.load(&current_thread.is_in_queue)
			&& may_run_here(current_thread, cpu_local.cpu_number) && !preset {
			apic.lapic_eoi()
			apic.lapic_timer_oneshot(mut cpu_local, scheduler_vector, effective_timeslice(current_thread))
			return
		}
		// Past the early return above this thread really is coming off the
		// CPU, so the turn it has just had is charged to its process. The
		// monotonic clock is the tick source here rather than a counter read,
		// which puts the resolution at one timer tick.
		proc.charge_cpu_time(mut current_thread, time.monotonic_ns())
		if preset {
			current_thread.context_preset = false
		} else {
			unsafe {
				current_thread.gpr_state = *gpr_state
			}
		}
		current_thread.gs_base = cpu.get_kernel_gs_base()
		current_thread.fs_base = cpu.get_fs_base()
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
		cpu_local.tss.ist3 = cpu_local.idle_pf_stack
		reap_dead_threads(mut cpu_local)
		await()
	}

	current_thread = next_thread
	proc.begin_cpu_time(mut current_thread, time.monotonic_ns())

	// The first CPU to run a thread claims it for its node, so that the pages
	// the thread goes on to fault in and the CPU it keeps returning to are on
	// the same side of the machine.
	if current_thread.numa_node < 0 {
		current_thread.numa_node = int(cpu_local.numa_node)
	}

	// A thread going back to userspace with a signal it has to take, or an exit
	// a sibling asked for, is sent to take care of it first; the hook points
	// the frame into the kernel. See userland.interrupt_return().
	if current_thread.gpr_state.cs == user_code_seg && user_signal_hook != unsafe { nil } {
		hook := unsafe { UserSignalHook(user_signal_hook) }
		hook(&current_thread.gpr_state)
	}

	// The SWAPGS below leaves GS on the thread for the kernel, and the
	// thread's own base parked in KERNEL_GS_BASE, whichever mode it returns
	// to; in userspace the two are the other way round. A user thread resumed
	// inside a syscall used to lose the GS base it had set with arch_prctl.
	if current_thread.gpr_state.cs == user_code_seg {
		cpu.set_gs_base(u64(current_thread))
		cpu.set_kernel_gs_base(current_thread.gs_base)
	} else {
		cpu.set_gs_base(current_thread.gs_base)
		cpu.set_kernel_gs_base(u64(current_thread))
	}
	cpu.set_fs_base(current_thread.fs_base)

	cpu_local.tss.ist3 = current_thread.pf_stack
	reap_dead_threads(mut cpu_local)

	if cpu.read_cr3() != current_thread.cr3 {
		cpu.write_cr3(current_thread.cr3)
	}

	fpu_restore(current_thread.fpu_storage)

	katomic.store(mut &current_thread.running_on, cpu_local.cpu_number)

	apic.lapic_eoi()
	apic.lapic_timer_oneshot(mut cpu_local, scheduler_vector, effective_timeslice(current_thread))

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
// itself -- it never lets go of its lock, so waiting for that would be waiting
// forever -- and its stacks are then its own CPU's to give back. Otherwise
// they are buried here.
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
		asm volatile amd64 {
			pause
			; ; ; memory
		}
	}
	set_itimer_real(t, 0, 0)
	if katomic.cas(mut &t.reap_claim, u32(0), u32(reap_claim_stopped)) {
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

@[noreturn]
pub fn dequeue_and_die() {
	asm volatile amd64 {
		cli
	}
	mut t := proc.current_thread()
	t.is_dead = true
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
	mut stacks := []voidptr{}

	stack_phys := memory.pmm_alloc(stack_size / page_size)
	stacks << stack_phys
	stack := u64(stack_phys) + stack_size + higher_half

	gpr_state := cpulocal.GPRState{
		cs: kernel_code_seg
		ds: kernel_data_seg
		es: kernel_data_seg
		ss: kernel_data_seg
		rflags: 0x202
		rip: u64(pc)
		rdi: u64(arg)
		rbp: u64(0)
		rsp: stack
	}

	mut t := &proc.Thread{
		process: kernel_process
		cr3: u64(kernel_process.pagemap.top_level)
		gpr_state: gpr_state
		timeslice: 5000
		running_on: u64(-1)
		stacks: stacks
		fpu_storage: voidptr(u64(memory.pmm_alloc(lib.div_roundup(fpu_storage_size, page_size))) + higher_half)
	}

	unsafe { stacks.free() }

	t.self = voidptr(t)
	t.gs_base = u64(voidptr(t))

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

	mut stack := unsafe { &u64(0) }
	mut stack_vma := u64(0)

	if _stack == 0 {
		mut user_stack_size := default_user_stack_size
		stack_limit := proc.soft_limit(process, proc.rlimit_stack)
		if stack_limit != proc.rlim_infinity && stack_limit < user_stack_size {
			user_stack_size = lib.align_down(stack_limit, page_size)
		}
		if user_stack_size < page_size {
			errno.set(errno.enomem)
			return none
		}
		stack_phys := memory.pmm_alloc(user_stack_size / page_size)
		stack = unsafe { &u64(u64(stack_phys) + user_stack_size + higher_half) }

		stack_vma = process.thread_stack_top
		process.thread_stack_top -= user_stack_size
		stack_bottom_vma := process.thread_stack_top
		process.thread_stack_top -= page_size

		mmap.map_range(mut process.pagemap, stack_bottom_vma, u64(stack_phys), user_stack_size, mmap.prot_read | mmap.prot_write, mmap.map_anonymous) or { return none }
	} else {
		stack = &u64(voidptr(_stack))
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
		unsafe {
			stack_top := stack
			mut orig_stack_vma := stack_vma

			for elem in envp {
				stack = &u64(u64(stack) - u64(elem.len + 1))
				C.memcpy(voidptr(stack), elem.str, elem.len + 1)
			}
			for elem in argv {
				stack = &u64(u64(stack) - u64(elem.len + 1))
				C.memcpy(voidptr(stack), elem.str, elem.len + 1)
			}

			stack = &u64(u64(stack) - (u64(stack) & 0x0f))

			// Ensure final stack pointer is 16 byte aligned
			if (argv.len + envp.len + 1) & 1 != 0 {
				stack = &stack[-1]
			}

			// Linux libcs use AT_RANDOM for their stack canary.
			stack = &u64(u64(stack) - 16)
			random_kernel_addr := u64(stack)
			if !krandom.fill(voidptr(random_kernel_addr), 16, true) {
				C.memset(voidptr(random_kernel_addr), 0, 16)
			}
			random_vma := stack_vma - (u64(stack_top) - random_kernel_addr)

			// Zero auxiliary vector entry
			stack[-1] = 0
			stack = &stack[-1]
			stack[-1] = 0
			stack = &stack[-1]

			stack = &stack[-2]
			stack[0] = elf.at_secure
			stack[1] = 0
			stack = &stack[-2]
			stack[0] = elf.at_hwcap2
			stack[1] = 0
			stack = &stack[-2]
			stack[0] = elf.at_hwcap
			stack[1] = 0
			stack = &stack[-2]
			stack[0] = elf.at_random
			stack[1] = random_vma
			stack = &stack[-2]
			stack[0] = elf.at_pagesz
			stack[1] = page_size
			stack = &stack[-2]
			stack[0] = elf.at_uid
			stack[1] = u64(process.uid)
			stack = &stack[-2]
			stack[0] = elf.at_euid
			stack[1] = u64(process.euid)
			stack = &stack[-2]
			stack[0] = elf.at_gid
			stack[1] = u64(process.gid)
			stack = &stack[-2]
			stack[0] = elf.at_egid
			stack[1] = u64(process.egid)
			stack = &stack[-2]
			stack[0] = elf.at_entry
			stack[1] = auxval.at_entry
			stack = &stack[-2]
			stack[0] = elf.at_phdr
			stack[1] = auxval.at_phdr
			stack = &stack[-2]
			stack[0] = elf.at_phent
			stack[1] = auxval.at_phent
			stack = &stack[-2]
			stack[0] = elf.at_phnum
			stack[1] = auxval.at_phnum
			stack = &stack[-2]
			stack[0] = elf.at_base
			stack[1] = auxval.at_base

			stack[-1] = 0
			stack = &stack[-1]
			stack = &stack[-envp.len]
			for i := u64(0); i < envp.len; i++ {
				orig_stack_vma -= u64(envp[i].len) + 1
				stack[i] = orig_stack_vma
			}

			stack[-1] = 0
			stack = &stack[-1]
			stack = &stack[-argv.len]
			for i := u64(0); i < argv.len; i++ {
				orig_stack_vma -= u64(argv[i].len) + 1
				stack[i] = orig_stack_vma
			}

			stack[-1] = u64(argv.len)
			stack = &stack[-1]

			t.gpr_state.rsp -= u64(stack_top) - u64(stack)
		}
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

	if autoenqueue == true {
		enqueue_thread(t, false)
	}

	return t
}

// Number a thread and add it to its process. Threads are numbered from the
// pid space, as on Linux and on arm64: the first thread of a process takes the
// pid as its tid, every other one an id no process can have while it lives.
// gettid(), tgkill() and the scheduling calls find a thread by that number.
fn attach_thread(mut process proc.Process, mut t proc.Thread) ?int {
	process.threads_lock.acquire()
	defer {
		process.threads_lock.release()
	}

	if process.threads.len == 0 && process.pid != 0 {
		t.tid = process.pid
		proc.bind_tid(t.tid, t)
		proc.number_thread(mut t, true)
	} else {
		t.tid = proc.allocate_tid(t)?
		proc.number_thread(mut t, false)
		// Signal dispositions are the process's, and rt_sigaction keeps every
		// thread on this list in step under this lock. The copy the caller made
		// from its creator can predate an rt_sigaction that ran on another CPU
		// in the meantime, and would then stay behind for good: musl's barrier
		// handler found such a thread still carrying another handler for
		// SIGSYNCCALL, which never acknowledged, and Firefox hung at startup.
		t.sigactions = process.threads[0].sigactions
	}

	process.threads << t
	return t.tid
}

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
		sched:          source.sched
		comm:           source.comm.clone()
	}

	t.self = voidptr(t)
	// In a syscall the user's GS base is the one swapgs put aside.
	t.gs_base = cpu.get_kernel_gs_base()
	t.fs_base = if set_tls { tls } else { cpu.get_fs_base() }

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

	return t
}

pub fn new_process(old_process &proc.Process, pagemap &memory.Pagemap) ?&proc.Process {
	if unsafe { old_process != nil } && !proc.may_create_process(old_process) {
		errno.set(errno.eagain)
		return none
	}
	// Freed when the process is reaped, in proc.free_pid().
	fds := []voidptr{len: proc.initial_fds} @[freed]
	mut new_proc := &proc.Process{
		pagemap: unsafe { nil }
		fds:     fds
	}

	new_proc.pid = proc.allocate_pid(new_proc) or {
		unsafe {
			new_proc.fds.free()
			free(new_proc)
		}
		return none
	}

	if unsafe { old_process != 0 } {
		new_proc.ppid = old_process.pid
		new_proc.pgid = old_process.pgid
		new_proc.sid = old_process.sid
		new_proc.tty_session = old_process.tty_session
		new_proc.pagemap = mmap.fork_pagemap(old_process.pagemap) or { return none }
		new_proc.thread_stack_top = old_process.thread_stack_top
		// The child has the parent's heap, so it has its break too; see
		// sched_arm64.v.
		new_proc.brk_base = old_process.brk_base
		new_proc.brk_current = old_process.brk_current
		new_proc.mmap_anon_non_fixed_base = old_process.mmap_anon_non_fixed_base
		new_proc.current_directory = old_process.current_directory
		proc.inherit_container_state(mut new_proc, old_process)
		new_proc.allow_wx = old_process.allow_wx
		new_proc.uid = old_process.uid
		new_proc.euid = old_process.euid
		new_proc.suid = old_process.suid
		new_proc.gid = old_process.gid
		new_proc.egid = old_process.egid
		new_proc.sgid = old_process.sgid
		new_proc.groups = old_process.groups.clone()
		new_proc.umask = old_process.umask
		new_proc.nice = old_process.nice
		new_proc.rlimits = old_process.rlimits
		// A NUMA memory policy is process state, like nice and the rlimits, so
		// a fork keeps the placement its parent asked for.
		new_proc.mempolicy_mode = old_process.mempolicy_mode
		new_proc.mempolicy_nodemask = old_process.mempolicy_nodemask
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

// ── ITIMER_REAL ──────────────────────────────────────────────────────────────

// setitimer(ITIMER_REAL) and alarm(): SIGALRM once the time is up, and again
// every interval after that. The same bookkeeping as arm64's, counted down
// from the clock tick instead of from the generic timer's counter.
const max_itimer_real = 32

struct ItimerRealEntry {
mut:
	thrd        &proc.Thread = unsafe { nil }
	value_us    i64
	interval_us i64
	active      bool
}

__global (
	itimer_real_entries [max_itimer_real]ItimerRealEntry
	itimer_real_lock    klock.Lock
	itimer_last_ns      u64
	// Set once by whichever set_itimer_real() gets to register the tick hook.
	// A word, as katomic.cas needs 4 or 8 bytes.
	itimer_hook_claimed u32
)

// Called by the clock tick. A tick that finds the table busy leaves the time
// to the next one, which counts it: the elapsed time is measured, not assumed.
fn tick_itimers() {
	if !itimer_real_lock.test_and_acquire() {
		return
	}
	defer {
		itimer_real_lock.release()
	}

	now := time.monotonic_ns()
	if itimer_last_ns == 0 || now <= itimer_last_ns {
		itimer_last_ns = now
		return
	}
	elapsed_us := i64((now - itimer_last_ns) / 1000)
	if elapsed_us <= 0 {
		return
	}
	itimer_last_ns += u64(elapsed_us) * 1000

	for i := 0; i < max_itimer_real; i++ {
		mut e := unsafe { &itimer_real_entries[i] }
		if !e.active || e.value_us <= 0 {
			continue
		}
		e.value_us -= elapsed_us
		if e.value_us <= 0 {
			// SIGALRM.
			katomic.bts(mut &e.thrd.pending_signals, proc.pending_bit(14))
			enqueue_thread(e.thrd, true)
			if e.interval_us > 0 {
				e.value_us = e.interval_us
			} else {
				e.active = false
			}
		}
	}
}

// set_itimer_real arms or disarms `thrd`'s ITIMER_REAL timer and returns the
// previous (value_us, interval_us).
pub fn set_itimer_real(thrd &proc.Thread, value_us i64, interval_us i64) (i64, i64) {
	arming := value_us > 0 || interval_us > 0
	if arming && katomic.cas(mut &itimer_hook_claimed, u32(0), u32(1)) {
		if !time.register_tick_hook(tick_itimers) {
			katomic.store(mut &itimer_hook_claimed, u32(0))
		}
	}

	itimer_real_lock.acquire()
	defer {
		itimer_real_lock.release()
	}

	for i := 0; i < max_itimer_real; i++ {
		mut e := unsafe { &itimer_real_entries[i] }
		if e.active && e.thrd == thrd {
			old_value := e.value_us
			old_interval := e.interval_us
			if !arming {
				e.active = false
			} else {
				e.value_us = value_us
				e.interval_us = interval_us
			}
			return old_value, old_interval
		}
	}

	if arming {
		if itimer_last_ns == 0 {
			itimer_last_ns = time.monotonic_ns()
		}
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

// Called by scheduler_isr once this CPU is on its own stacks and its IST3
// points at the thread it is about to run, or at its idle stack: the thread
// that died on this CPU is off its stacks by then. The Thread itself stays,
// as events and the tid table may still point at it.
fn reap_dead_threads(mut cpu_local cpulocal.Local) {
	if cpu_local.dying_thread == unsafe { nil } {
		return
	}
	mut dead := unsafe { &proc.Thread(cpu_local.dying_thread) }
	cpu_local.dying_thread = unsafe { nil }
	free_thread_stacks(mut dead)

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
