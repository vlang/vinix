// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
module table

import krandom
import memory
import proc

// OpenBSD's LP64 uvm_map_hint() randomizes placement inside a bounded 4 GiB
// spacing window. Vinix uses the same entropy scale while leaving its existing
// hole finder in charge of collision resolution.
const mmap_aslr_span = u64(4 * 1024 * 1024 * 1024)
const mmap_aslr_page = u64(4096)

fn randomized_mmap_hint(length u64) voidptr {
	process := proc.current_thread().process
	if process == unsafe { nil } {
		return unsafe { nil }
	}
	anchor := process.mmap_anon_non_fixed_base
	limit := memory.user_address_limit()
	if anchor == 0 || anchor >= limit || length >= limit - anchor {
		return unsafe { nil }
	}

	mut max_offset := limit - anchor - length
	if max_offset > mmap_aslr_span {
		max_offset = mmap_aslr_span
	}
	slots := max_offset / mmap_aslr_page
	if slots == 0 {
		return unsafe { nil }
	}

	mut random := u64(0)
	if !krandom.fill(voidptr(&random), sizeof(random), false) {
		return unsafe { nil }
	}
	offset := (random % (slots + 1)) * mmap_aslr_page
	return voidptr(anchor + offset)
}
