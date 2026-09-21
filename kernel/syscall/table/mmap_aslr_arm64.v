// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
module table

import file
import memory.mmap

fn syscall_linux_mmap_aslr(gpr_state voidptr, addr voidptr, length u64, prot u64,
	flags u64, fdnum int, offset i64) (u64, u64) {
	mut hint := addr
	if addr == unsafe { nil }
		&& flags & u64(mmap.map_fixed | mmap.map_fixed_noreplace) == 0 {
		hint = randomized_mmap_hint(length)
	}
	prot_and_flags := ((prot & u64(0xffffffff)) << 32) | (flags & u64(0xffffffff))
	return file.syscall_mmap(gpr_state, hint, length, prot_and_flags, fdnum, offset)
}
