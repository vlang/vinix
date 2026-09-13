module stubs

import lib

@[export: '__ctype_tolower_loc']
pub fn ctype_tolower_loc() &&int {
	lib.kpanic(unsafe { nil }, c'__ctype_tolower_loc is a stub')
}

@[export: '__ctype_toupper_loc']
pub fn ctype_toupper_loc() &&int {
	lib.kpanic(unsafe { nil }, c'__ctype_toupper_loc is a stub')
}

@[export: 'exit']
@[noreturn]
pub fn kexit(code int) {
	lib.kpanic(unsafe { nil }, c'Kernel has called exit()')
}
