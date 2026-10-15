// SPDX-License-Identifier: GPL-2.0-or-later
// Independent observations, actual V page allocator and RCU implementations.
@[translated]
module freefixture

#include "contract.h"

fn C.vkr_kmalloc(usize, u32) voidptr
fn C.vkr_page_allocation_size(voidptr) usize
fn C.vkr_kvfree(voidptr)
fn C.vkr_kvfree_call_rcu(voidptr, voidptr)
fn C.memcpy(voidptr,voidptr,usize) voidptr
// V passes a plain address; the included genuine C declaration preserves and
// statically checks the original const-qualified public signature.
fn C.kvfree(voidptr)
fn C.kvfree_call_rcu(&C.callback_head, voidptr)
struct C.frh_embedded { prefix u64, head C.callback_head, payload u64 }
fn C.kfree_rcu(&C.frh_embedded,voidptr)
fn C.kvfree_rcu(&C.frh_embedded,voidptr)
fn C.kvfree_rcu_mightsleep(voidptr)
struct C.kmem_cache {}
fn C.kmem_cache_create(&char,u32,u32,u32,fn(voidptr)) &C.kmem_cache
fn C.kmem_cache_alloc(&C.kmem_cache,u32) voidptr
fn C.kmem_cache_free(&C.kmem_cache,voidptr)
fn C.kmem_cache_destroy(&C.kmem_cache)
fn C.frh_bad_callback(usize) fn(&C.callback_head)
@[c_extern] __global C.compatcore__vkr_rcu_enqueued u64

struct FreeWaiter {
mut:
	thread C.pthread_t
	base voidptr
	entered u32
	done u32
	parks u32
}
struct Ordinary {
mut:
	head C.callback_head
	ledger &u32 = unsafe { nil }
	remaining u32
	free_self bool
}

@[cinit]
__global (
	page_guard u32
	page_live u32
	page_calls u32
	page_frees u32
	page_fail u32
	page_block_once u32
	page_free_entered u32
	page_free_release u32 = 1
	page_bases [8192]voidptr
	page_counts [8192]usize
	page_slots u32
	last_free_base voidptr
	expect_invalid_head voidptr
	expect_invalid_bytes [16]u8
	expect_invalid_page_frees u32
	expect_invalid_ordinal u64
	fatal_watch bool
	mixed_calls u32
)

fn page_lock() { unsafe { for C.rcuh_exchange32(&page_guard, 1) != 0 { C.sched_yield() } } }
fn page_unlock() { unsafe { C.rcuh_store32(&page_guard, 0) } }
@[export:'vinix_linuxkpi_page_size'] pub fn page_size() usize { return 4096 }
@[export:'vinix_linuxkpi_alloc_pages'] pub fn page_allocate(pages usize, reclaim bool) voidptr {
	unsafe {
		check(pages != 0 && (!reclaim || may_sleep()), @LINE)
		C.rcuh_add32(&page_calls, 1)
		if C.rcuh_load32(&page_fail) != 0 { return nil }
		mut base := voidptr(nil)
		check(C.posix_memalign(&base, 4096, pages * 4096) == 0 && base != nil, @LINE)
		// Poison unused cache-slot padding so owner rejection cannot rely on
		// zero-filled host allocations masquerading as real page metadata.
		C.memset(base, 0xa5, pages * 4096)
		page_lock()
		mut index := u32(0)
		for index < page_slots && page_bases[index] != nil { index++ }
		check(index < 8192, @LINE)
		if index == page_slots { page_slots++ }
		page_bases[index] = base; page_counts[index] = pages
		C.rcuh_add32(&page_live, u32(pages)); page_unlock()
		return base
	}
}
@[export:'vinix_linuxkpi_free_pages'] pub fn page_free(base voidptr, pages usize) {
	unsafe {
		if C.rcuh_exchange32(&page_block_once,0) != 0 {
			C.rcuh_store32(&page_free_entered,1)
			for C.rcuh_load32(&page_free_release) == 0 { C.sched_yield() }
		}
		page_lock(); mut index := u32(0)
		for index < page_slots && page_bases[index] != base { index++ }
		check(index < page_slots && page_bases[index] == base && page_counts[index] == pages, @LINE)
		page_bases[index] = nil; page_counts[index] = 0
		last_free_base = base
		C.rcuh_add32(&page_live, u32(0) - u32(pages)); C.rcuh_add32(&page_frees, 1)
		page_unlock(); C.free(base)
	}
}
@[export:'vkp_cache_ctor_warning'] pub fn cache_warning(value bool) { check(!value, @LINE) }

@[export:'vinix_linuxkpi_bug'; noreturn] pub fn bug(reason C.rcuh_const_charp, line i32) {
	unsafe {
		if fatal_watch {
			// Original head fields must stay untouched when validation fails.
			mut observed := [16]u8{}
			if expect_invalid_head != nil {
				C.memcpy(&observed[0],expect_invalid_head,16)
				for index := 0; index < 16; index++ { check(observed[index] == expect_invalid_bytes[index],@LINE) }
			}
			check(C.rcuh_load32(&page_frees) == expect_invalid_page_frees, @LINE)
			check(C.rcuh_load64(&C.compatcore__vkr_rcu_enqueued) == expect_invalid_ordinal,@LINE)
			C.fprintf(C.stderr, c'FREE validation preserved original head and allocation\n')
		}
		C.fprintf(C.stderr, c'RCU invariant: %s:%d\n', reason, line)
		C.abort()
	}
}

fn live() u32 { return unsafe { C.rcuh_load32(&page_live) } }
fn alloc(bytes usize) voidptr {
	base := C.vkr_kmalloc(bytes, 3264)
	check(usize(base) > 16 && C.vkr_page_allocation_size(base) == bytes, @LINE)
	return base
}
fn embedded_head(base voidptr, offset usize) &C.callback_head { return unsafe { &C.callback_head(usize(base) + offset) } }
fn ordinary_callback(storage &C.callback_head) {
	unsafe {
		node := &Ordinary(storage); ledger := node.ledger; remaining := node.remaining; owns := node.free_self
		check(!may_sleep() && pins() > 0, @LINE)
		C.rcuh_add32(ledger, 1)
		if remaining > 1 { node.remaining = remaining - 1; C.call_rcu(storage, ordinary_callback) }
		else if owns { C.kvfree(node) }
		// Never access storage after a requeue or actual free.
	}
}
fn test_immediate() {
	unsafe {
		before := live(); frees := C.rcuh_load32(&page_frees)
		for value in [usize(0), usize(1), usize(16)]! { C.kvfree(voidptr(value)); C.vkr_kvfree(voidptr(value)) }
		check(live() == before && C.rcuh_load32(&page_frees) == frees, @LINE)
		for size in [usize(1),usize(16),usize(17),usize(4096),usize(4104),usize(16384)]! {
			base := alloc(size); check(live() > before, @LINE)
			C.kvfree(base); check(live() == before, @LINE)
		}
		check(C.rcuh_load32(&page_frees) == frees + 6, @LINE)
	}
}
fn test_offset_scope(offset usize, kind u32) {
	unsafe {
		baseline := live()
		base := alloc(offset + 16); route(1)
		if kind == 0 || kind == 2 { preempt_disable() }
		mut saved := flags()
		if kind == 1 || kind == 2 { saved = irq_save() }
		if kind == 3 { lock_context(); context().depth++; cpu_depth[1]++; unlock_context() }
		entry_pins := pins(); entry_flags := flags(); entry_depth := depth()
		before := C.rcuh_load32(&page_calls); frees := C.rcuh_load32(&page_frees)
		C.rcuh_store32(&page_fail,1)
		C.kvfree_call_rcu(embedded_head(base,offset),base)
		check(C.rcuh_load32(&page_calls) == before && C.rcuh_load32(&page_fail) == 1, @LINE)
		check(C.rcuh_load32(&page_frees) == frees && pins() == entry_pins && flags() == entry_flags && depth() == entry_depth, @LINE)
		attempt := attempts(1); await_attempt(1,attempt)
		mut encoded := usize(0); C.memcpy(&encoded,voidptr(usize(embedded_head(base,offset))+8),sizeof(usize))
		check(C.rcuh_load32(&page_frees) == frees && encoded == offset, @LINE)
		if kind == 3 { lock_context(); context().depth--; cpu_depth[1]--; unlock_context() }
		if kind == 1 || kind == 2 { irq_restore(saved) }
		if kind == 0 || kind == 2 { preempt_enable() }
		route(0); C.rcuh_store32(&page_fail,0); C.rcu_barrier()
		check(live() == baseline && C.rcuh_load32(&page_frees) == frees + 1, @LINE)
	}
}
fn test_offsets_atomic() {
	unsafe {
		for offset in [usize(0), usize(8), usize(4088)]! {
			for kind := u32(0); kind < 4; kind++ { test_offset_scope(offset,kind) }
		}
	}
}
fn test_mixed() {
	unsafe {
		baseline := live(); mixed_calls = 0
		route(1); preempt_disable()
		mut stack_node := Ordinary{ledger: &mixed_calls, remaining: 5}
		C.call_rcu(&stack_node.head,ordinary_callback)
		for index := 0; index < 200; index++ {
			if index % 3 == 0 {
				node := &Ordinary(alloc(sizeof(Ordinary))); node.ledger = &mixed_calls; node.remaining = 1; node.free_self = true
				C.call_rcu(&node.head, ordinary_callback)
			} else { base := alloc(64); C.kvfree_call_rcu(embedded_head(base,8),base) }
		}
		check(C.rcuh_load32(&mixed_calls) == 0, @LINE); preempt_enable(); route(0)
		await32(&mixed_calls,72); C.rcu_barrier(); check(mixed_calls == 72 && live() == baseline, @LINE)
	}
}
fn test_original_macros() {
	unsafe {
		baseline := live(); route(1); preempt_disable()
		first := &C.frh_embedded(alloc(sizeof(C.frh_embedded)))
		second := &C.frh_embedded(alloc(sizeof(C.frh_embedded)))
		C.kfree_rcu(first,C.head); C.kvfree_rcu(second,C.head)
		preempt_enable(); route(0); C.rcu_barrier(); check(live() == baseline,@LINE)
	}
}
fn headless_actor(argument voidptr) voidptr {
	unsafe {
		waiter := &FreeWaiter(argument); context()
		C.rcuh_store32(&waiter.entered,1)
		C.kvfree_rcu_mightsleep(waiter.base)
		check(may_sleep(),@LINE); C.rcuh_store32(&waiter.done,1); C.pthread_exit(nil)
		return nil
	}
}
fn test_headless() {
	unsafe {
		baseline := live(); base := alloc(80); before := C.rcuh_load32(&page_calls); frees := C.rcuh_load32(&page_frees)
		route(1); preempt_disable(); mut waiter := FreeWaiter{base:base}
		C.rcuh_store32(&page_fail,1)
		check(C.pthread_create(&waiter.thread,nil,headless_actor,&waiter) == 0,@LINE)
		await32(&waiter.entered,1); attempt := attempts(1); await_attempt(1,attempt)
		// A callback barrier is not a join for a synchronous headless caller.
		mut empty := Waiter{}; start_waiter(&empty,.barrier,0); join_waiter(&empty)
		check(C.rcuh_load32(&waiter.done) == 0 && C.rcuh_load32(&page_frees) == frees && C.rcuh_load32(&page_calls) == before,@LINE)
		preempt_enable(); route(0)
		check(C.pthread_join(waiter.thread,nil) == 0 && C.rcuh_load32(&waiter.done) == 1,@LINE)
		C.rcuh_store32(&page_fail,0)
		check(live() == baseline && C.rcuh_load32(&page_frees) == frees+1 && C.rcuh_load32(&page_calls) == before,@LINE)
	}
}
fn test_barrier_snapshot() {
	unsafe {
		baseline := live(); first := alloc(64)
		frees := C.rcuh_load32(&page_frees)
		C.rcuh_store32(&page_free_release,0); C.rcuh_store32(&page_block_once,1)
		C.kvfree_call_rcu(embedded_head(first,8),first); await32(&page_free_entered,1)
		mut earlier := Waiter{}; start_waiter(&earlier,.barrier,0); await32(&earlier.parks,1)
		check(C.rcuh_load32(&page_frees) == frees && C.rcuh_load32(&earlier.done) == 0,@LINE)
		second := alloc(64)
		route(1); preempt_disable(); C.kvfree_call_rcu(embedded_head(second,0),second)
		C.rcuh_store32(&page_free_release,1); join_waiter(&earlier)
		// This backend's documented barrier snapshot ends after first's free,
		// although a later enqueue is still waiting on our genuine read scope.
		check(C.rcuh_load32(&page_frees) == frees+1 && live() > baseline,@LINE)
		preempt_enable(); route(0); C.rcu_barrier()
		check(C.rcuh_load32(&page_frees) == frees+2 && live() == baseline,@LINE)
	}
}
fn fatal_watch_head(storage voidptr) {
	unsafe {
		if storage != nil { for index := 0; index < 16; index++ { expect_invalid_bytes[index] = u8(0x80+index) }; C.memcpy(storage,&expect_invalid_bytes[0],16) }
		expect_invalid_head = storage; expect_invalid_page_frees = C.rcuh_load32(&page_frees)
		expect_invalid_ordinal = C.rcuh_load64(&C.compatcore__vkr_rcu_enqueued); fatal_watch = true
	}
}
fn invalid_case(mode i32) {
	unsafe {
		mut base := alloc(8192); mut storage := voidptr(embedded_head(base,8))
		match mode {
			10 { storage = embedded_head(base,4096) }
			11 { storage = embedded_head(base,1) }
			12 { base = alloc(24); storage = embedded_head(base,16) }
			13 { storage = embedded_head(base,0); base_before := voidptr(usize(base)+8); fatal_watch_head(storage); C.kvfree_call_rcu(&C.callback_head(storage),base_before) }
			14 { fatal_watch_head(nil); preempt_disable(); C.kvfree_call_rcu(nil,base) }
			15 { fatal_watch_head(nil); irq_save(); C.kvfree_call_rcu(nil,base) }
			16 { fatal_watch_head(nil); context().depth = 1; C.kvfree_call_rcu(nil,base) }
			17 { fatal_watch_head(storage); C.call_rcu(&C.callback_head(storage),C.frh_bad_callback(0)) }
			18 { fatal_watch_head(storage); C.call_rcu(&C.callback_head(storage),C.frh_bad_callback(8)) }
			19 { fatal_watch_head(storage); C.call_rcu(&C.callback_head(storage),C.frh_bad_callback(4095)) }
			20,21,22 {
				cache := C.kmem_cache_create(c'deferred-free-host',64,0,0,unsafe{nil}); check(cache != nil,@LINE)
				object := C.kmem_cache_alloc(cache,3264); check(object != nil,@LINE)
				fatal_watch_head(object)
				if mode == 20 { C.kvfree(object) }
				if mode == 21 { C.kvfree_call_rcu(&C.callback_head(object),object) }
				if mode == 22 { C.kvfree_call_rcu(nil,object) }
			}
			23 {
				mut foreign := voidptr(nil); check(C.posix_memalign(&foreign,16,96) == 0,@LINE); C.memset(foreign,0,96)
				owner := voidptr(usize(foreign)+32); fatal_watch_head(owner); C.kvfree_call_rcu(&C.callback_head(owner),owner)
			}
			24 { byte := &u8(usize(base)-1); *byte = *byte ^ 128 }
			25 { base = voidptr(usize(base)+1) }
			26 { base = alloc(8); storage = embedded_head(base,0) }
			27 { fatal_watch_head(storage); C.kvfree_call_rcu(&C.callback_head(storage),voidptr(16)) }
			else {}
		}
		fatal_watch_head(storage); C.kvfree_call_rcu(&C.callback_head(storage),base)
		check(false,@LINE)
	}
}
@[export:'main'] pub fn main(argc i32,argv &&char) i32 {
	unsafe {
		check(argc == 2 && C.pthread_key_create(&context_key,context_destructor) == 0,@LINE)
		mode := C.atoi(argv[1]); configured_cpus = 4; context().constructor = true
		check(C.vkm_cpu_masks_bootstrap(4) == 0,@LINE); C.rcuh_store32(&smp_transport_ready,1)
		check(C.vkr_rcu_bootstrap(4) == 0 && C.vkr_rcu_ready(),@LINE)
		if mode >= 10 { invalid_case(mode) }
		test_immediate(); test_offsets_atomic(); test_mixed(); test_original_macros(); test_headless(); test_barrier_snapshot()
		C.rcu_barrier(); C.vkr_rcu_shutdown_for_test()
		check(!C.vkr_rcu_ready() && live() == 0 && C.rcuh_load32(&worker_live) == 0 && C.rcuh_load32(&context_live) == 1,@LINE)
		owner := context(); check(C.pthread_setspecific(context_key,nil) == 0,@LINE); context_destructor(owner)
		check(C.rcuh_load32(&context_live) == 0 && C.pthread_key_delete(context_key) == 0,@LINE)
		C.printf(c'PASS: actual page allocator, immediate and mixed deferred frees, original zero/nonzero heads, atomic no-allocation submission, headless join; %u assertions\n',C.rcuh_load32(&assertions))
		return 0
	}
}
