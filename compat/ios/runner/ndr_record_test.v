// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32

$if macos {
	#include <mach/mach.h>
	#include <mach/ndr.h>
	@[typedef]
	struct C.NDR_record_t {
		mig_vers u8
		if_vers u8
		reserved1 u8
		mig_encoding u8
		int_rep u8
		char_rep u8
		float_rep u8
		reserved2 u8
	}
	fn C.mach_task_self() u32
	fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
	fn C.mach_port_deallocate(u32, u32) i32
}

fn ndr_check_bytes(entry u64) {
	assert entry != 0
	for index, expected in [u8(0), 0, 0, 0, 1, 0, 0, 0]! {
		assert unsafe { *(&u8(entry + u64(index))) } == expected
	}
	// MIG clients load the entire object, rather than dereferencing a pointer
	// cell. This is protocol metadata copied into a message, not a Mach call.
	mut word := u64(0)
	unsafe { C.memcpy(&word, voidptr(entry), 8) }
	assert word == 0x100000000
}

fn ndr_native(entry u64) {
	$if macos {
		handle := C.dlopen(c'/usr/lib/libSystem.B.dylib', 2)
		assert handle != unsafe { nil }
		reference := C.dlsym(handle, c'NDR_record'); assert reference != unsafe { nil }
		assert sizeof(C.NDR_record_t) == 8
		native := unsafe { &C.NDR_record_t(reference) }
		fields := [u64(unsafe { &native.mig_vers }), u64(unsafe { &native.if_vers }),
			u64(unsafe { &native.reserved1 }), u64(unsafe { &native.mig_encoding }),
			u64(unsafe { &native.int_rep }), u64(unsafe { &native.char_rep }),
			u64(unsafe { &native.float_rep }), u64(unsafe { &native.reserved2 })]!
		for i, field in fields { assert field - u64(reference) == u64(i) }
		ndr_check_bytes(u64(reference))
		assert C.memcmp(unsafe { voidptr(entry) }, reference, 8) == 0
		mut start := u64(reference); mut size := u64(0)
		mut info := [16]i32{}; mut count := u32(9); mut object := u32(0)
		task := C.mach_task_self()
		assert C.vm_region_64(task, unsafe { &start }, unsafe { &size }, 9,
			unsafe { &info[0] }, unsafe { &count }, unsafe { &object }) == 0
		assert u64(reference) >= start && u64(reference) + 8 <= start + size && info[0] & 3 == 3
		if object != 0 { assert C.mach_port_deallocate(task, object) == 0 }
		assert C.dlclose(handle) == 0
	}
}

fn ndr_consumer(entry u64) {
	page := u64(C.getpagesize())
	region := u64(C.mmap(unsafe { nil }, usize(page*3), C.PROT_NONE,
		C.MAP_PRIVATE|C.MAP_ANONYMOUS, -1, 0))
	assert region != u64(-1)
	assert C.mprotect(unsafe { voidptr(region+page) }, usize(page), C.PROT_READ|C.PROT_WRITE) == 0
	// Copy to the NDR field of guarded MIG-shaped messages at both aligned and
	// unaligned addresses. Bytes before and after the eight-byte field survive.
	for offset in [u64(0), 1, 7, 24, 65]! {
		message := region+page*2-40-offset
		unsafe { C.memset(voidptr(message), 0xa5, usize(40+offset)) }
		word := read64(entry)
		unsafe { C.memcpy(voidptr(message+24), &word, 8) }
		for i in 0 .. 24 { assert unsafe { *(&u8(message+u64(i))) } == 0xa5 }
		ndr_check_bytes(message+24)
		for i in u64(32) .. 40+offset { assert unsafe { *(&u8(message+i)) } == 0xa5 }
	}
	unsafe { C.memcpy(voidptr(region+page*2-8), voidptr(entry), 8) }
	ndr_check_bytes(region+page*2-8)
	assert C.munmap(unsafe { voidptr(region) }, usize(page*3)) == 0
}

fn ndr_worker(entry u64) {
	for _ in 0 .. 1000 {
		address := runtime_symbol('/usr/lib/libSystem.B.dylib', '_NDR_record') or { panic(err) }
		assert address == entry
		ndr_check_bytes(address)
	}
}

fn test_ndr_record() {
	assert system_data == unsafe { nil }
	if _ := system_data_symbol('_NDR_record') { assert false }
	for _ in 0 .. 2 {
		objc_start(); system_data_start()!
		darwin_set_errno(13)
		entry := runtime_symbol('/usr/lib/libSystem.B.dylib', '_NDR_record') or { panic(err) }
		assert unsafe { *C.ios_errno_address() } == 13
		assert entry == u64(unsafe { &system_data.ndr_record[0] })
		ndr_check_bytes(entry); ndr_native(entry); ndr_consumer(entry)
		for library in ['/usr/lib/libobjc.A.dylib', '/usr/lib/libz.1.dylib',
			'/System/Library/Frameworks/Foundation.framework/Foundation']! {
			if _ := runtime_symbol(library, '_NDR_record') { assert false }
		}
		// The export is writable. Resolving it again preserves caller changes;
		// publication must not reinitialize or substitute a freshly allocated copy.
		for i in 0 .. 8 {
			unsafe { *(&u8(entry+u64(i))) = u8(0x80+i) }
			assert system_data.ndr_record[i] == u8(0x80+i)
		}
		again := system_data_symbol('_NDR_record') or { panic('NDR record disappeared') }
		assert again == entry
		for i in 0 .. 8 { assert unsafe { *(&u8(entry+u64(i))) } == u8(0x80+i) }
		for i, byte in [u8(0), 0, 0, 0, 1, 0, 0, 0]! { unsafe { *(&u8(entry+u64(i))) = byte } }
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn ndr_worker(entry) }; workers.wait()
		unsafe { workers.free() }
		// A new runtime restores the native default even after guest mutation.
		unsafe { *(&u8(entry+4)) = 0x7f }
		objc_stop(); system_data_stop()
		assert system_data == unsafe { nil }
		if _ := system_data_symbol('_NDR_record') { assert false }
	}
	println('IOS-NDR-RECORD: native eight-byte layout/value, writable direct data, stable scoped identity, guarded aligned/unaligned message copies, eight concurrent readers, unchanged errno and two reset/teardown cycles')
}
