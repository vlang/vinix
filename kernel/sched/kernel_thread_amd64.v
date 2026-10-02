// SPDX-License-Identifier: GPL-2.0-or-later
module sched

import x86.cpu.local as cpulocal
import memory
import proc
import lib

// Failure injection belongs to the constructing task, so unrelated kernel
// workers cannot consume it when the caller migrates or sleeps in reclaim.
pub fn test_kernel_thread_failure(stage int) {
	$if kernel_stack_selftest ? { kernel_thread_stack_test_stage = stage }
	$if linuxkpi ? {
		mut caller := proc.current_thread()
		if caller != unsafe { nil } {
			caller.kernel_thread_fail_stage = stage
		}
	}
}

// All ownership stays here until every allocation succeeds. The returned
// thread is not queued or pinned; its caller must publish it or discard it.
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
		memory.kernel_stack_alloc(stack_size)
	}
	if stack_base == unsafe { nil } {
		return none
	}
	pf_stack_base := if fail_stage == 2 {
		unsafe { nil }
	} else {
		memory.kernel_stack_alloc(stack_size)
	}
	if pf_stack_base == unsafe { nil } {
		memory.kernel_stack_free(u64(stack_base))
		return none
	}
	fpu_phys := if fail_stage == 3 { unsafe { nil } } else { memory.pmm_alloc_fallible(fpu_pages) }
	if fpu_phys == unsafe { nil } {
		memory.kernel_stack_free(u64(pf_stack_base))
		memory.kernel_stack_free(u64(stack_base))
		return none
	}
	thread_mem := if fail_stage == 4 {
		unsafe { nil }
	} else {
		memory.malloc_packed_fallible(sizeof(proc.Thread))
	}
	if thread_mem == unsafe { nil } {
		memory.pmm_free(fpu_phys, fpu_pages)
		memory.kernel_stack_free(u64(pf_stack_base))
		memory.kernel_stack_free(u64(stack_base))
		return none
	}

	stack := u64(stack_base) + stack_size
	// IRET has no CALL return address; preserve the SysV function-entry ABI.
	entry_stack := stack - 8
	unsafe { C.memset(voidptr(entry_stack), 0, 8) }
	mut t := unsafe { &proc.Thread(thread_mem) }
	// Initialize in place: a heap-copied local Thread literal would introduce
	// another fallible allocation that V's manual-free runtime cannot recover.
	unsafe {
		*t = proc.Thread{
			process:      kernel_process
			cr3:          u64(kernel_process.pagemap.top_level)
			gpr_state:    cpulocal.GPRState{
				cs:     kernel_code_seg
				ds:     kernel_data_seg
				es:     kernel_data_seg
				ss:     kernel_data_seg
				rflags: 0x202
				rip:    u64(pc)
				rdi:    u64(arg)
				rsp:    entry_stack
			}
			timeslice:    5000
			running_on:   u64(-1)
			kernel_stack: stack
			pf_stack:     u64(pf_stack_base) + stack_size
			fpu_storage:  voidptr(u64(fpu_phys) + higher_half)
		}
	}
	t.self = voidptr(t)
	t.gs_base = u64(voidptr(t))
	// The inline Linux task view owns no allocation and publishes no reference.
	proc.linuxkpi_init_task(mut t, unsafe { nil })
	return t
}
