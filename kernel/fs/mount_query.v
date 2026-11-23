// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import errno
import kbudget
import lib
import memory
import proc
import usercopy
import vmstorage

const listmount_root = u64(-1)
const listmount_reverse = u32(1)
const listmount_max_ids = u64(1_000_000)
const listmount_stack_ids = 32
const mount_request_v0 = u64(24)

struct MountIdRequest {
mut:
	size u32
	spare u32
	id u64
	cursor u64
	namespace_id u64
}

fn read_mount_id_request(address u64) ?MountIdRequest {
	mut size := u32(0)
	if !usercopy.copy_from_user(unsafe { &size }, address, sizeof(u32)) {
		errno.set(errno.efault)
		return none
	}
	if u64(size) > memory.page_size { errno.set(errno.e2big); return none }
	if size < mount_request_v0 { errno.set(errno.einval); return none }
	if !usercopy.user_range(address, u64(size)) { errno.set(errno.efault); return none }

	// Read the extension first, in chunks that never cross a page. An
	// unsupported nonzero word takes precedence over a later copy fault.
	mut offset := u64(sizeof(MountIdRequest))
	for offset < size {
		start := address + offset
		length := if u64(size) - offset < 8 - (start & 7) { u64(size) - offset } else { 8 - (start & 7) }
		mut word := u64(0)
		if !usercopy.copy_from_user(unsafe { &word }, start, length) {
			errno.set(errno.efault)
			return none
		}
		if word != 0 { errno.set(errno.e2big); return none }
		offset += length
	}
	mut request := MountIdRequest{}
	length := if size < sizeof(MountIdRequest) { u64(size) } else { u64(sizeof(MountIdRequest)) }
	if !usercopy.copy_from_user(unsafe { &request }, address, length) {
		errno.set(errno.efault)
		return none
	}
	if request.spare != 0 || request.id <= mount_unique_id_offset {
		errno.set(errno.einval)
		return none
	}
	return request
}

pub fn syscall_listmount(_ voidptr, address u64, output u64, count u64, flags u32) (u64, u64) {
	if flags & ~listmount_reverse != 0 { return errno.err, errno.einval }
	if count > listmount_max_ids { return errno.err, errno.eoverflow }
	bytes := count * sizeof(u64)
	// The initial check is numerical. A low but unmapped address only
	// faults if the query actually has IDs to copy.
	limit := memory.user_address_limit()
	if output > limit || bytes > limit - output { return errno.err, errno.efault }
	mut request := read_mount_id_request(address) or { return errno.err, errno.get() }
	if request.cursor != 0 && request.cursor <= mount_unique_id_offset {
		return errno.err, errno.einval
	}
	reverse := flags & listmount_reverse != 0
	// Linux starts the forward search at cursor + 1 in an unsigned word.
	if !reverse && request.cursor == u64(-1) { request.cursor = 0 }
	if count <= listmount_stack_ids {
		mut stack := [listmount_stack_ids]u64{}
		return listmount_to_user(request, output, count, reverse, unsafe { &stack[0] })
	}
	reservation := vmstorage.allocation_bytes(bytes) or { return errno.err, errno.enomem }
	charge := proc.reserve_kernel(.scratch, reservation) or { return errno.err, errno.get() }
	defer { kbudget.release(charge) }
	buffer := memory.malloc_packed_fallible(bytes) @[freed]
	if buffer == unsafe { nil } { return errno.err, errno.enomem }
	defer { unsafe { free(buffer) } }
	return listmount_to_user(request, output, count, reverse, unsafe { &u64(buffer) })
}

fn listmount_to_user(request MountIdRequest, output u64, count u64, reverse bool, ids &u64) (u64, u64) {
	length := listmount_snapshot(request, count, reverse, ids) or { return errno.err, errno.get() }
	if length > 0 && !usercopy.copy_to_user(output, ids, length * sizeof(u64)) {
		return errno.err, errno.efault
	}
	return length, 0
}

fn listmount_snapshot(request MountIdRequest, count u64, reverse bool, ids &u64) ?u64 {
	vfs_lock.acquire()
	defer { vfs_lock.release() }
	process := calling_process()
	ns := proc.mount_namespace_of(process)
	if request.namespace_id != 0 && (ns == unsafe { nil } || request.namespace_id != ns.id) {
		errno.set(errno.enoent)
		return none
	}
	mut table := if ns == unsafe { nil } || ns.data == unsafe { nil } {
		initial_mount_table
	} else {
		unsafe { &MountTable(ns.data) }
	}
	context := unsafe { &lib.MountContext(C.vinix_stack_alloc(sizeof(lib.MountContext))) }
	saved := proc.snapshot_root_directory(process, context)
	root := if saved == unsafe { nil } {
		root_with_context(context)?
	} else {
		node := unsafe { &VFSNode(saved) }
		// A saved chroot is a path in the attachment originally opened.
		// An overmount on the same inode does not replace that path.
		if context.depth == 0 && !native_context(node, context) { return none }
		node
	}
	if voidptr(proc.mount_namespace_of(process)) != voidptr(ns) {
		errno.set(errno.eagain)
		return none
	}
	mut origin := root
	table.lock.acquire()
	if table.released {
		table.lock.release()
		errno.set(errno.enoent)
		return none
	}
	root_entry := mount_by_route_locked(table, lib.mount_context_top(context), true)
	mut anchor := root_entry
	if request.id != listmount_root {
		anchor = find_public_mount_locked(table, request.id)
		if anchor == unsafe { nil } {
			table.lock.release()
			errno.set(errno.enoent)
			return none
		}
		origin = anchor.root
		owner := if ns == unsafe { nil } { proc.user_namespace_of(unsafe { nil }) } else { ns.owner_user }
		if (root_entry == unsafe { nil } || !mount_path_beneath_locked(table, origin, anchor, root, root_entry))
			&& !proc.has_namespace_capability(process, proc.cap_sys_admin, owner) {
			table.lock.release()
			errno.set(errno.eperm)
			return none
		}
	}
	length := if anchor == unsafe { nil } { u64(0) } else {
		write_mount_ids_locked(table, origin, anchor, request, count, reverse, ids)
	}
	table.lock.release()
	// Like statfs, inspecting the starting object still needs metadata access.
	if !policy_check(origin, proc.policy_inspect) { return none }
	return length
}

fn unique_mount_id(entry &Mount) u64 {
	return mount_unique_id_offset + u64(entry.public_id)
}

fn find_public_mount_locked(table &MountTable, id u64) &Mount {
	for entry in table.mounts {
		current := unique_mount_id(entry)
		if current > id { break }
		if current == id && !entry.detached { return entry }
	}
	return unsafe { nil }
}

fn write_mount_ids_locked(table &MountTable, origin &VFSNode, anchor &Mount, request MountIdRequest,
	count u64, reverse bool, ids &u64) u64 {
	mut length := u64(0)
	for index := 0; index < table.mounts.len && length < count; index++ {
		entry := table.mounts[if reverse { table.mounts.len - index - 1 } else { index }]
		if entry.detached { continue }
		id := unique_mount_id(entry)
		if id == request.id { continue }
		if request.cursor != 0 && (if reverse { id >= request.cursor } else { id <= request.cursor }) {
			continue
		}
		if mount_path_beneath_locked(table, entry.root, entry, origin, anchor) {
			unsafe { ids[length] = id }
			length++
		}
	}
	return length
}
