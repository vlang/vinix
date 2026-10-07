// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module compatcore

#include "linuxkpi_smp_masks_v_primitives.h"

fn C.vkm_mask_storage(u32) voidptr
fn C.vkm_cpu_ids_storage() voidptr
fn C.vkm_online_storage() voidptr
fn C.vkms_load32(&u32, i32) u32
fn C.vkms_store32(&u32, u32, i32)

__global vkms_ready u32

@[export: 'vkm_cpu_masks_ready']
pub fn cpu_masks_ready() bool {
	return unsafe { C.vkms_load32(&vkms_ready, 2) != 0 }
}

// The native boot owner validates actual online Local IDs before this call.
// No ordinary compatibility user may observe publication in progress: Linux
// inline consumers read their original globals without consulting vkms_ready.
// Storage is permanent, and this function allocates and retains nothing.
@[export: 'vkm_cpu_masks_bootstrap']
pub fn cpu_masks_bootstrap(count u32) i32 {
	if count == 0 || count > u32(C.VKM_CPU_LIMIT) {
		return -22
	}
	if cpu_masks_ready() {
		return -114
	}
	for kind := u32(0); kind < 5; kind++ {
		unsafe {
			words := &u64(C.vkm_mask_storage(kind))
			for word := u32(0); word < u32(C.VKM_MASK_WORDS); word++ {
				mut value := u64(0)
				if kind != 4 {
					first := word * 64
					if count >= first + 64 {
						value = ~u64(0)
					} else if count > first {
						value = (u64(1) << (count - first)) - 1
					}
				}
				words[word] = value
			}
		}
	}
	unsafe {
		// The original online counter is signed int; every validated count fits.
		C.vkms_store32(&u32(C.vkm_online_storage()), count, 0)
		C.vkms_store32(&u32(C.vkm_cpu_ids_storage()), count, 0)
		C.vkms_store32(&vkms_ready, 1, 3)
	}
	return 0
}
