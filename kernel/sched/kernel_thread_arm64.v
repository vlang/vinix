// SPDX-License-Identifier: GPL-2.0-or-later
module sched

import aarch64.cpu.local as cpulocal
import memory
import proc
import lib

pub fn test_kernel_thread_failure(stage int) {
	$if kernel_stack_selftest ? { kernel_thread_stack_test_stage = stage }
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
	$if kernel_stack_selftest ? {
		fail_stage = kernel_thread_stack_test_stage
		kernel_thread_stack_test_stage = 0
	}
	$if linuxkpi ? {
		mut caller := proc.current_thread()
		if caller != unsafe { nil } {
			fail_stage = caller.kernel_thread_fail_stage
			caller.kernel_thread_fail_stage = 0
		}
	}
	fpu_pages := lib.div_roundup(fpu_storage_size, page_size)
	stack_base := if fail_stage == 1 {
		unsafe { nil }
	} else {
		memory.kernel_stack_alloc(kernel_stack_size)
	}
	if stack_base == unsafe { nil } {
		return none
	}
	fpu_phys := if fail_stage == 2 { unsafe { nil } } else { memory.pmm_alloc_fallible(fpu_pages) }
	if fpu_phys == unsafe { nil } {
		memory.kernel_stack_free(u64(stack_base))
		return none
	}
	thread_mem := if fail_stage == 3 {
		unsafe { nil }
	} else {
		memory.malloc_packed_fallible(sizeof(proc.Thread))
	}
	if thread_mem == unsafe { nil } {
		memory.pmm_free(fpu_phys, fpu_pages)
		memory.kernel_stack_free(u64(stack_base))
		return none
	}
	stack := u64(stack_base) + kernel_stack_size
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
			fpu_storage:      voidptr(u64(fpu_phys) + higher_half)
			fpu_storage_phys: u64(fpu_phys)
		}
	}
	t.self = voidptr(t)
	return t
}
