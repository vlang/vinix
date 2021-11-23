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

const stack_size = u64(0x200000)

const max_running_threads = int(512)

__global (
	scheduler_vector        byte
	scheduler_running_queue [512]&proc.Thread
	kernel_process          &proc.Process
	working_cpus            = u64(0)
)

pub fn initialise() {
	scheduler_vector = idt.allocate_vector()
	println('sched: Scheduler interrupt vector is 0x${scheduler_vector:x}')

	interrupt_table[scheduler_vector] = voidptr(scheduler_isr)
	idt.set_ist(scheduler_vector, 1)

	kernel_process = &proc.Process{
		pagemap: &kernel_pagemap
	}
}

fn get_next_thread(orig_i int) int {
	cpu_number := cpulocal.current().cpu_number

	mut index := orig_i + 1

	for {
		if index >= scheduler_running_queue.len {
			index = 0
		}

		mut thread := scheduler_running_queue[index]

		if thread != 0 {
			if katomic.load(thread.running_on) == cpu_number || thread.l.test_and_acquire() == true {
				return index
			}
		}

		if index == orig_i {
			break
		}

		index++
	}

	return -1
}

fn C.userland__dispatch_a_signal(context &cpulocal.GPRState)

fn scheduler_isr(_ u32, gpr_state &cpulocal.GPRState) {
	apic.lapic_timer_stop()

	mut cpu_local := cpulocal.current()

	katomic.store(cpu_local.is_idle, false)

	mut current_thread := proc.current_thread()

	new_index := get_next_thread(cpu_local.last_run_queue_index)

	if current_thread != 0 {
		current_thread.yield_await.release()

		if new_index == cpu_local.last_run_queue_index {
			apic.lapic_eoi()
			apic.lapic_timer_oneshot(mut cpu_local, scheduler_vector, current_thread.timeslice)
			return
		}
		unsafe {
			current_thread.gpr_state = *gpr_state
		}
		current_thread.kernel_gs_base = cpu.get_kernel_gs_base()
		current_thread.gs_base = cpu.get_gs_base()
		current_thread.fs_base = cpu.get_fs_base()
		current_thread.cr3 = cpu.read_cr3()
		fpu_save(current_thread.fpu_storage)
		katomic.store(current_thread.running_on, u64(-1))
		current_thread.l.release()

		katomic.dec(working_cpus)
	}

	if new_index == -1 {
		apic.lapic_eoi()
		cpu.set_gs_base(voidptr(&cpu_local.cpu_number))
		cpu.set_kernel_gs_base(voidptr(&cpu_local.cpu_number))
		cpu_local.last_run_queue_index = 0
		katomic.store(cpu_local.is_idle, true)
		if katomic.load(waiting_event_count) == 0 && katomic.load(working_cpus) == 0 {
			panic('Event heartbeat has flatlined :(')
		}
		await()
	}

	katomic.inc(working_cpus)

	current_thread = scheduler_running_queue[new_index]
	cpu_local.last_run_queue_index = new_index

	cpu.set_kernel_gs_base(current_thread.kernel_gs_base)
	cpu.set_gs_base(current_thread.gs_base)
	cpu.set_fs_base(current_thread.fs_base)

	cpu_local.tss.ist3 = current_thread.pf_stack

	if cpu.read_cr3() != current_thread.cr3 {
		cpu.write_cr3(current_thread.cr3)
	}

	fpu_restore(current_thread.fpu_storage)

	katomic.store(current_thread.running_on, cpu_local.cpu_number)

	apic.lapic_eoi()
	apic.lapic_timer_oneshot(mut cpu_local, scheduler_vector, current_thread.timeslice)

	new_gpr_state := &current_thread.gpr_state

	if new_gpr_state.cs == user_code_seg {
		asm volatile amd64 { swapgs }
		C.userland__dispatch_a_signal(new_gpr_state)
		asm volatile amd64 { swapgs }
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
		iretq
		; ; rm (new_gpr_state)
		; memory
	}

	for {}
}

pub fn enqueue_thread(_thread &proc.Thread, by_signal bool) bool {
	mut thread := unsafe { _thread }

	if thread.is_in_queue == true {
		return true
	}

	katomic.store(thread.enqueued_by_signal, by_signal)

	for i := u64(0); i < scheduler_running_queue.len; i++ {
		if katomic.cas(voidptr(&scheduler_running_queue[i]), u64(0), u64(thread)) {
			thread.is_in_queue = true

			// Check if any CPU is idle and wake it up
			for cpu in cpu_locals {
				if katomic.load(cpu.is_idle) == true {
					apic.lapic_send_ipi(byte(cpu.lapic_id), scheduler_vector)
					break
				}
			}

			return true
		}
	}

	return false
}

pub fn dequeue_thread(_thread &proc.Thread) bool {
	mut thread := unsafe { _thread }

	if thread.is_in_queue == false {
		return true
	}

	for i := u64(0); i < scheduler_running_queue.len; i++ {
		if katomic.cas(voidptr(&scheduler_running_queue[i]), u64(thread), u64(0)) {
			thread.is_in_queue = false
			return true
		}
	}

	return false
}

// Like dequeue_thread(), but it stops it immediately
pub fn intercept_thread(_thread &proc.Thread) ? {
	mut thread := unsafe { _thread }

	if voidptr(thread) == voidptr(proc.current_thread()) {
		return error('')
	}

	dequeue_thread(thread)

	running_on := thread.running_on

	if running_on == -1 {
		return
	}

	apic.lapic_send_ipi(byte(cpu_locals[running_on].lapic_id), scheduler_vector)

	thread.l.acquire()
	thread.l.release()
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
		cpu.set_gs_base(voidptr(&cpu_local.cpu_number))
		cpu.set_kernel_gs_base(voidptr(&cpu_local.cpu_number))
	}

	apic.lapic_send_ipi(byte(cpu_local.lapic_id), scheduler_vector)

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

[noreturn]
pub fn dequeue_and_die() {
	asm volatile amd64 {
		cli
	}
	mut thread := proc.current_thread()
	dequeue_thread(thread)
	for ptr in thread.stacks {
		memory.pmm_free(ptr, sched.stack_size / page_size)
	}
	unsafe {
		thread.stacks.free()
		free(thread)
	}
	yield(false)
	for {}
}

pub fn new_kernel_thread(pc voidptr, arg voidptr, autoenqueue bool) &proc.Thread {
	mut stacks := []voidptr{}

	stack_phys := memory.pmm_alloc(sched.stack_size / page_size)
	stacks << stack_phys
	stack := u64(stack_phys) + sched.stack_size + higher_half

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

	mut thread := &proc.Thread{
		process: kernel_process
		cr3: u64(kernel_process.pagemap.top_level)
		gpr_state: gpr_state
		timeslice: 5000
		running_on: u64(-1)
		stacks: stacks
		fpu_storage: voidptr(u64(memory.pmm_alloc(lib.div_roundup(fpu_storage_size, page_size))) +
			higher_half)
	}

	thread.self = voidptr(thread)
	thread.gs_base = u64(voidptr(thread))
	thread.kernel_gs_base = u64(voidptr(thread))

	if autoenqueue == true {
		enqueue_thread(thread, false)
	}

	return thread
}

pub fn new_user_thread(_process &proc.Process, want_elf bool, pc voidptr, arg voidptr, argv []string, envp []string, auxval &elf.Auxval, autoenqueue bool) ?&proc.Thread {
	mut process := unsafe { _process }

	mut stacks := []voidptr{}

	stack_phys := memory.pmm_alloc(sched.stack_size / page_size)
	mut stack := &u64(u64(stack_phys) + sched.stack_size + higher_half)

	stack_vma := process.thread_stack_top
	process.thread_stack_top -= sched.stack_size
	stack_bottom_vma := process.thread_stack_top
	process.thread_stack_top -= page_size

	mmap.map_range(process.pagemap, stack_bottom_vma, u64(stack_phys), sched.stack_size,
		mmap.prot_read | mmap.prot_write, mmap.map_anonymous) or { return none }

	kernel_stack_phys := memory.pmm_alloc(sched.stack_size / page_size)
	stacks << kernel_stack_phys
	kernel_stack := u64(kernel_stack_phys) + sched.stack_size + higher_half

	pf_stack_phys := memory.pmm_alloc(sched.stack_size / page_size)
	stacks << pf_stack_phys
	pf_stack := u64(pf_stack_phys) + sched.stack_size + higher_half

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

	mut thread := &proc.Thread{
		process: process
		cr3: u64(process.pagemap.top_level)
		gpr_state: gpr_state
		timeslice: 5000
		running_on: u64(-1)
		kernel_stack: kernel_stack
		pf_stack: pf_stack
		stacks: stacks
		fpu_storage: voidptr(u64(memory.pmm_alloc(lib.div_roundup(fpu_storage_size, page_size))) +
			higher_half)
	}

	thread.self = voidptr(thread)
	thread.gs_base = u64(0)
	thread.kernel_gs_base = u64(voidptr(thread))

	// Set up FPU control word and MXCSR as defined in the sysv ABI
	fpu_restore(thread.fpu_storage)

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

	fpu_save(thread.fpu_storage)

	// Set all sigactions to default
	for mut sa in thread.sigactions {
		sa.sa_sigaction = voidptr(-2)
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

			// Zero auxiliary vector entry
			stack[-1] = 0
			stack = &stack[-1]
			stack[-1] = 0
			stack = &stack[-1]

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

			thread.gpr_state.rsp -= u64(stack_top) - u64(stack)
		}
	}

	if autoenqueue == true {
		enqueue_thread(thread, false)
	}

	process.threads << thread

	return thread
}

pub fn new_process(old_process &proc.Process, pagemap &memory.Pagemap) ?&proc.Process {
	mut new_process := &proc.Process{
		pagemap: 0
	}

	new_process.pid = proc.allocate_pid(new_process) or { return none }

	new_process.threads = []&proc.Thread{}
	new_process.children = []&proc.Process{}

	if old_process != 0 {
		new_process.ppid = old_process.pid
		new_process.pagemap = mmap.fork_pagemap(old_process.pagemap) or { return none }
		new_process.thread_stack_top = old_process.thread_stack_top
		new_process.mmap_anon_non_fixed_base = old_process.mmap_anon_non_fixed_base
		new_process.current_directory = old_process.current_directory
	} else {
		new_process.ppid = 0
		new_process.pagemap = unsafe { pagemap }
		new_process.thread_stack_top = u64(0x70000000000)
		new_process.mmap_anon_non_fixed_base = u64(0x80000000000)
		new_process.current_directory = voidptr(vfs_root)
	}

	return new_process
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
