// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module userland

import errno
import usercopy

// Linux's limits: 128 KiB for one string, and 2 MiB for both vectors
// together, a quarter of the default stack.
const exec_string_max = 128 * 1024
const exec_total_max = u64(2 * 1024 * 1024)

fn free_exec_strings(mut strings []string) {
	for text in strings {
		unsafe { text.free() }
	}
	unsafe { strings.free() }
}

// What a vector takes up of the limit: each string, its terminator and the
// pointer to it.
fn exec_strings_size(strings []string) u64 {
	mut size := u64(0)
	for text in strings {
		size += u64(text.len) + 1 + sizeof(u64)
	}
	return size
}

// One of execve's vectors, argv or envp, copied in: each pointer and then the
// string it leads to, through usercopy, so that a vector that leads nowhere is
// EFAULT rather than a kernel fault. A null vector is an empty one, as on
// Linux. One that takes more than `budget` bytes is E2BIG.
fn exec_strings_from_user(vector u64, budget u64) ?[]string {
	mut strings := []string{}
	// Only built here, so growing it can give back what it outgrows.
	strings.flags |= .noslices
	if vector == 0 {
		return strings
	}
	mut used := u64(0)
	for i := u64(0); true; i++ {
		mut pointer := u64(0)
		if !usercopy.copy_from_user(voidptr(&pointer), vector + i * sizeof(u64), sizeof(u64)) {
			free_exec_strings(mut strings)
			errno.set(errno.efault)
			return none
		}
		if pointer == 0 {
			break
		}
		text := usercopy.copy_cstring_from_user(pointer, exec_string_max) or {
			if errno.get() == errno.enametoolong {
				errno.set(errno.e2big)
			}
			free_exec_strings(mut strings)
			return none
		}
		used += u64(text.len) + 1 + sizeof(u64)
		if used > budget {
			unsafe { text.free() }
			free_exec_strings(mut strings)
			errno.set(errno.e2big)
			return none
		}
		strings << text
	}
	return strings
}
