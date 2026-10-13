// SPDX-License-Identifier: GPL-2.0-or-later
module hwhost

fn test_boot_fat_volume_accounts_for_all_inputs_and_filesystem_headroom() {
	assert boot_fat_size([u64(1024), 1 << 20, 16 << 20, 8 << 20])! == u64(64) << 20
	assert boot_fat_size([u64(1) << 20, 16 << 20, 49 << 20])! == u64(128) << 20
	assert boot_fat_size([u64(1) << 20, 24 << 20, 256 << 20])! == u64(512) << 20
	for files in [[u64(4) << 30], [~u64(0)], [u64(3) << 30, 3 << 30, 3 << 30, 3 << 30, 3 << 30, 3 << 30]] {
		mut refused := false
		boot_fat_size(files) or { refused = true }
		assert refused
	}
}
