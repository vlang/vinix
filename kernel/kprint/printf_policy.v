// Console policy and bounded stack buffering for the native variadic entries.
@[translated]
module kprint

#include "printf_v.h"

fn C.vp_format(fn (i32, voidptr), voidptr, &char, voidptr) i32
fn C.vp_arg_string(voidptr) &char
fn C.vp_arg_int(voidptr) i32

struct PrintBuffer {
mut:
	data [256]u8
	len usize
}

fn policy_putchar(character i32, _ voidptr) {
	$if !prod {
		policy_serial(u8(character), false)
	}
}

fn policy_panic_putchar(character i32, _ voidptr) {
	policy_serial(u8(character), true)
	unsafe { policy_terminal(&char(&character), 1) }
}

fn policy_benchmark_putchar(character i32, _ voidptr) {
	policy_serial(u8(character), true)
}

fn policy_buffer_putchar(character i32, context voidptr) {
	unsafe {
		buffer := &PrintBuffer(context)
		if buffer.len == 256 {
			kwrite(&char(&buffer.data[0]), u64(buffer.len))
			buffer.len = 0
		}
		buffer.data[buffer.len] = u8(character)
		buffer.len++
	}
}

@[export: 'vinix_printf_policy']
pub fn printf_policy(format &char, arguments voidptr, kind i32) i32 {
	unsafe {
		if kind == 0 {
			$if prod { return 0 }
			printf_lock.acquire()
			result := C.vp_format(policy_putchar, nil, format, arguments)
			printf_lock.release()
			return result
		}
		if kind == 1 { return C.vp_format(policy_panic_putchar, nil, format, arguments) }
		if kind == 3 { return C.vp_format(policy_benchmark_putchar, nil, format, arguments) }
		mut buffer := PrintBuffer{}
		result := C.vp_format(policy_buffer_putchar, voidptr(&buffer), format, arguments)
		if buffer.len != 0 { kwrite(&char(&buffer.data[0]), u64(buffer.len)) }
		return result
	}
}

// V's assertion backend emits only %s and %.*s, plus a literal suffix.
@[export: 'vinix_fprintf_policy']
pub fn fprintf_policy(format &char, arguments voidptr) i32 {
	unsafe {
		mut rest := format
		if format[0] == `%` && format[1] == `s` {
			mut text := C.vp_arg_string(arguments)
			for *text != 0 {
				policy_panic_putchar(i32(u8(*text)), nil)
				text++
			}
			rest += 2
		} else if format[0] == `%` && format[1] == `.` && format[2] == `*` && format[3] == `s` {
			len := C.vp_arg_int(arguments)
			text := C.vp_arg_string(arguments)
			for i := i32(0); i < len; i++ { policy_panic_putchar(i32(u8(text[i])), nil) }
			rest += 4
		}
		for *rest != 0 {
			policy_panic_putchar(i32(u8(*rest)), nil)
			rest++
		}
		return 0
	}
}
