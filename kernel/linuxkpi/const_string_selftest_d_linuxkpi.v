// SPDX-License-Identifier: GPL-2.0-only
// Leaf-service ownership checks: no worker construction or hardware IRQ actor.
module linuxkpi

import proc
import x86.cpu
import x86.cpu.local as cpulocal

#include "linuxkpi_conststring_fixture_v_primitives.h"

fn C.vinix_linuxkpi_conststring_fixture_dup(voidptr, u32) voidptr
fn C.vinix_linuxkpi_conststring_fixture_free(voidptr)
fn C.vinix_linuxkpi_conststring_fixture_alloc(usize) voidptr
fn C.vinix_linuxkpi_conststring_fixture_gfp() u32
fn C.vinix_linuxkpi_conststring_fixture_literal() voidptr
fn C.vinix_linuxkpi_conststring_fixture_address(u32) usize
fn C.vinix_linuxkpi_conststring_fixture_rodata(voidptr) bool

// Only actual read-only pointers enter the ownership fast path. In particular,
// boundary probes below call the classifier alone, never strlen or kfree.
fn const_string_test_borrowed(ptr voidptr) bool {
	first := C.vinix_linuxkpi_conststring_fixture_dup(ptr, u32(-1))
	defer { C.vinix_linuxkpi_conststring_fixture_free(first) }
	if first != ptr { return false }
	second := C.vinix_linuxkpi_conststring_fixture_dup(ptr, C.vinix_linuxkpi_conststring_fixture_gfp())
	defer { C.vinix_linuxkpi_conststring_fixture_free(second) }
	return second == ptr && C.vinix_linuxkpi_conststring_fixture_rodata(ptr)
}

fn const_string_test_fast_batch() bool {
	literal := C.vinix_linuxkpi_conststring_fixture_literal()
	first := C.vinix_linuxkpi_conststring_fixture_address(0)
	end := C.vinix_linuxkpi_conststring_fixture_address(1)
	text := C.vinix_linuxkpi_conststring_fixture_address(2)
	if first == 0 || first >= end || text == 0 { return false }
	if !C.vinix_linuxkpi_conststring_fixture_rodata(voidptr(first))
		|| !C.vinix_linuxkpi_conststring_fixture_rodata(voidptr(end - 1))
		|| C.vinix_linuxkpi_conststring_fixture_rodata(voidptr(first - 1))
		|| C.vinix_linuxkpi_conststring_fixture_rodata(voidptr(end))
		|| C.vinix_linuxkpi_conststring_fixture_rodata(unsafe { nil })
		|| C.vinix_linuxkpi_conststring_fixture_rodata(voidptr(usize(-1)))
		|| C.vinix_linuxkpi_conststring_fixture_rodata(voidptr(text)) { return false }
	unsafe {
		bytes := &u8(literal)
		if bytes[0] != `v` || bytes[6] != `c` || bytes[21] != 0 { return false }
	}
	for _ in 0 .. 200 {
		if !const_string_test_borrowed(literal)
			|| !const_string_test_borrowed(voidptr(usize(literal) + 6))
			|| !const_string_test_borrowed(voidptr(usize(literal) + 21)) { return false }
		empty := C.vinix_linuxkpi_conststring_fixture_dup(unsafe { nil }, C.vinix_linuxkpi_conststring_fixture_gfp())
		C.vinix_linuxkpi_conststring_fixture_free(empty)
		if empty != unsafe { nil } { return false }
	}
	return true
}

// Pin while IRQs are off before restoring IF, so a migration cannot invalidate
// the CPU/depth witness between the IRQ-off and pinned IF-on phases.
fn const_string_test_contexts() bool {
	if !may_sleep() { return false }
	ints := cpu.interrupt_toggle(false)
	mut owner := proc.current_thread()
	if owner == unsafe { nil } { cpu.interrupt_toggle(ints); return false }
	index := cpulocal.current().cpu_number
	depth := preempt_depth[index]
	irq_depth := cpulocal.current().maskable_irq_depth
	gate := owner.linuxkpi_alloc_fail_after
	owner.linuxkpi_alloc_fail_after = 0
	mut valid := ints && depth == 0 && irq_depth == 0 && !may_sleep()
		&& const_string_test_fast_batch() && !cpu.interrupt_state()
		&& voidptr(proc.current_thread()) == voidptr(owner) && preempt_depth[index] == depth
		&& owner.linuxkpi_alloc_fail_after == 0
	preempt_disable()
	preempt_disable()
	cpu.interrupt_toggle(ints)
	valid = valid && !may_sleep() && const_string_test_fast_batch() && cpu.interrupt_state() == ints
		&& preempt_depth[index] == depth + 2 && owner.linuxkpi_alloc_fail_after == 0
	restore := cpu.interrupt_toggle(false)
	valid = valid && restore == ints && cpulocal.current().cpu_number == index
		&& cpulocal.current().maskable_irq_depth == irq_depth
		&& voidptr(proc.current_thread()) == voidptr(owner)
		&& preempt_depth[index] == depth + 2
	release_preemption(false)
	release_preemption(false)
	valid = valid && preempt_depth[index] == depth && owner.linuxkpi_alloc_fail_after == 0
	owner.linuxkpi_alloc_fail_after = gate
	cpu.interrupt_toggle(ints)
	return valid && cpu.interrupt_state() == ints && may_sleep()
}

// Each operation owns its source and both possible duplicate results locally.
// The defer handles every checked-failure return and restores the caller gate.
fn const_string_test_owned_operation(round u32) bool {
	if !may_sleep() { return false }
	mut owner := proc.current_thread()
	if owner == unsafe { nil } { return false }
	gate := owner.linuxkpi_alloc_fail_after
	mut source := unsafe { nil }
	mut copy := unsafe { nil }
	mut other := unsafe { nil }
	mut stack := [u8(`a`) + u8(round % 26), u8(`b`), u8(`c`), u8(0)]!
	mut empty := [u8(0)]!
	stack_ptr := unsafe { voidptr(&stack[0]) }
	empty_ptr := unsafe { voidptr(&empty[0]) }
	defer {
		// A failing duplicate-identity check must not free a stack source or
		// release an aliased owner twice. Successful duplicates own one result.
		if other != stack_ptr && other != empty_ptr && other != source && other != copy {
			C.vinix_linuxkpi_conststring_fixture_free(other)
		}
		if copy != stack_ptr && copy != empty_ptr && copy != source {
			C.vinix_linuxkpi_conststring_fixture_free(copy)
		}
		C.vinix_linuxkpi_conststring_fixture_free(source)
		owner.linuxkpi_alloc_fail_after = gate
	}
	owner.linuxkpi_alloc_fail_after = -1
	flags := C.vinix_linuxkpi_conststring_fixture_gfp()
	if C.vinix_linuxkpi_conststring_fixture_rodata(stack_ptr)
		|| C.vinix_linuxkpi_conststring_fixture_rodata(empty_ptr) { return false }
	copy = C.vinix_linuxkpi_conststring_fixture_dup(stack_ptr, flags)
	if copy == unsafe { nil } || copy == stack_ptr
		|| C.vinix_linuxkpi_conststring_fixture_rodata(copy) { return false }
	unsafe {
		bytes := &u8(copy)
		if bytes[0] != stack[0] || bytes[1] != `b` || bytes[2] != `c` || bytes[3] != 0 { return false }
		stack[0] = `!`
		bytes[1] = `z`
		if bytes[0] != u8(`a`) + u8(round % 26) || stack[1] != `b` { return false }
	}
	C.vinix_linuxkpi_conststring_fixture_free(copy)
	copy = unsafe { nil }
	copy = C.vinix_linuxkpi_conststring_fixture_dup(empty_ptr, flags)
	if copy == unsafe { nil } || copy == empty_ptr
		|| C.vinix_linuxkpi_conststring_fixture_rodata(copy) { return false }
	empty[0] = `!`
	if unsafe { *&u8(copy) } != 0 { return false }
	C.vinix_linuxkpi_conststring_fixture_free(copy)
	copy = unsafe { nil }
	source = C.vinix_linuxkpi_conststring_fixture_alloc(4)
	if source == unsafe { nil } || C.vinix_linuxkpi_conststring_fixture_rodata(source) { return false }
	unsafe {
		bytes := &u8(source)
		bytes[0] = `o`; bytes[1] = `w`; bytes[2] = `n`; bytes[3] = 0
	}
	copy = C.vinix_linuxkpi_conststring_fixture_dup(source, flags)
	if copy == unsafe { nil } || copy == source
		|| C.vinix_linuxkpi_conststring_fixture_rodata(copy) { return false }
	unsafe { *&u8(source) = `!` }
	C.vinix_linuxkpi_conststring_fixture_free(source)
	source = unsafe { nil }
	// The source owner is already freed before these reads of its duplicate.
	unsafe {
		bytes := &u8(copy)
		if bytes[0] != `o` || bytes[1] != `w` || bytes[2] != `n` || bytes[3] != 0 { return false }
	}
	C.vinix_linuxkpi_conststring_fixture_free(copy)
	copy = unsafe { nil }
	owner.linuxkpi_alloc_fail_after = 0
	copy = C.vinix_linuxkpi_conststring_fixture_dup(stack_ptr, flags)
	if copy != unsafe { nil } || owner.linuxkpi_alloc_fail_after != -1 { return false }
	owner.linuxkpi_alloc_fail_after = 1
	other = C.vinix_linuxkpi_conststring_fixture_dup(stack_ptr, u32(-1))
	if other != unsafe { nil } || owner.linuxkpi_alloc_fail_after != 1 { return false }
	literal := C.vinix_linuxkpi_conststring_fixture_literal()
	other = C.vinix_linuxkpi_conststring_fixture_dup(literal, u32(-1))
	if other != literal || owner.linuxkpi_alloc_fail_after != 1 { return false }
	C.vinix_linuxkpi_conststring_fixture_free(other)
	other = unsafe { nil }
	other = C.vinix_linuxkpi_conststring_fixture_dup(unsafe { nil }, flags)
	if other != unsafe { nil } || owner.linuxkpi_alloc_fail_after != 1 { return false }
	copy = C.vinix_linuxkpi_conststring_fixture_dup(stack_ptr, flags)
	if copy == unsafe { nil } || copy == stack_ptr || owner.linuxkpi_alloc_fail_after != 0 { return false }
	C.vinix_linuxkpi_conststring_fixture_free(copy)
	copy = unsafe { nil }
	if owner.linuxkpi_alloc_fail_after != 0 { return false }
	other = C.vinix_linuxkpi_conststring_fixture_dup(stack_ptr, flags)
	return other == unsafe { nil } && owner.linuxkpi_alloc_fail_after == -1 && may_sleep()
}

fn const_string_test_batch() bool {
	if !const_string_test_contexts() { return false }
	for round in u32(0) .. 200 {
		if !const_string_test_owned_operation(round) { return false }
	}
	return may_sleep()
}

fn const_string_native_selftest() bool {
	if !may_sleep() { return false }
	for round in 0 .. 3 {
		before := selftest_free_baseline()
		if !const_string_test_batch() { return false }
		C.kprintf(c'linuxkpi: constant string batch warmup %d free-byte baseline=%llu after=%llu\n', round + 1, before, selftest_free_baseline())
	}
	mut before := CPUFeatureHeapSnapshot{}
	mut after := CPUFeatureHeapSnapshot{}
	free_before := selftest_free_baseline()
	if !cpu_feature_test_heap(unsafe { &before }) || !const_string_test_batch() { return false }
	free_after := selftest_free_baseline()
	if !cpu_feature_test_heap(unsafe { &after }) { return false }
	mut equal := before.count == after.count
	for i in 0 .. before.count {
		if before.sizes[i] != after.sizes[i] || before.live[i] != after.live[i] {
			equal = false
			C.kprintf(c'linuxkpi: constant string heap class %d size_before=%llu size_after=%llu live_before=%llu live_after=%llu\n', i, before.sizes[i], after.sizes[i], before.live[i], after.live[i])
		}
	}
	C.kprintf(c'linuxkpi: constant string fourth batch free-byte baseline=%llu after=%llu heap_equal=%u\n', free_before, free_after, u32(equal))
	return free_before == free_after && equal
}
