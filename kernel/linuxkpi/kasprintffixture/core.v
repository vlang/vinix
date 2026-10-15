// SPDX-License-Identifier: GPL-2.0-only
// Genuine compiler va_list origins; all cursor arithmetic remains V.
@[translated]
module kasprintffixture

import abiargs

#include "linuxkpi_kasprintf_fixture_v_contract.h"

@[typedef]
struct C.vkf_native_va {}

@[typedef]
struct C.vks_const_char {}

@[typedef]
struct C.vks_const_void {}

struct C.va_format {
mut:
	fmt &C.vks_const_char
	va  voidptr
}

fn C.va_start(C.vkf_native_va, &C.vks_const_char)
fn C.va_end(C.vkf_native_va)
fn C.vkf_va_parameter(C.vkf_native_va) voidptr
fn C.vinix_kasprintf_va_storage(C.vkf_native_va) voidptr
fn C.vinix_kasprintf_descriptor_storage(C.va_format) voidptr
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.kvasprintf(u32, &C.vks_const_char, C.vkf_native_va) &char
fn C.kvasprintf_const(u32, &C.vks_const_char, C.vkf_native_va) &C.vks_const_char
fn C.kasprintf(u32, &C.vks_const_char, ...) &char
fn C.vkf_kvasprintf(u32, voidptr, voidptr) voidptr
fn C.vkf_kvasprintf_const(u32, voidptr, voidptr) voidptr
fn C.kfree_const(&C.vks_const_void)
fn C.kmalloc(usize, u32) voidptr
fn C.vinix_kasprintf_gfp_kernel() u32
fn C.vinix_linuxkpi_is_kernel_rodata(&C.vks_const_void) bool

// copied is a snapshot of this genuine compiler cursor, never a constructed
// va_list. Its pointers borrow this live variadic frame until va_end below.
fn genuine(mode u32, flags u32, slots u32, state &u32, fmt &C.vks_const_char, ...) voidptr {
	unsafe {
		ap := C.vkf_native_va{}
		C.va_start(ap, fmt)
		cursor := C.vkf_va_parameter(ap)
		mut before := [4]u64{}
		mut expected := [4]u64{}
		C.memcpy(&before[0], cursor, abiargs.native_size())
		C.memcpy(&expected[0], cursor, abiargs.native_size())
		// Typed aggregate va_list is by value outside SysV64; canonical calls always
		// mutate the actual origin. Advancing copied slots cannot alter the origin.
		if mode >= 2 || C.VINIX_VA_ABI == 3 {
			for _ in u32(0) .. slots { abiargs.word(&expected[0]) }
		}
		result := if mode == 0 {
			voidptr(C.kvasprintf(flags, fmt, ap))
		} else if mode == 1 {
			voidptr(C.kvasprintf_const(flags, fmt, ap))
		} else if mode == 2 {
			C.vkf_kvasprintf(flags, voidptr(fmt), cursor)
		} else {
			C.vkf_kvasprintf_const(flags, voidptr(fmt), cursor)
		}
		mut after := [4]u64{}
		C.memcpy(&after[0], cursor, abiargs.native_size())
		mut matches := true
		mut unchanged := true
		for index in usize(0) .. abiargs.native_size() / 8 {
			if after[index] != expected[index] { matches = false }
			if after[index] != before[index] { unchanged = false }
		}
		*state = u32(matches) | (u32(unchanged) << 1)
		C.va_end(ap)
		return result
	}
}

// The original descriptor borrows this live compiler-created nested cursor.
// Both outer formatting passes must leave that cursor byte-for-byte intact.
fn genuine_nested(flags u32, state &u32, fmt &C.vks_const_char, ...) voidptr {
	unsafe {
		ap := C.vkf_native_va{}
		C.va_start(ap, fmt)
		cursor := C.vkf_va_parameter(ap)
		mut before := [4]u64{}
		C.memcpy(&before[0], cursor, abiargs.native_size())
		mut descriptor := C.va_format{}
		descriptor.fmt = fmt
		descriptor.va = C.vinix_kasprintf_va_storage(ap)
		result := C.kasprintf(flags, &C.vks_const_char(c'outer<%pV>tail'), C.vinix_kasprintf_descriptor_storage(descriptor))
		mut after := [4]u64{}
		C.memcpy(&after[0], cursor, abiargs.native_size())
		mut same := true
		for index in usize(0) .. abiargs.native_size() / 8 {
			if before[index] != after[index] { same = false }
		}
		*state = if same { u32(3) } else { u32(0) }
		C.va_end(ap)
		return voidptr(result)
	}
}

@[export:'vinix_linuxkpi_kasprintf_fixture_run']
pub fn run(which u32, flags u32, source voidptr, state &u32) voidptr {
	unsafe {
		*state = 0
		if which == 0 {
			return genuine(0, flags, 8, state, &C.vks_const_char(c'%u/%s/%u/%u/%u/%u/%u/%u'), u32(1), c'cursor', u32(2), u32(3), u32(4), u32(5), u32(6), u32(7))
		}
		// This call enters the actual public named-two assembly capture.
		if which == 1 {
			return voidptr(C.kasprintf(flags, &C.vks_const_char(c'%u/%s/%u/%u/%u/%u/%u/%u'), u32(1), c'cursor', u32(2), u32(3), u32(4), u32(5), u32(6), u32(7)))
		}
		if which == 2 {
			return genuine(0, flags, 10, state, &C.vks_const_char(c'%*.*s|%+d|%d|%ld|%lld|%zu|%#x|%c|%%'), i32(-6), i32(3), source, i32(7), i32(-8), i64(-1234567890), i64(-9223372036854775807), usize(1234), u32(42), i32(`!`))
		}
		if which == 3 { return genuine(0, flags, 0, state, &C.vks_const_char(c'')) }
		if which == 4 { return genuine(0, flags, 1, state, &C.vks_const_char(c'%s'), source) }
		if which == 5 { return genuine(1, flags, 1, state, &C.vks_const_char(c'%s'), source) }
		if which == 6 { return genuine(1, flags, 0, state, &C.vks_const_char(source)) }
		if which == 7 {
			return genuine(2, flags, 8, state, &C.vks_const_char(c'%u/%s/%u/%u/%u/%u/%u/%u'), u32(1), c'cursor', u32(2), u32(3), u32(4), u32(5), u32(6), u32(7))
		}
		if which == 8 { return genuine(3, flags, 1, state, &C.vks_const_char(c'%s'), source) }
		if which == 9 { return genuine(3, flags, 0, state, &C.vks_const_char(source)) }
		// An ordinary allocation failure must preserve its genuine original cursor.
		if which == 10 {
			return genuine(0, flags, 0, state, &C.vks_const_char(c'%u/%s/%u/%u/%u/%u/%u/%u'), u32(1), c'cursor', u32(2), u32(3), u32(4), u32(5), u32(6), u32(7))
		}
		if which == 11 {
			return genuine(2, flags, 0, state, &C.vks_const_char(c'%u/%s/%u/%u/%u/%u/%u/%u'), u32(1), c'cursor', u32(2), u32(3), u32(4), u32(5), u32(6), u32(7))
		}
		if which == 12 {
			return genuine_nested(flags, state, &C.vks_const_char(c'%u/%s/%u/%u/%u/%u/%u/%u'), u32(11), c'nested', u32(22), u32(33), u32(44), u32(55), u32(66), u32(77))
		}
		return nil
	}
}

@[export:'vinix_linuxkpi_kasprintf_fixture_overflow']
pub fn overflow(flags u32, state &u32) bool {
	unsafe {
		mut format := [2314]u8{}
		for part in 0 .. 257 {
			offset := part * 9
			format[offset] = `%`
			format[offset + 1] = `8`
			format[offset + 2] = `3`
			format[offset + 3] = `8`
			format[offset + 4] = `8`
			format[offset + 5] = `6`
			format[offset + 6] = `0`
			format[offset + 7] = `7`
			format[offset + 8] = `u`
		}
		format[2313] = 0
		format_ptr := voidptr(&format[0])
		result := genuine(0, flags, 0, state, &C.vks_const_char(format_ptr), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0), u32(0))
		defer { if result != format_ptr { C.kfree_const(&C.vks_const_void(result)) } }
		return result == nil && *state == 3
	}
}

@[export:'vinix_linuxkpi_kasprintf_fixture_free']
pub fn free(ptr voidptr) {
	unsafe { C.kfree_const(&C.vks_const_void(ptr)) }
}

@[export:'vinix_linuxkpi_kasprintf_fixture_alloc']
pub fn alloc(size usize) voidptr { return C.kmalloc(size, C.vinix_kasprintf_gfp_kernel()) }

@[export:'vinix_linuxkpi_kasprintf_fixture_gfp']
pub fn gfp() u32 { return C.vinix_kasprintf_gfp_kernel() }

@[export:'vinix_linuxkpi_kasprintf_fixture_literal']
pub fn literal() voidptr { return unsafe { voidptr(c'vinix-format-constant') } }

@[export:'vinix_linuxkpi_kasprintf_fixture_rodata']
pub fn rodata(ptr voidptr) bool {
	return unsafe { C.vinix_linuxkpi_is_kernel_rodata(&C.vks_const_void(ptr)) }
}
