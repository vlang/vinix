// SPDX-License-Identifier: GPL-2.0-only
module linuxkpi

#include "symbols.h"
#include "linuxkpi_v_primitives.h"
#include "linuxkpi_const_string_v_primitives.h"

@[typedef]
struct C.vks_const_void {}

// V names these linker addresses as function designators, as the native paging
// code does. They are never called; symbols.h declares the real image arrays.
fn C.rodata_start()
fn C.rodata_end()

@[export: 'vinix_linuxkpi_is_kernel_rodata']
fn const_string_is_rodata(ptr &C.vks_const_void) bool {
	address := usize(ptr)
	first := usize(voidptr(C.rodata_start))
	last := usize(voidptr(C.rodata_end))
	return address >= first && address < last
}
