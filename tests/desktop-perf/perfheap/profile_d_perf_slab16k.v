// SPDX-License-Identifier: GPL-2.0-or-later
// Explicit current ARM profile; older medium-class layouts are not admitted.
module perfheap

pub const class_count = 18
pub const class_sizes = [u64(16), 32, 48, 64, 96, 128, 192, 256, 384, 512, 768,
	1024, 1536, 2048, 2688, 4048, 5392, 8096]!
pub const page_size = 16384
pub const schema = 'vinix-slab-18-16k-v1'
pub const page_error = 'slab schema requires 16384-byte pages'
pub const kernel_revision = 'a3d68ae67bb8f1fff788c919c46ca2bfbead222a'
pub const procfs_sha256 = 'd220ec2b632ac41b279dfbce312a89bca08ce1c0e31748c6c6cb42c410d28c44'
