// SPDX-License-Identifier: GPL-2.0-or-later
// Typed facade: original allocation and deferred-free macros own all actions.
@[translated]
module rcufreefixture

#include "linuxkpi_rcufree_fixture_v_contract.h"

struct C.vkrf_zero {
mut:
	magic u64
}
struct C.vkrf_middle {
mut:
	magic u64
}
struct C.vkrf_boundary {
mut:
	magic u64
}
fn C.kzalloc(usize, u32) voidptr
fn C.kvfree(voidptr)
fn C.kvfree_rcu_mightsleep(voidptr)
fn C.vkrf_kfree_zero(&C.vkrf_zero)
fn C.vkrf_kvfree_middle(&C.vkrf_middle)
fn C.vkrf_kvfree_boundary(&C.vkrf_boundary)

const magic = u64(0x7263752d66726565)

@[export: 'vinix_linuxkpi_rcufree_fixture_new']
pub fn object_new(kind u32) voidptr {
	unsafe {
		if kind == 0 {
			mut object := &C.vkrf_zero(C.kzalloc(sizeof(C.vkrf_zero), 3264))
			if object != nil { object.magic = magic }
			return object
		}
		if kind == 1 {
			mut object := &C.vkrf_middle(C.kzalloc(sizeof(C.vkrf_middle), 3264))
			if object != nil { object.magic = magic }
			return object
		}
		if kind == 2 {
			mut object := &C.vkrf_boundary(C.kzalloc(sizeof(C.vkrf_boundary), 3264))
			if object != nil { object.magic = magic }
			return object
		}
		return nil
	}
}

// Call only before ownership transfer, or while an independently held genuine
// reader protects the entire allocation. Never call after releasing that scope.
@[export: 'vinix_linuxkpi_rcufree_fixture_check']
pub fn object_check(kind u32, storage voidptr) bool {
	unsafe {
		if storage == nil { return false }
		return match kind {
			0 { (&C.vkrf_zero(storage)).magic == magic }
			1 { (&C.vkrf_middle(storage)).magic == magic }
			2 { (&C.vkrf_boundary(storage)).magic == magic }
			else { false }
		}
	}
}

@[export: 'vinix_linuxkpi_rcufree_fixture_enqueue']
pub fn object_enqueue(kind u32, storage voidptr) {
	unsafe {
		match kind {
			0 { C.vkrf_kfree_zero(&C.vkrf_zero(storage)) }
			1 { C.vkrf_kvfree_middle(&C.vkrf_middle(storage)) }
			2 { C.vkrf_kvfree_boundary(&C.vkrf_boundary(storage)) }
			else { assert false }
		}
	}
}

@[export: 'vinix_linuxkpi_rcufree_fixture_headless']
pub fn object_headless(storage voidptr) { C.kvfree_rcu_mightsleep(storage) }
@[export: 'vinix_linuxkpi_rcufree_fixture_immediate']
pub fn object_immediate(storage voidptr) { C.kvfree(storage) }
@[export: 'vinix_linuxkpi_rcufree_fixture_head_offset']
pub fn head_offset(kind u32) u32 {
	return match kind { 0 { u32(0) } 1 { u32(16) } 2 { u32(4088) } else { ~u32(0) } }
}
