@[manualfree]
module memory

import lib

// Boot-time tests of the actual allocator, enabled with -d heap_selftest.
// Run before SMP startup; free-page snapshots assume no concurrent clients.
// Two pages' worth of the smallest class and one more. On the stack it was 512,
// which an arm64 kernel's 16 KiB pages outgrow.
__global (
	heap_test_objects [2 * slab_max_capacity + 1]voidptr
)

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
		if slab.ent_size == 0 {
			continue
		}
		mut offset := slab_data_offset()
		$if xnu_zone ? {
			offset = lib.align_up(u64(sizeof(XnuHeapHeader)), 16)
		}
		capacity := (page_size - offset) / slab.ent_size
		count := capacity * 2 + 1
		heap_test_require(count <= u64(heap_test_objects.len))
		for i := u64(0); i < count; i++ {
			// malloc_packed() reaches every class; malloc() gives an arm64
			// kernel's medium ones, over 2 KiB, whole pages instead.
			ptr := malloc_packed(slab.ent_size)
			heap_test_require(ptr != unsafe { nil } && u64(ptr) % slab_alignment == 0)
			for j := u64(0); j < i; j++ {
				heap_test_require(heap_test_objects[int(j)] != ptr)
			}
			heap_test_bytes(ptr, slab.ent_size, 0)
			unsafe { C.memset(ptr, int(i % 251 + 1), slab.ent_size) }
			heap_test_objects[int(i)] = ptr
		}
		for i := u64(0); i < count; i += 2 {
			free(heap_test_objects[int(i)])
		}
		for i := u64(1); i < count; i += 2 {
			heap_test_bytes(heap_test_objects[int(i)], slab.ent_size, u8(i % 251 + 1))
			free(heap_test_objects[int(i)])
		}
		// All but one empty page must have been returned automatically.
		heap_test_require(free_bytes() == baseline - page_size)
		heap_test_require(heap_trim() == page_size)
		heap_test_require(free_bytes() == baseline)
	}

	// Every slab boundary, including zero and the transition to big_alloc.
	for mut slab in slabs {
		if slab.ent_size == 0 {
			continue
		}
		for delta := u64(0); delta < 3; delta++ {
			size := slab.ent_size - 1 + delta
			ptr := memory.malloc(size)
			heap_test_require(ptr != unsafe { nil } && u64(ptr) % slab_alignment == 0)
			heap_test_bytes(ptr, size, 0)
			free(ptr)
		}
	}
	zero := memory.malloc(0)
	heap_test_require(zero != unsafe { nil })
	free(zero)
	free(unsafe { nil })

	old := memory.malloc(17)
	unsafe { C.memset(old, 0x5a, 17) }
	grown := realloc(old, 65)
	heap_test_require(grown != unsafe { nil })
	heap_test_bytes(grown, 17, 0x5a)
	heap_test_require(realloc(grown, u64(-1)) == unsafe { nil })
	heap_test_bytes(grown, 17, 0x5a)
	free(grown)

	big := memory.malloc(page_size + 1)
	unsafe { C.memset(big, 0x6b, page_size + 1) }
	bigger := realloc(big, 2 * page_size + 1)
	heap_test_require(bigger != unsafe { nil })
	heap_test_bytes(bigger, page_size + 1, 0x6b)
	heap_test_require(realloc(bigger, u64(-1)) == unsafe { nil })
	heap_test_bytes(bigger, page_size + 1, 0x6b)
	free(bigger)

	// A write to a freed object is found when its slot is handed out again,
	// and the object's new owner still gets zeroes. The slot comes back once
	// the free slots ahead of it are taken.
	$if !xnu_zone ? {
		size := slabs[3].ent_size
		before := heap_written_after_free()
		mut freed := unsafe { &u64(memory.malloc(size)) }
		free(freed)
		unsafe {
			freed[1] = 0x5ca1ab1e
		}
		mut count := 0
		for count < heap_test_objects.len {
			ptr := memory.malloc(size)
			heap_test_objects[count] = ptr
			count++
			if ptr == voidptr(freed) {
				break
			}
		}
		heap_test_require(heap_test_objects[count - 1] == voidptr(freed))
		heap_test_bytes(freed, size, 0)
		heap_test_require(heap_written_after_free() == before + 1)
		for i := 0; i < count; i++ {
			free(heap_test_objects[i])
		}
		heap_trim()
		heap_test_require(heap_written_after_free() == before + 1)
	}

	cleared := calloc(7, 13)
	heap_test_require(cleared != unsafe { nil })
	heap_test_bytes(cleared, 91, 0)
	free(cleared)
	heap_test_require(calloc(u64(1) << 63, 2) == unsafe { nil })
	heap_test_require(memory.malloc(u64(-1)) == unsafe { nil })
	heap_trim()
	heap_test_require(free_bytes() == baseline)
	C.printf(c'heap: self-test passed\n')
}
