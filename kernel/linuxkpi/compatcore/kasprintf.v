// SPDX-License-Identifier: GPL-2.0-only
// Linux 6.6.157 lib/kasprintf.c; Copyright (C) 1991, 1992 Linus Torvalds.
@[translated]
module compatcore

import abiargs

#include "linuxkpi_kasprintf_v_primitives.h"

fn C.vinix_linuxkpi_warn_format(&C.vks_const_char, i32, &C.vks_const_char, ...)

const format_alloc_limit = usize(2147483646)

// The cursor is already addressable on every supported native ABI. Its copied
// pointers borrow the caller's still-live register-save and overflow storage.
@[export: 'vkf_kvasprintf']
pub fn format_alloc_vasprintf(flags u32, format voidptr, cursor voidptr) voidptr {
	unsafe {
		mut copied := [4]u64{}
		C.memcpy(&copied[0], cursor, abiargs.native_size())
		mut measured := FormatOutput{
			buf: &char(nil)
			count_checked: true
			count_limit: format_alloc_limit
		}
		vkr_format_parse(&measured, &char(format), &copied[0])
		if measured.count_overflow { return nil }
		first := measured.position
		capacity := first + usize(1)
		result := &char(C.kmalloc(capacity, flags))
		if is_null(result) { return nil }
		mut written := FormatOutput{
			buf: result
			size: capacity
			count_checked: true
			count_limit: format_alloc_limit
		}
		vkr_format_parse(&written, &char(format), cursor)
		result[if written.position < capacity { written.position } else { capacity - 1 }] = 0
		// Ordinary mismatches retain Linux's first-sized terminated allocation.
		// A second-pass count overflow is outside the supported length domain;
		// UINT_MAX reports that bounded condition without narrowing a wrapped count.
		second := if written.count_overflow { u32(-1) } else { u32(written.position) }
		if u32(first) != second {
			// The native translation has no imported C source-line identity.
			C.vinix_linuxkpi_warn_format(&C.vks_const_char(c'kernel/linuxkpi/compatcore/kasprintf.v'), 0,
				&C.vks_const_char(c'different return values (%u and %u) from vsnprintf("%s", ...)'),
				u32(first), second, &char(format))
		}
		return voidptr(result)
	}
}

@[export: 'vkf_kvasprintf_const']
pub fn format_alloc_vasprintf_const(flags u32, format voidptr, cursor voidptr) voidptr {
	unsafe {
		fmt := &char(format)
		if is_null(strchr(fmt, i32(`%`))) {
			return const_string_kstrdup(format, flags)
		}
		if fmt[0] == char(`%`) && fmt[1] == char(`s`) && fmt[2] == 0 {
			return const_string_kstrdup(vkr_arg_pointer(cursor), flags)
		}
		return format_alloc_vasprintf(flags, format, cursor)
	}
}

// The instruction-only variadic prologue has two named arguments and appends
// its canonical cursor; no va_list parameter normalization is needed here.
@[export: 'vinix_linuxkpi_kasprintf_entry']
pub fn format_alloc_asprintf_entry(flags u32, format voidptr, cursor voidptr) voidptr {
	return format_alloc_vasprintf(flags, format, cursor)
}
