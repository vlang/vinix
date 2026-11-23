// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import errno
import kbudget
import lib
import memory
import proc
import usercopy
import vmstorage

const statmount_sb_basic = u64(0x01)
const statmount_mnt_basic = u64(0x02)
const statmount_propagate_from = u64(0x04)
const statmount_mnt_root = u64(0x08)
const statmount_mnt_point = u64(0x10)
const statmount_fs_type = u64(0x20)
const statmount_mnt_ns_id = u64(0x40)
const statmount_mnt_opts = u64(0x80)
const statmount_paths = statmount_mnt_root | statmount_mnt_point | statmount_fs_type
const statmount_string_capacity = u64(3 * 4096 + 1)

// The Linux 6.12 fixed header. String offsets are relative to its end.
struct StatmountResult {
mut:
	size u32
	mnt_opts u32
	mask u64
	sb_dev_major u32
	sb_dev_minor u32
	sb_magic u64
	sb_flags u32
	fs_type u32
	mnt_id u64
	mnt_parent_id u64
	mnt_id_old u32
	mnt_parent_id_old u32
	mnt_attr u64
	mnt_propagation u64
	mnt_peer_group u64
	mnt_master u64
	propagate_from u64
	mnt_root u32
	mnt_point u32
	mnt_ns_id u64
	reserved [49]u64
}

struct StatmountStrings {
	data voidptr
mut:
	used u64
}

pub fn syscall_statmount(_ voidptr, address u64, output u64, size u64, flags u32) (u64, u64) {
	if flags != 0 { return errno.err, errno.einval }
	request := read_mount_id_request(address) or { return errno.err, errno.get() }
	ns := query_mount_namespace(request.namespace_id) or { return errno.err, errno.get() }
	limit := memory.user_address_limit()
	if output > limit || size > limit - output { return errno.err, errno.efault }
	if size == sizeof(StatmountResult) && request.parameter & (statmount_paths | statmount_mnt_opts) != 0 {
		return errno.err, errno.eoverflow
	}
	if request.parameter & statmount_paths == 0 {
		return statmount_to_user(ns, request, output, size, unsafe { nil })
	}
	reservation := vmstorage.allocation_bytes(statmount_string_capacity) or { return errno.err, errno.enomem }
	charge := proc.reserve_kernel(.scratch, reservation) or { return errno.err, errno.get() }
	defer { kbudget.release(charge) }
	buffer := memory.malloc_packed_fallible(statmount_string_capacity) @[freed]
	if buffer == unsafe { nil } { return errno.err, errno.enomem }
	defer { unsafe { free(buffer) } }
	return statmount_to_user(ns, request, output, size, buffer)
}

fn statmount_to_user(ns &proc.Namespace, request MountIdRequest, output u64, size u64, buffer voidptr) (u64, u64) {
	mut header := unsafe { &StatmountResult(C.vinix_stack_alloc(sizeof(StatmountResult))) }
	unsafe { *header = StatmountResult{} }
	mut strings := StatmountStrings{data: buffer}
	statmount_snapshot(ns, request, mut header, mut strings) or { return errno.err, errno.get() }
	header_bytes := if size < sizeof(StatmountResult) { size } else { u64(sizeof(StatmountResult)) }
	if strings.used > 0 && (header_bytes < sizeof(StatmountResult) || size - header_bytes < strings.used) {
		return errno.err, errno.eoverflow
	}
	header.size = u32(header_bytes + strings.used)
	if strings.used > 0 && !usercopy.copy_to_user(output + header_bytes, strings.data, strings.used) {
		return errno.err, errno.efault
	}
	if header_bytes > 0 && !usercopy.copy_to_user(output, header, header_bytes) {
		return errno.err, errno.efault
	}
	return 0, 0
}

fn statmount_snapshot(ns &proc.Namespace, request MountIdRequest, mut header StatmountResult,
	mut strings StatmountStrings) ? {
	vfs_lock.acquire()
	defer { vfs_lock.release() }
	view := mount_query_view(ns)?
	mut table := unsafe { view.table }
	table.lock.acquire()
	entry := if table.released { unsafe { &Mount(nil) } } else { find_public_mount_locked(table, request.id) }
	if entry == unsafe { nil } {
		table.lock.release()
		errno.set(errno.enoent)
		return none
	}
	root_entry := mount_by_route_locked(table, view.identity, true)
	visible := mount_query_visible_locked(view, root_entry, entry)
	if !visible && !mount_query_privileged(view) {
		table.lock.release()
		errno.set(errno.eperm)
		return none
	}
	table.lock.release()
	if !policy_check(entry.root, proc.policy_inspect) { return none }
	table.lock.acquire()
	defer { table.lock.release() }
	if table.released {
		errno.set(errno.enoent)
		return none
	}
	// There is no usercopy or backend I/O in this locked part.
	if !snapshot_statmount_fields(view, root_entry, entry, visible, request.parameter,
		mut header, mut strings) { return none }
}

fn snapshot_statmount_fields(view MountQueryView, root_entry &Mount, entry &Mount, visible bool, mask u64,
	mut header StatmountResult, mut strings StatmountStrings) bool {
	if mask & statmount_sb_basic != 0 { statmount_superblock(entry, mut header) }
	if mask & statmount_mnt_basic != 0 { statmount_attachment(view.table, entry, mut header) }
	if mask & statmount_propagate_from != 0 {
		// Vinix does not maintain Linux propagation groups.
		header.mask |= statmount_propagate_from
	}
	if mask & statmount_mnt_ns_id != 0 {
		header.mnt_ns_id = view.namespace_id
		header.mask |= statmount_mnt_ns_id
	}
	if mask & statmount_fs_type != 0 {
		header.fs_type = append_statmount_string(mut strings, entry.fstype) or { return false }
		header.mask |= statmount_fs_type
	}
	if mask & statmount_mnt_root != 0 {
		header.mnt_root = append_statmount_path(view.table, entry.root, unsafe { nil },
			entry.filesystem_root, unsafe { nil }, mut strings) or { return false }
		header.mask |= statmount_mnt_root
	}
	if mask & statmount_mnt_point != 0 {
		header.mnt_point = if visible {
			append_statmount_path(view.table, entry.root, entry, view.root, root_entry, mut strings) or { return false }
		} else {
			append_statmount_string(mut strings, '') or { return false }
		}
		header.mask |= statmount_mnt_point
	}
	return true
}

fn statmount_superblock(entry &Mount, mut header StatmountResult) {
	// Avoid a statfs operation under the VFS lock, particularly for network
	// filesystems. The magic numbers describe the mounted filesystem type.
	magic := match filesystem_kind(entry.fstype) {
		'tmpfs', 'devtmpfs' { u64(0x01021994) }
		'procfs' { u64(0x9fa0) }
		'sysfs' { u64(0x62656572) }
		'devpts' { u64(0x1cd1) }
		'cgroup2' { u64(0x63677270) }
		'mqueue' { u64(0x19800202) }
		'overlay' { u64(0x794c7630) }
		'ext2', 'ext4' { u64(0xef53) }
		'nfs' { u64(0x6969) }
		else { u64(0) }
	}
	root := entry.filesystem_root
	if magic == 0 || root == unsafe { nil } || root.resource == unsafe { nil } { return }
	device := if entry.mqueue_device != 0 { entry.mqueue_device } else { root.resource.stat.dev }
	header.sb_dev_major = u32(device >> 32)
	header.sb_dev_minor = u32(device)
	header.sb_magic = magic
	header.sb_flags = if root.read_only { u32(ms_rdonly) } else { u32(0) }
	header.mask |= statmount_sb_basic
}

fn statmount_attachment(table &MountTable, _entry &Mount, mut header StatmountResult) {
	mut entry := unsafe { _entry }
	entry.lock.acquire()
	parent := mount_by_route_locked(table, lib.mount_context_top(&entry.parent), false)
	flags := entry.flags
	entry.lock.release()
	header.mnt_id = unique_mount_id(entry)
	header.mnt_id_old = u32(entry.public_id)
	header.mnt_parent_id = if parent == unsafe { nil } { header.mnt_id } else { unique_mount_id(parent) }
	header.mnt_parent_id_old = if parent == unsafe { nil } { header.mnt_id_old } else { u32(parent.public_id) }
	header.mnt_attr = flags & (ms_rdonly | ms_nosuid | ms_nodev | ms_noexec)
	if flags & ms_nodiratime != 0 { header.mnt_attr |= mount_attr_nodiratime }
	if flags & ms_noatime != 0 {
		header.mnt_attr |= mount_attr_noatime
	} else if flags & ms_strictatime != 0 {
		header.mnt_attr |= mount_attr_strictatime
	}
	header.mnt_propagation = ms_private
	header.mask |= statmount_mnt_basic
}

fn statmount_string_start(mut strings StatmountStrings) u64 {
	if strings.used == 0 {
		unsafe { *&u8(strings.data) = 0 }
		strings.used = 1
	}
	return strings.used
}

fn append_statmount_string(mut strings StatmountStrings, value string) ?u32 {
	start := statmount_string_start(mut strings)
	length := u64(value.len)
	if length >= statmount_string_capacity - start { errno.set(errno.eoverflow); return none }
	unsafe {
		C.memcpy(voidptr(u64(strings.data) + start), value.str, length)
		*&u8(u64(strings.data) + start + length) = 0
	}
	strings.used += length + 1
	return u32(start)
}

// Build the path backwards in the unused string buffer. A filesystem-relative
// walk stays on the inode tree, while a mountpoint walk crosses attachments
// through their current parents before taking the next pathname component.
fn append_statmount_path(table &MountTable, node &VFSNode, entry &Mount, boundary &VFSNode,
	boundary_mount &Mount, mut strings StatmountStrings) ?u32 {
	start := statmount_string_start(mut strings)
	terminator := statmount_string_capacity - 1
	if start >= terminator { errno.set(errno.eoverflow); return none }
	mut position := terminator
	mut current := unsafe { node }
	mut mount := unsafe { entry }
	for _ in 0 .. 4096 {
		if current == unsafe { nil } { break }
		if voidptr(current) == voidptr(boundary) && voidptr(mount) == voidptr(boundary_mount) {
			if position == terminator {
				position--
				unsafe { *&u8(u64(strings.data) + position) = `/` }
			}
			length := terminator - position
			unsafe {
				C.memmove(voidptr(u64(strings.data) + start), voidptr(u64(strings.data) + position), length)
				*&u8(u64(strings.data) + start + length) = 0
			}
			strings.used += length + 1
			return u32(start)
		}
		if mount != unsafe { nil } && voidptr(current) == voidptr(mount.root) {
			current = mount.covered
			mount = mount_by_route_locked(table, lib.mount_context_top(&mount.parent), false)
			if mount == unsafe { nil } { break }
			continue
		}
		length := u64(current.name.len) + 1
		if length > position - start { errno.set(errno.eoverflow); return none }
		position -= length
		unsafe {
			*&u8(u64(strings.data) + position) = `/`
			C.memcpy(voidptr(u64(strings.data) + position + 1), current.name.str, length - 1)
		}
		current = current.parent
	}
	errno.set(errno.enoent)
	return none
}
