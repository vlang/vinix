// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout
import os

fn test_fragment_tail_local_preserves_scratch_and_leaves_reserved_word_empty() {
	local := os.read_file(g13layout.repo_root() + '/kernel/gpu/agx/fw/fragment.v')!
	check_fragment_tail_local(local)!
	for old, changed in {'.v13_5_partial { 0x4b8 }': '.v13_5_partial { 0x4a8 }',
		'0x8c8, voidptr(legacy), 0x8b0, 0x004)': '0x8cc, voidptr(legacy), 0x8b0, 0x004)',
		'0x8d0, voidptr(legacy), 0x8b4, 0x030)': '',
		'0x768, voidptr(legacy), 0x750, 0x008)': '',
		'0x900, voidptr(legacy), 0x8e4, 0x049)': '0x900, voidptr(legacy), 0x8e4, 0x041)',
		'.v12_3 { g13_fragment_cur_ts_offset }': '.v12_3 { 0x904 }',
		'0x4b8, voidptr(legacy), 0x4b0, 0x220)': '0x4a8, voidptr(legacy), 0x4b0, 0x220)'} {
		assert local.contains(old)
		if _ := check_fragment_tail_local(local.replace(old, changed)) { assert false, old }
	}
	if _ := check_fragment_tail_local(local + '\nunk_398_padding\n') { assert false }
}
