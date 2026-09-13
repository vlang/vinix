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

fn C.vinix_call_void_fn(f voidptr)

fn C.yield_dispatch(handler voidptr)

const max_reap_slots = 256

__global (
	// Per-CPU parking slot for the thread that most recently died there.
	reap_slots                 [max_reap_slots]&proc.Thread
	syscall_input_poll_lock    klock.Lock
	last_syscall_input_poll_ns u64
)

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

// Keep the syscall fallback narrower than the scheduler's normal platform
// callback. Polling networking or the console from an arbitrary syscall can
// recurse into facilities that syscall is about to use; VirtIO input has no
// such dependency and is all a CPU-bound translated GUI needs here.
pub fn poll_syscall_input() {
	ints := cpu.interrupt_toggle(false)
	defer {
		cpu.interrupt_toggle(ints)
	}
	if !syscall_input_poll_lock.test_and_acquire() {
		return
	}
	defer {
		syscall_input_poll_lock.release()
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

// Pick a thread for this CPU. On a machine with more than one memory node this
// runs twice: once accepting only threads already at home on this CPU's node,
// and then accepting anything. A thread therefore tends to keep running next to
// the memory it faulted in, while a node with nothing to do still takes work
// from a busy one rather than idling.
fn get_next_thread() &proc.Thread {
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
fn scan_run_queue(mut cpu_local cpulocal.Local, want_node int) &proc.Thread {
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
			cpu_number := cpu_local.cpu_number
			if cpu_number < 64 && t.affinity_mask & (u64(1) << cpu_number) == 0 {
				index++
				continue
			}
			if want_node >= 0 && t.numa_node >= 0 && t.numa_node != want_node {
				index++
				continue
			}
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

fn effective_timeslice(t &proc.Thread) u64 {
	weight := u64(20 - t.process.nice)
	mut slice := t.timeslice * weight / 20
	if slice == 0 {
		slice = 1
	}
	return slice
}

fn scheduler_timer_handler(_gpr_state voidptr) {
	gpr_state := unsafe { &cpulocal.GPRState(_gpr_state) }
	timer.stop()

	// Tick the monotonic/realtime clocks. The interval is measured from the
	// generic timer's counter rather than assumed, because this handler fires
	// on a timeslice, not at a fixed frequency.
	//
	// The same reading bills the outgoing thread and starts the incoming one,
	// so a switch neither loses time between the two nor counts it twice.
	now_ns := timer.get_ns()
	time.advance_to_ns(now_ns)

	// Tick per-process interval timers (SIGALRM)
	tick_itimers()

	mut cpu_local := cpulocal.current()
	// The idle loop normally polls UART, VirtIO input and networking. A busy
	// userspace workload can keep every CPU runnable indefinitely, so relying
	// on idle time alone strands keyboard and pointer reports in their VirtIO
	// queues. Poll once per CPU-0 timeslice as well; using one CPU preserves the
	// drivers' single-poller assumption while keeping the desktop interactive.
	if cpu_local.cpu_number == 0 && uart_poll_callback != voidptr(0) {
		C.vinix_call_void_fn(uart_poll_callback)
	}
	katomic.store(mut &cpu_local.is_idle, false)

	mut current_thread := proc.current_thread()
	mut next_thread := get_next_thread()

	if unsafe { current_thread != 0 } {
		current_thread.yield_await.release()

		if unsafe { next_thread == nil } && current_thread.is_in_queue {
			// No other thread is runnable, so the current one keeps its CPU.
			// A blocked current thread must instead fall through: otherwise a
			// later wakeup selects that same stale current thread and charges
			// its entire sleep interval as CPU time.
			timer.oneshot(effective_timeslice(current_thread))
			return
		}
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
	proc.begin_cpu_time(mut current_thread, now_ns)

	// The first CPU to run a thread claims it for its node, so that the pages
	// the thread goes on to fault in and the CPU it keeps returning to are on
	// the same side of the machine.
	if current_thread.numa_node < 0 {
		current_thread.numa_node = int(cpu_local.numa_node)
	}

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

	timer.oneshot(effective_timeslice(current_thread))

	// Restore ARM64 GPR state and return via eret (does not return).
	C.sched_switch_context(voidptr(&current_thread.gpr_state), current_thread.kernel_stack)
}

pub fn enqueue_thread(_thread &proc.Thread, by_signal bool) bool {
	mut t := unsafe { _thread }

	// A torn-down thread may still be referenced by event listener slots it
	// never got to detach; never let it back onto the run queue.
	if t.is_dead == true {
		return false
	}

	// A signal can arrive while the target is running immediately before it
	// removes itself from the run queue in event.await(). Publish the reason
	// first so the waiter can observe it after dequeuing itself.
	if by_signal {
		katomic.store(mut &t.enqueued_by_signal, true)
	}

	if t.is_in_queue == true {
		return true
	}

	for i := u64(0); i < max_running_threads; i++ {
		if katomic.cas[&proc.Thread](mut &scheduler_running_queue[i], unsafe { nil }, t) {
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

		// Poll UART for console input.
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

	// With no other runnable thread, scheduler_timer_handler parks the CPU by
	// clearing its current-thread slot and switching to the kernel pagemap, then
	// returns to this polling loop. If an interrupt wakes this same thread, there
	// is no sched_switch_context round trip to restore that per-CPU state for us.
	// Reclaim the CPU here before the blocking syscall resumes.
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
	cpu.interrupt_toggle(false)
	mut t := proc.current_thread()
	dequeue_thread(t)
	t.is_dead = true
	// This thread leaves the CPU here rather than through the switch in
	// scheduler_timer_handler, so its last turn is charged here or not at all.
	// A process that runs briefly and exits would otherwise report no CPU time
	// at all, which is exactly the process worth noticing.
	proc.charge_cpu_time(mut t, timer.get_ns())
	// tick_itimers() keeps a raw pointer to every armed thread, so the entry
	// has to go before the Thread struct can be recycled.
	set_itimer_real(t, 0, 0)
	// A running thread holds its own lock, taken by get_next_thread(). Nothing
	// will ever deschedule us to release it, and intercept_thread() would spin
	// on it forever, so hand it back here.
	katomic.store(mut &t.running_on, u64(-1))
	t.l.release()
	// Clear current thread so the scheduler timer handler knows
	// there is no running thread to save state from.
	mut cpu_local := cpulocal.current()
	proc.set_current_thread(cpu_local.cpu_number, unsafe { nil })
	hand_over_to_reaper(cpu_local.cpu_number, t)
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

	C.yield_dispatch(voidptr(scheduler_timer_handler))

	mut current_thread := proc.current_thread()
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

pub fn new_user_thread(_process &proc.Process, want_elf bool, pc voidptr, arg voidptr, _stack u64, argv []string, envp []string, auxval &elf.Auxval, autoenqueue bool) ?&proc.Thread {
	mut process := unsafe { _process }

	mut stacks := []voidptr{}
	defer {
		unsafe { stacks.free() }
	}

	mut stack := unsafe { &u64(0) }
	mut stack_vma := u64(0)

	if _stack == 0 {
		mut user_stack_size := stack_size
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

	kernel_stack_phys := memory.pmm_alloc(kernel_stack_size / page_size)
	stacks << kernel_stack_phys
	kernel_stack := u64(kernel_stack_phys) + kernel_stack_size + higher_half

	fpu_storage_phys := memory.pmm_alloc(lib.div_roundup(fpu_storage_size, page_size))

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

			// AT_RANDOM is shared by libc stack canaries and userspace ASLR.
			stack = &u64(u64(stack) - 16)
			random_kernel_addr := u64(stack)
			if !krandom.fill(voidptr(random_kernel_addr), 16, true) {
				C.memset(voidptr(random_kernel_addr), 0, 16)
			}
			random_vma := stack_vma - (u64(stack_top) - random_kernel_addr)

			// Auxiliary vector (NULL-terminated)
			stack[-1] = 0
			stack = &stack[-1]
			stack[-1] = 0
			stack = &stack[-1]

			stack = &stack[-2]
			stack[0] = elf.at_secure
			stack[1] = 0
			// Linux always publishes the ARM capability words. Their absence
			// makes crypto libraries fall back to executing optional instructions
			// under SIGILL probes. Advertise the mandatory FP/ASIMD baseline and
			// no optional extensions until Vinix enumerates ID registers itself.
			stack = &stack[-2]
			stack[0] = elf.at_hwcap2
			stack[1] = 0
			stack = &stack[-2]
			stack[0] = elf.at_hwcap
			stack[1] = 0x3
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

			t.gpr_state.sp -= u64(stack_top) - u64(stack)
		}
	}

	attach_thread(mut process, mut t)?

	if autoenqueue == true {
		enqueue_thread(t, false)
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
		// A NUMA memory policy is process state, like nice and the rlimits, so
		// a fork keeps the placement its parent asked for.
		new_proc.mempolicy_mode = old_process.mempolicy_mode
		new_proc.mempolicy_nodemask = old_process.mempolicy_nodemask
		new_proc.pagemap = mmap.fork_pagemap(old_process.pagemap) or { return none }
		new_proc.thread_stack_top = old_process.thread_stack_top
		new_proc.mmap_anon_non_fixed_base = old_process.mmap_anon_non_fixed_base
		new_proc.current_directory = old_process.current_directory
	} else {
		new_proc.ppid = 0
		new_proc.pgid = new_proc.pid
		new_proc.sid = new_proc.pid
		new_proc.pagemap = unsafe { pagemap }
		new_proc.thread_stack_top = elf.initial_stack_top()
		new_proc.mmap_anon_non_fixed_base = elf.initial_mmap_base()
		new_proc.current_directory = voidptr(vfs_root)
		new_proc.rlimits = proc.default_rlimits()
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
	freq := cpu.read_cntfrq_el0()
	mut ticks := freq / idle_tick_hz
	if ticks == 0 {
		ticks = 1
	}
	cpu.write_cntv_tval_el0(ticks)
	cpu.write_cntv_ctl_el0(1)

	// Polling idle loop used on both QEMU/HVF and early Apple bring-up.
	// Keep interrupts disabled, poll CNTV_CTL ISTATUS, and dispatch the
	// scheduler timer handler directly when the timer fires.
	cpu.interrupt_toggle(false)

	// Which CPU this is, read once. Only the boot CPU polls, because the input
	// drivers below assume a single poller and any CPU released into this loop
	// would otherwise become a second one.
	polls_input := cpu.read_tpidr_el1() == 0

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
		if polls_input && uart_poll_callback != voidptr(0) {
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
