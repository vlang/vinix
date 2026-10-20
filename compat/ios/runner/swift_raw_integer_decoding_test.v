// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>

$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFString.h>
}

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.CFStringCreateMutable(voidptr, i64) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRetain(voidptr) voidptr
fn C.CFRelease(voidptr)
fn C.mincore(voidptr, usize, &u8) i32

const raw_decoding_symbol = '_$sSYsSeRzSi8RawValueSYRtzrlE4fromxs7Decoder_p_tKcfC'

type RawDecodingInvoke = fn (u64, &u64, u64, u64, &u64)
type RawDecodingSign = fn (u64, u64) u64
type RawDecodingBox = fn (u64) SwiftArrayAllocation
type RawDecodingKeep = fn (u64) u64
type RawDecodingDrop = fn (u64)

struct RawDecodingApi {
	native bool
	entry  u64
	code   u64
	box    u64
	keep   RawDecodingKeep = swift_retain
	drop   RawDecodingDrop = swift_release
}

struct RawDecodingState {
	api             RawDecodingApi
	owner           u64
	error_owner     u64
	bits            u64
	size            u64
	failure         int
	container_boxed bool
	retained        bool
	reenter         bool
mut:
	metadata           u64
	raw_table          u64
	decoder_metadata   u64
	decoder_table      u64
	container_metadata u64
	container_table    u64
	heap_metadata      u64
	decoder_self       u64
	container_self     u64
	container_owner    u64
	getters            int
	decodes            int
	inits              int
	takes              int
	decoder_drops      int
	container_drops    int
	self_drops         int
}

fn raw_decoding_keep(api RawDecodingApi, owner u64) {
	$if macos {
		if api.native {
			C.CFRetain(voidptr(owner))
			return
		}
	}
	objc_retain(owner)
}

fn raw_decoding_drop(api RawDecodingApi, owner u64) {
	$if macos {
		if api.native {
			C.CFRelease(voidptr(owner))
			return
		}
	}
	objc_release(owner)
}

fn raw_decoding_refs(api RawDecodingApi, owner u64) i64 {
	$if macos {
		if api.native { return C.CFGetRetainCount(voidptr(owner)) }
	}
	return obj_header(owner).refs
}

fn raw_decoding_lookup() u64 {
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', raw_decoding_symbol) or { panic(err) }
}

fn raw_decoding_reenter(s &RawDecodingState) {
	if s.reenter {
		t := spawn raw_decoding_lookup()
		assert t.wait() == s.api.entry
	}
}

fn raw_decoding_box(s &RawDecodingState, metadata u64, heap u64) SwiftArrayAllocation {
	if s.api.native { return unsafe { RawDecodingBox(voidptr(s.api.box))(metadata) } }
	owner := swift_heap_allocate(heap, 48, 7)
	return SwiftArrayAllocation{ owner: owner, bytes: owner + 16 }
}

fn raw_decoding_getter(metadata u64, table u64, output u64, receiver u64, incoming u64) u64 {
	mut s := unsafe { &RawDecodingState(read64(receiver)) }
	assert metadata == s.decoder_metadata && table == s.decoder_table && receiver == s.decoder_self && incoming == 0
	assert s.getters == 0 && s.decodes == 0 && s.inits == 0 && s.decoder_drops == 0
	s.getters++
	raw_decoding_reenter(s)
	if s.failure == 1 {
		raw_decoding_keep(s.api, s.error_owner)
		return s.error_owner
	}
	mut payload := output
	if s.container_boxed {
		box := raw_decoding_box(s, s.container_metadata, s.heap_metadata)
		s.container_owner = box.owner
		payload = box.bytes
		if s.retained { s.api.keep(box.owner) }
		unsafe { *(&u64(output)) = box.owner }
	}
	s.container_self = payload
	unsafe {
		*(&u64(payload)) = u64(s)
		*(&u64(payload + 8)) = 0x12345678
		if s.container_boxed {
			*(&u64(payload + 16)) = 0x87654321
			*(&u64(payload + 24)) = 0xabcdef
		}
		*(&u64(output + 24)) = s.container_metadata
		*(&u64(output + 32)) = s.container_table
	}
	return 0
}

fn raw_decoding_int(metadata u64, table u64, receiver u64, incoming u64, output u64) u64 {
	mut s := unsafe { &RawDecodingState(read64(receiver)) }
	assert metadata == s.container_metadata && table == s.container_table && receiver == s.container_self && incoming == 0
	assert s.getters == 1 && s.decodes == 0 && s.inits == 0 && s.container_drops == 0 && s.decoder_drops == 0
	assert read64(receiver + 8) == 0x12345678
	s.decodes++
	raw_decoding_reenter(s)
	unsafe { *(&u64(output)) = s.bits }
	if s.failure == 2 {
		raw_decoding_keep(s.api, s.error_owner)
		return s.error_owner
	}
	return 0
}

fn raw_decoding_init(integer u64, metadata u64, table u64, receiver u64, output u64) {
	mut s := unsafe { &RawDecodingState(read64(metadata + 8)) }
	assert metadata == s.metadata && table == s.raw_table && receiver == metadata && read64(integer) == s.bits
	assert s.getters == 1 && s.decodes == 1 && s.inits == 0 && s.decoder_drops == 0
	assert s.container_drops == if s.retained && s.container_boxed { 0 } else { 1 }
	s.inits++
	raw_decoding_reenter(s)
	unsafe {
		C.memset(voidptr(output), 0xa7, usize(s.size))
		*(&u8(output + s.size)) = if s.failure == 3 { u8(1) } else { u8(0) }
		if s.size == 1 && s.failure == 3 { *(&u8(output)) = 0xff }
		if s.failure != 3 && s.size >= 24 {
			raw_decoding_keep(s.api, s.owner)
			*(&u64(output)) = u64(s)
			*(&u64(output + 8)) = s.bits
			*(&u64(output + 16)) = s.owner
		}
	}
}

fn raw_decoding_tag(value u64, cases u32, metadata u64) u32 {
	assert cases == 1
	size := read64((read64(metadata - 8) & 0x0000ffffffffffff) + 64)
	if size == 1 { return u32(unsafe { *(&u8(value)) } == 0xff) }
	return unsafe { *(&u8(value + size)) }
}

fn raw_decoding_store(value u64, tag u32, cases u32, metadata u64) {
	assert cases == 1
	size := read64((read64(metadata - 8) & 0x0000ffffffffffff) + 64)
	if size == 1 {
		if tag != 0 { unsafe { *(&u8(value)) = 0xff } }
		return
	}
	unsafe { *(&u8(value + size)) = u8(tag) }
}

fn raw_decoding_take(destination u64, source u64, metadata u64) u64 {
	mut s := unsafe { &RawDecodingState(read64(metadata + 8)) }
	assert s.inits == 1 && s.takes >= 0 && s.decoder_drops == 0
	s.takes++
	C.memcpy(voidptr(destination), voidptr(source), usize(s.size))
	raw_decoding_reenter(s)
	return destination
}

fn raw_decoding_self_drop(value u64, metadata u64) {
	mut s := unsafe { &RawDecodingState(read64(metadata + 8)) }
	assert s.self_drops == 0 && s.inits == 1
	if s.size >= 24 {
		assert read64(value) == u64(s) && read64(value + 8) == s.bits
		raw_decoding_drop(s.api, read64(value + 16))
	}
	s.self_drops++
	raw_decoding_reenter(s)
}

fn raw_decoding_value_drop(value u64, metadata u64) {
	mut s := unsafe { &RawDecodingState(read64(value)) }
	assert read64(value + 8) == 0x12345678
	if metadata == s.decoder_metadata {
		assert value == s.decoder_self && s.decoder_drops == 0 && s.getters == 1
		assert s.decodes == if s.failure in [1, 4]! { 0 } else { 1 }
		if !s.retained {
			assert s.container_drops == if s.failure == 1 { 0 } else { 1 }
		}
		s.decoder_drops++
	} else {
		assert metadata == s.container_metadata && value == s.container_self && s.container_drops == 0 && s.decodes == if s.failure == 4 {
			0
		} else {
			1
		}
		if !s.retained {
			assert s.decoder_drops == 0 && s.inits == 0
		}
		s.container_drops++
	}
	raw_decoding_reenter(s)
}

fn raw_decoding_box_drop(owner u64) {
	raw_decoding_value_drop(owner + 16, read64(read64(owner) + 8))
	swift_heap_deallocate(owner, 48, 7)
}

fn raw_decoding_emit(code u64) {
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0103e9, 0xaa0203f4,
		0xaa0303f5, 0xaa0403f3, 0xa9400520, 0xa9410d22, 0xaa1403e8, 0xd63f0200, 0xa9005674, 0xa9425bf5,
		0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	// Swift getter -> C, preserving incoming error; returned owned error -> x21.
	for i, op in [u32(0xa9bf7bfd), 0xaa0803e2, 0xaa1403e3, 0xaa1503e4, 0x580000d0, 0xd63f0200,
		0xaa0003f5, 0xa8c17bfd, 0xd65f03c0]! {
		write32(code + 128 + u64(i * 4), op)
	}
	unsafe { *(&u64(code + 168)) = u64(voidptr(raw_decoding_getter)) }
	for i, op in [u32(0xa9be7bfd), 0xaa1403e2, 0xaa1503e3, 0x910043e4, 0x58000110, 0xd63f0200,
		0xaa0003f5, 0xf9400be0, 0xa8c27bfd, 0xd65f03c0]! {
		write32(code + 192 + u64(i * 4), op)
	}
	unsafe { *(&u64(code + 240)) = u64(voidptr(raw_decoding_int)) }
	for i, op in [u32(0xa9bf7bfd), 0xaa1403e3, 0xaa0803e4, 0x580000b0, 0xd63f0200, 0xd28acf15,
		0xa8c17bfd, 0xd65f03c0]! {
		write32(code + 256 + u64(i * 4), op)
	}
	unsafe { *(&u64(code + 288)) = u64(voidptr(raw_decoding_init)) }
	for i, op in [u32(0xaa1403e0), 0x58000070, 0xd61f0200]! { write32(code + 320 + u64(i * 4), op) }
	unsafe { *(&u64(code + 336)) = u64(voidptr(raw_decoding_box_drop)) }
	write32(code + 384, 0xdac10020)
	write32(code + 388, 0xd65f03c0)
	write32(code + 400, 0xdac10820)
	write32(code + 404, 0xd65f03c0)
}

fn raw_decoding_api(native bool, code u64) RawDecodingApi {
	$if macos {
		if native {
			core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
			return RawDecodingApi{
				native: true
				code:   code
				entry:  u64(C.dlsym(core, raw_decoding_symbol[1..].str))
				box:    u64(C.dlsym(core, c'swift_allocBox'))
				keep:   unsafe { RawDecodingKeep(C.dlsym(core, c'swift_retain')) }
				drop:   unsafe { RawDecodingDrop(C.dlsym(core, c'swift_release')) }
			}
		}
	}
	return RawDecodingApi{ code: code, entry: raw_decoding_lookup() }
}

fn raw_decoding_case(api RawDecodingApi, bits u64, decoder_boxed bool, container_boxed bool, retained bool, at_end bool, failure int, size u64) {
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page * 5, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert span != u64(-1)
	defer { assert C.munmap(voidptr(span), page * 5) == 0 }
	data := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert data != u64(-1)
	defer { assert C.munmap(voidptr(data), page) == 0 }
	for offset in [u64(page), u64(page * 3)]! {
		assert C.mprotect(voidptr(span + offset), page, C.PROT_READ | C.PROT_WRITE) == 0
	}
	decoder := span + u64(page) + if at_end { u64(page) - 40 } else { u64(0) }
	output := span + u64(page * 3) + if at_end { u64(page) - size } else { u64(0) }
	mut owner := u64(0)
	mut error_owner := u64(0)
	$if macos {
		if api.native {
			owner = u64(C.CFStringCreateMutable(unsafe { nil }, 0))
			error_owner = u64(C.CFStringCreateMutable(unsafe { nil }, 0))
		}
	}
	if !api.native {
		owner = owned_string('owned decoded Self')
		error_owner = owned_string('original owned decoding error')
	}
	defer {
		raw_decoding_drop(api, owner)
		raw_decoding_drop(api, error_owner)
	}
	mut s := RawDecodingState{
		api:                api
		owner:              owner
		error_owner:        error_owner
		bits:               bits
		size:               size
		failure:            failure
		container_boxed:    container_boxed
		retained:           retained
		reenter:            !api.native && bits == 0x8000000000000000
		metadata:           data + 16
		raw_table:          data + 1120
		decoder_metadata:   data + if decoder_boxed { u64(544) } else { u64(192) }
		container_metadata: data + if container_boxed { u64(720) } else { u64(368) }
		decoder_table:      data + 960
		container_table:    data + 1024
		heap_metadata:      data + 912
	}
	// Self's value witnesses, including Optional's single-payload tag operations.
	for i, target in [u64(unsafe { voidptr(raw_decoding_take) }),
		u64(unsafe { voidptr(raw_decoding_self_drop) }), u64(unsafe { voidptr(raw_decoding_take) }),
		u64(unsafe { voidptr(raw_decoding_take) }), u64(unsafe { voidptr(raw_decoding_take) }),
		u64(unsafe { voidptr(raw_decoding_take) }), u64(unsafe { voidptr(raw_decoding_tag) }),
		u64(unsafe { voidptr(raw_decoding_store) })]! {
		slot := data + 64 + u64(i * 8)
		mut callback := target
		$if macos {
			if api.native {
				discriminator := [u64(0xda4a), 0x04f8, 0xe3ba, 0x8753, 0x48d8, 0xefda, 0x60f0,
					0xa0d1]![i]
				callback = unsafe { RawDecodingSign(voidptr(api.code + 384))(target, slot | (discriminator << 48)) }
			}
		}
		unsafe { *(&u64(slot)) = callback }
	}
	for i in 0 .. 5 {
		metadata := data + 16 + u64(i * 176)
		witness := data + 64 + u64(i * 176)
		mut pointer := witness
		$if macos {
			if api.native {
				pointer = unsafe { RawDecodingSign(voidptr(api.code + 400))(witness, (metadata - 8) | (u64(0x2e3f) << 48)) }
			}
		}
		unsafe {
			*(&u64(metadata - 8)) = pointer
			*(&u64(metadata)) = 0x200
			*(&u64(metadata + 8)) = u64(&s)
		}
		if i == 0 {
			unsafe {
				*(&u64(witness + 64)) = size
				*(&u64(witness + 72)) = if size == 1 { u64(1) } else { (size + 7) & ~u64(7) }
			}
			write32(witness + 80, if size == 1 {
				u32(0x10000)
			} else if size > 24 {
				u32(0x30007)
			} else {
				u32(0x10007)
			})
			write32(witness + 84, if size == 1 { u32(1) } else { u32(0) })
		} else {
			mut destroy := u64(voidptr(raw_decoding_value_drop))
			$if macos {
				if api.native {
					destroy = unsafe { RawDecodingSign(voidptr(api.code + 384))(destroy, (witness + 8) | (u64(0x04f8) << 48)) }
				}
			}
			unsafe {
				*(&u64(witness + 8)) = destroy
				*(&u64(witness + 64)) = if i < 3 { u64(16) } else { u64(32) }
				*(&u64(witness + 72)) = if i < 3 { u64(16) } else { u64(32) }
			}
			write32(witness + 80, if i < 3 { u32(0x10007) } else { u32(0x30007) })
		}
	}
	for i, heap in [u64(880), 912]! {
		unsafe {
			*(&u64(data + heap - 16)) = api.code + 320
			*(&u64(data + heap)) = 0x400
			*(&u64(data + heap + 8)) = data + 544 + u64(i * 176)
		}
	}
	for i, item in [[u64(1000), api.code + 128, 0x3fd3]!, [u64(1080), api.code + 192, 0x6ae2]!,
		[u64(1136), api.code + 256, 0x3b26]!]! {
		slot := data + item[0]
		mut callback := item[1]
		$if macos {
			if api.native {
				callback = unsafe { RawDecodingSign(voidptr(api.code + 384))(callback, slot | (item[2] << 48)) }
			}
		}
		unsafe { *(&u64(slot)) = if failure == 4 && i == 1 { u64(0) } else { callback } }
	}
	// Both unused generic arguments are unreadable. RawValue metadata is also unreadable.
	unsafe { *(&u64(s.raw_table + 8)) = span }
	mut decoder_owner := u64(0)
	mut payload := decoder
	if decoder_boxed {
		box := raw_decoding_box(unsafe { &s }, s.decoder_metadata, data + 880)
		decoder_owner = box.owner
		payload = box.bytes
		if retained { api.keep(box.owner) }
	}
	s.decoder_self = payload
	unsafe {
		*(&u64(payload)) = u64(&s)
		*(&u64(payload + 8)) = 0x12345678
		if decoder_boxed {
			*(&u64(payload + 16)) = 0x87654321
			*(&u64(payload + 24)) = 0xabcdef
			*(&u64(decoder)) = decoder_owner
		}
		*(&u64(decoder + 24)) = s.decoder_metadata
		*(&u64(decoder + 32)) = s.decoder_table
		C.memset(voidptr(output), 0xcc, usize(size))
	}
	assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ) == 0
	assert C.mprotect(voidptr(data), page, C.PROT_READ) == 0
	args := [decoder, s.metadata, span, s.raw_table]!
	mut capture := [u64(0xaaaa), 0, 0, 0xbbbb]!
	target := if failure == 0 {
		output
	} else if failure == 5 {
		u64(0)
	} else {
		span
	}
	if failure in [3, 4, 5]! {
		assert !api.native
		if _ := swift_raw_integer_decoding_checked(decoder, s.metadata, span, s.raw_table, target, 0) {
			assert false
		} else {
			assert err.msg().contains(if failure == 3 {
				'DecodingError.dataCorrupted'
			} else {
				'unsupported'
			})
		}
	} else {
		unsafe { RawDecodingInvoke(voidptr(api.code))(api.entry, &args[0], target, 0, &capture[1]) }
		assert capture == [u64(0xaaaa), target, if failure == 0 { u64(0) } else { error_owner },
			0xbbbb]!
	}
	assert s.getters == 1 && s.decodes == if failure in [1, 4]! { 0 } else { 1 }
	assert s.inits == if failure in [0, 3, 5]! { 1 } else { 0 }
	assert s.decoder_drops == if retained && decoder_boxed { 0 } else { 1 }
	assert s.container_drops == if failure == 1 || (retained && container_boxed) { 0 } else { 1 }
	assert raw_decoding_refs(api, error_owner) == if failure in [1, 2]! { 2 } else { 1 }
	if failure in [1, 2]! { raw_decoding_drop(api, error_owner) }
	if failure == 0 {
		if size >= 24 {
			assert read64(output) == u64(unsafe { &s }) && read64(output + 8) == bits && raw_decoding_refs(api, owner) == 2
		} else {
			for i in 0 .. size {
				assert unsafe { *(&u8(output + i)) } == 0xa7
			}
		}
		raw_decoding_self_drop(output, s.metadata)
	} else {
		for i in 0 .. size {
			assert unsafe { *(&u8(output + i)) } == 0xcc
		}
	}
	if retained && container_boxed && failure != 1 { api.drop(s.container_owner) }
	if retained && decoder_boxed { api.drop(decoder_owner) }
	assert s.decoder_drops == 1 && s.container_drops == if failure == 1 { 0 } else { 1 }
	assert raw_decoding_refs(api, owner) == 1
	assert s.self_drops == if failure in [0, 5]! { 1 } else { 0 }
}

fn raw_decoding_values(api RawDecodingApi) {
	for bits in [u64(0), 1, ~u64(0), 0x8000000000000000, 0x7fffffffffffffff, 0x1122334455667788]! {
		for decoder_boxed in [false, true]! {
			for container_boxed in [false, true]! {
				for retained in [false, true]! {
					for at_end in [false, true]! {
						for failure in 0 .. 3 {
							raw_decoding_case(api, bits, decoder_boxed, container_boxed, retained, at_end, failure, 24)
						}
					}
				}
			}
		}
	}
}

fn raw_decoding_worker(api RawDecodingApi, i int) {
	raw_decoding_case(api, 0x8000000000000000, i % 2 == 0, i % 3 == 0, true, true, i % 3, 32)
}

fn test_swift_raw_integer_decoding() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	raw_decoding_emit(code)
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 408))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	$if macos {
		raw_decoding_values(raw_decoding_api(true, code))
		println('NATIVE-RAW-INTEGER-DECODING: 288 cases; consumed inline/boxed/shared Decoder/container, original owned getter/decode errors, raw initializer ABI, non-POD Self and guarded result transfer')
	}
	for _ in 0 .. 2 {
		objc_start()
		baseline := ios_runtime.live
		api := raw_decoding_api(false, code)
		raw_decoding_values(api)
		for size in [u64(1), 24, 32]! {
			for boxed in [false, true]! {
				for failure in [0, 3, 4, 5]! {
					raw_decoding_case(api, 1, boxed, boxed, false, true, failure, size)
				}
			}
		}
		mut workers := []thread{}
		for i in 0 .. 8 { workers << spawn raw_decoding_worker(api, i) }
		workers.wait()
		unsafe { workers.free() }
		for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/swift/libswiftFoundation.dylib']! {
			assert runtime_symbol(library, raw_decoding_symbol) == none
		}
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', raw_decoding_symbol[1..]) == none
		ios_runtime.swift_concurrency_retired = true
		if _ := swift_raw_integer_decoding_checked(0, 0, 0, 0, 0, 0) {
			assert false
		}
		ios_runtime.swift_concurrency_retired = false
		assert ios_runtime.live == baseline && ios_runtime.swift_heap.len == 0
		arena := ios_runtime.swift_hash_code
		objc_stop()
		assert ios_runtime.swift_hash_code == 0
		$if macos {
			assert C.mprotect(voidptr(arena), page, C.PROT_READ) == -1
		} $else {
			mut resident := u8(0)
			assert C.mincore(voidptr(arena), page, unsafe { &resident }) == -1
		}
	}
	assert C.munmap(voidptr(code), page) == 0
	println('IOS-RAW-INTEGER-DECODING: Int decoding and failable raw initializer dispatch, original error transfer, exact owned Decoder/container cleanup, guarded 1/24/32-byte Self, shared boxes, eight workers, reentrant callbacks and two drained/unmapped lifetimes; invalid rawValue explicitly requires DecodingError.dataCorrupted support')
}
