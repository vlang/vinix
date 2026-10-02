// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module sched

import memory

fn C.vinix_stack_guard_message(message charptr)

__global kernel_thread_stack_test_stage int

fn selftest_thread_stacks() {
	$if kernel_stack_selftest ? {
		warm := try_new_kernel_thread(unsafe { nil }, unsafe { nil }) or {
			panic('Cannot warm guarded thread self-test')
		}
		free_thread_memory(warm)
		baseline := memory.free_bytes()
		stages := $if aarch64 ? { 3 } $else { 4 }
		for iteration := 0; iteration < 32; iteration++ {
			for stage := 1; stage <= stages; stage++ {
				test_kernel_thread_failure(stage)
				if unexpected := try_new_kernel_thread(unsafe { nil }, unsafe { nil }) {
					free_thread_memory(unexpected)
					panic('Guarded thread failure injection did not fail')
				}
				if memory.free_bytes() != baseline { panic('Guarded thread failure retained pages') }
			}
			thr := try_new_kernel_thread(unsafe { nil }, unsafe { nil }) or {
				panic('Guarded thread success unexpectedly failed')
			}
			free_thread_memory(thr)
			if memory.free_bytes() != baseline { panic('Guarded thread retirement retained pages') }
		}
		C.vinix_stack_guard_message(c'STACK-GUARD PASS 32 unpublished thread allocation/rollback/retirement cycles\n')
	}
}
