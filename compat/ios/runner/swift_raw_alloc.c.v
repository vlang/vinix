// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftRawAllocationFailure {}
fn (_ &SwiftRawAllocationFailure) msg() string { return 'iOS: invalid or failed Swift raw allocation' }
fn (_ &SwiftRawAllocationFailure) code() int { return 1 }
__global swift_raw_allocation_failure_value = SwiftRawAllocationFailure{}
fn swift_raw_allocation_failure() IError { return unsafe { &swift_raw_allocation_failure_value } }

// Swift raw allocations have no object header or ARC ownership. They share
// the POSIX allocator with libSystem malloc/posix_memalign/free; adding a
// private header would break that interoperability and pointer alignment.
fn swift_raw_allocate_checked(size u64, mask u64) !u64 {
	if size > 0x7fffffffffffffff
		|| (mask != u64(-1) && (mask >= 0x7fffffffffffffff || (mask + 1) & mask != 0)) {
		return swift_raw_allocation_failure()
	}
	count := if size == 0 { u64(1) } else { size }
	if mask <= 15 {
		pointer := u64(C.malloc(usize(count)))
		if pointer == 0 { return swift_raw_allocation_failure() }
		return pointer
	}
	// -1 requests Swift's default manual-allocation alignment (16 on ARM64).
	alignment := if mask == u64(-1) { u64(16) } else { mask + 1 }
	pointer := unsafe { &u64(C.__builtin_alloca(8)) }
	unsafe { *pointer = 0 }
	if C.posix_memalign(unsafe { voidptr(pointer) }, usize(alignment), usize(count)) != 0 {
		return swift_raw_allocation_failure()
	}
	return unsafe { *pointer }
}

fn swift_raw_allocate(size u64, mask u64) u64 {
	return swift_raw_allocate_checked(size, mask) or { panic(err) }
}

// Native slowDealloc ignores byte count. POSIX aligned allocations and malloc
// both use free, including the unknown-size/alignment (-1) pointer getters.
fn swift_raw_deallocate(pointer u64, _size u64, _mask u64) {
	C.free(unsafe { voidptr(pointer) })
}

// The four native pointer methods share one entry: raw pointer in x0, no
// element metadata access, destructor or x20 Self. The caller must first
// deinitialize any stored values, just as for the native Swift method.
fn swift_pointer_deallocate(pointer u64, _metadata u64) {
	swift_raw_deallocate(pointer, u64(-1), u64(-1))
}

fn swift_raw_alloc_symbol(symbol string) ?u64 {
	return match symbol {
		'_$sSw5countSivg', '_$sSW5countSivg', '_$sSw8endIndexSivg', '_$sSW8endIndexSivg' {
			u64(unsafe { voidptr(swift_raw_buffer_count) })
		}
		'_$sSw11baseAddressSvSgvg', '_$sSW11baseAddressSVSgvg' { u64(unsafe { voidptr(swift_raw_buffer_base) }) }
		'_$sSw10copyMemory4fromySW_tF' { u64(unsafe { voidptr(swift_raw_buffer_copy) }) }
		'_$sSv10copyMemory4from9byteCountySV_SitF' { u64(unsafe { voidptr(swift_raw_pointer_copy) }) }
		'_$sSp8allocate8capacitySpyxGSi_tFZ' { u64(unsafe { voidptr(swift_pointer_allocate) }) }
		'_swift_arrayDestroy' { u64(unsafe { voidptr(swift_array_destroy_elements) }) }
		'_$sSp12deinitialize5countSvSi_tF' { u64(unsafe { voidptr(swift_pointer_deinitialize) }) }
		'_swift_slowAlloc' { u64(unsafe { voidptr(swift_raw_allocate) }) }
		'_swift_slowDealloc' { u64(unsafe { voidptr(swift_raw_deallocate) }) }
		'_$sSp10deallocateyyF', '_$sSP10deallocateyyF',
		'_$sSv10deallocateyyF', '_$sSV10deallocateyyF' {
			u64(unsafe { voidptr(swift_pointer_deallocate) })
		}
		else { none }
	}
}
