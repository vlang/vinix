// SPDX-License-Identifier: GPL-2.0-or-later
// Default profile retains the original source-pinned 4 KiB contract.
module perfheap

pub const class_count = 14
pub const class_sizes = [u64(16), 32, 48, 64, 96, 128, 192, 256, 384, 512, 768,
	1024, 1536, 2048]!
pub const page_size = 4096
pub const schema = 'vinix-slab-14-4k-v1'
pub const page_error = 'slab schema requires 4096-byte pages'
pub const kernel_revision = '9acefa77bee69247c837e97987a2377536aa41cc'
pub const procfs_sha256 = 'd6c9bddf457cc46c9b588749768e9e4bdce43a51ac540d52b696a6447298d1b1'
