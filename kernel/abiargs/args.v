// Native integer/pointer variadic slots. Kernel formatters do not accept floats.
@[translated]
module abiargs

#include "varargs_abi.h"

struct C.vinix_va_aapcs64 {
mut:
	stack   voidptr
	gr_top  voidptr
	vr_top  voidptr
	gr_offs i32
	vr_offs i32
}

struct C.vinix_va_sysv64 {
mut:
	gp_offset         u32
	fp_offset         u32
	overflow_arg_area voidptr
	reg_save_area     voidptr
}

fn slot(cursor voidptr) voidptr {
	unsafe {
		if C.VINIX_VA_ABI == 1 {
			stack := &voidptr(cursor)
			address := *stack
			*stack = voidptr(uint(*stack) + 8)
			return address
		}
		if C.VINIX_VA_ABI == 2 {
			list := &C.vinix_va_aapcs64(cursor)
			offset := list.gr_offs
			if offset < 0 {
				list.gr_offs = offset + 8
				if list.gr_offs <= 0 {
					return voidptr(uint(list.gr_top) + uint(i64(offset)))
				}
			}
			stack := uint(list.stack)
			list.stack = voidptr(stack + 8)
			return voidptr(stack)
		}
		list := &C.vinix_va_sysv64(cursor)
		if list.gp_offset < 48 {
			address := uint(list.reg_save_area) + uint(list.gp_offset)
			list.gp_offset += 8
			return voidptr(address)
		}
		stack := uint(list.overflow_arg_area)
		list.overflow_arg_area = voidptr(stack + 8)
		return voidptr(stack)
	}
}

pub fn word(cursor voidptr) u64 {
 unsafe { return *&u64(slot(cursor)) }
}

pub fn integer(cursor voidptr) u32 {
 unsafe { return *&u32(slot(cursor)) }
}

// Darwin passes va_list as a pointer value; give parsing a local cursor.
pub fn parameter(args voidptr, local &voidptr) voidptr {
	unsafe {
		if C.VINIX_VA_ABI == 1 { *local = args; return local }
		return args
	}
}

pub fn native_size() uint {
	if C.VINIX_VA_ABI == 1 { return sizeof(voidptr) }
	if C.VINIX_VA_ABI == 2 { return sizeof(C.vinix_va_aapcs64) }
	return sizeof(C.vinix_va_sysv64)
}
