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

pub fn initialise() {
	scheduler_vector = idt.allocate_vector()
	println('sched: Scheduler interrupt vector is 0x${scheduler_vector:x}')

	interrupt_table[scheduler_vector] = voidptr(scheduler_isr)
	idt.set_ist(scheduler_vector, 1)

	kernel_process = &proc.Process{
		pagemap: &kernel_pagemap
	}
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

fn C.userland__dispatch_a_signal(context &cpulocal.GPRState)

fn scheduler_isr(_ u32, gpr_state &cpulocal.GPRState) {
	apic.lapic_timer_stop()

	mut cpu_local := cpulocal.current()

	katomic.store(mut &cpu_local.is_idle, false)

	mut current_thread := proc.current_thread()

	mut next_thread := get_next_thread()

	if unsafe { current_thread != 0 } {
		current_thread.yield_await.release()

		if unsafe { next_thread == nil } && current_thread.is_in_queue {
			apic.lapic_eoi()
			apic.lapic_timer_oneshot(mut cpu_local, scheduler_vector, effective_timeslice(current_thread))
			return
		}
		// Past the early return above this thread really is coming off the
		// CPU, so the turn it has just had is charged to its process. The
		// monotonic clock is the tick source here rather than a counter read,
		// which puts the resolution at one timer tick.
		proc.charge_cpu_time(mut current_thread, time.monotonic_ns())
		unsafe {
			current_thread.gpr_state = *gpr_state
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

	cpu.set_gs_base(u64(current_thread))
	if current_thread.gpr_state.cs == 0x43 {
		cpu.set_kernel_gs_base(current_thread.gs_base)
	} else {
		cpu.set_kernel_gs_base(u64(current_thread))
	}
	cpu.set_fs_base(current_thread.fs_base)

	cpu_local.tss.ist3 = current_thread.pf_stack

	if cpu.read_cr3() != current_thread.cr3 {
		cpu.write_cr3(current_thread.cr3)
	}

	fpu_restore(current_thread.fpu_storage)

	katomic.store(mut &current_thread.running_on, cpu_local.cpu_number)

	apic.lapic_eoi()
	apic.lapic_timer_oneshot(mut cpu_local, scheduler_vector, effective_timeslice(current_thread))

	new_gpr_state := &current_thread.gpr_state

	if new_gpr_state.cs == user_code_seg {
		// C.userland__dispatch_a_signal(new_gpr_state)
	}

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

	if t.is_in_queue == true {
		return true
	}

	for i := u64(0); i < max_running_threads; i++ {
		if katomic.cas[&proc.Thread](mut &scheduler_running_queue[i], unsafe { nil }, t) {
			t.is_in_queue = true

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
	dequeue_thread(t)
	// This thread leaves the CPU here rather than through the switch in
	// scheduler_isr, so its last turn is charged here or not at all.
	proc.charge_cpu_time(mut t, time.monotonic_ns())
	unsafe {
	}
	yield(false)
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

	// POSIX threads inherit the creating thread's signal mask, while signal
	// dispositions are shared by the process. Vinix stores both on Thread, so
	// copy the current values before the new thread can be scheduled. Wine
	// installs its exception handlers before creating Windows threads.
	new_thread.sigentry = current_thread.sigentry
	new_thread.sigactions = current_thread.sigactions
	new_thread.masked_signals = current_thread.masked_signals

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

	// Linux spells SIG_DFL as zero. The original Vinix/mlibc ABI uses -2.
	for mut sa in t.sigactions {
		if process.linux_abi {
			sa.sa_sigaction = voidptr(0)
		} else {
			sa.sa_sigaction = voidptr(-2)
		}
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

			// Linux libcs use AT_RANDOM for their stack canary. It is also harmless
			// for the legacy mlibc loader, which ignores unknown entries.
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

	if autoenqueue == true {
		enqueue_thread(t, false)
	}

	t.tid = process.threads.len
	process.threads << t

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
		new_proc.tty_session = old_process.tty_session
		new_proc.pagemap = mmap.fork_pagemap(old_process.pagemap) or { return none }
		new_proc.thread_stack_top = old_process.thread_stack_top
		new_proc.mmap_anon_non_fixed_base = old_process.mmap_anon_non_fixed_base
		new_proc.current_directory = old_process.current_directory
		new_proc.linux_abi = old_process.linux_abi
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
	}

	return new_proc
}

pub fn await() {
	asm volatile amd64 {
		cli
	}
	mut cpu_local := cpulocal.current()
	apic.lapic_timer_oneshot(mut cpu_local, scheduler_vector, 20000)
	asm volatile amd64 {
		sti
		1:
		hlt
		jmp b1
		; ; ; memory
	}
}
