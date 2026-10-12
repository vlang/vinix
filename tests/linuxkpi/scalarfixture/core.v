// SPDX-License-Identifier: GPL-2.0-or-later
// Calls the real compiler macros and production exports; no substitute bodies.
@[translated]
module scalarfixture

#include "scalar_v_contract.h"
@[typedef]
struct C.vsh_constp {}

@[typedef]
struct C.vsh_volatile_u16 {}

@[typedef]
struct C.vsh_volatile_u32 {}

@[typedef]
struct C.vsh_volatile_u64 {}

@[typedef]
struct C.vsh_umode {}

@[typedef]
struct C.vsh_error_calls {
	cast     fn (C.vsh_constp) voidptr
	create   fn (isize) voidptr
	decode   fn (C.vsh_constp) isize
	classify fn (C.vsh_constp) bool
}

struct C.rlimit {
mut:
	rlim_cur usize
	rlim_max usize
}

struct C.rlimit64 {
mut:
	rlim_cur u64
	rlim_max u64
}

fn C.assert(bool)
fn C.puts(&char) i32
fn C.__atomic_store_n(voidptr, ...)
fn C.upper_32_bits(...) u32
fn C.lower_32_bits(...) u32
fn C.ERR_CAST(C.vsh_constp) voidptr
fn C.ERR_PTR(isize) voidptr
fn C.PTR_ERR(C.vsh_constp) isize
fn C.IS_ERR(C.vsh_constp) bool
fn C.vsh_as_const(voidptr) C.vsh_constp

@[c_extern]
__global C.RLIM_INFINITY usize

@[c_extern]
__global C.RLIM_NLIMITS u32

@[c_extern]
__global C.RLIMIT_CPU u32

@[c_extern]
__global C.RLIMIT_FSIZE u32

@[c_extern]
__global C.RLIMIT_DATA u32

@[c_extern]
__global C.RLIMIT_STACK u32

@[c_extern]
__global C.RLIMIT_CORE u32

@[c_extern]
__global C.RLIMIT_RSS u32

@[c_extern]
__global C.RLIMIT_NPROC u32

@[c_extern]
__global C.RLIMIT_NOFILE u32

@[c_extern]
__global C.RLIMIT_MEMLOCK u32

@[c_extern]
__global C.RLIMIT_AS u32

@[c_extern]
__global C.RLIMIT_LOCKS u32

@[c_extern]
__global C.RLIMIT_SIGPENDING u32

@[c_extern]
__global C.RLIMIT_MSGQUEUE u32

@[c_extern]
__global C.RLIMIT_NICE u32

@[c_extern]
__global C.RLIMIT_RTPRIO u32

@[c_extern]
__global C.RLIMIT_RTTIME u32

fn once16(count &u32, value u16) u16 {
	unsafe {
		(*count)++
		return value
	}
}

fn once32(count &u32, value u32) u32 {
	unsafe {
		(*count)++
		return value
	}
}

fn once64(count &u32, value u64) u64 {
	unsafe {
		(*count)++
		return value
	}
}

@[direct_array_access]
fn extractors() {
	unsafe {
		values := [u64(0), u64(0xffff), u64(0x10000), u64(0xffffffff), u64(1) << 32, u64(1) << 63,
			~u64(0)]!
		low := [u32(0), u32(0xffff), u32(0x10000), u32(0xffffffff), u32(0), u32(0), u32(0xffffffff)]!
		high := [u32(0), u32(0), u32(0), u32(0), u32(1), u32(0x80000000), u32(0xffffffff)]!
		mut narrow := C.vsh_volatile_u16{}
		mut word := C.vsh_volatile_u32{}
		mut wide := C.vsh_volatile_u64{}
		for index in 0 .. 7 {
			C.__atomic_store_n(&narrow, u16(values[index]), i32(0))
			C.__atomic_store_n(&word, u32(values[index]), i32(0))
			C.__atomic_store_n(&wide, values[index], i32(0))
			C.assert(C.lower_32_bits(narrow) == u32(u16(values[index])))
			C.assert(C.upper_32_bits(narrow) == 0)
			C.assert(C.lower_32_bits(word) == low[index])
			C.assert(C.upper_32_bits(word) == 0)
			C.assert(C.lower_32_bits(wide) == low[index])
			C.assert(C.upper_32_bits(wide) == high[index])
			mut count := u32(0)
			C.assert(C.lower_32_bits(once16(&count, u16(values[index]))) == u32(u16(values[index])) && count == 1)
			count = 0
			C.assert(C.upper_32_bits(once16(&count, u16(values[index]))) == 0 && count == 1)
			count = 0
			C.assert(C.lower_32_bits(once32(&count, u32(values[index]))) == low[index] && count == 1)
			count = 0
			C.assert(C.upper_32_bits(once32(&count, u32(values[index]))) == 0 && count == 1)
			count = 0
			C.assert(C.lower_32_bits(once64(&count, values[index])) == low[index] && count == 1)
			count = 0
			C.assert(C.upper_32_bits(once64(&count, values[index])) == high[index] && count == 1)
		}
		// Original signed operands keep arithmetic right-shift semantics.
		C.assert(C.upper_32_bits(i64(-1)) == ~u32(0))
		C.assert(C.lower_32_bits(i64(-1)) == ~u32(0))
		C.assert(C.upper_32_bits(i32(-1)) == ~u32(0))
		C.assert(C.upper_32_bits(i64(-9223372036854775807) - 1) == u32(0x80000000))
	}
}

@[direct_array_access]
fn error_casts() {
	unsafe {
		calls := C.vsh_error_calls{ cast: C.ERR_CAST, create: C.ERR_PTR, decode: C.PTR_ERR, classify: C.IS_ERR }
		mut object := u64(0x123456789abcdef0)
		readonly := C.vsh_as_const(&object)
		C.assert(calls.cast(C.vsh_as_const(nil)) == nil)
		C.assert(calls.cast(readonly) == voidptr(&object))
		C.assert(object == u64(0x123456789abcdef0))
		errors := [isize(-1), isize(-4095), isize(-4096)]!
		for code in errors {
			original := calls.create(code)
			C.assert(usize(original) == usize(code))
			converted := calls.cast(C.vsh_as_const(original))
			C.assert(converted == original && calls.decode(C.vsh_as_const(converted)) == code)
			if code >= -4095 { C.assert(calls.classify(C.vsh_as_const(converted))) }
			// -4096 checks identity only; it is outside the original MAX_ERRNO domain.
		}
		for _ in 0 .. 1024 { C.assert(calls.cast(readonly) == voidptr(&object)) }
	}
}

@[direct_array_access]
fn resource_types() {
	unsafe {
		ids := [C.RLIMIT_CPU, C.RLIMIT_FSIZE, C.RLIMIT_DATA, C.RLIMIT_STACK, C.RLIMIT_CORE,
			C.RLIMIT_RSS, C.RLIMIT_NPROC, C.RLIMIT_NOFILE, C.RLIMIT_MEMLOCK, C.RLIMIT_AS,
			C.RLIMIT_LOCKS, C.RLIMIT_SIGPENDING, C.RLIMIT_MSGQUEUE, C.RLIMIT_NICE, C.RLIMIT_RTPRIO,
			C.RLIMIT_RTTIME]!
		for index in 0 .. 16 { C.assert(ids[index] == u32(index)) }
		C.assert(C.RLIM_NLIMITS == 16 && C.RLIM_INFINITY == ~usize(0))
		mut mode := C.vsh_umode{}
		C.__atomic_store_n(&mode, u16(0xffff), i32(0))
		C.assert(usize(mode) == 65535 && sizeof(C.vsh_umode) == 2)
		mutable := C.rlimit{ rlim_cur: 0, rlim_max: C.RLIM_INFINITY }
		immutable := C.rlimit64{ rlim_cur: 0, rlim_max: ~u64(0) }
		C.assert(mutable.rlim_cur == 0 && mutable.rlim_max == ~usize(0))
		C.assert(immutable.rlim_cur == 0 && immutable.rlim_max == ~u64(0))
	}
}

@[export: 'main']
pub fn run() i32 {
	extractors()
	error_casts()
	resource_types()
	C.puts(c'PASS: native scalar extraction/evaluation, ERR_CAST identity/const ABI, umode and original resource constants/layouts')
	return 0
}
