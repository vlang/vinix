// Fixed-argument V bridges called by the native variadic prologues.
@[translated]
module kprint

import abiargs

@[export: 'vinix_printf_entry']
pub fn printf_entry(format &char, args voidptr) i32 {
	return printf_policy(format, args, 0)
}

@[export: 'vinix_panic_entry']
pub fn panic_entry(format &char, args voidptr) i32 {
	return printf_policy(format, args, 1)
}

@[export: 'vinix_kprintf_entry']
pub fn kprintf_entry(format &char, args voidptr) i32 {
	return printf_policy(format, args, 2)
}

@[export: 'vinix_benchmark_entry']
pub fn benchmark_entry(format &char, args voidptr) i32 {
	return printf_policy(format, args, 3)
}

@[export: 'vinix_fprintf_entry']
pub fn fprintf_entry(_ voidptr, format &char, args voidptr) i32 {
	return fprintf_policy(format, args)
}

@[export: 'vp_arg_string']
pub fn arg_string(args voidptr) &char {
	return unsafe { &char(usize(abiargs.word(args))) }
}

@[export: 'vp_arg_int']
pub fn arg_int(args voidptr) i32 {
	return i32(abiargs.integer(args))
}
