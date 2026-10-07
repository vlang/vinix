// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module headercore

#include "linuxkpi_smp_masks_v_contract.h"

struct C.cpumask {}
@[typedef]
struct C.vkms_const_cpumask {}

@[c_extern]
__global C.__cpu_possible_mask C.cpumask
@[c_extern]
__global C.__cpu_online_mask C.cpumask
@[c_extern]
__global C.__cpu_present_mask C.cpumask
@[c_extern]
__global C.__cpu_active_mask C.cpumask
@[c_extern]
__global C.__cpu_dying_mask C.cpumask
@[c_extern]
__global C.__num_online_cpus C.atomic_t
@[c_extern]
__global C.nr_cpu_ids u32

fn C.cpumask_bits(&C.cpumask) voidptr
fn C.cpumask_test_cpu(i32, &C.cpumask) bool
fn C.cpumask_weight(&C.cpumask) u32
fn C.cpumask_of(u32) C.vkms_const_cpumask
fn C.vkms_all_mask() C.vkms_const_cpumask
fn C.vkms_const_bits(C.vkms_const_cpumask) voidptr
fn C.num_online_cpus() u32
fn C.vkm_cpu_masks_ready() bool

fn cpu_mask_original(kind u32) &C.cpumask {
	unsafe {
		match kind {
			0 { return &C.__cpu_possible_mask }
			1 { return &C.__cpu_online_mask }
			2 { return &C.__cpu_present_mask }
			3 { return &C.__cpu_active_mask }
			4 { return &C.__cpu_dying_mask }
			else { return nil }
		}
	}
}

@[export: 'vkm_mask_storage']
pub fn cpu_mask_storage(kind u32) voidptr {
	mask := cpu_mask_original(kind)
	if usize(mask) == 0 {
		return unsafe { nil }
	}
	return C.cpumask_bits(mask)
}

@[export: 'vkm_cpu_ids_storage']
pub fn cpu_ids_storage() voidptr {
	return unsafe { &C.nr_cpu_ids }
}

@[export: 'vkm_online_storage']
pub fn online_storage() voidptr {
	return unsafe { &C.__num_online_cpus.counter }
}

// Checked internal queries acquire publication. Original Linux inline readers
// remain governed by native boot ordering, not by these wrapper guards.
@[export: 'vkm_mask_has']
pub fn cpu_mask_has(kind u32, cpu u32) bool {
	if !C.vkm_cpu_masks_ready() || cpu >= unsafe { C.nr_cpu_ids } {
		return false
	}
	mask := cpu_mask_original(kind)
	return usize(mask) != 0 && C.cpumask_test_cpu(i32(cpu), mask)
}

@[export: 'vkm_mask_weight']
pub fn cpu_mask_weight(kind u32) u32 {
	if !C.vkm_cpu_masks_ready() {
		return 0
	}
	mask := cpu_mask_original(kind)
	if usize(mask) == 0 {
		return 0
	}
	return C.cpumask_weight(mask)
}

// Constant masks cover full NR_CPUS storage, independently of installed IDs.
// Use original bitmap primitives rather than exceeding cpumask_test_cpu's
// documented cpu < nr_cpu_ids precondition.
@[export: 'vkm_mask_of_has']
pub fn cpu_mask_of_has(selected u32, cpu u32) bool {
	if selected >= u32(C.VKM_CPU_LIMIT) || cpu >= u32(C.VKM_CPU_LIMIT) {
		return false
	}
	return C.test_bit(i32(cpu), C.vkms_const_bits(C.cpumask_of(selected)))
}

@[export: 'vkm_all_has']
pub fn all_cpu_has(cpu u32) bool {
	if cpu >= u32(C.VKM_CPU_LIMIT) {
		return false
	}
	return C.test_bit(i32(cpu), C.vkms_const_bits(C.vkms_all_mask()))
}

@[export: 'vkm_online_count']
pub fn online_cpu_count() u32 {
	if !C.vkm_cpu_masks_ready() {
		return 0
	}
	return C.num_online_cpus()
}

@[export: 'vkm_cpu_ids']
pub fn installed_cpu_ids() u32 {
	if !C.vkm_cpu_masks_ready() {
		return 0
	}
	return unsafe { C.nr_cpu_ids }
}
