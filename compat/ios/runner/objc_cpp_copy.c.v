// SPDX-License-Identifier: GPL-2.0-or-later
module main

type ObjCppCopyHelper = fn (u64, u64)

// Process-lifetime, separately padded native mutex storage. No per-copy map,
// allocation, object metadata or ownership is needed. Keep it across runtime
// shutdown: property callbacks and future runtimes may still use these locks.
struct ObjCppCopyLock {
mut:
	words [16]u64
}
__global objc_cpp_copy_locks = [8]ObjCppCopyLock{}
__global objc_cpp_copy_initialized = false

fn objc_cpp_copy_index(address u64) int {
	return int(((address >> 4) ^ (address >> 9)) & 7)
}
fn objc_cpp_copy_lock(index int) voidptr {
	return unsafe { voidptr(&objc_cpp_copy_locks[index].words[0]) }
}
fn objc_cpp_copy_initialize() {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if objc_cpp_copy_initialized { return }
	if C.ios_sizeof_mutex() > sizeof(ObjCppCopyLock) { panic('iOS: C++ property mutex exceeds native storage') }
	for i in 0 .. 8 {
		if C.ios_mutex_create(objc_cpp_copy_lock(i), 0) != 0 { panic('iOS: cannot initialize C++ property mutex') }
	}
	objc_cpp_copy_initialized = true
}

fn objc_copy_cpp_atomic(destination u64, source u64, copy_helper u64) {
	if copy_helper == 0 { panic('iOS: atomic C++ property copy requires a callback') }
	objc_cpp_copy_initialize()
	dst := objc_cpp_copy_index(destination)
	src := objc_cpp_copy_index(source)
	first := objc_cpp_copy_lock(if dst < src { dst } else { src })
	second := objc_cpp_copy_lock(if dst < src { src } else { dst })
	if C.pthread_mutex_lock(first) != 0 { panic('iOS: cannot lock C++ property storage') }
	// Equal addresses and hash collisions acquire the shared stripe once.
	if first != second && C.pthread_mutex_lock(second) != 0 { panic('iOS: cannot lock C++ property storage') }
	// The initialization/registry lock is dropped before either stripe is
	// acquired. The callback owns the actual copy and its C++ resource lifetime.
	unsafe { ObjCppCopyHelper(voidptr(copy_helper))(destination, source) }
	if first != second && C.pthread_mutex_unlock(second) != 0 { panic('iOS: cannot unlock C++ property storage') }
	if C.pthread_mutex_unlock(first) != 0 { panic('iOS: cannot unlock C++ property storage') }
}
