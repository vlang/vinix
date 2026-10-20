// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>

$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFString.h>
	#include <objc/runtime.h>
}

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.objc_getClass(&char) voidptr
fn C.CFStringCreateMutable(voidptr, i64) voidptr
fn C.CFRetain(voidptr) voidptr
fn C.CFRelease(voidptr)
fn C.CFGetRetainCount(voidptr) i64
fn C.mincore(voidptr, usize, &u8) i32

const storage_symbol = '_$sSTsE32withContiguousStorageIfAvailableyqd__Sgqd__SRy7ElementQzGKXEKlF'

type StorageInvoke = fn (u64, &u64, u64, u64, &u64, u64)
type StorageSign = fn (u64, u64) u64
type StorageMetadata = fn (u64) u64

struct StorageApi {
	native      bool
	entry       u64
	code        u64
	integer     u64
	string_type u64
	object_type u64
	void_type   u64
	owner       u64
}

struct StorageState {
	api     StorageApi
	size    u64
	kind    int
	reenter bool
mut:
	metadata u64
	output   u64
	stores   int
}

fn storage_forbidden_copy(_destination u64, _source u64, _metadata u64) u64 {
	panic('Sequence storage default copied a value')
}

fn storage_forbidden_destroy(_value u64, _metadata u64) {
	panic('Sequence storage default destroyed a borrowed value')
}

fn storage_forbidden_tag(_value u64, _cases u32, _metadata u64) u32 {
	panic('Sequence storage default read an uninitialized Optional')
}

fn storage_lookup() u64 {
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', storage_symbol) or { panic(err) }
}

fn storage_store(value u64, which u32, cases u32, metadata u64) {
	mut s := unsafe { &StorageState(read64(metadata + 8)) }
	assert metadata == s.metadata && value == s.output && which == 1 && cases == 1
	s.stores++
	if s.reenter {
		t := spawn storage_lookup()
		assert t.wait() == s.api.entry
	}
	if s.kind == 7 {
		unsafe { *(&u64(value + 8)) = 0 }
	} else {
		C.memset(voidptr(value), 0, usize(s.size))
		unsafe { *(&u8(value + s.size)) = 1 }
	}
}

fn storage_refs(api StorageApi) i64 {
	$if macos {
		if api.native { return C.CFGetRetainCount(voidptr(api.owner)) }
	}
	return obj_header(api.owner).refs
}

fn storage_emit(code u64) {
	// entry, five Swift arguments, borrowed Self, indirect result, capture,
	// incoming x21. Capture x20/x21 after the generic rethrows method returns.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0103e9, 0xaa0203f4,
		0xaa0303e8, 0xaa0403f3, 0xaa0503f5, 0xa9400520, 0xa9410d22, 0xf9401124, 0xd63f0200, 0xf9000260,
		0xf9000675, 0xf9000a74, 0xa9425bf5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	write32(code + 128, 0xd4200000) // Forbidden closure: BRK.
	write32(code + 192, 0xdac10020)
	write32(code + 196, 0xd65f03c0)
	write32(code + 208, 0xdac10820)
	write32(code + 212, 0xd65f03c0)
}

fn storage_api(native bool, code u64) StorageApi {
	$if macos {
		if native {
			core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
			metadata := unsafe { StorageMetadata(C.dlsym(core, c'swift_getObjCClassMetadata')) }
			return StorageApi{
				native:      true
				code:        code
				entry:       u64(C.dlsym(core, storage_symbol[1..].str))
				integer:     u64(C.dlsym(core, c'$sSiN'))
				string_type: u64(C.dlsym(core, c'$sSSN'))
				object_type: metadata(u64(C.objc_getClass(c'NSString')))
				void_type:   u64(C.dlsym(core, c'$sytN')) + 8
				owner:       u64(C.CFStringCreateMutable(unsafe { nil }, 0))
			}
		}
	}
	return StorageApi{
		code:        code
		entry:       storage_lookup()
		integer:     swift_integer_metadata()
		string_type: swift_string_metadata()
		object_type: swift_objc_metadata(ios_runtime.names['NSString'])
		void_type:   swift_void_full_metadata() + 8
		owner:       owned_string('storage default borrowed Self/context')
	}
}

fn storage_drop(api StorageApi) {
	assert storage_refs(api) == 1
	$if macos {
		if api.native {
			C.CFRelease(voidptr(api.owner))
			return
		}
	}
	objc_release(api.owner)
}

fn storage_case(api StorageApi, kind int, fill u8, incoming u64, protected bool, guard u64) {
	page := usize(C.getpagesize())
	mut state := StorageState{
		api:     api
		kind:    kind
		size:    if kind == 4 {
			0
		} else if kind == 5 {
			3
		} else if kind == 6 {
			64
		} else {
			24
		}
		reenter: !api.native && kind == 6 && fill == 0x71 && !protected
	}
	allocation := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert allocation != u64(-1)
	defer { assert C.munmap(voidptr(allocation), page) == 0 }
	metadata := allocation + 16
	witness := allocation + 64
	unsafe {
		*(&u64(metadata - 8)) = witness
		*(&u64(metadata)) = 0x200
		*(&u64(metadata + 8)) = u64(&state)
	}
	for i in 0 .. 8 {
		unsafe { *(&u64(witness + u64(i * 8))) = u64(voidptr(storage_forbidden_copy)) }
	}
	unsafe {
		*(&u64(witness + 8)) = u64(voidptr(storage_forbidden_destroy))
		*(&u64(witness + 48)) = u64(voidptr(storage_forbidden_tag))
		*(&u64(witness + 56)) = u64(voidptr(storage_store))
	}
	alignment := if kind == 6 {
		u64(32)
	} else if kind == 5 {
		u64(4)
	} else if kind == 4 {
		u64(1)
	} else {
		u64(8)
	}
	unsafe {
		*(&u64(witness + 64)) = state.size
		*(&u64(witness + 72)) = if state.size == 0 {
			u64(1)
		} else {
			(state.size + alignment - 1) & ~(alignment - 1)
		}
		*(&u32(witness + 80)) = u32(alignment - 1)
		*(&u32(witness + 84)) = if kind == 7 { u32(1) } else { u32(0) }
	}
	result := match kind {
		0 { api.integer }
		1 { api.string_type }
		2 { api.object_type }
		3 { api.void_type }
		else { metadata }
	}
	state.metadata = result
	$if macos {
		if api.native && kind >= 4 {
			sign_data := unsafe { StorageSign(voidptr(api.code + 208)) }
			sign_code := unsafe { StorageSign(voidptr(api.code + 192)) }
			unsafe {
				*(&u64(metadata - 8)) = sign_data(witness, (metadata - 8) | (u64(11839) << 48))
				*(&u64(witness + 56)) = sign_code(u64(voidptr(storage_store)), (witness + 56) | (u64(41169) << 48))
			}
		}
	}
	assert C.mprotect(voidptr(allocation), page, C.PROT_READ) == 0
	vwt := read64(result - 8) & 0x0000ffffffffffff
	size := read64(vwt + 64)
	align := u64(read32(vwt + 80) & 255) + 1
	width := if kind in [1, 2, 7]! { size } else { size + 1 }
	buffer := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert buffer != u64(-1)
	defer { assert C.munmap(voidptr(buffer), page * 3) == 0 }
	assert C.mprotect(voidptr(buffer + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
	C.memset(voidptr(buffer + u64(page)), i32(fill), page)
	output := (buffer + u64(page * 2) - width) & ~(align - 1)
	state.output = output
	mut self := [api.owner, u64(0x123456789abcdef0)]!
	self_ptr := if protected { guard } else { u64(unsafe { &self[0] }) }
	unused := if protected { guard } else { u64(0) }
	args := [if protected { guard } else { api.code + 128 }, unused, unused, result, unused]!
	mut observed := [u64(0), 0, 0]!
	invoke := unsafe { StorageInvoke(voidptr(api.code)) }
	invoke(api.entry, unsafe { &args[0] }, self_ptr, output, unsafe { &observed[0] }, incoming)
	assert observed[1] == incoming && observed[2] == self_ptr
	assert self[0] == api.owner && self[1] == 0x123456789abcdef0 && storage_refs(api) == 1
	assert state.stores == if kind >= 4 { 1 } else { 0 }
	for i in buffer + u64(page) .. buffer + u64(page * 2) {
		mut expected := fill
		if kind == 1 || kind == 7 {
			if i >= output + 8 && i < output + 16 { expected = 0 }
		} else if kind == 2 {
			if i >= output && i < output + 8 { expected = 0 }
		} else if i >= output && i < output + size {
			expected = 0
		} else if i == output + size {
			expected = 1
		}
		assert unsafe { *(&u8(i)) } == expected, 'native=${api.native} kind=${kind} offset=${i - output}'
	}
}

fn storage_values(api StorageApi, guard u64) {
	for kind in 0 .. 8 {
		for fill in [u8(0), 0x71, 0xff]! {
			for incoming in [u64(0), 0x1357]! {
				for protected in [false, true]! {
					storage_case(api, kind, fill, incoming, protected, guard)
				}
			}
		}
	}
}

fn storage_worker(api StorageApi, guard u64) { storage_case(api, 6, 0x71, 0x1357, false, guard) }

fn storage_reject(api StorageApi, guard u64) {
	for metadata in [u64(0), 1, 7, api.integer | 1]! {
		if _ := swift_sequence_storage_checked(metadata, guard) {
			assert false
		}
	}
	if _ := swift_sequence_storage_checked(guard, 0) {
		assert false
	}
	if _ := swift_sequence_storage_checked(api.integer, guard + 1) {
		assert false
	}
	if _ := swift_sequence_storage_checked(api.integer, ~u64(7)) {
		assert false
	}
	mut vwt := [12]u64{}
	for i in 0 .. 12 { vwt[i] = read64(read64(api.integer - 8) + u64(i * 8)) }
	mut metadata := [u64(unsafe { &vwt[0] }), 0x200, 0]!
	result := u64(unsafe { &metadata[1] })
	for pair in [[u64(7), 0]!, [u64(7), 1]!, [u64(8), 65537]!, [u64(9), 0]!, [u64(10), 0x400007]!,
		[u64(10), 2]!, [u64(2), 0]!, [u64(4), 0]!, [u64(6), 0]!]! {
		old := vwt[int(pair[0])]
		vwt[int(pair[0])] = pair[1]
		if _ := swift_sequence_storage_checked(result, guard) {
			assert false
		}
		vwt[int(pair[0])] = old
	}
	ios_runtime.swift_concurrency_retired = true
	if _ := swift_sequence_storage_checked(guard, guard) {
		assert false
	}
	ios_runtime.swift_concurrency_retired = false
}

fn test_swift_sequence_storage() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	guard := u64(C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1) && guard != u64(-1)
	storage_emit(code)
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 216))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	$if macos {
		api := storage_api(true, code)
		storage_values(api, guard)
		storage_drop(api)
		println('NATIVE-SEQUENCE-STORAGE: 96 default cases; nil Int/String/ObjC/Void and custom Result layouts, exact bytes and guards, protected closure/context/Self/witnesses, preserved incoming x21 and borrowed ownership')
	}
	for _ in 0 .. 2 {
		objc_start()
		baseline := ios_runtime.live
		mut publishers := []thread u64{}
		for _ in 0 .. 8 { publishers << spawn storage_lookup() }
		entries := publishers.wait()
		unsafe { publishers.free() }
		assert entries.len == 8 && entries.all(it == entries[0])
		unsafe { entries.free() }
		api := storage_api(false, code)
		storage_values(api, guard)
		storage_reject(api, guard)
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn storage_worker(api, guard) }
		workers.wait()
		unsafe { workers.free() }
		for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/swift/libswiftFoundation.dylib']! {
			assert runtime_symbol(library, storage_symbol) == none
		}
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', storage_symbol[1..]) == none
		storage_drop(api)
		assert ios_runtime.live == baseline && ios_runtime.swift_arrays.len == 0
		arena := ios_runtime.swift_sequence_arena
		objc_stop()
		assert ios_runtime.swift_sequence_arena == 0
		$if macos {
			assert C.mprotect(voidptr(arena), page, C.PROT_READ) == -1
		} $else {
			mut resident := u8(0)
			assert C.mincore(voidptr(arena), page, unsafe { &resident }) == -1
		}
	}
	assert C.munmap(voidptr(code), page) == 0 && C.munmap(voidptr(guard), page) == 0
	println('IOS-SEQUENCE-STORAGE: 96 cases per lifetime; nil through Result witnesses, no closure or Sequence access, exact output/ownership and x20/x21 preservation, zero-size/padding/alignment/spare inhabitants, read-only metadata, protected inputs, invalid/overflow/retired rejection, eight cold publishers/workers, reentrant stores and two drained/unmapped lifetimes')
}
