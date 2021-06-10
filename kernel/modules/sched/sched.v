module sched

import x86.cpu
import x86.cpu.local as cpulocal
import x86.idt
import x86.apic
import x86.msr
import katomic
import proc
import memory
import file
import elf

__global (
	scheduler_vector byte
	scheduler_running_queue []&proc.Thread
	kernel_process &proc.Process
)

const max_running_threads = int(512)

pub fn initialise() {
	scheduler_running_queue = []&proc.Thread{cap: max_running_threads,
											 len: max_running_threads,
											 init: voidptr(0)}

	scheduler_vector = idt.allocate_vector()
	println('sched: Scheduler interrupt vector is 0x${scheduler_vector:x}')

	interrupt_table[scheduler_vector] = voidptr(scheduler_isr)

	idt.set_ist(scheduler_vector, 1)

	kernel_process = &proc.Process{pagemap: kernel_pagemap}
}

fn get_next_thread(orig_i int) (int, &proc.Thread) {
	mut index := orig_i + 1

	for {
		if index >= scheduler_running_queue.len {
			index = 0
		}

		mut thread := scheduler_running_queue[index]

		if thread != 0 && thread.l.test_and_acquire() == true {
			return index, thread
		}

		if index == orig_i {
			break
		}

		index++
	}

	return -1, 0
}

fn scheduler_isr(_ u32, gpr_state &cpulocal.GPRState) {
	apic.lapic_timer_stop()

	mut cpu_local := cpulocal.current()

	katomic.store(cpu_local.is_idle, false)

	mut current_thread := &proc.Thread(cpu_local.current_thread)

	if current_thread != 0 {
		current_thread.yield_await.release()
	}

	new_index, new_thread := get_next_thread(cpu_local.last_run_queue_index)

	if current_thread != 0 && voidptr(new_thread) != voidptr(current_thread) {
		unsafe { current_thread.gpr_state = gpr_state[0] }
		current_thread.user_gs = cpu.get_user_gs()
		current_thread.user_fs = cpu.get_user_fs()
		current_thread.l.release()
	}

	if current_thread != 0 && voidptr(new_thread) == voidptr(current_thread) {
		apic.lapic_eoi()
		apic.lapic_timer_oneshot(scheduler_vector, current_thread.timeslice)
		cpu_local.last_run_queue_index = new_index
		return
	}

	if new_index == -1 {
		apic.lapic_eoi()
		cpu_local.current_thread = voidptr(0)
		cpu_local.last_run_queue_index = 0
		katomic.store(cpu_local.is_idle, true)
		await()
	}

	current_thread = new_thread
	cpu_local.last_run_queue_index = new_index
	cpu_local.current_thread = current_thread

	cpu.set_user_gs(current_thread.user_gs)
	cpu.set_user_fs(current_thread.user_fs)

	msr.wrmsr(0x175, current_thread.kernel_stack)

	current_thread.process.pagemap.switch_to()

	apic.lapic_eoi()
	apic.lapic_timer_oneshot(scheduler_vector, current_thread.timeslice)

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
		iretq
		;
		; rm (new_gpr_state)
		; memory
	}

	panic('We really should not get here')
}

pub fn enqueue_thread(_thread &proc.Thread) bool {
	mut thread := unsafe { _thread }

	if thread.is_in_queue == true {
		return true
	}

	for i := u64(0); i < scheduler_running_queue.len; i++ {
		if katomic.cas(voidptr(&scheduler_running_queue[i]), u64(0), u64(thread)) {
			thread.is_in_queue = true

			// Check if any CPU is idle and wake it up
			for cpu in cpu_locals {
				if katomic.load(cpu.is_idle) == true {
					apic.lapic_send_ipi(cpu.lapic_id, scheduler_vector)
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

pub fn yield() {
	asm volatile amd64 { cli }

	mut current_thread := &proc.Thread(cpulocal.current().current_thread)

	current_thread.yield_await.acquire()

	apic.lapic_timer_oneshot(scheduler_vector, 1)

	asm volatile amd64 { sti }

	current_thread.yield_await.acquire()
	current_thread.yield_await.release()
}

pub fn dequeue_and_yield() {
	asm volatile amd64 { cli }
	dequeue_thread(cpulocal.current().current_thread)
	yield()
}

pub fn new_kernel_thread(pc voidptr, arg voidptr, autoenqueue bool) &proc.Thread {
	stack_size := 8192

	stack := &[]u8{cap: stack_size, len: stack_size, init: 0}

	gpr_state := cpulocal.GPRState{
		cs: kernel_code_seg
		ds: kernel_data_seg
		es: kernel_data_seg
		ss: kernel_data_seg
		rflags: 0x202
		rip: u64(pc)
		rdi: u64(arg)
		rsp: unsafe { u64(&stack[0]) + u64(stack_size - 8) }
	}

	thread := &proc.Thread{
		process: kernel_process
		gpr_state: gpr_state
		timeslice: 5000
	}

	if autoenqueue == true {
		enqueue_thread(thread)
	}

	return thread
}

pub fn new_user_thread(_process &proc.Process, want_elf bool,
					   pc voidptr, arg voidptr,
					   argv []string, envp []string, auxval &elf.Auxval,
					   autoenqueue bool) &proc.Thread {
	mut process := unsafe { _process }

	stack_size := u64(65536)

	stack_phys := memory.pmm_alloc(stack_size / page_size)
	mut stack := &u64(u64(stack_phys) + stack_size + higher_half)

	stack_vma := process.thread_stack_top
	process.thread_stack_top -= stack_size
	stack_bottom_vma := process.thread_stack_top
	process.thread_stack_top -= page_size

	for i := u64(0); i < stack_size / page_size; i++ {
		process.pagemap.map_page(stack_bottom_vma + i * page_size,
								 u64(stack_phys) + i * page_size,
								 0x07)
	}

	kernel_stack := u64(memory.pmm_alloc(stack_size / page_size)) + stack_size + higher_half

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
		gpr_state: gpr_state
		timeslice: 5000
		kernel_stack: kernel_stack
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
		enqueue_thread(thread)
	}

	process.threads << thread

	return thread
}

pub fn new_process(old_process &proc.Process, pagemap &memory.Pagemap) &proc.Process {
	if old_process != 0 {
		panic('old_process')
	}

	new_process := &proc.Process{
		pagemap: pagemap
		threads: []&proc.Thread{}
		fds: []&file.FD{}
		children: []&proc.Process{}
		thread_stack_top: u64(0x70000000000)
	}

	return new_process
}

pub fn await() {
	apic.lapic_timer_oneshot(scheduler_vector, 20000)
	asm volatile amd64 {
		sti
		1:
		hlt
		jmp b1
		;
		;
		; memory
	}
}
