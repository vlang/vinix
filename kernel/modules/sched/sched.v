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

const stack_size = u64(0x200000)

const max_running_threads = int(512)

__global (
	scheduler_vector        u8
	scheduler_running_queue [512]&proc.Thread
	kernel_process          &proc.Process
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
			apic.lapic_timer_oneshot(mut cpu_local, scheduler_vector, current_thread.timeslice)
			return
		}
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
	apic.lapic_timer_oneshot(mut cpu_local, scheduler_vector, current_thread.timeslice)

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

	for {}
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

			// Check if any CPU is idle and wake it up
			for cpu in cpu_locals {
				if katomic.load(&cpu.is_idle) == true {
					apic.lapic_send_ipi(u8(cpu.lapic_id), scheduler_vector)
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
	// for ptr in t.stacks {
	// memory.pmm_free(ptr, sched.stack_size / page_size)
	//}
	unsafe {
		// t.stacks.free()
		// free(t)
	}
	yield(false)
	for {}
}

pub fn new_kernel_thread(pc voidptr, arg voidptr, autoenqueue bool) &proc.Thread {
	mut stacks := []voidptr{}

	stack_phys := memory.pmm_alloc(stack_size / page_size)
	stacks << stack_phys
	stack := u64(stack_phys) + stack_size + higher_half

	gpr_state := cpulocal.GPRState{
		cs:     kernel_code_seg
		ds:     kernel_data_seg
		es:     kernel_data_seg
		ss:     kernel_data_seg
		rflags: 0x202
		rip:    u64(pc)
		rdi:    u64(arg)
		rbp:    u64(0)
		rsp:    stack
	}

	mut t := &proc.Thread{
		process:     kernel_process
		cr3:         u64(kernel_process.pagemap.top_level)
		gpr_state:   gpr_state
		timeslice:   5000
		running_on:  u64(-1)
		stacks:      stacks
		fpu_storage: voidptr(u64(memory.pmm_alloc(lib.div_roundup(fpu_storage_size, page_size))) +
			higher_half)
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

	pf_stack_phys := memory.pmm_alloc(stack_size / page_size)
	stacks << pf_stack_phys
	pf_stack := u64(pf_stack_phys) + stack_size + higher_half

	gpr_state := cpulocal.GPRState{
		cs:     user_code_seg
		ds:     user_data_seg
		es:     user_data_seg
		ss:     user_data_seg
		rflags: 0x202
		rip:    u64(pc)
		rdi:    u64(arg)
		rsp:    u64(stack_vma)
	}

	mut t := &proc.Thread{
		process:      process
		cr3:          u64(process.pagemap.top_level)
		gpr_state:    gpr_state
		timeslice:    5000
		running_on:   u64(-1)
		kernel_stack: kernel_stack
		pf_stack:     pf_stack
		stacks:       stacks
		fpu_storage:  voidptr(u64(memory.pmm_alloc(lib.div_roundup(fpu_storage_size, page_size))) +
			higher_half)
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

	// Set all sigactions to default
	for mut sa in t.sigactions {
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
			stack[0] = elf.at_secure
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
	mut new_process := &proc.Process{
		pagemap: unsafe { nil }
	}

	new_process.pid = proc.allocate_pid(new_process) or { return none }

	if unsafe { old_process != 0 } {
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
