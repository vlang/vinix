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

const raw_encoding_symbol = '_$sSYsSERzSi8RawValueSYRtzrlE6encode2toys7Encoder_p_tKF'

type RawEncodingInvoke = fn (u64, &u64, u64, u64, &u64)
type RawEncodingSign = fn (u64, u64) u64

struct RawEncodingApi {
	native bool
	entry  u64
	code   u64
}

struct RawEncodingState {
	api         RawEncodingApi
	owner       u64
	error_owner u64
	bits        u64
	incoming    u64
	failing     bool
	missing     bool
	reenter     bool
mut:
	metadata           u64
	raw_table          u64
	encoder_metadata   u64
	encoder_table      u64
	container_metadata u64
	container_table    u64
	source             u64
	encoder_self       u64
	container          u64
	getters            int
	raw_getters        int
	encodes            int
	drops              int
}

fn raw_encoding_keep(api RawEncodingApi, owner u64) {
	$if macos {
		if api.native {
			C.CFRetain(voidptr(owner))
			return
		}
	}
	objc_retain(owner)
}

fn raw_encoding_drop(api RawEncodingApi, owner u64) {
	$if macos {
		if api.native {
			C.CFRelease(voidptr(owner))
			return
		}
	}
	objc_release(owner)
}

fn raw_encoding_refs(api RawEncodingApi, owner u64) i64 {
	$if macos {
		if api.native { return C.CFGetRetainCount(voidptr(owner)) }
	}
	return obj_header(owner).refs
}

fn raw_encoding_lookup() u64 {
	return runtime_symbol('/usr/lib/swift/libswiftCore.dylib', raw_encoding_symbol) or { panic(err) }
}

fn raw_encoding_reenter(s &RawEncodingState) {
	if s.reenter {
		t := spawn raw_encoding_lookup()
		assert t.wait() == s.api.entry
	}
}

fn raw_encoding_get_container(metadata u64, table u64, output u64, receiver u64) {
	mut s := unsafe { &RawEncodingState(read64(receiver)) }
	assert metadata == s.encoder_metadata && table == s.encoder_table && receiver == s.encoder_self
	assert s.getters == 0 && s.raw_getters == 0 && s.encodes == 0 && s.drops == 0
	assert raw_encoding_refs(s.api, s.owner) == 1
	s.getters++
	s.container = output
	raw_encoding_keep(s.api, s.owner)
	unsafe {
		*(&u64(output)) = u64(s)
		*(&u64(output + 8)) = 0x12345678
		*(&u64(output + 16)) = 0x87654321
		*(&u64(output + 24)) = s.container_metadata
		*(&u64(output + 32)) = s.container_table
	}
	raw_encoding_reenter(s)
}

fn raw_encoding_get_raw(metadata u64, table u64, output u64, receiver u64) {
	mut s := unsafe { &RawEncodingState(read64(metadata + 8)) }
	assert metadata == s.metadata && table == s.raw_table && receiver == s.source
	assert unsafe { *(&u8(receiver)) } == 0x79 && output & 7 == 0
	assert s.getters == 1 && s.raw_getters == 0 && s.encodes == 0 && s.drops == 0
	assert raw_encoding_refs(s.api, s.owner) == 2
	s.raw_getters++
	unsafe { *(&u64(output)) = s.bits }
	raw_encoding_reenter(s)
}

fn raw_encoding_encode(bits u64, metadata u64, table u64, receiver u64, incoming u64) u64 {
	mut s := unsafe { &RawEncodingState(read64(receiver)) }
	assert metadata == s.container_metadata && table == s.container_table && receiver == s.container
	assert s.getters == 1 && s.raw_getters == 1 && s.encodes == 0 && s.drops == 0
	assert bits == s.bits && incoming == s.incoming
	assert read64(receiver + 8) == 0x12345678 && read64(receiver + 16) == 0x87654321
	assert raw_encoding_refs(s.api, s.owner) == 2
	s.encodes++
	unsafe { *(&u64(receiver + 8)) = 0xfeedface }
	raw_encoding_reenter(s)
	if s.failing {
		raw_encoding_keep(s.api, s.error_owner)
		return s.error_owner
	}
	return 0
}

fn raw_encoding_destroy(value u64, metadata u64) {
	mut s := unsafe { &RawEncodingState(read64(value)) }
	assert metadata == s.container_metadata && value == s.container && s.drops == 0
	assert s.getters == 1 && s.raw_getters == 1 && s.encodes == if s.missing { 0 } else { 1 }
	assert read64(value + 8) == if s.missing { u64(0x12345678) } else { u64(0xfeedface) }
	assert raw_encoding_refs(s.api, s.owner) == 2
	s.drops++
	raw_encoding_drop(s.api, s.owner)
	raw_encoding_reenter(s)
}

fn raw_encoding_emit(code u64) {
	// C entry, arguments, Self, incoming error and capture -> Swift. Capture
	// callee-saved Self and returned owned error; x8 is deliberately unmapped.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0103e9, 0xaa0203f4,
		0xaa0303f5, 0xaa0403f3, 0xa9400520, 0xa9410d22, 0xaa0203e8, 0xd63f0200, 0xa9005674, 0xa9425bf5,
		0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	for offset, target in {
		u64(128): u64(voidptr(raw_encoding_get_container))
		u64(192): u64(voidptr(raw_encoding_get_raw))
	} {
		for i, op in [u32(0xa9bf7bfd), 0xaa0803e2, 0xaa1403e3, 0x580000b0, 0xd63f0200, 0xd28acf15,
			0xa8c17bfd, 0xd65f03c0]! {
			write32(code + offset + u64(i * 4), op)
		}
		unsafe { *(&u64(code + offset + 32)) = target }
	}
	for i, op in [u32(0xa9bf7bfd), 0xaa1403e3, 0xaa1503e4, 0x580000b0, 0xd63f0200, 0xaa0003f5,
		0xa8c17bfd, 0xd65f03c0]! {
		write32(code + 256 + u64(i * 4), op)
	}
	unsafe { *(&u64(code + 288)) = u64(voidptr(raw_encoding_encode)) }
	write32(code + 384, 0xdac10020)
	write32(code + 388, 0xd65f03c0)
	write32(code + 400, 0xdac10820)
	write32(code + 404, 0xd65f03c0)
}

fn raw_encoding_api(native bool, code u64) RawEncodingApi {
	$if macos {
		if native {
			core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
			return RawEncodingApi{ native: true, code: code, entry: u64(C.dlsym(core, raw_encoding_symbol[1..].str)) }
		}
	}
	return RawEncodingApi{ code: code, entry: raw_encoding_lookup() }
}

fn raw_encoding_case(api RawEncodingApi, bits u64, incoming u64, boxed bool, at_end bool, failing bool, missing bool) {
	page := usize(C.getpagesize())
	span := u64(C.mmap(unsafe { nil }, page * 5, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert span != u64(-1)
	defer { assert C.munmap(voidptr(span), page * 5) == 0 }
	data := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert data != u64(-1)
	defer { assert C.munmap(voidptr(data), page) == 0 }
	assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
	assert C.mprotect(voidptr(span + u64(page * 3)), page, C.PROT_READ | C.PROT_WRITE) == 0
	mut owner := u64(0)
	mut error_owner := u64(0)
	$if macos {
		if api.native {
			owner = u64(C.CFStringCreateMutable(unsafe { nil }, 0))
			error_owner = u64(C.CFStringCreateMutable(unsafe { nil }, 0))
		}
	}
	if !api.native {
		owner = owned_string('borrowed RawRepresentable and owned encoding container')
		error_owner = owned_string('original owned encoding error')
	}
	defer {
		raw_encoding_drop(api, owner)
		raw_encoding_drop(api, error_owner)
	}
	mut s := RawEncodingState{
		api:         api
		owner:       owner
		error_owner: error_owner
		bits:        bits
		incoming:    incoming
		failing:     failing
		missing:     missing
		reenter:     !api.native && bits == 0x8000000000000000 && !at_end
	}
	s.metadata = data + 16
	s.encoder_metadata = data + 64
	s.container_metadata = data + 128
	s.raw_table = data + 192
	s.encoder_table = data + 256
	s.container_table = data + 320
	encoder_vwt := data + 448
	container_vwt := data + 576
	mut encoder_pointer := encoder_vwt
	mut container_pointer := container_vwt
	mut getter := api.code + 128
	mut raw := api.code + 192
	mut encode := api.code + 256
	mut destroy := u64(voidptr(raw_encoding_destroy))
	$if macos {
		if api.native {
			code := unsafe { RawEncodingSign(voidptr(api.code + 384)) }
			pointer := unsafe { RawEncodingSign(voidptr(api.code + 400)) }
			encoder_pointer = pointer(encoder_vwt, (s.encoder_metadata - 8) | (u64(11839) << 48))
			container_pointer = pointer(container_vwt, (s.container_metadata - 8) | (u64(11839) << 48))
			getter = code(getter, (s.encoder_table + 40) | (u64(59009) << 48))
			raw = code(raw, (s.raw_table + 24) | (u64(15752) << 48))
			encode = code(encode, (s.container_table + 56) | (u64(24649) << 48))
			destroy = code(destroy, (container_vwt + 8) | (u64(1272) << 48))
		}
	}
	unsafe {
		*(&u64(s.encoder_metadata)) = 0x200
		*(&u64(s.container_metadata)) = 0x200
		*(&u64(s.metadata + 8)) = u64(&s)
		*(&u64(s.encoder_metadata - 8)) = encoder_pointer
		*(&u64(s.container_metadata - 8)) = container_pointer
		*(&u64(s.raw_table + 8)) = span
		*(&u64(s.raw_table + 24)) = raw
		*(&u64(s.encoder_table + 40)) = getter
		*(&u64(s.container_table + 56)) = if missing { u64(0) } else { encode }
		*(&u64(encoder_vwt + 8)) = u64(voidptr(raw_encoding_destroy))
		*(&u64(container_vwt + 8)) = destroy
		*(&u64(encoder_vwt + 64)) = if boxed { u64(32) } else { u64(16) }
		*(&u64(encoder_vwt + 72)) = if boxed { u64(32) } else { u64(16) }
		*(&u32(encoder_vwt + 80)) = if boxed { u32(0x02030007) } else { u32(0x02010007) }
		*(&u64(container_vwt + 64)) = 16
		*(&u64(container_vwt + 72)) = 16
		*(&u32(container_vwt + 80)) = 0x02010007
	}
	encoder := span + u64(page) + if at_end { u64(page) - 40 } else { u64(0) }
	s.source = span + u64(page * 3) + if at_end { u64(page) - 1 } else { u64(0) }
	box := span + u64(page) + 128
	s.encoder_self = if boxed { box + 16 } else { encoder }
	unsafe {
		*(&u64(box + 16)) = u64(&s)
		*(&u64(box + 24)) = 0x12345678
		*(&u64(encoder)) = if boxed { box } else { u64(&s) }
		*(&u64(encoder + 8)) = 0x12345678
		*(&u64(encoder + 16)) = 0x87654321
		*(&u64(encoder + 24)) = s.encoder_metadata
		*(&u64(encoder + 32)) = s.encoder_table
		*(&u8(s.source)) = 0x79
	}
	assert C.mprotect(voidptr(data), page, C.PROT_READ) == 0
	assert C.mprotect(voidptr(span + u64(page)), page, C.PROT_READ) == 0
	assert C.mprotect(voidptr(span + u64(page * 3)), page, C.PROT_READ) == 0
	args := [encoder, s.metadata, span, s.raw_table]!
	mut observed := [u64(0xaaaa), 0, 0, 0xbbbb]!
	if missing {
		assert !api.native
		if _ := swift_raw_integer_encoding_checked(encoder, s.metadata, span, s.raw_table, s.source, incoming) {
			assert false
		}
	} else {
		invoke := unsafe { RawEncodingInvoke(voidptr(api.code)) }
		invoke(api.entry, unsafe { &args[0] }, s.source, incoming, unsafe { &observed[1] })
		assert observed == [u64(0xaaaa), s.source, if failing { error_owner } else { u64(0) },
			0xbbbb]!
	}
	assert s.getters == 1 && s.raw_getters == 1 && s.encodes == if missing { 0 } else { 1 }
	assert s.drops == 1 && raw_encoding_refs(api, owner) == 1
	assert raw_encoding_refs(api, error_owner) == if failing && !missing { 2 } else { 1 }
	if failing && !missing { raw_encoding_drop(api, error_owner) }
	assert unsafe { *(&u8(s.source)) } == 0x79 && read64(encoder) == if boxed {
		box
	} else {
		u64(unsafe { &s })
	}
}

fn raw_encoding_values(api RawEncodingApi) {
	for bits in [u64(0), 1, ~u64(0), 0x8000000000000000, 0x7fffffffffffffff, 0x1122334455667788,
		0x8000000000000001, 0xffffffff00000000]! {
		for incoming in [u64(0), 0x1357]! {
			for boxed in [false, true]! {
				for at_end in [false, true]! {
					for failing in [false, true]! {
						raw_encoding_case(api, bits, incoming, boxed, at_end, failing, false)
					}
				}
			}
		}
	}
}

fn raw_encoding_worker(api RawEncodingApi) {
	raw_encoding_case(api, 0x8000000000000000, 0x1357, true, false, true, false)
}

fn raw_encoding_reject(guard u64) {
	for args in [[u64(0), guard, guard]!, [guard, u64(1), guard]!, [guard, guard, u64(0)]!]! {
		if _ := swift_raw_integer_encoding_checked(args[0], args[1], guard, args[2], 0, 0) {
			assert false
		}
	}
	for table in [u64(0), 1, ~u64(7)]! {
		if _ := swift_raw_encoding_callback_checked(table, 24) {
			assert false
		}
	}
	mut table := [u64(0), 0, 0, 0]!
	for bad in [u64(0), 1]! {
		table[3] = bad
		if _ := swift_raw_encoding_callback_checked(u64(unsafe { &table[0] }), 24) {
			assert false
		}
	}
	for value in [u64(0), 1, ~u64(7)]! {
		if _ := swift_raw_encoding_value_checked(value) {
			assert false
		}
	}
	ios_runtime.swift_concurrency_retired = true
	if _ := swift_raw_integer_encoding_checked(guard, guard, guard, guard, guard, 0) {
		assert false
	}
	ios_runtime.swift_concurrency_retired = false
}

fn test_swift_raw_integer_encoding() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	guard := u64(C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1) && guard != u64(-1)
	raw_encoding_emit(code)
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 408))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	$if macos {
		raw_encoding_values(raw_encoding_api(true, code))
		println('NATIVE-RAW-INTEGER-ENCODING: 128 cases; container/getter/Int witness/destroy order, exact signed Int bits, original owned error and incoming x21, borrowed inline/boxed Encoder, one-byte readonly Self, protected unused witnesses and clobbering nonthrowing getters')
	}
	for _ in 0 .. 2 {
		objc_start()
		baseline := ios_runtime.live
		api := raw_encoding_api(false, code)
		raw_encoding_values(api)
		for boxed in [false, true]! { raw_encoding_case(api, 1, 0, boxed, false, false, true) }
		raw_encoding_reject(guard)
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn raw_encoding_worker(api) }
		workers.wait()
		unsafe { workers.free() }
		for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/swift/libswiftFoundation.dylib']! {
			assert runtime_symbol(library, raw_encoding_symbol) == none
		}
		assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', raw_encoding_symbol[1..]) == none
		assert ios_runtime.live == baseline
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
	assert C.munmap(voidptr(code), page) == 0 && C.munmap(voidptr(guard), page) == 0
	println('IOS-RAW-INTEGER-ENCODING: protocol-dispatched Int encoding, exact owned container cleanup on success/throw/dispatch failure, original error transfer, borrowed Encoder/Self, readonly guarded records, unused conformance/associated metadata, eight workers, reentrant callbacks and two drained/unmapped lifetimes; boxed mutable containers remain unsupported')
}
