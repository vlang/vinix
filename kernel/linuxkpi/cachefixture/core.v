// SPDX-License-Identifier: GPL-2.0-only
// Independent native fixture; original assertions and workload are retained.
@[translated]
module cachefixture

#include "linuxkpi_cache_fixture_v_contract.h"

struct C.kmem_cache {}

struct C.completion {}

@[typedef]
struct C.pthread_t {}

type CacheCtor = fn (voidptr)
type CacheThread = fn (voidptr) voidptr

fn C.kmem_cache_create(&char, usize, usize, usize, CacheCtor) &C.kmem_cache
fn C.kmem_cache_destroy(&C.kmem_cache)
fn C.kmem_cache_zalloc(&C.kmem_cache, u32) voidptr
fn C.kmem_cache_alloc(&C.kmem_cache, u32) voidptr
fn C.kmem_cache_free(&C.kmem_cache, voidptr)
fn C.kmem_cache_size(&C.kmem_cache) usize
fn C.kmem_cache_shrink(&C.kmem_cache) i32
fn C.vinix_linuxkpi_test_alloc_oom(i32)
fn C.vinix_linuxkpi_page_size() usize
fn C.vinix_linuxkpi_alloc_gfp_pages(usize, u32) voidptr
fn C.vinix_linuxkpi_free_pages(voidptr, usize)
fn C.vinix_linuxkpi_irq_save() usize
fn C.vinix_linuxkpi_irq_restore(usize)
fn C.vinix_linuxkpi_irq_flags() usize
fn C.vinix_linuxkpi_preempt_count() u32
fn C.vinix_linuxkpi_worker_bind(u32) i32
fn C.vinix_linuxkpi_cpu_id() u32
fn C.vinix_linuxkpi_percpu_count() u32
fn C.vinix_linuxkpi_may_sleep() bool
fn C.memchr_inv(voidptr, i32, usize) voidptr
fn C.memset(voidptr, i32, usize) voidptr
fn C.__atomic_add_fetch(&u32, u32, i32) u32
fn C.__atomic_load_n(&u32, i32) u32
fn C.__atomic_store_n(&u32, u32, i32)
fn C.init_completion(&C.completion)
fn C.complete(&C.completion)
fn C.complete_all(&C.completion)
fn C.wait_for_completion(&C.completion)
fn C.wait_for_completion_timeout(&C.completion, usize) usize
fn C.cond_resched() i32
fn C.pthread_create(voidptr, voidptr, CacheThread, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.pthread_exit(voidptr)
fn C.vinix_linuxkpi_fixture_cache_ctor(voidptr)
fn C.vinix_linuxkpi_fixture_cache_thread(voidptr) voidptr

@[c_extern]
__global C.GFP_KERNEL u32

@[c_extern]
__global C.GFP_ATOMIC u32

@[c_extern]
__global C.GFP_NOWAIT u32

@[c_extern]
__global C.__GFP_DMA32 u32

@[c_extern]
__global C.__GFP_NOFAIL u32

@[c_extern]
__global C.__GFP_ACCOUNT u32

@[c_extern]
__global C.SLAB_TYPESAFE_BY_RCU usize

@[c_extern]
__global C.SLAB_RECLAIM_ACCOUNT usize

@[c_extern]
__global C.SLAB_CACHE_DMA usize

@[c_extern]
__global C.SLAB_CACHE_DMA32 usize

@[c_extern]
__global C.SLAB_PANIC usize

@[c_extern]
__global C.SLAB_POISON usize

@[c_extern]
__global C.SLAB_HWCACHE_ALIGN usize

__global cache_ctor_calls u32

struct CacheObject {
mut:
	magic      u64
	generation u32
	payload    [85]u8
}

struct CacheWorker {
mut:
	cache       &C.kmem_cache = unsafe { nil }
	thread      C.pthread_t
	entered     C.completion
	go          C.completion
	held        C.completion
	release     C.completion
	done        C.completion
	cpu         u32
	cancel      u32
	result      i32
	initialized bool
	started     bool
}

@[export: 'vinix_linuxkpi_fixture_cache_ctor']
pub fn cache_ctor(object voidptr) {
	unsafe {
		mut value := &CacheObject(object)
		value.magic = 0x6b70692d63616368
		value.generation = 0
		C.memset(&value.payload[0], 0x3c, sizeof(value.payload))
		C.__atomic_add_fetch(&cache_ctor_calls, 1, 0)
	}
}

fn cache_basic() i32 {
	unsafe {
		mut result := i32(0)
		C.vinix_linuxkpi_test_alloc_oom(0)
		if C.vinix_linuxkpi_alloc_gfp_pages(0, C.GFP_KERNEL) != nil { result = -5 }
		if C.vinix_linuxkpi_alloc_gfp_pages(~usize(0) / C.vinix_linuxkpi_page_size() + 1, C.GFP_KERNEL) != nil {
			result = -5
		}
		unsupported := C.vinix_linuxkpi_alloc_gfp_pages(1, C.GFP_KERNEL | C.__GFP_DMA32)
		if unsupported != nil {
			C.vinix_linuxkpi_free_pages(unsupported, 1)
			result = -5
		}
		probe := C.vinix_linuxkpi_alloc_gfp_pages(1, C.GFP_KERNEL)
		C.vinix_linuxkpi_test_alloc_oom(-1)
		if probe != nil {
			C.vinix_linuxkpi_free_pages(probe, 1)
			result = -5
		}
		rejected := [C.SLAB_TYPESAFE_BY_RCU, C.SLAB_RECLAIM_ACCOUNT, C.SLAB_CACHE_DMA,
			C.SLAB_CACHE_DMA32, C.SLAB_PANIC, C.SLAB_POISON]!
		for flag in rejected {
			unexpected := C.kmem_cache_create(c'native-rejected', 97, 0, flag, CacheCtor(nil))
			if unexpected != nil {
				C.kmem_cache_destroy(unexpected)
				result = -5
			}
		}
		mut irq := C.vinix_linuxkpi_irq_save()
		unexpected := C.kmem_cache_create(c'native-atomic-create', 97, 0, 0, CacheCtor(nil))
		C.vinix_linuxkpi_irq_restore(irq)
		if unexpected != nil {
			C.kmem_cache_destroy(unexpected)
			result = -5
		}
		for stage in 0 .. 2 {
			C.vinix_linuxkpi_test_alloc_oom(i32(stage))
			failed := C.kmem_cache_create(c'native-create-rollback', 97, 0, 0, CacheCtor(nil))
			C.vinix_linuxkpi_test_alloc_oom(-1)
			if failed != nil {
				C.kmem_cache_destroy(failed)
				result = -5
			}
		}
		alignment := [u32(0), 64, 256, 8192]!
		for i in 0 .. alignment.len {
			cache := C.kmem_cache_create(c'native-alignment', 97, alignment[i], C.SLAB_HWCACHE_ALIGN, CacheCtor(nil))
			if cache == nil { return -12 }
			mut refill_irq := usize(0)
			if i == 0 { refill_irq = C.vinix_linuxkpi_irq_save() }
			object := C.kmem_cache_zalloc(cache, C.GFP_KERNEL)
			if i == 0 && ((C.vinix_linuxkpi_irq_flags() & (usize(1) << 9)) != 0 || C.vinix_linuxkpi_preempt_count() != 0) {
				result = -5
			}
			if i == 0 { C.vinix_linuxkpi_irq_restore(refill_irq) }
			if object == nil {
				C.kmem_cache_destroy(cache)
				return -12
			}
			align := if alignment[i] > 64 { alignment[i] } else { u32(64) }
			if C.kmem_cache_size(cache) != 97 || (usize(object) & (align - 1)) != 0 || C.memchr_inv(object, 0, 97) != nil {
				result = -5
			}
			C.memset(object, 0x79, 97)
			if C.kmem_cache_shrink(cache) != 1 || C.memchr_inv(object, 0x79, 97) != nil {
				result = -5
			}
			C.kmem_cache_free(cache, object)
			C.kmem_cache_free(cache, nil)
			if C.kmem_cache_shrink(cache) != 0 { result = -5 }
			C.kmem_cache_destroy(cache)
		}
		mut objects := [128]&CacheObject{}
		mut count := u32(0)
		cache := C.kmem_cache_create(c'native-constructor', sizeof(CacheObject), 0, C.SLAB_HWCACHE_ALIGN, C.vinix_linuxkpi_fixture_cache_ctor)
		if cache == nil { return -12 }
		C.vinix_linuxkpi_test_alloc_oom(0)
		mut failed := &CacheObject(C.kmem_cache_alloc(cache, C.GFP_KERNEL))
		C.vinix_linuxkpi_test_alloc_oom(-1)
		if failed != nil {
			C.kmem_cache_free(cache, failed)
			result = -5
		}
		if C.kmem_cache_shrink(cache) != 0 { result = -5 }
		objects[0] = &CacheObject(C.kmem_cache_alloc(cache, C.GFP_KERNEL))
		if objects[0] == nil {
			C.kmem_cache_destroy(cache)
			return -12
		}
		count = 1
		constructors := C.__atomic_load_n(&cache_ctor_calls, 2)
		C.vinix_linuxkpi_test_alloc_oom(0)
		for count < 128 {
			objects[count] = &CacheObject(C.kmem_cache_alloc(cache, C.GFP_ATOMIC))
			if objects[count] == nil { break }
			count++
		}
		if count <= 1 || count == 128 || C.__atomic_load_n(&cache_ctor_calls, 2) != constructors {
			result = -5
		}
		for i := u32(0); i < count; i++ {
			if objects[i].magic != 0x6b70692d63616368 || objects[i].generation != 0 { result = -5 }
			objects[i].generation = i + 17
			C.memset(&objects[i].payload[0], 0xb7, sizeof(objects[i].payload))
			for j := u32(0); j < i; j++ {
				if usize(objects[j]) == usize(objects[i]) { result = -5 }
			}
		}
		only_free := objects[0]
		C.kmem_cache_free(cache, only_free)
		objects[0] = nil
		C.vinix_linuxkpi_test_alloc_oom(0)
		rejected_gfp := [C.GFP_KERNEL | C.__GFP_DMA32, C.GFP_KERNEL | C.__GFP_NOFAIL,
			C.GFP_KERNEL | C.__GFP_ACCOUNT]!
		for gfp in rejected_gfp {
			bad := C.kmem_cache_alloc(cache, gfp)
			if bad != nil {
				C.kmem_cache_free(cache, bad)
				result = -5
			}
		}
		irq = C.vinix_linuxkpi_irq_save()
		objects[0] = &CacheObject(C.kmem_cache_alloc(cache, C.GFP_KERNEL))
		if (C.vinix_linuxkpi_irq_flags() & (usize(1) << 9)) != 0 || C.vinix_linuxkpi_preempt_count() != 0 {
			result = -5
		}
		C.vinix_linuxkpi_irq_restore(irq)
		if usize(objects[0]) != usize(only_free) || objects[0] == nil || objects[0].magic != 0x6b70692d63616368 || objects[0].generation != 17 || C.memchr_inv(&objects[0].payload[0], 0xb7, sizeof(objects[0].payload)) != nil {
			result = -5
		}
		if C.kmem_cache_shrink(cache) != 1 { result = -5 }
		for i := u32(0); i < count; i++ { C.kmem_cache_free(cache, objects[i]) }
		if C.kmem_cache_shrink(cache) != 0 { result = -5 }
		C.vinix_linuxkpi_test_alloc_oom(0)
		failed = &CacheObject(C.kmem_cache_alloc(cache, C.GFP_NOWAIT))
		if failed != nil {
			C.kmem_cache_free(cache, failed)
			result = -5
		}
		C.vinix_linuxkpi_test_alloc_oom(-1)
		zeroed := C.kmem_cache_zalloc(cache, C.GFP_KERNEL)
		if zeroed == nil || C.memchr_inv(zeroed, 0, sizeof(CacheObject)) != nil { result = -5 }
		C.kmem_cache_free(cache, zeroed)
		C.kmem_cache_destroy(cache)
		return result
	}
}

@[export: 'vinix_linuxkpi_fixture_cache_thread']
pub fn cache_thread(argument voidptr) voidptr {
	unsafe {
		mut test := &CacheWorker(argument)
		test.result = C.vinix_linuxkpi_worker_bind(test.cpu)
		C.complete(&test.entered)
		C.wait_for_completion(&test.go)
		for repeat := u32(0); test.result == 0 && repeat < 64 && C.__atomic_load_n(&test.cancel, 2) == 0; repeat++ {
			mut objects := [16]&CacheObject{}
			mut count := u32(0)
			for count < 16 {
				mut irq := usize(0)
				if (repeat & 1) != 0 { irq = C.vinix_linuxkpi_irq_save() }
				objects[count] = &CacheObject(C.kmem_cache_alloc(test.cache, if (repeat & 1) != 0 {
					C.GFP_ATOMIC
				} else {
					C.GFP_KERNEL
				}))
				if ((C.vinix_linuxkpi_irq_flags() & (usize(1) << 9)) != 0) != ((repeat & 1) == 0) || C.vinix_linuxkpi_preempt_count() != 0 {
					test.result = -5
				}
				if (repeat & 1) != 0 { C.vinix_linuxkpi_irq_restore(irq) }
				if objects[count] == nil {
					test.result = -12
					break
				}
				if objects[count].magic != 0x6b70692d63616368 { test.result = -5 }
				objects[count].generation = test.cpu + 1
				C.memset(&objects[count].payload[0], i32(test.cpu), sizeof(objects[count].payload))
				count++
			}
			if repeat == 0 {
				C.complete(&test.held)
				C.wait_for_completion(&test.release)
			}
			for i := u32(0); i < count; i++ {
				if objects[i].generation != test.cpu + 1 || C.memchr_inv(&objects[i].payload[0], i32(test.cpu), sizeof(objects[i].payload)) != nil {
					test.result = -5
				}
				C.kmem_cache_free(test.cache, objects[i])
			}
			C.cond_resched()
			if C.vinix_linuxkpi_cpu_id() != test.cpu || !C.vinix_linuxkpi_may_sleep() {
				test.result = -5
			}
		}
		C.complete(&test.done)
		C.pthread_exit(nil)
		return nil
	}
}

// Controller records stay on its stack until every started pthread is joined.
// Cleanup opens every initialized gate, including partial startup failures.
fn cache_workers(cache &C.kmem_cache, tests &CacheWorker, cpus u32, result &i32) {
	unsafe {
		if cpus == 0 || cpus > 64 {
			*result = -95
			return
		}
		for i := u32(0); i < 4; i++ {
			mut test := &tests[i]
			test.cache = cache
			test.cpu = i % cpus
			C.init_completion(&test.entered)
			C.init_completion(&test.go)
			C.init_completion(&test.held)
			C.init_completion(&test.release)
			C.init_completion(&test.done)
			test.initialized = true
			if C.pthread_create(&test.thread, nil, C.vinix_linuxkpi_fixture_cache_thread, test) != 0 {
				*result = -12
				return
			}
			test.started = true
			if C.wait_for_completion_timeout(&test.entered, 1000) == 0 {
				*result = -5
				return
			}
		}
		for i in 0 .. 4 { C.complete(&tests[i].go) }
		for i in 0 .. 4 {
			if C.wait_for_completion_timeout(&tests[i].held, 1000) == 0 {
				*result = -5
				return
			}
		}
		if C.kmem_cache_shrink(cache) != 1 { *result = -5 }
		for i in 0 .. 4 { C.complete(&tests[i].release) }
		for i in 0 .. 128 {
			left := C.kmem_cache_shrink(cache)
			if left != 0 && left != 1 { *result = -5 }
			C.cond_resched()
		}
		for i in 0 .. 4 {
			if C.wait_for_completion_timeout(&tests[i].done, 1000) == 0 {
				*result = -5
				return
			}
		}
	}
}

@[export: 'vinix_linuxkpi_cache_native_selftest']
pub fn cache_selftest() i32 {
	unsafe {
		mut result := cache_basic()
		cache := C.kmem_cache_create(c'native-concurrent', sizeof(CacheObject), 0, C.SLAB_HWCACHE_ALIGN, C.vinix_linuxkpi_fixture_cache_ctor)
		if cache == nil { return -12 }
		mut tests := [4]CacheWorker{}
		cpus := C.vinix_linuxkpi_percpu_count()
		cache_workers(cache, &tests[0], cpus, &result)
		for i in 0 .. 4 {
			C.__atomic_store_n(&tests[i].cancel, 1, 3)
			if tests[i].initialized {
				C.complete_all(&tests[i].go)
				C.complete_all(&tests[i].release)
			}
		}
		for i in 0 .. 4 {
			if tests[i].started && (C.pthread_join(tests[i].thread, nil) != 0 || tests[i].result != 0) {
				result = -5
			}
		}
		if C.kmem_cache_shrink(cache) != 0 { result = -5 }
		C.kmem_cache_destroy(cache)
		return result
	}
}
