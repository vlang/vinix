module sched

import x86.cpu
import x86.cpu.local as cpulocal
import x86.idt
import x86.apic
import x86.pit
import klock
import katomic
import proc

__global (
	scheduler_lock klock.Lock
	scheduler_vector byte
	scheduler_ap_vector byte
	scheduler_running_queue []&proc.Thread
	scheduling_cpus u64
	kernel_process &proc.Process
)

const max_running_threads = int(65536)

pub fn initialise() {
	scheduler_running_queue = []&proc.Thread{cap: max_running_threads,
											 len: 0,
							  				 init: 0}

	// Set PIT tick to 250Hz
	pit.set_freq(250)

	scheduler_vector = idt.allocate_vector()
	println('sched: Scheduler interrupt vector (BSP) is 0x${scheduler_vector:x}')

	scheduler_ap_vector = idt.allocate_vector()
	println('sched: Scheduler interrupt vector (AP) is 0x${scheduler_ap_vector:x}')

	interrupt_table[scheduler_vector] = voidptr(scheduler_isr)
	interrupt_table[scheduler_ap_vector] = voidptr(scheduler_ap_isr)

	idt.set_ist(scheduler_vector, 1)
	idt.set_ist(scheduler_ap_vector, 1)

	kernel_process = &proc.Process{pagemap: kernel_pagemap}

	apic.io_apic_set_irq_redirect(cpu_locals[0].lapic_id, scheduler_vector, 0, true)
}

fn scheduler_isr(num u32, gpr_state &cpulocal.GPRState) {
	if scheduler_lock.test_and_acquire() == false {
		return
	}

	katomic.store(scheduling_cpus, cpus_online)

	// Trigger scheduler_ap_isr on APs
	for cpu_local in cpu_locals {
		if cpu_local.lapic_id == bsp_lapic_id {
			continue
		}
		apic.lapic_send_ipi(cpu_local.lapic_id, scheduler_ap_vector)
	}

	scheduler_common(gpr_state)
}

fn scheduler_ap_isr(num u32, gpr_state &cpulocal.GPRState) {
	scheduler_common(gpr_state)
}

fn get_next_thread(orig_i int) (int, &proc.Thread) {
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

fn scheduler_common(gpr_state &cpulocal.GPRState) {
	if gpr_state.cs & 0x03 != 0 {
		cpu.swapgs()
	}

	mut cpu_local := cpulocal.current()
	mut current_thread := &proc.Thread(cpu_local.current_thread)

	if current_thread != 0 {
		current_thread.yield_await.release()
	}

	new_index, new_thread := get_next_thread(cpu_local.last_run_queue_index)

	if new_index == -1 {
		if gpr_state.cs & 0x03 != 0 {
			cpu.swapgs()
		}
		apic.lapic_eoi()
		if katomic.dec(scheduling_cpus) == false {
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
		current_thread.user_gs = cpu.get_user_gs()
		current_thread.user_fs = cpu.get_user_fs()
		current_thread.user_stack = cpu_local.user_stack
		current_thread.l.release()
	}

	current_thread = new_thread
	cpu_local.last_run_queue_index = new_index
	cpu_local.current_thread = current_thread

	cpu.set_user_gs(current_thread.user_gs)
	cpu.set_user_fs(current_thread.user_fs)

	cpu_local.user_stack = current_thread.user_stack
	cpu_local.kernel_stack = current_thread.kernel_stack

	if current_thread.gpr_state.cs & 0x03 != 0 {
		cpu.swapgs()
	}

	current_thread.process.pagemap.switch_to()

	apic.lapic_eoi()
	if katomic.dec(scheduling_cpus) == false {
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

pub fn enqueue_thread(_thread &proc.Thread) bool {
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

pub fn dequeue_thread(_thread &proc.Thread) bool {
	mut thread := unsafe { _thread }

	if thread.is_in_queue == false {
		return true
	}

	scheduler_lock.acquire()

	//scheduler_running_queue = scheduler_running_queue.filter(it != _thread)

	thread.is_in_queue = false

	scheduler_lock.release()

	return true
}

pub fn yield() {
	asm volatile amd64 { cli }

	mut current_thread := &proc.Thread(cpulocal.current().current_thread)

	current_thread.yield_await.acquire()

	apic.lapic_send_ipi(cpulocal.current().lapic_id, scheduler_ap_vector)

	asm volatile amd64 { sti }

	current_thread.yield_await.acquire()
}

pub fn dequeue_and_yield() {
	asm volatile amd64 { cli }
	dequeue_thread(cpulocal.current().current_thread)
	yield()
}

pub fn new_kernel_thread(pc voidptr, arg voidptr, autoenqueue bool) &proc.Thread {
	stack_size := 8192

	stack := &[]u8{cap: stack_size, len: stack_size, init: 0}

	gpr_state := cpulocal.GPRState {
		cs: kernel_code_seg
		ss: kernel_data_seg
		rflags: 0x202
		rip: u64(pc)
		rdi: u64(arg)
		rsp: unsafe { u64(&stack[0]) + u64(stack_size - 8) }
	}

	thread := &proc.Thread{
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
