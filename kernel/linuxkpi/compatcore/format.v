// SPDX-License-Identifier: GPL-2.0-only
// Linux 6.6.157 number/string/pointer rules, derived from lib/vsprintf.c.
// Copyright (C) 1991, 1992 Linus Torvalds, Lars Wirzenius.
@[translated]
module compatcore

#include "linuxkpi_runtime_v_primitives.h"


@[c: '__atomic_compare_exchange_n']
fn C.vkr_compare32(&u32, &u32, u32, bool, i32, i32) bool

__global (
	vkr_pointer_key       [2]u64
	vkr_pointer_key_state u32
)

struct FormatSpec {
mut:
	width     i32
	precision i32
	flags     u32
	base      u32
}

struct FormatOutput {
mut:
	buf      &char
	size     usize
	position usize
	status   u32
	stop     bool
}

@[export: 'vkr_format_key']
pub fn vkr_format_key(key &u64) i32 {
	unsafe {
		if usize(key) == 0 { return -22 }
		if !C.vinix_linuxkpi_may_sleep() { return -11 }
		mut expected := u32(0)
		if !C.vkr_compare32(&vkr_pointer_key_state, &expected, 1, false, 4, 2) {
			return if expected == 2 { i32(-114) } else { i32(-11) }
		}
		vkr_pointer_key[0] = key[0]
		vkr_pointer_key[1] = key[1]
		C.vkp_store32(&vkr_pointer_key_state, 2, 3)
		return 0
	}
}

fn vkrf_alnum(c u8) bool {
	return (c >= `0` && c <= `9`) || (c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`)
}

fn vkrf_bytes(out &FormatOutput, data &char, len usize) {
	unsafe {
		if out.position < out.size {
			available := out.size - out.position
			copy := if len < available { len } else { available }
			if copy != 0 { C.memcpy(out.buf + out.position, data, copy) }
		}
		out.position += len
	}
}

fn vkrf_pad(out &FormatOutput, c u8, len usize) {
	unsafe {
		if out.position < out.size {
			available := out.size - out.position
			copy := if len < available { len } else { available }
			if copy != 0 { C.memset(out.buf + out.position, i32(c), copy) }
		}
		out.position += len
	}
}

fn vkrf_char(out &FormatOutput, c u8) {
	mut byte := c
	unsafe { vkrf_bytes(out, &char(&byte), 1) }
}

fn vkrf_number(out &FormatOutput, input u64, original FormatSpec) {
	unsafe {
		digits := &char(c'0123456789ABCDEF')
		mut reversed := [24]u8{}
		mut value := input
		mut spec := original
		mut sign := u8(0)
		mut count := u32(0)
		mut width := spec.width
		mut precision := spec.precision
		zero := value == 0
		prefix := (spec.flags & 64) != 0 && spec.base != 10
		if (spec.flags & 2) != 0 { spec.flags &= ~u32(16) }
		if (spec.flags & 1) != 0 {
			if i64(value) < 0 {
				sign = `-`
				value = u64(0) - value
			} else if (spec.flags & 4) != 0 {
				sign = `+`
			} else if (spec.flags & 8) != 0 {
				sign = ` `
			}
			if sign != 0 { width-- }
		}
		if prefix {
			if spec.base == 16 {
				width -= 2
			} else if !zero {
				width--
			}
		}
		for {
			reversed[count] = u8(digits[value % spec.base]) | u8(spec.flags & 32)
			count++
			value /= spec.base
			if value == 0 { break }
		}
		if i32(count) > precision { precision = i32(count) }
		width -= precision
		if width > 0 && (spec.flags & (16 | 2)) == 0 {
			vkrf_pad(out, ` `, usize(width))
			width = 0
		}
		if sign != 0 { vkrf_char(out, sign) }
		if prefix {
			if spec.base == 16 || !zero { vkrf_char(out, `0`) }
			if spec.base == 16 { vkrf_char(out, `X` | u8(spec.flags & 32)) }
		}
		if width > 0 && (spec.flags & 2) == 0 {
			vkrf_pad(out, if (spec.flags & 16) != 0 { u8(`0`) } else { u8(` `) }, usize(width))
			width = 0
		}
		if precision > i32(count) { vkrf_pad(out, `0`, usize(precision - i32(count))) }
		for count != 0 {
			count--
			vkrf_char(out, reversed[count])
		}
		if width > 0 { vkrf_pad(out, ` `, usize(width)) }
	}
}

fn vkrf_string(out &FormatOutput, str &char, spec FormatSpec) {
	unsafe {
		mut len := usize(0)
		for (spec.precision < 0 || len < u32(spec.precision)) && str[len] != 0 { len++ }
		spaces := if spec.width > 0 && usize(spec.width) > len {
			usize(spec.width) - len
		} else {
			usize(0)
		}
		if (spec.flags & 2) == 0 { vkrf_pad(out, ` `, spaces) }
		vkrf_bytes(out, str, len)
		if (spec.flags & 2) != 0 { vkrf_pad(out, ` `, spaces) }
	}
}

fn vkrf_error(out &FormatOutput, text &char, original FormatSpec) {
	mut spec := original
	if spec.precision == -1 { spec.precision = 16 }
	vkrf_string(out, text, spec)
}

fn vkrf_is_err(ptr voidptr) bool { return u64(ptr) >= u64(-4095) }

fn vkrf_bad_pointer(out &FormatOutput, ptr voidptr, spec FormatSpec) bool {
	if usize(ptr) == 0 {
		vkrf_error(out, c'(null)', spec)
		return true
	}
	if usize(ptr) < 4096 || vkrf_is_err(ptr) {
		vkrf_error(out, c'(efault)', spec)
		return true
	}
	return false
}

fn vkrf_hex_address(out &FormatOutput, value u64, size u32) {
	vkrf_number(out, value, FormatSpec{ base: 16, width: i32(2 + 2 * size), precision: -1, flags: 64 | 32 | 16 })
}

fn vkrf_pointer_number(out &FormatOutput, value u64, original FormatSpec) {
	mut spec := original
	spec.base = 16
	spec.flags |= 32
	if spec.width == -1 {
		spec.width = 16
		spec.flags |= 16
	}
	vkrf_number(out, value, spec)
}

fn vkrf_pointer_id(out &FormatOutput, ptr voidptr, original FormatSpec) {
	unsafe {
		if usize(ptr) == 0 || vkrf_is_err(ptr) {
			vkrf_pointer_number(out, u64(ptr), original)
			return
		}
		if C.vkp_load32(&vkr_pointer_key_state, 2) != 2 {
			mut spec := original
			spec.width = 16
			vkrf_error(out, c'(____ptrval____)', spec)
			return
		}
		hash := vkr_pointer_hash(u64(ptr), &vkr_pointer_key[0])
		vkrf_pointer_number(out, hash & 0xffffffff, original)
	}
}

fn vkrf_decimal_spec() FormatSpec { return FormatSpec{ base: 10, width: 0, precision: -1 } }

fn vkrf_resource(out &FormatOutput, res voidptr, outer FormatSpec, original_decode bool) {
	unsafe {
		if vkrf_bad_pointer(out, res, outer) { return }
		flags := vkr_resource_flags(res)
		start := vkr_resource_start(res)
		end := vkr_resource_end(res)
		mut buf := [128]char{}
		mut local := FormatOutput{ buf: &buf[0], size: sizeof(buf) }
		mut spec := FormatSpec{ base: 16, width: 10, precision: -1, flags: 64 | 32 | 16 }
		mut decode := original_decode
		mut kind := &char(c'??? ')
		if (flags & 0x100) != 0 {
			kind = &char(c'io  ')
			spec.width = 6
		} else if (flags & 0x200) != 0 {
			kind = &char(c'mem ')
		} else if (flags & 0x400) != 0 {
			kind = &char(c'irq ')
			spec = vkrf_decimal_spec()
		} else if (flags & 0x800) != 0 {
			kind = &char(c'dma ')
			spec = vkrf_decimal_spec()
		} else if (flags & 0x1000) != 0 {
			kind = &char(c'bus ')
			spec.width = 2
			spec.flags &= ~u32(64)
		} else {
			decode = false
		}
		vkrf_char(&local, `[`)
		vkrf_bytes(&local, kind, 4)
		if decode && (flags & 0x20000000) != 0 {
			vkrf_bytes(&local, c'size ', 5)
			vkrf_number(&local, end - start + 1, spec)
		} else {
			vkrf_number(&local, start, spec)
			if start != end {
				vkrf_char(&local, `-`)
				vkrf_number(&local, end, spec)
			}
		}
		if decode {
			if (flags & 0x00100000) != 0 { vkrf_bytes(&local, c' 64bit', 6) }
			if (flags & 0x00002000) != 0 { vkrf_bytes(&local, c' pref', 5) }
			if (flags & 0x00200000) != 0 { vkrf_bytes(&local, c' window', 7) }
			if (flags & 0x10000000) != 0 { vkrf_bytes(&local, c' disabled', 9) }
		} else {
			vkrf_bytes(&local, c' flags ', 7)
			spec = FormatSpec{ base: 16, precision: -1, flags: 64 | 32 }
			vkrf_number(&local, flags, spec)
		}
		vkrf_char(&local, `]`)
		buf[local.position] = 0
		vkrf_string(out, &buf[0], outer)
	}
}

fn vkrf_hex_bytes(out &FormatOutput, bytes &u8, spec FormatSpec, suffix u8) {
	unsafe {
		hex := &char(c'0123456789abcdef')
		if spec.width == 0 { return }
		if vkrf_bad_pointer(out, bytes, spec) { return }
		len := if spec.width < 0 {
			i32(1)
		} else if spec.width > 64 {
			i32(64)
		} else {
			spec.width
		}
		separator := if suffix == `C` {
			u8(`:`)
		} else if suffix == `D` {
			u8(`-`)
		} else if suffix == `N` {
			u8(0)
		} else {
			u8(` `)
		}
		for i := i32(0); i < len; i++ {
			byte := bytes[i]
			vkrf_char(out, u8(hex[byte >> 4]))
			vkrf_char(out, u8(hex[byte & 15]))
			if separator != 0 && i != len - 1 { vkrf_char(out, separator) }
		}
	}
}

fn vkrf_bitmap(out &FormatOutput, bits &u64, spec FormatSpec, list bool) {
	unsafe {
		if vkrf_bad_pointer(out, bits, spec) { return }
		nr_bits := if spec.width > 0 { u32(spec.width) } else { u32(0) }
		if list {
			mut first := true
			mut index := u32(0)
			for index < nr_bits {
				if !native_test_bit(index, bits) {
					index++
					continue
				}
				first_bit := index
				index++
				for index < nr_bits && native_test_bit(index, bits) { index++ }
				if !first { vkrf_char(out, `,`) }
				first = false
				vkrf_number(out, first_bit, vkrf_decimal_spec())
				if index > first_bit + 1 {
					vkrf_char(out, `-`)
					vkrf_number(out, index - 1, vkrf_decimal_spec())
				}
			}
		} else {
			mut chunk_spec := FormatSpec{ base: 16, precision: 0, flags: 32 | 16 }
			mut chunks := (nr_bits + 31) / 32
			for chunks != 0 {
				chunks--
				first_bit := chunks * 32
				len := if nr_bits - first_bit < 32 { nr_bits - first_bit } else { u32(32) }
				word := first_bit / 64
				bit := first_bit % 64
				value := u32((bits[word] >> bit) & ((u64(1) << len) - 1))
				chunk_spec.width = i32((len + 3) / 4)
				vkrf_number(out, value, chunk_spec)
				if chunks != 0 { vkrf_char(out, `,`) }
			}
		}
	}
}

fn vkrf_fourcc(out &FormatOutput, pointer voidptr, spec FormatSpec) {
	unsafe {
		if vkrf_bad_pointer(out, pointer, spec) { return }
		mut original := u32(0)
		C.memcpy(&original, pointer, sizeof(original))
		value := original & ~(u32(1) << 31)
		mut text := [32]char{}
		mut local := FormatOutput{ buf: &text[0], size: sizeof(text) }
		for i := u32(0); i < 4; i++ {
			c := u8(value >> (8 * i))
			vkrf_char(&local, if c >= 32 && c < 127 { c } else { u8(`.`) })
		}
		if (original & (u32(1) << 31)) != 0 {
			vkrf_bytes(&local, c' big-endian (', 13)
		} else {
			vkrf_bytes(&local, c' little-endian (', 16)
		}
		vkrf_hex_address(&local, original, 4)
		vkrf_char(&local, `)`)
		text[local.position] = 0
		vkrf_string(out, &text[0], spec)
	}
}

fn vkrf_unsupported(out &FormatOutput, extension &char, len usize) {
	unsafe {
		vkrf_bytes(out, c'(unsupported %p', 15)
		vkrf_bytes(out, extension, if len < 12 { len } else { usize(12) })
		vkrf_char(out, `)`)
		out.status |= 2
		out.stop = true
	}
}

fn vkrf_pointer(out &FormatOutput, extension &char, len usize, ptr voidptr, original FormatSpec) {
	unsafe {
		mut spec := original
		if len == 0 {
			vkrf_pointer_id(out, ptr, spec)
			return
		}
		match u8(extension[0]) {
			`S`, `s`, `B` { vkrf_hex_address(out, u64(ptr), 8) }
			`x` { vkrf_pointer_number(out, u64(ptr), spec) }
			`K` { vkrf_pointer_id(out, ptr, spec) }
			`e` {
				if vkrf_is_err(ptr) {
					spec.flags |= 1
					spec.base = 10
					vkrf_number(out, u64(i64(i32(usize(ptr)))), spec)
				} else {
					vkrf_pointer_id(out, ptr, spec)
				}
			}
			`R`, `r` { vkrf_resource(out, ptr, spec, extension[0] == char(`R`)) }
			`h` { vkrf_hex_bytes(out, ptr, spec, if len > 1 { u8(extension[1]) } else { u8(0) }) }
			`b` { vkrf_bitmap(out, ptr, spec, len > 1 && extension[1] == char(`l`)) }
			`a` {
				if vkrf_bad_pointer(out, ptr, spec) { return }
				mut value := u64(0)
				C.memcpy(&value, ptr, sizeof(value))
				vkrf_hex_address(out, value, 8)
			}
			`4` {
				if len >= 3 && extension[1] == char(`c`) && extension[2] == char(`c`) {
					vkrf_fourcc(out, ptr, spec)
				} else {
					vkrf_error(out, c'(%p4?)', spec)
				}
			}
			`V` {
				if vkrf_bad_pointer(out, ptr, spec) { return }
				mut inner := FormatOutput{
					buf:  if out.position < out.size { out.buf + out.position } else { &char(0) }
					size: if out.position < out.size { out.size - out.position } else { usize(0) }
				}
				vkr_nested_parse(&inner, ptr)
				out.position += inner.position
				out.status |= inner.status
				if (inner.status & 2) != 0 { out.stop = true }
			}
			else { vkrf_unsupported(out, extension, len) }
		}
	}
}

fn vkrf_decimal(format &&char) u32 {
	unsafe {
		mut result := u32(0)
		for (*format)[0] >= char(`0`) && (*format)[0] <= char(`9`) {
			result = result * 10 + u32((*format)[0] - char(`0`))
			*format = *format + 1
		}
		return result
	}
}

fn vkrf_width_literal(input u32) i32 {
	value := input & 0xffffff
	return if (value & 0x800000) != 0 { i32(value) - 0x1000000 } else { i32(value) }
}

fn vkrf_precision_literal(value u32) i32 {
	precision := i32(i16(value))
	return if precision < 0 { i32(0) } else { precision }
}

@[export: 'vkr_format_parse']
pub fn vkr_format_parse(out &FormatOutput, format &char, args voidptr) {
	unsafe {
		mut fmt := format
		for fmt[0] != 0 && !out.stop {
			if fmt[0] != char(`%`) {
				vkrf_char(out, u8(fmt[0]))
				fmt++
				continue
			}
			fmt++
			mut spec := FormatSpec{ base: 10, width: -1, precision: -1 }
			for {
				if fmt[0] == char(`-`) {
					spec.flags |= 2
				} else if fmt[0] == char(`+`) {
					spec.flags |= 4
				} else if fmt[0] == char(` `) {
					spec.flags |= 8
				} else if fmt[0] == char(`#`) {
					spec.flags |= 64
				} else if fmt[0] == char(`0`) {
					spec.flags |= 16
				} else {
					break
				}
				fmt++
			}
			if fmt[0] >= char(`0`) && fmt[0] <= char(`9`) {
				spec.width = vkrf_width_literal(vkrf_decimal(&fmt))
			} else if fmt[0] == char(`*`) {
				mut width := vkr_arg_int(args)
				fmt++
				if vkrf_width_literal(u32(width)) != width {
					if width > 8388607 { width = 8388607 }
					if width < -8388607 { width = -8388607 }
				}
				if width < 0 {
					spec.flags |= 2
					width = vkrf_width_literal(u32(0) - u32(width))
				}
				spec.width = width
			}
			if fmt[0] == char(`.`) {
				fmt++
				if fmt[0] >= char(`0`) && fmt[0] <= char(`9`) {
					spec.precision = vkrf_precision_literal(vkrf_decimal(&fmt))
				} else if fmt[0] == char(`*`) {
					mut precision := vkr_arg_int(args)
					fmt++
					if precision > 32767 { precision = 32767 }
					if precision < 0 { precision = 0 }
					spec.precision = precision
				}
			}
			mut qualifier := u8(0)
			if fmt[0] == char(`h`) || fmt[0] == char(`l`) || fmt[0] == char(`L`) || fmt[0] == char(`z`) || fmt[0] == char(`t`) {
				qualifier = u8(fmt[0])
				fmt++
				if qualifier == `h` && fmt[0] == char(`h`) {
					qualifier = `H`
					fmt++
				} else if qualifier == `l` && fmt[0] == char(`l`) {
					qualifier = `L`
					fmt++
				}
			}
			conversion := u8(fmt[0])
			if conversion != 0 { fmt++ }
			if conversion == `%` {
				vkrf_char(out, `%`)
				continue
			}
			if conversion == `c` {
				c := u8(vkr_arg_int(args))
				pad := if spec.width > 1 { u32(spec.width - 1) } else { u32(0) }
				if (spec.flags & 2) == 0 { vkrf_pad(out, ` `, pad) }
				vkrf_char(out, c)
				if (spec.flags & 2) != 0 { vkrf_pad(out, ` `, pad) }
				continue
			}
			if conversion == `s` {
				str := vkr_arg_pointer(args)
				if !vkrf_bad_pointer(out, str, spec) { vkrf_string(out, str, spec) }
				continue
			}
			if conversion == `p` {
				extension := fmt
				for vkrf_alnum(u8(fmt[0])) { fmt++ }
				vkrf_pointer(out, extension, usize(fmt) - usize(extension), vkr_arg_pointer(args), spec)
				continue
			}
			if conversion == `o` {
				spec.base = 8
			} else if conversion == `x` || conversion == `X` {
				spec.base = 16
				if conversion == `x` { spec.flags |= 32 }
			} else if conversion == `d` || conversion == `i` {
				spec.flags |= 1
			} else if conversion != `u` {
				out.status |= 1
				out.stop = true
				continue
			}
			mut value := u64(0)
			if qualifier == `L` {
				value = u64(vkr_arg_llong(args))
			} else if qualifier == `l` {
				value = if (spec.flags & 1) != 0 {
					u64(vkr_arg_long(args))
				} else {
					vkr_arg_ulong(args)
				}
			} else if qualifier == `z` {
				value = if (spec.flags & 1) != 0 {
					u64(vkr_arg_long(args))
				} else {
					u64(vkr_arg_size(args))
				}
			} else if qualifier == `t` {
				value = u64(vkr_arg_ptrdiff(args))
			} else if qualifier == `H` {
				value = if (spec.flags & 1) != 0 {
					u64(i64(i8(vkr_arg_int(args))))
				} else {
					u64(u8(vkr_arg_int(args)))
				}
			} else if qualifier == `h` {
				value = if (spec.flags & 1) != 0 {
					u64(i64(i16(vkr_arg_int(args))))
				} else {
					u64(u16(vkr_arg_int(args)))
				}
			} else if (spec.flags & 1) != 0 {
				value = u64(i64(vkr_arg_int(args)))
			} else {
				value = u64(vkr_arg_uint(args))
			}
			vkrf_number(out, value, spec)
		}
	}
}

@[export: 'vkr_format_entry']
pub fn vkr_format_entry(buf &char, size usize, fmt &char, args voidptr, status &u32) i32 {
	unsafe {
		if size > 2147483647 {
			if usize(status) != 0 { *status = 1 }
			return 0
		}
		mut out := FormatOutput{ buf: buf, size: size }
		vkr_format_parse(&out, fmt, args)
		if size != 0 { buf[if out.position < size { out.position } else { size - 1 }] = 0 }
		if out.position >= size && out.position != 0 { out.status |= 4 }
		if usize(status) != 0 { *status = out.status }
		return i32(out.position)
	}
}

// scnprintf reports retained bytes and does not consume arguments at size zero.
@[export: 'vkr_format_sc_entry']
pub fn vkr_format_sc_entry(buf &char, size usize, fmt &char, args voidptr) i32 {
	if size == 0 { return 0 }
	count := vkr_format_entry(buf, size, fmt, args, unsafe { nil })
	return if usize(count) < size { count } else { i32(size - 1) }
}
