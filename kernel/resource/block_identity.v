// SPDX-License-Identifier: GPL-2.0-or-later
module resource

import stat

// A device capability's physical extent, independent of its VFS pathname and
// inode's user-visible rdev. Only actual block drivers implement this method.
// Partitions retain this scalar description, not a borrowed policy pointer.
pub struct BlockIdentity {
pub:
	is_block bool
	disk_id u64
	start u64
	length u64
}

pub fn (identity BlockIdentity) valid() bool {
	return identity.is_block && identity.disk_id != 0 && identity.length != 0
		&& identity.start <= u64(-1) - identity.length
}

pub fn (identity BlockIdentity) overlaps(other BlockIdentity) bool {
	return identity.valid() && other.valid() && identity.disk_id == other.disk_id
		&& identity.start < other.start + other.length
		&& other.start < identity.start + identity.length
}

pub interface BlockIdentityResource {
	block_identity() BlockIdentity
}

struct BlockIdentityCall {
mut:
	device BlockIdentityResource
}

// Converting an optional interface can box a promoted local in manualfree V.
// Dispatch through a caller-stack slot; no pointer survives this call.
pub fn block_identity(mut res Resource) BlockIdentity {
	if res is BlockIdentityResource {
		mut call := unsafe { &BlockIdentityCall(C.vinix_stack_alloc(sizeof(BlockIdentityCall))) }
		unsafe { call.device = BlockIdentityResource(res) }
		return call.device.block_identity()
	}
	return BlockIdentity{is_block: stat.isblk(res.stat.mode)}
}
