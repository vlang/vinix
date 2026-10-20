// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct ObjBlockImp {
	block u64 // One Block_copy reference, transferred out before disposal callbacks.
	size usize
}

fn objc_imp_with_block(block u64) u64 {
	$if !arm64 { panic('iOS: Block-backed IMPs require ARM64') }
	if block == 0 { return 0 }
	C.ios_objc_initialize_lock()
	retired := ios_runtime.block_imps_retired
	C.ios_objc_initialize_unlock()
	if retired { panic('iOS: Block-backed IMP creation after runtime shutdown') }
	// User copy/dispose helpers may enter the runtime or wait for another thread.
	copied := block_copy(block)
	page := usize(C.getpagesize())
	allocation := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if allocation == unsafe { voidptr(-1) } {
		block_release(copied)
		panic('iOS: cannot allocate Block-backed IMP')
	}
	base := u64(allocation)
	// Method (self, _cmd, args...) -> Block (block, self, args...). Both
	// implicit arguments occupy two integer registers. Tail-call with the
	// original SP/LR, x2-x8 and every SIMD register, including indirect results.
	write32(base, 0xaa0003e1) // mov x1, x0
	write32(base + 4, 0x58000060) // ldr x0, literal at +16
	write32(base + 8, 0xf9400810) // ldr x16, [x0, #16] (Block invoke)
	write32(base + 12, 0xd61f0200) // br x16
	unsafe { *(&u64(base + 16)) = copied }
	C.__builtin___clear_cache(allocation, unsafe { voidptr(base + 16) })
	if C.mprotect(allocation, page, C.PROT_READ | C.PROT_EXEC) != 0 {
		C.munmap(allocation, page)
		block_release(copied)
		panic('iOS: cannot seal Block-backed IMP')
	}
	C.ios_objc_initialize_lock()
	if ios_runtime.block_imps_retired {
		C.ios_objc_initialize_unlock()
		C.munmap(allocation, page)
		block_release(copied)
		panic('iOS: Block-backed IMP creation during runtime shutdown')
	}
	ios_runtime.block_imps[base] = ObjBlockImp{block: copied, size: page}
	C.ios_objc_initialize_unlock()
	return base
}

// Borrowed identity, like imp_getBlock: callers coordinate removal with use.
fn objc_imp_get_block(imp u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	entry := ios_runtime.block_imps[imp] or { return 0 }
	return entry.block
}

// The caller must detach the IMP and drain invocations before removing it.
// No metadata lookup dereferences a caller-supplied IMP address.
fn objc_imp_remove_block(imp u64) bool {
	C.ios_objc_initialize_lock()
	entry := ios_runtime.block_imps[imp] or {
		C.ios_objc_initialize_unlock()
		return false
	}
	ios_runtime.block_imps.delete(imp)
	C.ios_objc_initialize_unlock()
	block_release(entry.block)
	if C.munmap(unsafe { voidptr(imp) }, entry.size) != 0 {
		panic('iOS: cannot retire Block-backed IMP')
	}
	return true
}

fn objc_block_imps_stop() {
	// All application workers have drained. Dispose captures while Foundation,
	// class metadata and autorelease pools remain available to their callbacks.
	C.ios_objc_initialize_lock()
	ios_runtime.block_imps_retired = true
	C.ios_objc_initialize_unlock()
	for {
		C.ios_objc_initialize_lock()
		mut candidate := u64(0)
		for imp, _ in ios_runtime.block_imps { candidate = imp; break }
		C.ios_objc_initialize_unlock()
		if candidate == 0 { break }
		objc_imp_remove_block(candidate)
	}
	C.ios_objc_initialize_lock()
	unsafe { ios_runtime.block_imps.free() }
	C.ios_objc_initialize_unlock()
}
