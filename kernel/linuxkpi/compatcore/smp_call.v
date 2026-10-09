// SPDX-License-Identifier: GPL-2.0-or-later
// Native boot-only Linux CSD queues. Original record access lives in headercore;
// transport is a real native maskable IPI. Callbacks are fast and nonblocking.
@[translated]
module compatcore

#include "linuxkpi_smp_call_v_primitives.h"

type SmpCallFn = fn (voidptr)
type SmpCondFn = fn (i32, voidptr) bool
@[typedef]
struct C.vks_smp_const_void {}
fn C.vks_smp_csd_flags(voidptr) &u32
fn C.vks_smp_csd_next(voidptr) voidptr
fn C.vks_smp_csd_set_next(voidptr, voidptr)
fn C.vks_smp_csd_function(voidptr) SmpCallFn
fn C.vks_smp_csd_info(voidptr) voidptr
fn C.vks_smp_csd_set_callback(voidptr, SmpCallFn, voidptr)
fn C.vks_smp_mask_has(C.vks_smp_const_void, u32) bool
fn C.vkm_cpu_masks_ready() bool
fn C.vkm_cpu_ids() u32
fn C.vkm_online_count() u32
fn C.vks_smp_load32(&u32, i32) u32
fn C.vks_smp_store32(&u32, u32, i32)
fn C.vks_smp_load_word(&usize, i32) usize
fn C.vks_smp_exchange_word(&usize, usize, i32) usize
fn C.vks_smp_compare_word(&usize, &usize, usize, i32, i32) bool
fn C.vks_smp_fence(i32)
fn C.vinix_linuxkpi_smp_send_ipi(u32)
fn C.vinix_linuxkpi_smp_boot_context() bool
fn C.vinix_linuxkpi_smp_task_present() bool
fn C.vinix_linuxkpi_maskable_irq_depth() u32
fn C.vinix_linuxkpi_cpu_id() u32
fn C.vinix_linuxkpi_preempt_disable()
fn C.vinix_linuxkpi_preempt_enable()

__global (
	vks_smp_published u32
	vks_smp_cpu_count u32
	vks_smp_heads [256]usize
	vks_smp_single_owner voidptr
	vks_smp_many_owner voidptr
	vks_smp_single_slots usize
	vks_smp_many_slots usize
)

@[export: 'vks_smp_ready']
pub fn smp_calls_ready() bool {
	return unsafe { C.vks_smp_load32(&vks_smp_published, 2) != 0 }
}

@[export: 'vks_smp_bootstrap']
pub fn smp_bootstrap(count u32) i32 {
	if count == 0 || count > u32(C.VKS_SMP_CPU_LIMIT) { return -22 }
	if !C.vkm_cpu_masks_ready() || count != C.vkm_cpu_ids() || count != C.vkm_online_count() {
		return -22
	}
	if smp_calls_ready() { return -114 }
	if !C.vinix_linuxkpi_smp_boot_context() { return -1 }
	// count <= 256 bounds both products and padding in the native 64-bit ABI.
	single_bytes := usize(count) * usize(C.VKS_SMP_CSD_BYTES) + usize(C.VKS_SMP_CSD_ALIGN) - 1
	many_bytes := usize(count) * usize(count) * usize(C.VKS_SMP_CSD_BYTES) + usize(C.VKS_SMP_CSD_ALIGN) - 1
	single_owner := C.kmalloc(single_bytes, u32(C.VKS_SMP_GFP_KERNEL))
	if usize(single_owner) == 0 { return -12 }
	many_owner := C.kmalloc(many_bytes, u32(C.VKS_SMP_GFP_KERNEL))
	if usize(many_owner) == 0 {
		C.kfree(single_owner)
		return -12
	}
	C.memset(single_owner, 0, single_bytes)
	C.memset(many_owner, 0, many_bytes)
	unsafe {
		vks_smp_single_owner = single_owner
		vks_smp_many_owner = many_owner
		vks_smp_single_slots = (usize(single_owner) + usize(C.VKS_SMP_CSD_ALIGN) - 1) & ~(usize(C.VKS_SMP_CSD_ALIGN) - 1)
		vks_smp_many_slots = (usize(many_owner) + usize(C.VKS_SMP_CSD_ALIGN) - 1) & ~(usize(C.VKS_SMP_CSD_ALIGN) - 1)
		for index := 0; index < 256; index++ { vks_smp_heads[index] = 0 }
		vks_smp_cpu_count = count
		C.vks_smp_store32(&vks_smp_published, 1, 3)
	}
	return 0
}

fn smp_task_context() bool {
	return (C.vinix_linuxkpi_irq_flags() & 512) != 0 && C.vinix_linuxkpi_maskable_irq_depth() == 0
		&& C.vinix_linuxkpi_smp_task_present()
}

fn smp_wait_csd(csd voidptr) {
	flags := C.vks_smp_csd_flags(csd)
	for (C.vks_smp_load32(flags, 2) & u32(C.VKS_SMP_LOCK)) != 0 {
		// Spin only services native TLB shootdowns; callbacks require their IPI.
		C.vinix_linuxkpi_spin_wait()
	}
}

fn smp_claim_csd(csd voidptr, sync bool) {
	smp_wait_csd(csd)
	C.vks_smp_store32(C.vks_smp_csd_flags(csd), u32(C.VKS_SMP_LOCK) | if sync { u32(C.VKS_SMP_SYNC) } else { u32(0) }, 0)
	C.vks_smp_fence(3)
}

// Returns whether an empty head became nonempty. No node read is permitted
// after the successful release CAS: a target can already unlock and free it.
fn smp_enqueue(cpu u32, csd voidptr) bool {
	unsafe {
		head := &vks_smp_heads[cpu]
		mut previous := C.vks_smp_load_word(head, 0)
		for {
			C.vks_smp_csd_set_next(csd, voidptr(previous))
			if C.vks_smp_compare_word(head, &previous, usize(csd), 3, 0) {
				return previous == 0
			}
		}
	}
}

fn smp_execute_single(source u32, cpu i32, csd voidptr) i32 {
	if cpu == i32(source) {
		callback := C.vks_smp_csd_function(csd)
		info := C.vks_smp_csd_info(csd)
		C.vks_smp_store32(C.vks_smp_csd_flags(csd), 0, 3)
		flags := C.vinix_linuxkpi_irq_save()
		callback(info)
		C.vinix_linuxkpi_irq_restore(flags)
		return 0
	}
	if cpu < 0 || u32(cpu) >= unsafe { vks_smp_cpu_count } {
		C.vks_smp_store32(C.vks_smp_csd_flags(csd), 0, 3)
		return -6
	}
	if smp_enqueue(u32(cpu), csd) { C.vinix_linuxkpi_smp_send_ipi(u32(cpu)) }
	return 0
}

@[export: 'vks_smp_single']
pub fn smp_single(wait u32, cpu i32, callback SmpCallFn, info voidptr, stack_csd voidptr) i32 {
	require(smp_calls_ready() && smp_task_context())
	C.vinix_linuxkpi_preempt_disable()
	source := C.vinix_linuxkpi_cpu_id()
	require(source < unsafe { vks_smp_cpu_count })
	mut csd := unsafe { voidptr(usize(stack_csd)) }
	if wait == 0 {
		csd = unsafe { voidptr(vks_smp_single_slots + usize(source) * usize(C.VKS_SMP_CSD_BYTES)) }
		smp_claim_csd(csd, false)
	} else {
		require(usize(csd) != 0 && (usize(csd) & (usize(C.VKS_SMP_CSD_ALIGN) - 1)) == 0)
		C.vks_smp_store32(C.vks_smp_csd_flags(csd), u32(C.VKS_SMP_LOCK) | u32(C.VKS_SMP_SYNC), 0)
	}
	C.vks_smp_csd_set_callback(csd, callback, info)
	result := smp_execute_single(source, cpu, csd)
	if wait != 0 { smp_wait_csd(csd) }
	C.vinix_linuxkpi_preempt_enable()
	return result
}

@[export: 'vks_smp_async']
pub fn smp_async(cpu i32, csd voidptr) i32 {
	require(smp_calls_ready() && usize(csd) != 0)
	C.vinix_linuxkpi_preempt_disable()
	flags := C.vks_smp_csd_flags(csd)
	// Caller serialization is required by Linux. Busy wins over invalid CPU.
	if (C.vks_smp_load32(flags, 2) & u32(C.VKS_SMP_LOCK)) != 0 {
		C.vinix_linuxkpi_preempt_enable()
		return -16
	}
	C.vks_smp_store32(flags, u32(C.VKS_SMP_LOCK), 0)
	C.vks_smp_fence(3)
	source := C.vinix_linuxkpi_cpu_id()
	require(source < unsafe { vks_smp_cpu_count })
	result := smp_execute_single(source, cpu, csd)
	C.vinix_linuxkpi_preempt_enable()
	return result
}

@[export: 'vks_smp_drain']
pub fn smp_drain(cpu u32) {
	require(smp_calls_ready() && cpu < unsafe { vks_smp_cpu_count }
		&& cpu == C.vinix_linuxkpi_cpu_id()
		&& (C.vinix_linuxkpi_irq_flags() & 512) == 0
		&& C.vinix_linuxkpi_maskable_irq_depth() != 0)
	mut entry := unsafe { voidptr(C.vks_smp_exchange_word(&vks_smp_heads[cpu], 0, 2)) }
	mut fifo := unsafe { voidptr(0) }
	for usize(entry) != 0 {
		next := C.vks_smp_csd_next(entry)
		C.vks_smp_csd_set_next(entry, fifo)
		fifo = entry
		entry = next
	}
	// Partition while every node is still locked. Independent head/tail values
	// preserve FIFO within each class and survive synchronous owner retirement.
	mut sync_head := unsafe { voidptr(0) }
	mut sync_tail := unsafe { voidptr(0) }
	mut async_head := unsafe { voidptr(0) }
	mut async_tail := unsafe { voidptr(0) }
	for usize(fifo) != 0 {
		next := C.vks_smp_csd_next(fifo)
		kind := C.vks_smp_load32(C.vks_smp_csd_flags(fifo), 0) & u32(C.VKS_SMP_TYPE_MASK)
		require(kind == 0 || kind == u32(C.VKS_SMP_SYNC))
		C.vks_smp_csd_set_next(fifo, unsafe { nil })
		if kind == u32(C.VKS_SMP_SYNC) {
			if usize(sync_tail) != 0 { C.vks_smp_csd_set_next(sync_tail, fifo) } else { sync_head = fifo }
			sync_tail = fifo
		} else {
			if usize(async_tail) != 0 { C.vks_smp_csd_set_next(async_tail, fifo) } else { async_head = fifo }
			async_tail = fifo
		}
		fifo = next
	}
	for usize(sync_head) != 0 {
		next := C.vks_smp_csd_next(sync_head)
		callback := C.vks_smp_csd_function(sync_head)
		info := C.vks_smp_csd_info(sync_head)
		callback(info)
		C.vks_smp_store32(C.vks_smp_csd_flags(sync_head), 0, 3)
		sync_head = next
	}
	for usize(async_head) != 0 {
		next := C.vks_smp_csd_next(async_head)
		callback := C.vks_smp_csd_function(async_head)
		info := C.vks_smp_csd_info(async_head)
		C.vks_smp_store32(C.vks_smp_csd_flags(async_head), 0, 3)
		callback(info)
		// callback may free/requeue this CSD. Only the detached next value lives.
		async_head = next
	}
}

@[export: 'vks_smp_many']
pub fn smp_many(mask C.vks_smp_const_void, callback SmpCallFn, info voidptr, wait bool, run_local bool, condition SmpCondFn) {
	require(smp_calls_ready() && smp_task_context() && C.vinix_linuxkpi_preempt_count() != 0
		&& usize(mask) != 0)
	source := C.vinix_linuxkpi_cpu_id()
	count := unsafe { vks_smp_cpu_count }
	require(source < count)
	mut candidates := [4]u64{}
	mut selected := [4]u64{}
	// Linux snapshots mask membership before condition callbacks can edit
	// caller-owned mask storage. Local membership has the same snapshot boundary.
	local_selected := run_local && C.vks_smp_mask_has(mask, source)
	for target := u32(0); target < count; target++ {
		if target != source && C.vks_smp_mask_has(mask, target) {
			unsafe { candidates[target / 64] |= u64(1) << (target % 64) }
		}
	}
	for target := u32(0); target < count; target++ {
		if unsafe { (candidates[target / 64] & (u64(1) << (target % 64))) == 0 } { continue }
		if usize(condition) != 0 && !condition(i32(target), info) { continue }
		csd := unsafe { voidptr(vks_smp_many_slots + (usize(source) * usize(count) + usize(target)) * usize(C.VKS_SMP_CSD_BYTES)) }
		smp_claim_csd(csd, wait)
		C.vks_smp_csd_set_callback(csd, callback, info)
		if smp_enqueue(target, csd) { C.vinix_linuxkpi_smp_send_ipi(target) }
		// No ASYNC node reads after publish. These stack bits outlive its reuse.
		unsafe { selected[target / 64] |= u64(1) << (target % 64) }
	}
	if local_selected
		&& (usize(condition) == 0 || condition(i32(source), info)) {
		flags := C.vinix_linuxkpi_irq_save()
		callback(info)
		C.vinix_linuxkpi_irq_restore(flags)
	}
	if wait {
		for target := u32(0); target < count; target++ {
			if unsafe { (selected[target / 64] & (u64(1) << (target % 64))) != 0 } {
				csd := unsafe { voidptr(vks_smp_many_slots + (usize(source) * usize(count) + usize(target)) * usize(C.VKS_SMP_CSD_BYTES)) }
				smp_wait_csd(csd)
			}
		}
	}
}
