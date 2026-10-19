// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Both native platforms use signed, four-byte wchar_t. Darwin ARM64's
// va_list is a pointer to anonymous eight-byte stack slots; AAPCS64 also
// carries register-save ranges. Empty ranges make libc consume those slots.
fn C.vswscanf(voidptr, voidptr, voidptr) i32
fn C.wcsrtombs(voidptr, voidptr, usize, voidptr) usize
fn C.ios_swscanf()
type WideScanNative = fn (voidptr, voidptr, voidptr) i32
type WideScanEncode = fn (voidptr, voidptr, usize, voidptr) usize

// Darwin long double is double, whereas Linux ARM64 uses sixteen bytes.
// Rewrite L floats and strip h on narrow character conversions, where musl
// otherwise selects a different destination layout. Skip literals/scansets.
// The common game formats borrow the original string without allocating.
fn wide_scan_format(format &i32) &i32 {
	mut index := usize(0)
	mut removed := usize(0)
	mut length := usize(0)
	mut copy := &i32(unsafe { nil })
	for unsafe { format[index] } != 0 {
		if unsafe { format[index] } != `%` { index++; continue }
		index++
		if unsafe { format[index] } == `%` { index++; continue }
		for unsafe { format[index] } == `*` || (unsafe { format[index] } >= `0` && unsafe { format[index] } <= `9`)
			|| unsafe { format[index] } == `$` { index++ }
		long_double := unsafe { format[index] } == `L` && unsafe { format[index + 1] } in [i32(`a`), `A`, `e`, `E`, `f`, `F`, `g`, `G`]!
		narrow_char := unsafe { format[index] } == `h` && unsafe { format[index + 1] } in [i32(`c`), `s`, `[`]!
		if long_double || narrow_char {
			if copy == unsafe { nil } {
				length = C.wcslen(format)
				if length > (~usize(0) / 4) - 1 { darwin_set_errno(12); return unsafe { nil } }
				copy = C.malloc((length + 1) * 4)
				if copy == unsafe { nil } { darwin_set_errno(12); return unsafe { nil } }
				C.memcpy(copy, format, (length + 1) * 4)
			}
			if long_double {
				unsafe { copy[index - removed] = `l` }
			} else {
				C.memmove(unsafe { voidptr(&copy[index - removed]) }, unsafe { voidptr(&copy[index + 1 - removed]) }, (length - index) * 4)
				removed++
			}
		}
		for unsafe { format[index] } in [i32(`h`), `l`, `j`, `z`, `t`, `L`, `q`]! { index++ }
		if unsafe { format[index] } == `[` {
			index++
			if unsafe { format[index] } == `^` { index++ }
			if unsafe { format[index] } == `]` { index++ }
			for unsafe { format[index] } != 0 && unsafe { format[index] } != `]` { index++ }
		}
		if unsafe { format[index] } != 0 { index++ }
	}
	return if copy == unsafe { nil } { format } else { copy }
}

@[export: 'ios_swscanf_stack']
fn darwin_vswscanf(input &i32, format &i32, stack voidptr) i32 {
	native := unsafe { WideScanNative(voidptr(C.vswscanf)) }
	$if macos { return native(input, format, stack) }
	$if linux {
		address := C.ios_errno_address()
		saved := unsafe { *address }
		// Darwin converts the complete input in the current locale before
		// assigning anything, even for %ls or an early matching failure.
		mut source := voidptr(input)
		state := C.__builtin_alloca(sizeof(C.mbstate_t))
		C.memset(state, 0, sizeof(C.mbstate_t))
		encode_input := unsafe { WideScanEncode(voidptr(C.wcsrtombs)) }
		if encode_input(unsafe { nil }, unsafe { voidptr(&source) }, 0, state) == ~usize(0) {
			darwin_set_errno(92)
			return -1
		}
		converted := wide_scan_format(format)
		if converted == unsafe { nil } { return -1 }
		mut arguments := [u64(stack), 0, 0, 0]!
		unsafe { *address = 0 }
		result := native(input, converted, unsafe { voidptr(&arguments[0]) })
		error_code := unsafe { *address }
		if voidptr(converted) != voidptr(format) { unsafe { C.free(converted) } }
		// musl's integer scanner sets EINVAL for a matching failure (including
		// empty input). Darwin returns the count/EOF and leaves errno alone.
		unsafe { *address = if error_code == 0 || error_code == C.EINVAL { saved } else if error_code == C.EILSEQ { 92 } else { i32(darwin_native_error(int(error_code))) } }
		return result
	}
}
