@[has_globals]
module sched

import aarch64.cpu
import aarch64.cpu.local as cpulocal
import aarch64.timer
import aarch64.uart
import katomic
import klock
import proc
import memory
import memory.mmap
import elf
import lib
import errno
import time

fn C.sched_switch_context(gpr_state &cpulocal.GPRState, kernel_stack u64)
fn C.vinix_call_void_fn(f voidptr)

pub fn initialise() {
	kernel_process = &proc.Process{
		pagemap: &kernel_pagemap
	}

	println('sched: ARM64 scheduler initialised')
}

// Register a callback called from the scheduler's await() loop.
// Used by the console module to poll UART without a separate thread.
pub fn set_uart_poll_callback(cb voidptr) {
	uart_poll_callback = cb
}

// Returns the scheduler's timer interrupt handler for use by the
// interrupt controller (GIC or AIC).
pub fn get_timer_handler() fn (voidptr) {
	return scheduler_timer_handler
}

fn get_next_thread() &proc.Thread {
	mut cpu_local := cpulocal.current()

	mut orig_i := cpu_local.last_run_queue_index

	if orig_i >= max_running_threads {
		orig_i = 0
	}

	mut index := orig_i + 1

	for {
		if index >= max_running_threads {
			index = 0
		}

		mut t := scheduler_running_queue[index]

		if unsafe { t != 0 } {
			if t.l.test_and_acquire() == true {
				cpu_local.last_run_queue_index = index
				return t
			}
		}

		if index == orig_i {
			break
		}

		index++
	}

	cpu_local.last_run_queue_index = index
	return unsafe { nil }
}

fn scheduler_timer_handler(_gpr_state voidptr) {
	gpr_state := unsafe { &cpulocal.GPRState(_gpr_state) }
	timer.stop()

	// Tick the monotonic/realtime clocks
	time.timer_handler()

	// Tick per-process interval timers (SIGALRM)
	tick_itimers()

	mut cpu_local := cpulocal.current()
	katomic.store(mut &cpu_local.is_idle, false)

	mut current_thread := proc.current_thread()
	mut next_thread := get_next_thread()

	if unsafe { current_thread != 0 } {
		current_thread.yield_await.release()

		if unsafe { next_thread == nil } {
			// No thread to switch to. If the current thread is still in
			// the run queue, re-arm the timer for its next timeslice.
			// Either way, return without modifying thread state — the
			// caller (yield_dispatch or interrupt) continues running.
			if current_thread.is_in_queue {
				timer.oneshot(current_thread.timeslice)
			}
			return
		}
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
		current_thread.l.release()
	}

	if unsafe { next_thread == nil } {
		// Called from the idle loop (await): no current thread, no next
		// thread. Go idle and return to await()'s polling loop.
		cpu.write_tpidr_el1(cpu_local.cpu_number)
		proc.set_current_thread(cpu_local.cpu_number, unsafe { nil })
		katomic.store(mut &cpu_local.is_idle, true)
		kernel_pagemap.switch_to()
		return
	}

	current_thread = next_thread
	proc.set_current_thread(cpu_local.cpu_number, current_thread)

	cpu.write_tpidr_el0(current_thread.tpidr_el0)

	if cpu.read_ttbr0_el1() != current_thread.ttbr0 {
		cpu.write_ttbr0_el1(current_thread.ttbr0)
		cpu.isb()
		cpu.tlbi_vmalle1()
	}

	fpu_restore(current_thread.fpu_storage)
	katomic.store(mut &current_thread.running_on, cpu_local.cpu_number)

	// Debug: check if x30 is corrupted when restoring state for pid 3
	if current_thread.process.pid == 3 && current_thread.gpr_state.x30 == u64(0x220000) {
		print('\nSCHED RESTORE: pid=3 x30=0x220000! pc=0x${current_thread.gpr_state.pc:x} sp=0x${current_thread.gpr_state.sp:x} pstate=0x${current_thread.gpr_state.pstate:x}\n')
	}

	timer.oneshot(current_thread.timeslice)

	// Restore ARM64 GPR state and return via eret (does not return).
	C.sched_switch_context(&current_thread.gpr_state, current_thread.kernel_stack)
}

pub fn enqueue_thread(_thread &proc.Thread, by_signal bool) bool {
	mut t := unsafe { _thread }

	if t.is_in_queue == true {
		return true
	}

	katomic.store(mut &t.enqueued_by_signal, by_signal)

	for i := u64(0); i < max_running_threads; i++ {
		if katomic.cas[&proc.Thread](mut &scheduler_running_queue[i], unsafe { nil },
			t)
		{
			t.is_in_queue = true

			// Wake any idle CPUs via SEV
			for cpu_entry in cpu_locals {
				if katomic.load(&cpu_entry.is_idle) == true {
					cpu.sev()
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

	if t.is_in_queue == false {
		return true
	}

	for i := u64(0); i < max_running_threads; i++ {
		if katomic.cas[&proc.Thread](mut &scheduler_running_queue[i], t, unsafe { nil }) {
			t.is_in_queue = false
			return true
		}
	}

	return false
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

pub fn yield(save_ctx bool) {
	cpu.interrupt_toggle(false)
	timer.stop()
	mut current_thread := proc.current_thread()

	if save_ctx == false {
		// Dying thread path (dequeue_and_die). Enter idle scheduler loop.
		timer.oneshot(1)
		cpu.interrupt_toggle(true)
		await()
		return
	}

	// Blocking yield: HVF workaround.
	// IRQ delivery to guest is broken, so we can't rely on preemptive context
	// switching. Instead, poll the timer and when it fires, dispatch the
	// scheduler via yield_dispatch(). This saves our kernel context into a
	// GPRState on the stack and switches to any runnable thread. When this
	// thread is later re-enqueued and re-scheduled, sched_switch_context
	// restores our kernel context and we resume here.
	freq := cpu.read_cntfrq_el0()
	ticks := freq / 20 // 50ms ticks
	cpu.write_cntv_tval_el0(ticks)
	cpu.write_cntv_ctl_el0(1)

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
		}

		// Poll UART for console input
		if uart_poll_callback != voidptr(0) {
			C.vinix_call_void_fn(uart_poll_callback)
		}

		// Check if we've been re-enqueued by an event trigger
		if current_thread.is_in_queue {
			break
		}

		asm volatile aarch64 {
			yield
			; ; ; memory
		}
	}

	// Thread re-enqueued. Re-arm timer for normal scheduling.
	timer.oneshot(current_thread.timeslice)
	cpu.interrupt_toggle(true)
}

pub fn dequeue_and_yield() {
	cpu.interrupt_toggle(false)
	dequeue_thread(proc.current_thread())
	yield(true)
}

@[noreturn]
pub fn dequeue_and_die() {
	cpu.interrupt_toggle(false)
	mut t := proc.current_thread()
	dequeue_thread(t)
	// Clear current thread so the scheduler timer handler knows
	// there is no running thread to save state from.
	mut cpu_local := cpulocal.current()
	proc.set_current_thread(cpu_local.cpu_number, unsafe { nil })
	yield(false)
	for {}
}

pub fn new_kernel_thread(pc voidptr, arg voidptr, autoenqueue bool) &proc.Thread {
	mut stacks := []voidptr{}

	stack_phys := memory.pmm_alloc(stack_size / page_size)
	stacks << stack_phys
	stack := u64(stack_phys) + stack_size + higher_half

	gpr_state := cpulocal.GPRState{
		pc:     u64(pc) // elr_el1 = entry point
		x0:     u64(arg) // first argument in x0
		sp:     stack
		pstate: 0x3c5 // EL1h, DAIF masked
	}

	mut t := &proc.Thread{
		process:     kernel_process
		ttbr0:       u64(kernel_process.pagemap.top_level)
		gpr_state:   gpr_state
		timeslice:   5000
		running_on:  u64(-1)
		stacks:      stacks
		fpu_storage: voidptr(u64(memory.pmm_alloc(lib.div_roundup(fpu_storage_size, page_size))) +
			higher_half)
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

	mut new_thread := new_user_thread(process, false, pc, unsafe { nil }, stack, empty_string_array,
		empty_string_array, unsafe { nil }, false) or { return errno.err, errno.get() }

	enqueue_thread(new_thread, false)

	return u64(new_thread.tid), 0
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
		stack_phys := memory.pmm_alloc(stack_size / page_size)
		stack = unsafe { &u64(u64(stack_phys) + stack_size + higher_half) }

		stack_vma = process.thread_stack_top
		process.thread_stack_top -= stack_size
		stack_bottom_vma := process.thread_stack_top
		process.thread_stack_top -= page_size

		mmap.map_range(mut process.pagemap, stack_bottom_vma, u64(stack_phys), stack_size,
			mmap.prot_read | mmap.prot_write, mmap.map_anonymous) or { return none }
	} else {
		stack = &u64(voidptr(_stack))
		stack_vma = _stack
	}

	kernel_stack_phys := memory.pmm_alloc(stack_size / page_size)
	stacks << kernel_stack_phys
	kernel_stack := u64(kernel_stack_phys) + stack_size + higher_half

	gpr_state := cpulocal.GPRState{
		pc:     u64(pc)
		x0:     u64(arg)
		sp:     u64(stack_vma)
		pstate: 0x000 // EL0t, no DAIF masking
	}

	mut t := &proc.Thread{
		process:      process
		ttbr0:        u64(process.pagemap.top_level)
		gpr_state:    gpr_state
		timeslice:    5000
		running_on:   u64(-1)
		kernel_stack: kernel_stack
		stacks:       stacks
		fpu_storage:  voidptr(u64(memory.pmm_alloc(lib.div_roundup(fpu_storage_size, page_size))) +
			higher_half)
	}

	t.self = voidptr(t)
	t.tpidr_el0 = u64(0)

	// Set all sigactions to default (SIG_DFL = 0 on Linux, -2 on mlibc)
	for mut sa in t.sigactions {
		sa.sa_sigaction = voidptr(0)
	}

	if want_elf == true {
		if auxval != unsafe { nil } {
			uart.puts(c'ELF auxval: base=0x')
			uart.put_hex(auxval.at_base)
			uart.puts(c' phdr=0x')
			uart.put_hex(auxval.at_phdr)
			uart.puts(c' entry=0x')
			uart.put_hex(auxval.at_entry)
			uart.putc(`\n`)
		}
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

			if (argv.len + envp.len + 1) & 1 != 0 {
				stack = &stack[-1]
			}

			// Write 16 bytes of "random" data for AT_RANDOM
			// (musl uses this for stack canary)
			stack = &u64(u64(stack) - 16)
			random_kernel_addr := u64(stack)
			*&u64(random_kernel_addr) = 0xdeadbeef12345678
			*&u64(random_kernel_addr + 8) = 0xabcdef0987654321
			random_vma := stack_vma - (u64(stack_top) - random_kernel_addr)

			// Auxiliary vector (NULL-terminated)
			stack[-1] = 0
			stack = &stack[-1]
			stack[-1] = 0
			stack = &stack[-1]

			stack = &stack[-2]
			stack[0] = elf.at_secure
			stack[1] = 0
			stack = &stack[-2]
			stack[0] = elf.at_random
			stack[1] = random_vma
			stack = &stack[-2]
			stack[0] = elf.at_pagesz
			stack[1] = page_size
			stack = &stack[-2]
			stack[0] = elf.at_uid
			stack[1] = 0
			stack = &stack[-2]
			stack[0] = elf.at_euid
			stack[1] = 0
			stack = &stack[-2]
			stack[0] = elf.at_gid
			stack[1] = 0
			stack = &stack[-2]
			stack[0] = elf.at_egid
			stack[1] = 0
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

			t.gpr_state.sp -= u64(stack_top) - u64(stack)
		}
	}

	if autoenqueue == true {
		enqueue_thread(t, false)
	}

	t.tid = process.threads.len
	process.threads << t

	return t
}

pub fn new_process(old_process &proc.Process, pagemap &memory.Pagemap) ?&proc.Process {
	mut new_proc := &proc.Process{
		pagemap: unsafe { nil }
	}

	new_proc.pid = proc.allocate_pid(new_proc) or { return none }

	if unsafe { old_process != 0 } {
		new_proc.ppid = old_process.pid
		new_proc.pagemap = mmap.fork_pagemap(old_process.pagemap) or { return none }
		new_proc.thread_stack_top = old_process.thread_stack_top
		new_proc.mmap_anon_non_fixed_base = old_process.mmap_anon_non_fixed_base
		new_proc.current_directory = old_process.current_directory
	} else {
		new_proc.ppid = 0
		new_proc.pagemap = unsafe { pagemap }
		new_proc.thread_stack_top = u64(0x70000000000)
		new_proc.mmap_anon_non_fixed_base = u64(0x80000000000)
		new_proc.current_directory = voidptr(vfs_root)
	}

	return new_proc
}

pub fn await() {
	// Arm virtual timer for scheduler tick (50ms)
	freq := cpu.read_cntfrq_el0()
	ticks := freq / 20
	cpu.write_cntv_tval_el0(ticks)
	cpu.write_cntv_ctl_el0(1)

	// Polling idle loop used on both QEMU/HVF and early Apple bring-up.
	// Keep interrupts disabled, poll CNTV_CTL ISTATUS, and dispatch the
	// scheduler timer handler directly when the timer fires.
	cpu.interrupt_toggle(false)

	for {
		vctl := cpu.read_cntv_ctl_el0()
		if vctl & 0x4 != 0 {
			// Timer fired. Dispatch scheduler in polling mode.
			scheduler_timer_handler(unsafe { nil })

			// Re-arm timer for next tick
			cpu.write_cntv_tval_el0(ticks)
			cpu.write_cntv_ctl_el0(1)
		}

		// Poll UART input while idle (no separate thread — HVF workaround).
		// Uses a callback set by the console module to avoid circular imports.
		if uart_poll_callback != voidptr(0) {
			C.vinix_call_void_fn(uart_poll_callback)
		}

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
			// Fire SIGALRM (signal 14)
			katomic.bts(mut &e.thrd.pending_signals, u8(14))
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
