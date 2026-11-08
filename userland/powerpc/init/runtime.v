// SPDX-License-Identifier: GPL-2.0-or-later
module main

import powerpc.runtime

@[export: 'memcpy']
fn copy_bytes(dst voidptr, src voidptr, size u32) voidptr { return runtime.copy(dst, src, size) }

@[export: 'memset']
fn fill_bytes(dst voidptr, value i32, size u32) voidptr { return runtime.fill(dst, value, size) }

@[export: 'memmove']
fn move_bytes(dst voidptr, src voidptr, size u32) voidptr { return runtime.move(dst, src, size) }
