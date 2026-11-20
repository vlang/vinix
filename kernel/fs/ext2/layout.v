// SPDX-License-Identifier: GPL-2.0-or-later
module ext2

import errno

const ext4_inode_extents = u32(0x80000)
const ext4_incompat_supported = u32(0x2 | 0x40 | 0x80 | 0x200 | 0x2000)

struct VolumeLayout {
	block_bytes      u64
	descriptor_bytes u64
	read_only        bool
}

// Extended fields are read from the complete 1024-byte superblock, rather
// than changing the native ext2 writer's existing on-disk structure.
fn disk_u16(data voidptr, offset u64) u16 {
	p := unsafe { &u8(data) }
	return unsafe { u16(p[offset]) | (u16(p[offset + 1]) << 8) }
}

fn disk_u32(data voidptr, offset u64) u32 {
	return u32(disk_u16(data, offset)) | (u32(disk_u16(data, offset + 2)) << 16)
}

fn volume_layout(mut sb EXT2Superblock, data voidptr, bytes u64, ext4 bool) ?VolumeLayout {
	if sb.block_size > 2 || sb.version_maj > 1 {
		errno.set(errno.einval)
		return none
	}
	block_bytes := u64(1024) << sb.block_size
	if sb.version_maj == 0 { sb.inode_size = 128 }
	inode_bytes := u64(sb.inode_size)
	if sb.block_cnt <= sb.sb_block || sb.inode_cnt < 2
		|| sb.sb_block != if block_bytes == 1024 { u32(1) } else { u32(0) }
		|| inode_bytes < sizeof(EXT2Inode) || inode_bytes > block_bytes
		|| inode_bytes & (inode_bytes - 1) != 0
		|| sb.blocks_per_group == 0 || sb.blocks_per_group > block_bytes * 8
		|| sb.inodes_per_group == 0 || sb.inodes_per_group > block_bytes * 8
		|| u64(sb.block_cnt) * block_bytes > bytes {
		errno.set(errno.einval)
		return none
	}
	groups := (u64(sb.block_cnt - sb.sb_block) + sb.blocks_per_group - 1) / sb.blocks_per_group
	if u64(sb.inode_cnt) > groups * sb.inodes_per_group {
		errno.set(errno.einval)
		return none
	}
	mut descriptor_bytes := u64(32)
	if ext4 {
		// JBD2 recovery and orphan cleanup must happen in Linux before this
		// read-only driver reads home metadata. Inline/encrypted data, meta_bg,
		// bigalloc and unknown incompatible formats cannot be interpreted here.
		if sb.os_id != 0 || sb.req_features & ~ext4_incompat_supported != 0
			|| sb.non_supported_features & u32(0x200 | 0x8000 | 0x10000) != 0 {
			errno.set(errno.eopnotsupp)
			return none
		}
		if sb.fs_state != 1 || disk_u32(data, 0xe8) != 0 {
			errno.set(errno.euclean)
			return none
		}
		if sb.req_features & 0x80 != 0 {
			// The existing data-block interface is u32. Accept the common 64-bit
			// descriptor format, but refuse volumes beyond that address space.
			if disk_u32(data, 0x150) != 0 {
				errno.set(errno.eopnotsupp)
				return none
			}
			descriptor_bytes = disk_u16(data, 0xfe)
			if descriptor_bytes != 64 {
				errno.set(errno.einval)
				return none
			}
		}
		if (u64(sb.sb_block) + 1) * block_bytes > u64(sb.block_cnt) * block_bytes
			|| groups > (u64(sb.block_cnt) * block_bytes - (u64(sb.sb_block) + 1) * block_bytes) / descriptor_bytes {
			errno.set(errno.einval)
			return none
		}
	} else if sb.req_features & ~u32(2) != 0 || sb.opt_features & 4 != 0 {
		errno.set(errno.eopnotsupp)
		return none
	}
	// Unknown read-only-compatible features must never be written by ext2.
	return VolumeLayout{block_bytes, descriptor_bytes, ext4 || sb.non_supported_features & ~u32(3) != 0}
}
