// SPDX-License-Identifier: GPL-2.0-or-later
module ext2

import errno
import memory
import posix_acl
import resource as resource_mod
import time

fn (mut filesystem EXT2Filesystem) ea_data_block(block u32) bool {
	if block <= filesystem.superblock.sb_block || block >= filesystem.superblock.block_cnt {
		return false
	}
	if filesystem.superblock.blocks_per_group == 0 || filesystem.superblock.inode_size == 0 {
		return false
	}
	group := (block - filesystem.superblock.sb_block) / filesystem.superblock.blocks_per_group
	if filesystem.superblock.non_supported_features & ext2_feature_ro_compat_sparse_super == 0
		|| mkfs_has_backup(u64(group)) {
		start := u64(filesystem.superblock.sb_block) + u64(group) * u64(filesystem.superblock.blocks_per_group)
		gdt_blocks := (filesystem.bgd_cnt * sizeof(EXT2BlockGroupDescriptor) + filesystem.block_size - 1)
			/ filesystem.block_size
		if u64(block) < start + 1 + gdt_blocks { return false }
	}
	mut descriptor := unsafe { &EXT2BlockGroupDescriptor(C.__builtin_alloca(sizeof(EXT2BlockGroupDescriptor))) }
	unsafe { *descriptor = EXT2BlockGroupDescriptor{} }
	if descriptor.read_entry(mut filesystem, group) < 0 { return false }
	table_blocks := (u64(filesystem.superblock.inodes_per_group) * u64(filesystem.superblock.inode_size)
		+ filesystem.block_size - 1) / filesystem.block_size
	if block == descriptor.block_addr_bitmap || block == descriptor.block_addr_inode
		|| (block >= descriptor.inode_table_block
			&& u64(block) - u64(descriptor.inode_table_block) < table_blocks) { return false }
	return true
}

fn ea_key(name string) ?(u8, string) {
	if name == posix_acl.access_name { return u8(2), '' }
	if name == posix_acl.default_name { return u8(3), '' }
	if name.starts_with('user.') { return u8(1), unsafe { tos(name.str + 5, name.len - 5) } }
	if name.starts_with('trusted.') { return u8(4), unsafe { tos(name.str + 8, name.len - 8) } }
	if name.starts_with('security.') { return u8(6), unsafe { tos(name.str + 9, name.len - 9) } }
	errno.set(errno.enotsup)
	return none
}

fn ea_prefix(index u8) string {
	return match index { 1 { 'user.' } 2 { posix_acl.access_name }
		3 { posix_acl.default_name } 4 { 'trusted.' } 6 { 'security.' } else { '' } }
}

// Called under the filesystem lock. The caller always frees the returned
// private heap buffer; backing I/O copies it through the existing DMA bounce.
fn (mut filesystem EXT2Filesystem) ea_read(block u32) ?voidptr {
	if filesystem.block_size < 1024 || filesystem.block_size > 65536
		|| !filesystem.ea_data_block(block) {
		errno.set(errno.eio)
		return none
	}
	data := memory.calloc(filesystem.block_size, 1) @[freed]
	if data == unsafe { nil } { errno.set(errno.enomem); return none }
	filesystem.raw_device_read(data, u64(block) * filesystem.block_size, filesystem.block_size) or {
		memory.free(data)
		return none
	}
	if !ea_validate(data, int(filesystem.block_size)) {
		memory.free(data)
		errno.set(errno.eio)
		return none
	}
	return data
}

fn (mut filesystem EXT2Filesystem) ea_release(block u32, data voidptr) ? {
	mut header := unsafe { &EAHeader(data) }
	if header.refs == 1 { filesystem.free_block(block)?; return }
	header.refs--
	filesystem.raw_device_write(data, u64(block) * filesystem.block_size, sizeof(EAHeader))?
}

fn (mut this EXT2Resource) read_xattr(name string, mut value []u8) ? {
	index, short_name := ea_key(name)?
	this.l.acquire()
	defer { this.l.release() }
	this.filesystem.l.acquire()
	defer { this.filesystem.l.release() }
	mut inode := unsafe { &EXT2Inode(C.__builtin_alloca(sizeof(EXT2Inode))) }
	unsafe { *inode = EXT2Inode{} }
	inode.read_entry(mut this.filesystem, u32(this.stat.ino))?
	if inode.eab == 0 { errno.set(errno.enodata); return none }
	block := this.filesystem.ea_read(inode.eab)?
	defer { memory.free(block) }
	offset := ea_find(block, index, short_name)
	if offset < 0 { errno.set(errno.enodata); return none }
	entry := ea_entry(block, offset)
	if index == 2 || index == 3 {
		disk := unsafe { (&u8(u64(block) + u64(entry.value_offset))).vbytes(int(entry.value_size)) }
		if !posix_acl.from_disk(disk, mut value) { errno.set(errno.eio); return none }
		return
	}
	for i in 0 .. int(entry.value_size) {
		value << unsafe { *(&u8(u64(block) + u64(entry.value_offset) + u64(i))) }
	}
}

fn (mut this EXT2Resource) snapshot_permissions(mut acl []u8) ?resource_mod.PermissionMetadata {
	this.l.acquire()
	defer { this.l.release() }
	this.filesystem.l.acquire()
	defer { this.filesystem.l.release() }
	mut inode := unsafe { &EXT2Inode(C.__builtin_alloca(sizeof(EXT2Inode))) }
	unsafe { *inode = EXT2Inode{} }
	inode.read_entry(mut this.filesystem, u32(this.stat.ino))?
	if inode.eab != 0 {
		block := this.filesystem.ea_read(inode.eab)?
		defer { memory.free(block) }
		position := ea_find(block, 2, '')
		if position >= 0 {
			entry := ea_entry(block, position)
			disk := unsafe { (&u8(u64(block) + u64(entry.value_offset))).vbytes(int(entry.value_size)) }
			if !posix_acl.from_disk(disk, mut acl) { errno.set(errno.eio); return none }
		}
	}
	return resource_mod.PermissionMetadata{u32(inode.permissions), u32(inode.user_id), u32(inode.group_id)}
}

fn (mut this EXT2Resource) list_xattrs(mut names []u8) ? {
	this.l.acquire()
	defer { this.l.release() }
	this.filesystem.l.acquire()
	defer { this.filesystem.l.release() }
	mut inode := unsafe { &EXT2Inode(C.__builtin_alloca(sizeof(EXT2Inode))) }
	unsafe { *inode = EXT2Inode{} }
	inode.read_entry(mut this.filesystem, u32(this.stat.ino))?
	if inode.eab == 0 { return }
	block := this.filesystem.ea_read(inode.eab)?
	defer { memory.free(block) }
	mut offset := ea_header_size
	for unsafe { *(&u32(u64(block) + u64(offset))) } != 0 {
		entry := ea_entry(block, offset)
		prefix := ea_prefix(entry.index)
		if prefix.len != 0 {
			for c in prefix { names << c }
			for c in ea_name(block, offset) { names << c }
			names << 0
		}
		offset += ea_round(ea_entry_size + int(entry.name_len))
	}
}

fn (mut this EXT2Resource) write_xattr(name string, value []u8, flags int) ? {
	if posix_acl.is_name(name) { this.write_acl(name, value, flags)?; return }
	this.ea_change(name, value, flags, false)?
}

fn (mut this EXT2Resource) write_acl(name string, value []u8, flags int) ? {
	if value.len != 0 && !posix_acl.valid(value) { errno.set(errno.einval); return none }
	this.l.acquire()
	defer { this.l.release() }
	this.filesystem.l.acquire()
	defer { this.filesystem.l.release() }
	mut desired_mode := u32(0xffffffff)
	mut removing := value.len <= 4
	if !removing && name == posix_acl.access_name {
		derived, extended := posix_acl.mode(value, this.stat.mode)
		desired_mode = if flags & resource_mod.acl_clear_setgid != 0 { derived & ~u32(0o2000) } else { derived }
		removing = !extended
	}
	mut disk := []u8{} @[freed]
	disk.flags |= .noslices
	defer { unsafe { disk.free() } }
	if !removing && !posix_acl.to_disk(value, mut disk) { errno.set(errno.einval); return none }
	this.ea_change_locked(name, disk, flags & 3, removing, desired_mode, false)?
}

fn (mut this EXT2Resource) delete_xattr(name string) ? {
	empty := []u8{} @[freed]
	defer { unsafe { empty.free() } }
	this.ea_change(name, empty, if posix_acl.is_name(name) { 0 } else { 2 }, true)?
}

fn (mut this EXT2Resource) ea_change(name string, value []u8, flags int, removing bool) ? {
	this.l.acquire()
	defer { this.l.release() }
	this.filesystem.l.acquire()
	defer { this.filesystem.l.release() }
	this.ea_change_locked(name, value, flags, removing, u32(0xffffffff), false)?
}

// ACL permission changes use a private EA block even when the old block is
// exclusive. The inode then publishes its new mode and EA pointer together.
fn (mut this EXT2Resource) ea_change_locked(name string, value []u8, flags int,
	removing bool, desired_mode u32, metadata bool) ? {
	index, short_name := ea_key(name)?
	mut inode := unsafe { &EXT2Inode(C.__builtin_alloca(sizeof(EXT2Inode))) }
	unsafe { *inode = EXT2Inode{} }
	inode.read_entry(mut this.filesystem, u32(this.stat.ino))?
	mut old := voidptr(unsafe { nil })
	if inode.eab != 0 { old = this.filesystem.ea_read(inode.eab)? }
	defer { memory.free(old) }
	if inode.eab != 0 && inode.sector_cnt < u32(this.filesystem.block_size / 512) {
		errno.set(errno.eio)
		return none
	}
	position := if old == unsafe { nil } { -1 } else { ea_find(old, index, short_name) }
	if position >= 0 && flags & 1 != 0 { errno.set(errno.eexist); return none }
	if position < 0 && flags & 2 != 0 { errno.set(errno.enodata); return none }
	if this.filesystem.block_size < 1024 || this.filesystem.block_size > 65536 {
		errno.set(errno.enotsup)
		return none
	}
	output := memory.calloc(this.filesystem.block_size, 1) @[freed]
	if output == unsafe { nil } { errno.set(errno.enomem); return none }
	defer { memory.free(output) }
	count := ea_rebuild(old, output, int(this.filesystem.block_size), index, short_name,
		value.data, value.len, removing)?
	old_block := inode.eab
	old_sectors := inode.sector_cnt
	mut allocated := u32(0)
	if count == 0 {
		inode.eab = 0
		if old_block != 0 { inode.sector_cnt -= u32(this.filesystem.block_size / 512) }
	} else {
		// Exclusive blocks can be rewritten. Shared Linux-created blocks must
		// be copied before the inode pointer changes.
		if old == unsafe { nil } || unsafe { &EAHeader(old) }.refs > 1 || desired_mode != u32(0xffffffff) {
			allocated = this.filesystem.allocate_block() or { errno.set(errno.enospc); return none }
			inode.eab = allocated
			if old_block == 0 { inode.sector_cnt += u32(this.filesystem.block_size / 512) }
		}
		this.filesystem.raw_device_write(output, u64(inode.eab) * this.filesystem.block_size,
			this.filesystem.block_size) or {
			if allocated != 0 { this.filesystem.free_block(allocated) or {} }
			return none
		}
		if this.filesystem.superblock.opt_features & 8 == 0 {
			this.filesystem.superblock.opt_features |= 8
			this.filesystem.write_superblock() or {
				this.filesystem.superblock.opt_features &= ~u32(8)
				if allocated != 0 { this.filesystem.free_block(allocated) or {} }
				return none
			}
		}
	}
	if desired_mode != u32(0xffffffff) { inode.permissions = u16(desired_mode) }
	if metadata {
		inode.user_id = u16(this.stat.uid)
		inode.group_id = u16(this.stat.gid)
		inode.access_time = stat_seconds(this.stat.atim)
		inode.mod_time = stat_seconds(this.stat.mtim)
		inode.flags = (inode.flags & ~resource_mod.attributes_kept) | (this.attr_bits & resource_mod.attributes_kept)
	}
	inode.creation_time = ext2_now()
	inode.write_entry(mut this.filesystem, u32(this.stat.ino)) or {
		inode.eab = old_block
		inode.sector_cnt = old_sectors
		// Cache/device errors cannot prove the inode pointer stayed unchanged.
		// Quarantine a newly allocated block rather than make a possibly
		// published pointer refer to space reused by another file.
		return none
	}
	this.stat.blocks = inode.sector_cnt
	if desired_mode != u32(0xffffffff) { this.stat.mode = desired_mode }
	this.stat.ctim = time.TimeSpec{tv_sec: i64(inode.creation_time)}
	if old_block != 0 && old_block != inode.eab { this.filesystem.ea_release(old_block, old)? }
	flush_on_return()
}

// The inode pointer is removed before the old block becomes allocatable, so
// an error can leave an orphan block but cannot leave a live dangling pointer.
fn (mut inode EXT2Inode) delete_ea(mut filesystem EXT2Filesystem, inode_index u32) ? {
	if inode.eab == 0 { return }
	block := inode.eab
	data := filesystem.ea_read(block)?
	defer { memory.free(data) }
	if inode.sector_cnt < u32(filesystem.block_size / 512) {
		errno.set(errno.eio)
		return none
	}
	inode.eab = 0
	inode.sector_cnt -= u32(filesystem.block_size / 512)
	inode.write_entry(mut filesystem, inode_index)?
	filesystem.ea_release(block, data)?
}
