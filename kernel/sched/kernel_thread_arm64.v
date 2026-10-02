// SPDX-License-Identifier: GPL-2.0-or-later
module sched

import aarch64.cpu.local as cpulocal
import memory
import proc
import lib

pub fn test_kernel_thread_failure(stage int) {
	$if linuxkpi ? {
		mut caller := proc.current_thread()
		if caller != unsafe { nil } {
			caller.kernel_thread_fail_stage = stage
		}
	}
}

// This constructor never publishes the thread. Failure gives back every
// successful allocation; publication failure uses discard_unstarted_thread.
pub fn try_new_kernel_thread(pc voidptr, arg voidptr) ?&proc.Thread {
	mut fail_stage := 0
	$if linuxkpi ? {
		mut caller := proc.current_thread()
		if caller != unsafe { nil } {
			fail_stage = caller.kernel_thread_fail_stage
			caller.kernel_thread_fail_stage = 0
		}
	}
	stack_pages := kernel_stack_size / page_size
	fpu_pages := lib.div_roundup(fpu_storage_size, page_size)
	stack_phys := if fail_stage == 1 {
		unsafe { nil }
	} else {
		memory.pmm_alloc_fallible(stack_pages)
	}
	if stack_phys == unsafe { nil } {
		return none
	}
	fpu_phys := if fail_stage == 2 { unsafe { nil } } else { memory.pmm_alloc_fallible(fpu_pages) }
	if fpu_phys == unsafe { nil } {
		memory.pmm_free(stack_phys, stack_pages)
		return none
	}
	thread_mem := if fail_stage == 3 {
		unsafe { nil }
	} else {
		memory.malloc_packed_fallible(sizeof(proc.Thread))
	}
	if thread_mem == unsafe { nil } {
		memory.pmm_free(fpu_phys, fpu_pages)
		memory.pmm_free(stack_phys, stack_pages)
		return none
	}
	stack := u64(stack_phys) + kernel_stack_size + higher_half
	mut t := unsafe { &proc.Thread(thread_mem) }
	unsafe {
		*t = proc.Thread{
			process:          kernel_process
			ttbr0:            kernel_process.pagemap.tagged_root()
			gpr_state:        cpulocal.GPRState{
				pc:     u64(pc)
				x0:     u64(arg)
				sp:     stack
				pstate: u64(0x3c5) | kernel_pstate_pan
			}
			timeslice:        5000
			running_on:       u64(-1)
			kernel_stack:     stack
			kstack_phys:      u64(stack_phys)
			fpu_storage:      voidptr(u64(fpu_phys) + higher_half)
			fpu_storage_phys: u64(fpu_phys)
		}
	}
	t.self = voidptr(t)
	return t
}
