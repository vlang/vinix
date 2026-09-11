@[manualfree]
module memory

import lib

// Boot-time tests of the actual allocator, enabled with -d heap_selftest.
// Run before SMP startup; free-page snapshots assume no concurrent clients.
fn heap_test_require(ok bool) {
	if !ok {
		lib.kpanic(unsafe { nil }, c'Heap self-test failed')
	}
}

fn heap_test_bytes(ptr voidptr, size u64, value u8) {
	unsafe {
		bytes := &u8(ptr)
		for i := u64(0); i < size; i++ {
			heap_test_require(bytes[i] == value)
		}
	}
}

fn heap_selftest() {
	heap_trim()
	baseline := free_bytes()
	for mut slab in slabs {
		capacity := (page_size - slab_data_offset()) / slab.ent_size
		count := capacity * 2 + 1
		heap_test_require(count <= 512)
		mut objects := [512]voidptr{}
		for i := u64(0); i < count; i++ {
			ptr := slab.alloc()
			heap_test_require(ptr != unsafe { nil } && u64(ptr) % slab_alignment == 0)
			for j := u64(0); j < i; j++ {
				heap_test_require(objects[int(j)] != ptr)
			}
			heap_test_bytes(ptr, slab.ent_size, 0)
			unsafe { C.memset(ptr, int(i % 251 + 1), slab.ent_size) }
			objects[int(i)] = ptr
		}
		for i := u64(0); i < count; i += 2 {
			slab.sfree(objects[int(i)])
		}
		for i := u64(1); i < count; i += 2 {
			heap_test_bytes(objects[int(i)], slab.ent_size, u8(i % 251 + 1))
			slab.sfree(objects[int(i)])
		}
		// All but one empty page must have been returned automatically.
		heap_test_require(free_bytes() == baseline - page_size)
		heap_test_require(heap_trim() == page_size)
		heap_test_require(free_bytes() == baseline)
	}

	// Every slab boundary, including zero and the transition to big_alloc.
	for mut slab in slabs {
		for delta := u64(0); delta < 3; delta++ {
			size := slab.ent_size - 1 + delta
			ptr := malloc(size)
			heap_test_require(ptr != unsafe { nil } && u64(ptr) % slab_alignment == 0)
			heap_test_bytes(ptr, size, 0)
			free(ptr)
		}
	}
	zero := malloc(0)
	heap_test_require(zero != unsafe { nil })
	free(zero)
	free(unsafe { nil })

	old := malloc(17)
	unsafe { C.memset(old, 0x5a, 17) }
	grown := realloc(old, 65)
	heap_test_require(grown != unsafe { nil })
	heap_test_bytes(grown, 17, 0x5a)
	heap_test_require(realloc(grown, u64(-1)) == unsafe { nil })
	heap_test_bytes(grown, 17, 0x5a)
	free(grown)

	big := malloc(page_size + 1)
	unsafe { C.memset(big, 0x6b, page_size + 1) }
	bigger := realloc(big, 2 * page_size + 1)
	heap_test_require(bigger != unsafe { nil })
	heap_test_bytes(bigger, page_size + 1, 0x6b)
	heap_test_require(realloc(bigger, u64(-1)) == unsafe { nil })
	heap_test_bytes(bigger, page_size + 1, 0x6b)
	free(bigger)

	cleared := calloc(7, 13)
	heap_test_require(cleared != unsafe { nil })
	heap_test_bytes(cleared, 91, 0)
	free(cleared)
	heap_test_require(calloc(u64(1) << 63, 2) == unsafe { nil })
	heap_test_require(malloc(u64(-1)) == unsafe { nil })
	heap_trim()
	heap_test_require(free_bytes() == baseline)
	C.printf(c'heap: self-test passed\n')
}
