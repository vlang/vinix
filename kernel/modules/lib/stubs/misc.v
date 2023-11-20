// misc.v: Stubs for the generated V code.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module stubs

import lib

@[export: '__ctype_tolower_loc']
pub fn ctype_tolower_loc() &&int {
	lib.kpanic(voidptr(0), c'__ctype_tolower_loc is a stub')
}

@[export: '__ctype_toupper_loc']
pub fn ctype_toupper_loc() &&int {
	lib.kpanic(voidptr(0), c'__ctype_toupper_loc is a stub')
}

@[export: 'exit']
@[noreturn]
pub fn kexit(code int) {
	lib.kpanic(voidptr(0), c'Kernel has called exit()')
}

@[export: 'qsort']
pub fn qsort(ptr voidptr, count u64, size u64, comp fn (a voidptr, b voidptr) int) {
	lib.kpanic(voidptr(0), c'qsort is a stub')
}
