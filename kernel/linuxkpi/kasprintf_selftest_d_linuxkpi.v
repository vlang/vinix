// SPDX-License-Identifier: GPL-2.0-only
// Leaf variadic allocation ownership; no worker or hardware IRQ actor.
module linuxkpi

import proc
import x86.cpu
import x86.cpu.local as cpulocal

#include "linuxkpi_kasprintf_fixture_v_primitives.h"

fn C.vinix_linuxkpi_kasprintf_fixture_run(u32, u32, voidptr, &u32) voidptr
fn C.vinix_linuxkpi_kasprintf_fixture_overflow(u32, &u32) bool
fn C.vinix_linuxkpi_kasprintf_fixture_free(voidptr)
fn C.vinix_linuxkpi_kasprintf_fixture_alloc(usize) voidptr
fn C.vinix_linuxkpi_kasprintf_fixture_gfp() u32
fn C.vinix_linuxkpi_kasprintf_fixture_literal() voidptr
fn C.vinix_linuxkpi_kasprintf_fixture_rodata(voidptr) bool

fn kasprintf_test_text(ptr voidptr, expected &char) bool {
	unsafe {
		if ptr == nil { return false }
		bytes := &u8(ptr)
		wanted := &u8(expected)
		for index in 0 .. 256 {
			if bytes[index] != wanted[index] { return false }
			if bytes[index] == 0 { return true }
		}
		return false
	}
}

fn kasprintf_test_borrowed(ptr voidptr) bool {
	mut state := u32(0)
	for which in u32(5) .. 10 {
		if which == 7 { continue }
		result := C.vinix_linuxkpi_kasprintf_fixture_run(which, u32(-1), ptr, &state)
		// All results here either remain NULL or borrow real rodata.
		C.vinix_linuxkpi_kasprintf_fixture_free(result)
		expected := if which == 5 || which == 8 { u32(1) } else { u32(3) }
		if result != ptr || state != expected { return false }
	}
	return true
}

fn kasprintf_test_fast_batch() bool {
	literal := C.vinix_linuxkpi_kasprintf_fixture_literal()
	unsafe {
		if (&u8(literal))[0] != `v` || (&u8(literal))[6] != `f` || (&u8(literal))[21] != 0 {
			return false
		}
	}
	for _ in 0 .. 200 {
		if !kasprintf_test_borrowed(literal)
			|| !kasprintf_test_borrowed(voidptr(usize(literal) + 6))
			|| !kasprintf_test_borrowed(voidptr(usize(literal) + 21)) {
			return false
		}
		mut state := u32(0)
		first := C.vinix_linuxkpi_kasprintf_fixture_run(5, u32(-1), unsafe { nil }, &state)
		C.vinix_linuxkpi_kasprintf_fixture_free(first)
		if first != unsafe { nil } || state != 1 { return false }
		second := C.vinix_linuxkpi_kasprintf_fixture_run(8, u32(-1), unsafe { nil }, &state)
		C.vinix_linuxkpi_kasprintf_fixture_free(second)
		if second != unsafe { nil } || state != 1 { return false }
	}
	return true
}

fn kasprintf_test_contexts() bool {
	if !may_sleep() { return false }
	ints := cpu.interrupt_toggle(false)
	mut owner := proc.current_thread()
	if owner == unsafe { nil } {
		cpu.interrupt_toggle(ints)
		return false
	}
	index := cpulocal.current().cpu_number
	depth := preempt_depth[index]
	irq_depth := cpulocal.current().maskable_irq_depth
	gate := owner.linuxkpi_alloc_fail_after
	owner.linuxkpi_alloc_fail_after = 0
	mut valid := ints && depth == 0 && irq_depth == 0 && !may_sleep()
		&& kasprintf_test_fast_batch() && !cpu.interrupt_state()
		&& voidptr(proc.current_thread()) == voidptr(owner) && preempt_depth[index] == depth
		&& owner.linuxkpi_alloc_fail_after == 0
	preempt_disable()
	preempt_disable()
	cpu.interrupt_toggle(ints)
	valid = valid && !may_sleep() && kasprintf_test_fast_batch() && cpu.interrupt_state() == ints
		&& preempt_depth[index] == depth + 2 && owner.linuxkpi_alloc_fail_after == 0
	restore := cpu.interrupt_toggle(false)
	valid = valid && restore == ints && cpulocal.current().cpu_number == index
		&& cpulocal.current().maskable_irq_depth == irq_depth
		&& voidptr(proc.current_thread()) == voidptr(owner) && preempt_depth[index] == depth + 2
	release_preemption(false)
	release_preemption(false)
	valid = valid && preempt_depth[index] == depth && owner.linuxkpi_alloc_fail_after == 0
	owner.linuxkpi_alloc_fail_after = gate
	cpu.interrupt_toggle(ints)
	return valid && cpu.interrupt_state() == ints && may_sleep()
}

fn kasprintf_test_owned_operation() bool {
	if !may_sleep() { return false }
	mut owner := proc.current_thread()
	if owner == unsafe { nil } { return false }
	gate := owner.linuxkpi_alloc_fail_after
	mut source := unsafe { nil }
	mut result := unsafe { nil }
	mut other := unsafe { nil }
	mut stack := [u8(`a`), `l`, `p`, `h`, `a`, `b`, `e`, `t`, 0]!
	stack_ptr := unsafe { voidptr(&stack[0]) }
	defer {
		if other != stack_ptr && other != source && other != result {
			C.vinix_linuxkpi_kasprintf_fixture_free(other)
		}
		if result != stack_ptr && result != source {
			C.vinix_linuxkpi_kasprintf_fixture_free(result)
		}
		C.vinix_linuxkpi_kasprintf_fixture_free(source)
		owner.linuxkpi_alloc_fail_after = gate
	}
	owner.linuxkpi_alloc_fail_after = -1
	flags := C.vinix_linuxkpi_kasprintf_fixture_gfp()
	mut state := u32(0)
	for which in u32(0) .. 4 {
		result = C.vinix_linuxkpi_kasprintf_fixture_run(which, flags, stack_ptr, &state)
		if result == unsafe { nil } || result == stack_ptr || C.vinix_linuxkpi_kasprintf_fixture_rodata(result) {
			return false
		}
		expected_state := if which == 1 {
			u32(0)
		} else if which == 3 {
			u32(3)
		} else {
			u32(1)
		}
		text := if which == 2 {
			c'alp   |+7|-8|-1234567890|-9223372036854775807|1234|0x2a|!|%'
		} else if which == 3 {
			c''
		} else {
			c'1/cursor/2/3/4/5/6/7'
		}
		if state != expected_state || !kasprintf_test_text(result, text) { return false }
		stack[0] = `!`
		if !kasprintf_test_text(result, text) { return false }
		stack[0] = `a`
		C.vinix_linuxkpi_kasprintf_fixture_free(result)
		result = unsafe { nil }
	}
	result = C.vinix_linuxkpi_kasprintf_fixture_run(7, flags, stack_ptr, &state)
	if result == unsafe { nil } || result == stack_ptr || state != 1
		|| !kasprintf_test_text(result, c'1/cursor/2/3/4/5/6/7') {
		return false
	}
	C.vinix_linuxkpi_kasprintf_fixture_free(result)
	result = unsafe { nil }
	result = C.vinix_linuxkpi_kasprintf_fixture_run(12, flags, stack_ptr, &state)
	if result == unsafe { nil } || result == stack_ptr || state != 3
		|| !kasprintf_test_text(result, c'outer<11/nested/22/33/44/55/66/77>tail') {
		return false
	}
	C.vinix_linuxkpi_kasprintf_fixture_free(result)
	result = unsafe { nil }
	result = C.vinix_linuxkpi_kasprintf_fixture_run(4, flags, unsafe { nil }, &state)
	if result == unsafe { nil } || state != 1 || !kasprintf_test_text(result, c'(null)') {
		return false
	}
	C.vinix_linuxkpi_kasprintf_fixture_free(result)
	result = unsafe { nil }
	result = C.vinix_linuxkpi_kasprintf_fixture_run(5, flags, stack_ptr, &state)
	if result == unsafe { nil } || result == stack_ptr || state != 1
		|| C.vinix_linuxkpi_kasprintf_fixture_rodata(result) || !kasprintf_test_text(result, c'alphabet') {
		return false
	}
	stack[0] = `!`
	if !kasprintf_test_text(result, c'alphabet') { return false }
	stack[0] = `a`
	C.vinix_linuxkpi_kasprintf_fixture_free(result)
	result = unsafe { nil }
	source = C.vinix_linuxkpi_kasprintf_fixture_alloc(9)
	if source == unsafe { nil } { return false }
	unsafe {
		for index in 0 .. 9 { (&u8(source))[index] = stack[index] }
	}
	result = C.vinix_linuxkpi_kasprintf_fixture_run(8, flags, source, &state)
	if result == unsafe { nil } || result == source || result == stack_ptr || state != 1
		|| C.vinix_linuxkpi_kasprintf_fixture_rodata(result) {
		return false
	}
	unsafe { *&u8(source) = `!` }
	C.vinix_linuxkpi_kasprintf_fixture_free(source)
	source = unsafe { nil }
	if !kasprintf_test_text(result, c'alphabet') { return false }
	C.vinix_linuxkpi_kasprintf_fixture_free(result)
	result = unsafe { nil }
	owner.linuxkpi_alloc_fail_after = 0
	result = C.vinix_linuxkpi_kasprintf_fixture_run(10, flags, stack_ptr, &state)
	if result != unsafe { nil } || state != 3 || owner.linuxkpi_alloc_fail_after != -1 {
		return false
	}
	owner.linuxkpi_alloc_fail_after = 0
	result = C.vinix_linuxkpi_kasprintf_fixture_run(11, flags, stack_ptr, &state)
	if result != unsafe { nil } || state != 3 || owner.linuxkpi_alloc_fail_after != -1 {
		return false
	}
	owner.linuxkpi_alloc_fail_after = 1
	result = C.vinix_linuxkpi_kasprintf_fixture_run(10, u32(-1), stack_ptr, &state)
	if result != unsafe { nil } || state != 3 || owner.linuxkpi_alloc_fail_after != 1 {
		return false
	}
	result = C.vinix_linuxkpi_kasprintf_fixture_run(1, u32(-1), stack_ptr, &state)
	if result != unsafe { nil } || state != 0 || owner.linuxkpi_alloc_fail_after != 1 {
		return false
	}
	if !kasprintf_test_borrowed(C.vinix_linuxkpi_kasprintf_fixture_literal()) || owner.linuxkpi_alloc_fail_after != 1 {
		return false
	}
	if !C.vinix_linuxkpi_kasprintf_fixture_overflow(flags, &state) || state != 3 || owner.linuxkpi_alloc_fail_after != 1 {
		return false
	}
	result = C.vinix_linuxkpi_kasprintf_fixture_run(0, flags, stack_ptr, &state)
	if result == unsafe { nil } || result == stack_ptr || state != 1 || owner.linuxkpi_alloc_fail_after != 0 {
		return false
	}
	C.vinix_linuxkpi_kasprintf_fixture_free(result)
	result = unsafe { nil }
	other = C.vinix_linuxkpi_kasprintf_fixture_run(10, flags, stack_ptr, &state)
	if other != unsafe { nil } || state != 3 || owner.linuxkpi_alloc_fail_after != -1 {
		return false
	}
	owner.linuxkpi_alloc_fail_after = 1
	result = C.vinix_linuxkpi_kasprintf_fixture_run(1, flags, stack_ptr, &state)
	if result == unsafe { nil } || result == stack_ptr || state != 0 || owner.linuxkpi_alloc_fail_after != 0 {
		return false
	}
	C.vinix_linuxkpi_kasprintf_fixture_free(result)
	result = unsafe { nil }
	return owner.linuxkpi_alloc_fail_after == 0 && may_sleep()
}

fn kasprintf_test_batch() bool {
	if !kasprintf_test_contexts() { return false }
	for _ in 0 .. 200 { if !kasprintf_test_owned_operation() { return false } }
	return may_sleep()
}

fn kasprintf_native_selftest() bool {
	if !may_sleep() { return false }
	for round in 0 .. 3 {
		before := selftest_free_baseline()
		if !kasprintf_test_batch() { return false }
		C.kprintf(c'linuxkpi: formatted allocation batch warmup %d free-byte baseline=%llu after=%llu\n', round + 1, before, selftest_free_baseline())
	}
	mut before := CPUFeatureHeapSnapshot{}
	mut after := CPUFeatureHeapSnapshot{}
	free_before := selftest_free_baseline()
	if !cpu_feature_test_heap(unsafe { &before }) || !kasprintf_test_batch() { return false }
	free_after := selftest_free_baseline()
	if !cpu_feature_test_heap(unsafe { &after }) { return false }
	mut equal := before.count == after.count
	for index in 0 .. before.count {
		if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] {
			equal = false
			C.kprintf(c'linuxkpi: formatted allocation heap class %d size_before=%llu size_after=%llu live_before=%llu live_after=%llu\n', index, before.sizes[index], after.sizes[index], before.live[index], after.live[index])
		}
	}
	C.kprintf(c'linuxkpi: formatted allocation fourth batch free-byte baseline=%llu after=%llu heap_equal=%u\n', free_before, free_after, u32(equal))
	return free_before == free_after && equal
}
