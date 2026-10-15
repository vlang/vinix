// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module fencecontainerfixture

#include "linuxkpi_fence_container_fixture_v_contract.h"

struct C.dma_fence {
mut:
	flags u64
	context u64
	seqno u64
}
struct C.dma_fence_array {}
struct C.dma_fence_array_cb {}
struct C.dma_fence_chain {
mut:
	prev_seqno u64
}
fn C.dma_fence_array_create(i32, &&C.dma_fence, u64, u32, bool) &C.dma_fence_array
fn C.dma_fence_chain_alloc() &C.dma_fence_chain
fn C.dma_fence_chain_free(&C.dma_fence_chain)
fn C.dma_fence_chain_init(&C.dma_fence_chain, &C.dma_fence, &C.dma_fence, u64)
fn C.dma_fence_chain_walk(&C.dma_fence) &C.dma_fence
fn C.dma_fence_chain_find_seqno(&&C.dma_fence, u64) i32
fn C.dma_fence_array_first(&C.dma_fence) &C.dma_fence
fn C.dma_fence_array_next(&C.dma_fence, u32) &C.dma_fence
fn C.dma_fence_match_context(&C.dma_fence, u64) bool
fn C.dma_fence_is_array(&C.dma_fence) bool
fn C.dma_fence_is_chain(&C.dma_fence) bool
fn C.fct_refcount(voidptr) u32
fn C.fct_pending(voidptr) i32
fn C.__atomic_load_n(&u64, i32) u64

@[export: 'vinix_linuxkpi_fct_bytes']
pub fn bytes(kind u32) u32 {
	return if kind == 0 { u32(sizeof(C.dma_fence_array)) }
		else if kind == 1 { u32(sizeof(C.dma_fence_chain)) }
		else { u32(sizeof(C.dma_fence_array_cb)) }
}
@[export: 'vinix_linuxkpi_fct_array']
pub fn array(count i32, vector voidptr, context u64, seqno u32, any bool) voidptr {
	unsafe { return C.dma_fence_array_create(count, &&C.dma_fence(vector), context, seqno, any) }
}
@[export: 'vinix_linuxkpi_fct_chain_alloc']
pub fn chain_alloc() voidptr { return C.dma_fence_chain_alloc() }
@[export: 'vinix_linuxkpi_fct_chain_free']
pub fn chain_free(storage voidptr) { unsafe { C.dma_fence_chain_free(&C.dma_fence_chain(storage)) } }
@[export: 'vinix_linuxkpi_fct_chain_init']
pub fn chain_init(storage voidptr, prev voidptr, contained voidptr, seqno u64) {
	unsafe { C.dma_fence_chain_init(&C.dma_fence_chain(storage), &C.dma_fence(prev), &C.dma_fence(contained), seqno) }
}
@[export: 'vinix_linuxkpi_fct_walk']
pub fn walk(storage voidptr) voidptr { unsafe { return C.dma_fence_chain_walk(&C.dma_fence(storage)) } }
@[export: 'vinix_linuxkpi_fct_find']
pub fn find(storage &voidptr, seqno u64) i32 { unsafe { return C.dma_fence_chain_find_seqno(&&C.dma_fence(storage), seqno) } }
@[export: 'vinix_linuxkpi_fct_first']
pub fn first(storage voidptr) voidptr { unsafe { return C.dma_fence_array_first(&C.dma_fence(storage)) } }
@[export: 'vinix_linuxkpi_fct_next']
pub fn next(storage voidptr, index u32) voidptr { unsafe { return C.dma_fence_array_next(&C.dma_fence(storage), index) } }
@[export: 'vinix_linuxkpi_fct_match']
pub fn match(storage voidptr, context u64) bool { unsafe { return C.dma_fence_match_context(&C.dma_fence(storage), context) } }
@[export: 'vinix_linuxkpi_fct_kind']
pub fn kind(storage voidptr) u32 {
	unsafe { fence := &C.dma_fence(storage)
		return if C.dma_fence_is_array(fence) { u32(1) } else if C.dma_fence_is_chain(fence) { u32(2) } else { u32(0) }
	}
}
@[export: 'vinix_linuxkpi_fct_refs']
pub fn refs(storage voidptr) u32 { return C.fct_refcount(storage) }
@[export: 'vinix_linuxkpi_fct_value']
pub fn value(storage voidptr, kind u32) u64 {
	unsafe { fence := &C.dma_fence(storage)
		if kind == 0 { return C.__atomic_load_n(&fence.flags, 2) }
		if kind == 1 { return fence.context }
		if kind == 2 { return fence.seqno }
		return (&C.dma_fence_chain(storage)).prev_seqno
	}
}
@[export: 'vinix_linuxkpi_fct_pending']
pub fn pending(storage voidptr) i32 { return C.fct_pending(storage) }
