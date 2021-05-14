module sched

import x86
import klock
import memory

__global (
	scheduler_lock klock.Lock
	scheduler_vector byte
	scheduler_ap_vector byte
	scheduler_running_queue []&Thread
	scheduling_cpus u64
	kernel_process &Process
)

const max_running_threads = int(65536)

struct Process {
pub mut:
	pagemap memory.Pagemap
}

struct Thread {
pub mut:
	is_in_queue bool
	l klock.Lock
	process &Process
	gpr_state x86.CPUGPRState
	user_gs u64
	user_fs u64
	user_stack u64
	kernel_stack u64
}

pub fn initialise() {
	scheduler_running_queue = []&Thread{cap: max_running_threads,
										len: 0,
							  			init: 0}

	// Set PIT tick to 250Hz
	x86.pit_set_freq(250)

	scheduler_vector = x86.idt_allocate_vector()
	println('sched: Scheduler interrupt vector (BSP) is 0x${scheduler_vector:x}')

	scheduler_ap_vector = x86.idt_allocate_vector()
	println('sched: Scheduler interrupt vector (AP) is 0x${scheduler_ap_vector:x}')

	interrupt_table[scheduler_vector] = voidptr(scheduler_isr)
	interrupt_table[scheduler_ap_vector] = voidptr(scheduler_ap_isr)

	x86.idt_set_ist(scheduler_vector, 1)
	x86.idt_set_ist(scheduler_ap_vector, 1)

	kernel_process = &Process{pagemap: kernel_pagemap}

	x86.io_apic_set_irq_redirect(cpu_locals[0].lapic_id, scheduler_vector, 0, true)
}

fn scheduler_isr(num u32, gpr_state &x86.CPUGPRState) {
	if scheduler_lock.test_and_acquire() == false {
		return
	}

	x86.atomic_store(scheduling_cpus, cpus_online)

	// Trigger scheduler_ap_isr on APs
	for cpu_local in cpu_locals {
		if cpu_local.lapic_id == bsp_lapic_id {
			continue
		}
		x86.lapic_send_ipi(cpu_local.lapic_id, scheduler_ap_vector)
	}

	scheduler_common(gpr_state)
}

fn scheduler_ap_isr(num u32, gpr_state &x86.CPUGPRState) {
	scheduler_common(gpr_state)
}

fn get_next_thread(orig_i int) (int, &Thread) {
	mut index := orig_i + 1

	for i := 0; i < scheduler_running_queue.len; i++ {
		if index >= scheduler_running_queue.len {
			index = 0
		}

		thread := scheduler_running_queue[index]

		if thread != 0 && thread.l.test_and_acquire() == true {
			return i, thread
		}

		if index == orig_i {
			break
		}

		index++
	}

	return -1, 0
}

fn scheduler_common(gpr_state &x86.CPUGPRState) {
	if gpr_state.cs & 0x03 != 0 {
		x86.swapgs()
	}

	mut cpu_local := x86.current_cpu()
	mut current_thread := &Thread(cpu_local.current_thread)

	new_index, new_thread := get_next_thread(cpu_local.last_run_queue_index)

	if new_index == -1 {
		if gpr_state.cs & 0x03 != 0 {
			x86.swapgs()
		}
		x86.lapic_eoi()
		if x86.atomic_dec(scheduling_cpus) == false {
			scheduler_lock.release()
		}
		if current_thread != 0 {
			return
		} else {
			// Idle
			await()
		}
	}

	if current_thread != 0 {
		unsafe { current_thread.gpr_state = gpr_state[0] }
		current_thread.user_gs = x86.get_user_gs()
		current_thread.user_fs = x86.get_user_fs()
		current_thread.user_stack = cpu_local.user_stack
		current_thread.l.release()
	}

	current_thread = new_thread
	cpu_local.last_run_queue_index = new_index
	cpu_local.current_thread = current_thread

	x86.set_user_gs(current_thread.user_gs)
	x86.set_user_fs(current_thread.user_fs)

	cpu_local.user_stack = current_thread.user_stack
	cpu_local.kernel_stack = current_thread.kernel_stack

	if current_thread.gpr_state.cs & 0x03 != 0 {
		x86.swapgs()
	}

	current_thread.process.pagemap.switch_to()

	x86.lapic_eoi()
	if x86.atomic_dec(scheduling_cpus) == false {
		scheduler_lock.release()
	}

	new_gpr_state := &current_thread.gpr_state

	asm volatile amd64 {
		mov rsp, new_gpr_state
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

pub fn enqueue_thread(_thread &Thread) bool {
	mut thread := unsafe { _thread }

	if thread.is_in_queue == true {
		return true
	}

	scheduler_lock.acquire()

	scheduler_running_queue << thread

	thread.is_in_queue = true

	scheduler_lock.release()

	return true
}

pub fn new_kernel_thread(pc voidptr, arg voidptr, autoenqueue bool) &Thread {
	stack_size := 8192

	stack := &[]u8{cap: stack_size, len: stack_size, init: 0}

	gpr_state := x86.CPUGPRState {
		cs: kernel_code_seg
		ss: kernel_data_seg
		rflags: 0x202
		rip: u64(pc)
		rdi: u64(arg)
		rsp: unsafe { u64(&stack[0]) + u64(stack_size - 8) }
	}

	thread := &Thread{
		process: kernel_process
		gpr_state: gpr_state
	}

	if autoenqueue == true {
		enqueue_thread(thread)
	}

	return thread
}

pub fn await() {
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
