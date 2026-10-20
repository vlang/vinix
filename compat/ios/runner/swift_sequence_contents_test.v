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

const contents_symbol = '_$sSTsE13_copyContents12initializing8IteratorQz_SitSry7ElementQzG_tF'

type ContentsInvoke = fn (u64, &u64, u64, u64, &u64)
type ContentsSign = fn (u64, u64) u64
type ContentsMetadata = fn (u64) u64

struct ContentsApi {
	native      bool
	code        u64
	entry       u64
	integer     u64
	string_type u64
	object_type u64
}

struct ContentsState {
	api           ContentsApi
	kind          int
	count         u64
	owner         u64
	iterator_size u64
	reenter       bool
mut:
	element        u64
	sequence       u64
	iterator       u64
	table          u64
	iterator_table u64
	source         u64
	copies         int
	makes          int
	nexts          int
	takes          int
	destroys       int
}

fn contents_keep(api ContentsApi, owner u64) {
	$if macos {
		if api.native {
			C.CFRetain(voidptr(owner))
			return
		}
	}
	objc_retain(owner)
}

fn contents_drop(api ContentsApi, owner u64) {
	$if macos {
		if api.native {
			C.CFRelease(voidptr(owner))
			return
		}
	}
	objc_release(owner)
}

fn contents_refs(api ContentsApi, owner u64) i64 {
	$if macos {
		if api.native { return C.CFGetRetainCount(voidptr(owner)) }
	}
	return obj_header(owner).refs
}

fn contents_lookup(entry u64) {
	assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', contents_symbol) or { panic(err) } == entry
}

fn contents_copy(destination u64, source u64, metadata u64) u64 {
	mut s := unsafe { &ContentsState(read64(metadata + 8)) }
	s.copies++
	contents_keep(s.api, s.owner)
	C.memcpy(voidptr(destination), voidptr(source), usize(read64((read64(metadata - 8) & 0x0000ffffffffffff) + 64)))
	return destination
}

fn contents_take(destination u64, source u64, metadata u64) u64 {
	size := read64((read64(metadata - 8) & 0x0000ffffffffffff) + 64)
	C.memcpy(voidptr(destination), voidptr(source), usize(size))
	return destination
}

fn contents_destroy(value u64, metadata u64) {
	mut s := unsafe { &ContentsState(read64(metadata + 8)) }
	assert metadata == s.iterator && read64(value) == u64(s)
	s.destroys++
	contents_drop(s.api, s.owner)
}

fn contents_tag(value u64, _cases u32, metadata u64) u32 {
	return u32(unsafe { *(&u8(value + read64(read64(metadata - 8) + 64))) })
}

fn contents_element_take(destination u64, source u64, metadata u64) u64 {
	mut s := unsafe { &ContentsState(read64(metadata + 8)) }
	s.takes++
	return contents_take(destination, source, metadata)
}

fn contents_element_destroy(_value u64, _metadata u64) {}

fn contents_make(metadata u64, table u64, output u64, receiver u64) {
	mut s := unsafe { &ContentsState(read64(metadata + 8)) }
	assert metadata == s.sequence && table == s.table && receiver == s.source
	assert read64(receiver) == u64(s) && s.copies == 0 && s.makes == 0
	if s.reenter {
		t := spawn contents_lookup(s.api.entry)
		t.wait()
	}
	s.makes++
	C.memset(voidptr(output), 0xa1, usize(s.iterator_size))
	unsafe {
		*(&u64(output)) = u64(s)
		*(&u64(output + 8)) = 0
	}
}

fn contents_next(metadata u64, table u64, output u64, receiver u64) {
	mut s := unsafe { &ContentsState(read64(metadata + 8)) }
	assert metadata == s.iterator && table == s.iterator_table && read64(receiver) == u64(s)
	index := read64(receiver + 8)
	assert index <= s.count
	if s.reenter {
		t := spawn contents_lookup(s.api.entry)
		t.wait()
	}
	s.nexts++
	if index == s.count {
		if s.kind == 1 {
			unsafe { *(&u64(output + 8)) = 0 }
		} else if s.kind == 2 {
			unsafe { *(&u64(output)) = 0 }
		} else {
			size := read64((read64(s.element - 8) & 0x0000ffffffffffff) + 64)
			C.memset(voidptr(output), 0, usize(size))
			unsafe { *(&u8(output + size)) = 1 }
		}
		return
	}
	if s.kind == 1 {
		contents_keep(s.api, s.owner)
		unsafe {
			*(&u64(output)) = 0
			*(&u64(output + 8)) = s.owner | 0x5000000000000000
		}
	} else if s.kind == 2 {
		contents_keep(s.api, s.owner)
		unsafe { *(&u64(output)) = s.owner }
	} else {
		size := read64((read64(s.element - 8) & 0x0000ffffffffffff) + 64)
		for i in u64(0) .. size {
			unsafe { *(&u8(output + i)) = u8(index * 7 + i) }
		}
		unsafe { *(&u8(output + size)) = 0 }
	}
	unsafe { *(&u64(receiver + 8)) = index + 1 }
}

fn contents_emit(code u64) {
	// x8 points at protected memory: Iterator is explicitly indirect in x0.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0103e9, 0xaa0203f4,
		0xaa0303e8, 0xaa0403f3, 0xa9400520, 0xa9410d22, 0xf9401124, 0xaa1f03f5, 0xd63f0200, 0xf9000260,
		0xf9000675, 0xf9000a74, 0xa9425bf5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	for offset, target in {
		u64(128): u64(voidptr(contents_make))
		u64(160): u64(voidptr(contents_next))
	} {
		write32(code + offset, 0xaa0803e2)
		write32(code + offset + 4, 0xaa1403e3)
		write32(code + offset + 8, 0x58000090)
		write32(code + offset + 12, 0xd61f0200)
		unsafe { *(&u64(code + offset + 24)) = target }
	}
	write32(code + 192, 0xdac10020)
	write32(code + 196, 0xd65f03c0)
	write32(code + 208, 0xdac10820)
	write32(code + 212, 0xd65f03c0)
}

fn contents_api(native bool, code u64) ContentsApi {
	$if macos {
		if native {
			core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
			metadata := unsafe { ContentsMetadata(C.dlsym(core, c'swift_getObjCClassMetadata')) }
			return ContentsApi{
				native:      true
				code:        code
				entry:       u64(C.dlsym(core, contents_symbol[1..].str))
				integer:     u64(C.dlsym(core, c'$sSiN'))
				string_type: u64(C.dlsym(core, c'$sSSN'))
				object_type: metadata(u64(C.objc_getClass(c'NSString')))
			}
		}
	}
	return ContentsApi{
		code:        code
		entry:       runtime_symbol('/usr/lib/swift/libswiftCore.dylib', contents_symbol) or { panic(err) }
		integer:     swift_integer_metadata()
		string_type: swift_string_metadata()
		object_type: swift_objc_metadata(ios_runtime.names['NSString'])
	}
}

fn contents_value(value u64, kind int, index u64, owner u64, size u64) {
	if kind == 1 {
		assert read64(value) == 0 && read64(value + 8) == owner | 0x5000000000000000
	} else if kind == 2 {
		assert read64(value) == owner
	} else {
		for i in u64(0) .. size {
			assert unsafe { *(&u8(value + i)) } == u8(index * 7 + i)
		}
	}
}

fn contents_case(api ContentsApi, kind int, count u64, capacity u64, iterator_size u64, guard u64) {
	mut owner := u64(0)
	$if macos {
		if api.native { owner = u64(C.CFStringCreateMutable(unsafe { nil }, 0)) }
	}
	if !api.native { owner = owned_string('copyContents owned iterator and Element') }
	mut s := ContentsState{
		api:           api
		kind:          kind
		count:         count
		owner:         owner
		iterator_size: iterator_size
		reenter:       !api.native && kind == 2 && count == 9 && capacity == 3
	}
	mut seq_vwt := [12]u64{}
	mut iter_vwt := [12]u64{}
	mut elem_vwt := [12]u64{}
	mut seq_meta := [u64(unsafe { &seq_vwt[0] }), 0x200, u64(unsafe { &s })]!
	mut iter_meta := [u64(unsafe { &iter_vwt[0] }), 0x200, u64(unsafe { &s })]!
	mut elem_meta := [u64(unsafe { &elem_vwt[0] }), 0x200, u64(unsafe { &s })]!
	s.sequence = u64(unsafe { &seq_meta[1] })
	s.iterator = u64(unsafe { &iter_meta[1] })
	s.element = if kind == 0 {
		api.integer
	} else if kind == 1 {
		api.string_type
	} else if kind == 2 {
		api.object_type
	} else {
		u64(unsafe { &elem_meta[1] })
	}
	for i in 0 .. 8 {
		seq_vwt[i] = u64(voidptr(contents_take))
		iter_vwt[i] = seq_vwt[i]
		elem_vwt[i] = seq_vwt[i]
	}
	seq_vwt[1] = u64(voidptr(contents_destroy))
	iter_vwt[1] = seq_vwt[1]
	seq_vwt[2] = u64(voidptr(contents_copy))
	iter_vwt[2] = seq_vwt[2]
	seq_vwt[6] = u64(voidptr(contents_tag))
	iter_vwt[6] = seq_vwt[6]
	elem_vwt[6] = seq_vwt[6]
	seq_vwt[8] = 8
	seq_vwt[9] = 8
	seq_vwt[10] = 7
	iter_vwt[8] = iterator_size
	iter_vwt[9] = iterator_size
	iter_vwt[10] = 7
	// Shim-only unusual Element layouts: empty (stride 1), 3-byte/stride 4,
	// and a 64-byte value aligned to 32 bytes, with no spare inhabitants.
	if kind >= 3 {
		assert !api.native
		elem_vwt[8] = if kind == 3 {
			0
		} else if kind == 4 {
			3
		} else {
			64
		}
		elem_vwt[9] = if kind == 3 {
			1
		} else if kind == 4 {
			4
		} else {
			64
		}
		elem_vwt[10] = if kind == 3 {
			0
		} else if kind == 4 {
			3
		} else {
			31
		}
		elem_vwt[1] = u64(voidptr(contents_element_destroy))
		elem_vwt[4] = u64(voidptr(contents_element_take))
	}
	mut it_table := [u64(0), s.element, api.code + 160]!
	mut table := [u64(0), u64(unsafe { &it_table[0] }), s.element, s.iterator, api.code + 128]!
	s.table = u64(unsafe { &table[0] })
	s.iterator_table = u64(unsafe { &it_table[0] })
	mut source := [u64(unsafe { &s }), 0x123456789abcdef0]!
	s.source = u64(unsafe { &source[0] })
	$if macos {
		if api.native {
			data := unsafe { ContentsSign(voidptr(api.code + 208)) }
			code := unsafe { ContentsSign(voidptr(api.code + 192)) }
			seq_meta[0] = data(seq_meta[0], u64(unsafe { &seq_meta[0] }) | (u64(11839) << 48))
			iter_meta[0] = data(iter_meta[0], u64(unsafe { &iter_meta[0] }) | (u64(11839) << 48))
			table[1] = data(table[1], (s.table + 8) | (u64(0xb734) << 48))
			table[2] = data(table[2], (s.table + 16) | (u64(0xb6c5) << 48))
			table[3] = data(table[3], (s.table + 24) | (u64(0xcbc) << 48))
			table[4] = code(table[4], (s.table + 32) | (u64(27944) << 48))
			it_table[2] = code(it_table[2], (s.iterator_table + 16) | (u64(65124) << 48))
		}
	}
	vwt := read64(s.element - 8) & 0x0000ffffffffffff
	size := read64(vwt + 64)
	stride := read64(vwt + 72)
	alignment := u64(read32(vwt + 80) & 255) + 1
	bytes := u64(C.malloc(usize((capacity + 2) * stride + alignment + 64)))
	assert bytes != 0
	defer { C.free(voidptr(bytes)) }
	C.memset(voidptr(bytes), 0x71, usize((capacity + 2) * stride + alignment + 64))
	destination := (bytes + alignment + 31) & ~(alignment - 1)
	mut iterator := [32]u64{}
	iterator[0] = 0xaaaabbbb
	iterator[31] = 0xccccdddd
	output := u64(unsafe { &iterator[1] })
	C.memset(voidptr(output), 0x81, usize(iterator_size + 8))
	mut observed := [u64(0), 0, 0]!
	args := [output, if capacity == 0 && count % 2 == 0 { u64(0) } else { destination }, capacity,
		s.sequence, s.table]!
	contents_keep(api, owner) // Ownership transferred from Self to returned Iterator.
	invoke := unsafe { ContentsInvoke(voidptr(api.code)) }
	invoke(api.entry, unsafe { &args[0] }, s.source, guard, unsafe { &observed[0] })
	written := if capacity < count { capacity } else { count }
	assert observed[0] == written && observed[1] == 0 && observed[2] == s.source, 'native=${api.native} kind=${kind} count=${count} capacity=${capacity} iterator=${iterator_size} observed=${observed} written=${written} self=${s.source}'
	assert s.makes == 1 && s.copies == 0 && s.destroys == 0
	assert s.nexts == int(written + if count < capacity { u64(1) } else { u64(0) })
	assert read64(output) == u64(unsafe { &s }) && read64(output + 8) == written
	assert iterator[0] == 0xaaaabbbb && iterator[31] == 0xccccdddd && read64(output + iterator_size) == 0x8181818181818181
	for i in u64(16) .. iterator_size {
		assert unsafe { *(&u8(output + i)) } == 0xa1
	}
	assert source[0] == u64(unsafe { &s }) && source[1] == 0x123456789abcdef0
	assert unsafe { *(&u8(destination - 1)) } == 0x71
	for i in u64(0) .. written {
		contents_value(destination + i * stride, kind, i, owner, size)
		for j in size .. stride {
			assert unsafe { *(&u8(destination + i * stride + j)) } == 0x71
		}
	}
	for i in written * stride .. (capacity + 1) * stride {
		assert unsafe { *(&u8(destination + i)) } == 0x71
	}
	assert contents_refs(api, owner) == 2 + if kind in [1, 2]! { i64(written) } else { i64(0) }
	if kind >= 3 {
		assert s.takes == int(written)
	}
	destroy := unsafe { SwiftSequenceDestroy(voidptr(read64(vwt + 8) & 0x0000ffffffffffff)) }
	for i in u64(0) .. written { destroy(destination + i * stride, s.element) }
	// Resume the returned iterator through every remaining value and repeated nil.
	mut item := [96]u8{}
	ip := (u64(unsafe { &item[0] }) + 31) & ~u64(31)
	for i in written .. count {
		contents_next(s.iterator, s.iterator_table, ip, output)
		contents_value(ip, kind, i, owner, size)
		destroy(ip, s.element)
	}
	for _ in 0 .. 3 { contents_next(s.iterator, s.iterator_table, ip, output) }
	contents_destroy(output, s.iterator)
	assert s.destroys == 1 && contents_refs(api, owner) == 1
	contents_drop(api, owner)
}

fn contents_values(api ContentsApi, guard u64) {
	for kind in 0 .. if api.native { 3 } else { 6 } {
		for count in [u64(0), 1, 9, 33]! {
			for capacity in [u64(0), 1, 3, 9, 40]! {
				for size in [u64(16), 24, 128]! {
					contents_case(api, kind, count, capacity, size, guard)
				}
			}
		}
	}
}

fn contents_worker(api ContentsApi, guard u64) { contents_case(api, 2, 33, 9, 24, guard) }

fn contents_reject(api ContentsApi, guard u64) {
	for args in [[u64(0), guard, 1]!, [guard, u64(0), 1]!, [guard, guard, ~u64(0)]!]! {
		if _ := swift_sequence_contents_checked(args[0], args[1], i64(args[2]), guard, guard, guard) {
			assert false
		}
	}
	mut it := [u64(0), api.integer, api.code + 160]!
	mut table := [u64(0), u64(unsafe { &it[0] }), api.integer, api.integer, api.code + 128]!
	tp := u64(unsafe { &table[0] })
	for args in [[guard + 1, guard, u64(1), guard]!, [guard, guard + 1, u64(1), guard]!,
		[guard, guard, u64(1), guard + 1]!, [guard, ~u64(7), u64(2), guard]!,
		[~u64(7), guard, u64(1), guard]!, [guard, guard, u64(1), ~u64(7)]!]! {
		if _ := swift_sequence_contents_checked(args[0], args[1], i64(args[2]), api.integer, tp, args[3]) {
			assert false
		}
	}
	for slot in 1 .. 5 {
		old := table[slot]
		for bad in [u64(0), old | 1]! {
			table[slot] = bad
			if _ := swift_sequence_contents_checked(guard, guard, 1, api.integer, tp, guard) {
				assert false
			}
		}
		table[slot] = old
	}
	it[1] = api.string_type
	if _ := swift_sequence_contents_checked(guard, guard, 1, api.integer, tp, guard) {
		assert false
	}
	it[1] = api.integer
	ios_runtime.swift_concurrency_retired = true
	if _ := swift_sequence_contents_checked(guard, guard, 1, api.integer, guard, guard) {
		assert false
	}
	ios_runtime.swift_concurrency_retired = false
}

fn test_swift_sequence_contents() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	guard := u64(C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1) && guard != u64(-1)
	contents_emit(code)
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 216))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	$if macos {
		contents_values(contents_api(true, code), guard)
		println('NATIVE-SEQUENCE-CONTENTS: 180 custom Sequence cases; explicit indirect Iterator, consuming Self, Int/String/ObjC elements, empty/partial/exact/oversized buffers, no extra next, resumed iterator and exact ownership')
	}
	for _ in 0 .. 2 {
		objc_start()
		baseline := ios_runtime.live
		api := contents_api(false, code)
		contents_values(api, guard)
		contents_reject(api, guard)
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn contents_worker(api, guard) }
		workers.wait()
		unsafe { workers.free() }
		for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/swift/libswiftFoundation.dylib']! {
			assert runtime_symbol(library, contents_symbol) == none
		}
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', contents_symbol[1..]) == none
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
	println('IOS-SEQUENCE-CONTENTS: 360 cases per lifetime; consuming Self and owned resumed Iterator, move-only initialization, zero-size/stride-padding/32-byte-aligned Elements, protected x8 and buffer guards, incomplete/tagged/misaligned/overflow/retired rejection, eight readers, reentrant callbacks and two drained/unmapped lifetimes')
}
