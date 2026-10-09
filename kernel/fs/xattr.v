// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Extended attributes: named values kept with a file, set and read with
// (l|f)setxattr, (l|f)getxattr, (l|f)listxattr and (l|f)removexattr. tmpfs
// and ext2 keep them; ext2 stores Linux-compatible external attribute blocks.
// Docker's overlay2 storage driver
// marks the directories of a layer that hide what is below them with
// trusted.overlay.opaque, and images carry security.capability on the
// programs they grant capabilities to.
module fs

import kbudget
import errno
import file
import proc
import posix_acl
import resource
import security
import stat
import usercopy

const xattr_create = 1
const xattr_replace = 2
const xattr_name_max = 255
const xattr_size_max = 65536

struct XAttr {
mut:
	kernel_charge kbudget.Charge
	name  string
	value []u8
}

// The attributes of one file, made when the first is set.
struct XAttrSet {
mut:
	kernel_charge kbudget.Charge
	entries []XAttr
}

// Nothing slices the entries, so one that grows frees the buffer it outgrew.
fn new_xattr_set() ?&XAttrSet {
	charge := proc.reserve_kernel(.file, u64(sizeof(XAttr)) * 256 * 2 + 256)?
	mut set := &XAttrSet{
		kernel_charge: charge
		entries: []XAttr{}
	}
	set.entries.flags |= .noslices
	return set
}

// The file a call acts on and, when it came by a name or a descriptor that
// has one, the node that names it.
struct XAttrTarget {
mut:
	node &VFSNode           = unsafe { nil }
	res  &resource.Resource = unsafe { nil }
}

// `access` is what the call asks of the file, for pledge(2) and unveil(2).
fn xattr_target_by_path(_path charptr, follow bool, access u32) ?XAttrTarget {
	path := usercopy.copy_cstring_from_user(u64(_path), 4096)?
	defer {
		unsafe { path.free() }
	}
	if path.len == 0 {
		errno.set(errno.enoent)
		return none
	}
	parent := get_parent_dir(at_fdcwd, path)?
	node := get_node(parent, path, follow)?
	if !policy_check(node, access) {
		return none
	}
	return XAttrTarget{
		node: node
		res:  node.resource
	}
}

fn xattr_target_of_fd(fd &file.FD) XAttrTarget {
	return XAttrTarget{
		node: unsafe { &VFSNode(fd.handle.node) }
		res:  fd.handle.resource
	}
}

// An attribute name, checked as Linux checks one: 1 to 255 bytes, in a
// namespace the filesystem keeps.
fn xattr_name(_name charptr) ?string {
	name := usercopy.copy_cstring_from_user(u64(_name), xattr_name_max + 1) or {
		if errno.get() == errno.enametoolong {
			errno.set(errno.erange)
		}
		return none
	}
	if name.len == 0 {
		unsafe { name.free() }
		errno.set(errno.erange)
		return none
	}
	if !posix_acl.is_name(name) && !name.starts_with('user.') && !name.starts_with('trusted.')
		&& !name.starts_with('security.') {
		unsafe { name.free() }
		errno.set(errno.enotsup)
		return none
	}
	if name == 'user.' || name == 'trusted.' || name == 'security.' {
		unsafe { name.free() }
		errno.set(errno.einval)
		return none
	}
	return name
}

// The tmpfs file behind the in-memory overlay helpers, or nil. Syscalls use
// the backend interface below, which also supports persistent ext2 storage.
fn tmpfs_resource_of(res &resource.Resource) &TmpFSResource {
	mut r := unsafe { res }
	if r != unsafe { nil } {
		if mut r is TmpFSResource {
			return r
		}
	}
	return unsafe { nil }
}

// trusted.* is for the administrator alone, to read as well as to write. An
// overlay keeps its own trusted.overlay.* in its layers and shows none of it.
fn xattr_visible(target XAttrTarget, name string) bool {
	if xattr_on_overlay(target) && name.starts_with('trusted.overlay.') {
		return false
	}
	return !name.starts_with('trusted.') || proc.current_has_capability(proc.cap_sys_admin)
}

fn xattr_on_overlay(target XAttrTarget) bool {
	return target.node != unsafe { nil } && target.node.overlay != unsafe { nil }
}

// A change through an overlay goes to the upper copy, made first.
fn xattr_target_to_change(target XAttrTarget, name string) ?XAttrTarget {
	if !xattr_on_overlay(target) {
		return target
	}
	if name.starts_with('trusted.overlay.') {
		errno.set(errno.eperm)
		return none
	}
	overlay_copy_up(target.node)?
	return XAttrTarget{
		node: target.node
		res:  target.node.resource
	}
}

// What setting or removing `name` on `target` needs, as on Linux.
fn xattr_may_change(target XAttrTarget, name string, removing bool) ? {
	mut mandatory_res := target.res
	security.mac_require(mut mandatory_res, proc.mac_metadata)?
	if target.node != unsafe { nil } && read_only(target.node) {
		errno.set(errno.erofs)
		return none
	}
	if target.node != unsafe { nil } && !attr_allows_metadata(target.node) {
		return none
	}
	if posix_acl.is_name(name) {
		if stat.islnk(target.res.stat.mode) { errno.set(errno.enotsup); return none }
		if name == posix_acl.default_name && !stat.isdir(target.res.stat.mode) {
			if removing { return }
			errno.set(errno.eacces)
			return none
		}
		if !owns_resource(target.res.stat.uid) { errno.set(errno.eperm); return none }
		return
	}
	if name.starts_with('trusted.') {
		if !proc.current_has_capability(proc.cap_sys_admin) {
			errno.set(errno.eperm)
			return none
		}
		return
	}
	if name.starts_with('security.') {
		needed := if name == security.mac_label_name { proc.cap_mac_admin }
			else if name == 'security.capability' { proc.cap_setfcap } else { proc.cap_sys_admin }
		if !proc.current_has_capability(needed) {
			errno.set(errno.eperm)
			return none
		}
		return
	}
	// user.* is only for regular files and directories, and whoever may
	// write the file may change them.
	if !stat.isreg(target.res.stat.mode) && !stat.isdir(target.res.stat.mode) {
		errno.set(errno.eperm)
		return none
	}
	if stat.isdir(target.res.stat.mode) && target.res.stat.mode & 0o1000 != 0
		&& !owns_resource(target.res.stat.uid) {
		errno.set(errno.eperm)
		return none
	}
	if target.node != unsafe { nil } {
		require_access(target.node, access_write)?
	} else if !owns_resource(target.res.stat.uid) {
		errno.set(errno.eacces)
		return none
	}
}

fn xattr_find(set &XAttrSet, name string) int {
	if set == unsafe { nil } {
		return -1
	}
	for i, entry in set.entries {
		if entry.name == name {
			return i
		}
	}
	return -1
}

fn xattr_set(given XAttrTarget, _name charptr, value voidptr, size u64, flags int) (u64, u64) {
	scratch := proc.reserve_kernel(.scratch, 4 * xattr_size_max + 1024) or { return errno.err, errno.get() }
	defer { kbudget.release(scratch) }
	if flags & ~(xattr_create | xattr_replace) != 0 { return errno.err, errno.einval }
	if size > xattr_size_max { return errno.err, errno.e2big }
	name := xattr_name(_name) or { return errno.err, errno.get() }
	defer { unsafe { name.free() } }
	label_change := name == security.mac_label_name
	if label_change && !proc.mac_begin_label_change() { return errno.err, errno.eperm }
	defer { if label_change { proc.mac_end_label_change() } }
	target := xattr_target_to_change(given, name) or { return errno.err, errno.get() }
	mut res := target.res
	if !resource.has_xattrs(mut res) { return errno.err, errno.enotsup }
	mut data := []u8{len: int(size)} @[freed]
	defer { unsafe { data.free() } }
	if size > 0 && !usercopy.copy_from_user(unsafe { &data[0] }, u64(value), size) {
		return errno.err, errno.efault
	}
	if label_change { security.mac_parse_label(data) or { return errno.err, errno.get() } }
	if posix_acl.is_name(name) && data.len != 0 && !posix_acl.valid(data) {
		return errno.err, errno.einval
	}
	xattr_may_change(target, name, data.len <= 4) or { return errno.err, errno.get() }
	mut backend_flags := if posix_acl.is_name(name) { 0 } else { flags }
	if name == posix_acl.access_name && !may_keep_setgid(res.stat.gid) {
		backend_flags |= resource.acl_clear_setgid
	}
	resource.set_xattr(mut res, name, data, backend_flags) or { return errno.err, errno.get() }
	if target.node != unsafe { nil } { inotify_emit(target.node, '', in_attrib, 0) }
	return 0, 0
}

fn xattr_may_read(target XAttrTarget, name string) ? {
	mut mandatory_res := target.res
	security.mac_require(mut mandatory_res, proc.mac_read)?
	if posix_acl.is_name(name) {
		if stat.islnk(target.res.stat.mode) { errno.set(errno.enotsup); return none }
		if name == posix_acl.default_name && !stat.isdir(target.res.stat.mode) {
			errno.set(errno.enodata)
			return none
		}
	}
	if name.starts_with('user.') {
		if !stat.isreg(target.res.stat.mode) && !stat.isdir(target.res.stat.mode) {
			errno.set(errno.enodata)
			return none
		}
		if target.node != unsafe { nil } { require_access(target.node, access_read)? }
	}
}

fn xattr_get(target XAttrTarget, _name charptr, value voidptr, size u64) (u64, u64) {
	scratch := proc.reserve_kernel(.scratch, 4 * xattr_size_max + 1024) or { return errno.err, errno.get() }
	defer { kbudget.release(scratch) }
	name := xattr_name(_name) or { return errno.err, errno.get() }
	defer { unsafe { name.free() } }
	if !xattr_visible(target, name) { return errno.err, errno.enodata }
	xattr_may_read(target, name) or { return errno.err, errno.get() }
	mut res := target.res
	mut copied := []u8{} @[freed]
	copied.flags |= .noslices
	defer { unsafe { copied.free() } }
	resource.get_xattr(mut res, name, mut copied) or { return errno.err, errno.get() }
	length := u64(copied.len)
	if size == 0 { return length, 0 }
	if size < length { return errno.err, errno.erange }
	if length > 0 && !usercopy.copy_to_user(u64(value), copied.data, length) {
		return errno.err, errno.efault
	}
	return length, 0
}

fn xattr_list(target XAttrTarget, list voidptr, size u64) (u64, u64) {
	scratch := proc.reserve_kernel(.scratch, 4 * xattr_size_max + 1024) or { return errno.err, errno.get() }
	defer { kbudget.release(scratch) }
	mut res := target.res
	security.mac_require(mut res, proc.mac_inspect) or { return errno.err, errno.get() }
	mut all_names := []u8{} @[freed]
	all_names.flags |= .noslices
	defer { unsafe { all_names.free() } }
	resource.xattr_names(mut res, mut all_names) or { return errno.err, errno.get() }
	mut names := []u8{cap: all_names.len} @[freed]
	defer { unsafe { names.free() } }
	mut start := 0
	for i, c in all_names {
		if c != 0 { continue }
		// Borrow the backend's name while its owned list is alive.
		name := unsafe { tos(&u8(u64(all_names.data) + u64(start)), i - start) }
		if xattr_visible(target, name) {
			for j in start .. i + 1 { names << all_names[j] }
		}
		start = i + 1
	}
	length := u64(names.len)
	if size == 0 { return length, 0 }
	if size < length { return errno.err, errno.erange }
	if length > 0 && !usercopy.copy_to_user(u64(list), names.data, length) {
		return errno.err, errno.efault
	}
	return length, 0
}

fn xattr_remove(given XAttrTarget, _name charptr) (u64, u64) {
	name := xattr_name(_name) or { return errno.err, errno.get() }
	defer { unsafe { name.free() } }
	label_change := name == security.mac_label_name
	if label_change && !proc.mac_begin_label_change() { return errno.err, errno.eperm }
	defer { if label_change { proc.mac_end_label_change() } }
	target := xattr_target_to_change(given, name) or { return errno.err, errno.get() }
	xattr_may_change(target, name, true) or { return errno.err, errno.get() }
	mut res := target.res
	resource.remove_xattr(mut res, name) or { return errno.err, errno.get() }
	if target.node != unsafe { nil } { inotify_emit(target.node, '', in_attrib, 0) }
	return 0, 0
}

// tmpfs owns the copied names/values until replacement, deletion, or unlink.
fn (mut res TmpFSResource) read_xattr(name string, mut value []u8) ? {
	res.l.acquire()
	defer { res.l.release() }
	index := xattr_find(res.xattrs, name)
	if index < 0 { errno.set(errno.enodata); return none }
	for c in res.xattrs.entries[index].value { value << c }
}

fn (mut res TmpFSResource) snapshot_permissions(mut acl []u8) ?resource.PermissionMetadata {
	res.l.acquire()
	defer { res.l.release() }
	index := xattr_find(res.xattrs, posix_acl.access_name)
	if index >= 0 { for byte in res.xattrs.entries[index].value { acl << byte } }
	return resource.PermissionMetadata{res.stat.mode, res.stat.uid, res.stat.gid}
}

fn (mut res TmpFSResource) write_xattr(name string, value []u8, flags int) ? {
	res.l.acquire()
	defer { res.l.release() }
	index := xattr_find(res.xattrs, name)
	if index >= 0 && flags & xattr_create != 0 { errno.set(errno.eexist); return none }
	if index < 0 && flags & xattr_replace != 0 { errno.set(errno.enodata); return none }
	if posix_acl.is_name(name) {
		if value.len != 0 && !posix_acl.valid(value) { errno.set(errno.einval); return none }
		mut requested_mode := res.stat.mode
		mut removing := value.len <= 4
		if !removing && name == posix_acl.access_name {
			derived, extended := posix_acl.mode(value, res.stat.mode)
			requested_mode = if flags & resource.acl_clear_setgid != 0 { derived & ~u32(0o2000) } else { derived }
			removing = !extended
		}
		if removing {
			if index >= 0 {
				kbudget.release(res.xattrs.entries[index].kernel_charge)
				unsafe { res.xattrs.entries[index].name.free(); res.xattrs.entries[index].value.free() }
				res.xattrs.entries.delete(index)
			}
		} else { xattr_put_bytes(mut res, name, value.clone())? }
		res.stat.mode = requested_mode
		res.stat.ctim = realtime_clock
		return
	}
	xattr_put_bytes(mut res, name, value.clone())?
	res.stat.ctim = realtime_clock
}

fn (mut res TmpFSResource) list_xattrs(mut names []u8) ? {
	res.l.acquire()
	defer { res.l.release() }
	if res.xattrs != unsafe { nil } {
		for entry in res.xattrs.entries {
			for c in entry.name { names << c }
			names << 0
		}
	}
}

fn (mut res TmpFSResource) delete_xattr(name string) ? {
	res.l.acquire()
	defer { res.l.release() }
	index := xattr_find(res.xattrs, name)
	if index < 0 {
		if posix_acl.is_name(name) { return }
		errno.set(errno.enodata)
		return none
	}
	kbudget.release(res.xattrs.entries[index].kernel_charge)
	unsafe {
		res.xattrs.entries[index].name.free()
		res.xattrs.entries[index].value.free()
	}
	res.xattrs.entries.delete(index)
	res.stat.ctim = realtime_clock
}

// Whether a tmpfs file has the attribute `name` set to `expected`.
fn xattr_equals(res &resource.Resource, name string, expected string) bool {
	mut tfile := tmpfs_resource_of(res)
	if tfile == unsafe { nil } {
		return false
	}
	tfile.l.acquire()
	defer {
		tfile.l.release()
	}
	index := xattr_find(tfile.xattrs, name)
	if index < 0 {
		return false
	}
	value := tfile.xattrs.entries[index].value
	if value.len != expected.len {
		return false
	}
	for i in 0 .. value.len {
		if value[i] != expected[i] {
			return false
		}
	}
	return true
}

fn xattr_put_bytes(mut tfile TmpFSResource, name string, value []u8) ? {
	mut installed := false
	defer { if !installed { unsafe { value.free() } } }
	if tfile.xattrs == unsafe { nil } { tfile.xattrs = new_xattr_set()? }
	if tfile.xattrs.entries.len >= 256 && xattr_find(tfile.xattrs, name) < 0 { errno.set(errno.enospc); return none }
	charge := proc.reserve_kernel(.file, u64(value.cap) * 2 + u64(name.len) * 2 + 256)?
	index := xattr_find(tfile.xattrs, name)
	if index >= 0 {
		kbudget.release(tfile.xattrs.entries[index].kernel_charge)
		unsafe { tfile.xattrs.entries[index].value.free() }
		tfile.xattrs.entries[index].kernel_charge = charge
		installed = true
		tfile.xattrs.entries[index].value = value
		return
	}
	tfile.xattrs.entries << XAttr{
		kernel_charge: charge
		name:  name.clone()
		value: value
	}
	installed = true
}

// Set an attribute from inside the kernel, as overlay marks a directory
// opaque. Files that keep none are left alone.
fn xattr_put(res &resource.Resource, name string, value string) ? {
	mut tfile := tmpfs_resource_of(res)
	if tfile == unsafe { nil } {
		return
	}
	tfile.l.acquire()
	defer {
		tfile.l.release()
	}
	xattr_put_bytes(mut tfile, name, value.bytes())?
}

// Backends copy the input before returning. A value removed after listing is
// absent from this copy; other failures must prevent publishing the upper file.
fn copy_one_xattr(mut source resource.Resource, mut dest resource.Resource, name string) ? {
	mut value := []u8{} @[freed]
	value.flags |= .noslices
	defer { unsafe { value.free() } }
	resource.get_xattr(mut source, name, mut value) or {
		if errno.get() == errno.enodata { return }
		return none
	}
	resource.set_xattr(mut dest, name, value, 0)?
}

// Give `to` the attributes `from` has, except names beginning with `skip`.
// The list and each value are caller-owned snapshots. No backend name is
// borrowed across its lock release, including when the source is changed.
fn copy_xattrs(from &resource.Resource, to &resource.Resource, skip string) ? {
	mut source := unsafe { from }
	mut dest := unsafe { to }
	mut names := []u8{} @[freed]
	names.flags |= .noslices
	defer { unsafe { names.free() } }
	resource.xattr_names(mut source, mut names)?
	mut start := 0
	for i, c in names {
		if c != 0 { continue }
		name := unsafe { tos(&u8(u64(names.data) + u64(start)), i - start) }
		if name.len == 0 { errno.set(errno.eio); return none }
		if !name.starts_with(skip) { copy_one_xattr(mut source, mut dest, name)? }
		start = i + 1
	}
	if start != names.len { errno.set(errno.eio); return none }
}

// Called when a tmpfs file goes.
fn free_xattrs(set &XAttrSet) {
	if set == unsafe { nil } {
		return
	}
	mut owned := unsafe { set }
	for mut entry in owned.entries {
		kbudget.release(entry.kernel_charge)
		unsafe {
			entry.name.free()
			entry.value.free()
		}
	}
	kbudget.release(owned.kernel_charge)
	unsafe {
		owned.entries.free()
		free(owned)
	}
}

fn (mut res TmpFSResource) sync_acl_mode() ? {
	res.l.acquire()
	defer { res.l.release() }
	res.sync_acl_mode_locked(res.stat.mode)?
}

fn (mut res TmpFSResource) chmod_mode(mode u32) ? {
	res.l.acquire()
	defer { res.l.release() }
	desired := (res.stat.mode & stat.ifmt) | (mode & 0o7777)
	res.sync_acl_mode_locked(desired)?
	res.stat.mode = desired
	res.stat.ctim = realtime_clock
}

fn (mut res TmpFSResource) sync_acl_mode_locked(mode u32) ? {
	index := xattr_find(res.xattrs, posix_acl.access_name)
	if index >= 0 {
		if !posix_acl.valid(res.xattrs.entries[index].value)
			|| res.xattrs.entries[index].value.len <= 4 { errno.set(errno.eio); return none }
		posix_acl.chmod(mut res.xattrs.entries[index].value, mode)
	}
}

pub fn syscall_setxattr(_ voidptr, _path charptr, _name charptr, value voidptr, size u64, flags int) (u64, u64) {
	target := xattr_target_by_path(_path, true, proc.policy_fattr) or { return errno.err, errno.get() }
	return xattr_set(target, _name, value, size, flags)
}

pub fn syscall_lsetxattr(_ voidptr, _path charptr, _name charptr, value voidptr, size u64, flags int) (u64, u64) {
	target := xattr_target_by_path(_path, false, proc.policy_fattr) or { return errno.err, errno.get() }
	return xattr_set(target, _name, value, size, flags)
}

pub fn syscall_fsetxattr(_ voidptr, fdnum int, _name charptr, value voidptr, size u64, flags int) (u64, u64) {
	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}
	fd.handle.mac_check(proc.mac_metadata) or { return errno.err, errno.get() }
	return xattr_set(xattr_target_of_fd(fd), _name, value, size, flags)
}

pub fn syscall_getxattr(_ voidptr, _path charptr, _name charptr, value voidptr, size u64) (u64, u64) {
	target := xattr_target_by_path(_path, true, proc.policy_read) or { return errno.err, errno.get() }
	return xattr_get(target, _name, value, size)
}

pub fn syscall_lgetxattr(_ voidptr, _path charptr, _name charptr, value voidptr, size u64) (u64, u64) {
	target := xattr_target_by_path(_path, false, proc.policy_read) or { return errno.err, errno.get() }
	return xattr_get(target, _name, value, size)
}

pub fn syscall_fgetxattr(_ voidptr, fdnum int, _name charptr, value voidptr, size u64) (u64, u64) {
	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}
	fd.handle.mac_check(proc.mac_read) or { return errno.err, errno.get() }
	return xattr_get(xattr_target_of_fd(fd), _name, value, size)
}

pub fn syscall_listxattr(_ voidptr, _path charptr, list voidptr, size u64) (u64, u64) {
	target := xattr_target_by_path(_path, true, proc.policy_read) or { return errno.err, errno.get() }
	return xattr_list(target, list, size)
}

pub fn syscall_llistxattr(_ voidptr, _path charptr, list voidptr, size u64) (u64, u64) {
	target := xattr_target_by_path(_path, false, proc.policy_read) or { return errno.err, errno.get() }
	return xattr_list(target, list, size)
}

pub fn syscall_flistxattr(_ voidptr, fdnum int, list voidptr, size u64) (u64, u64) {
	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}
	fd.handle.mac_check(proc.mac_inspect) or { return errno.err, errno.get() }
	return xattr_list(xattr_target_of_fd(fd), list, size)
}

pub fn syscall_removexattr(_ voidptr, _path charptr, _name charptr) (u64, u64) {
	target := xattr_target_by_path(_path, true, proc.policy_fattr) or { return errno.err, errno.get() }
	return xattr_remove(target, _name)
}

pub fn syscall_lremovexattr(_ voidptr, _path charptr, _name charptr) (u64, u64) {
	target := xattr_target_by_path(_path, false, proc.policy_fattr) or { return errno.err, errno.get() }
	return xattr_remove(target, _name)
}

pub fn syscall_fremovexattr(_ voidptr, fdnum int, _name charptr) (u64, u64) {
	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}
	fd.handle.mac_check(proc.mac_metadata) or { return errno.err, errno.get() }
	return xattr_remove(xattr_target_of_fd(fd), _name)
}

// Reserve an opacity marker before creating a directory or removing the
// whiteout it replaces. Installing this prepared entry cannot fail a quota.
fn prepare_opaque_xattr() ?&XAttrSet {
 mut set := new_xattr_set()?
 charge := proc.reserve_kernel(.file, 512) or { free_xattrs(set); return none }
 value := [u8(`y`)] @[freed]
 set.entries << XAttr{kernel_charge: charge, name: 'trusted.overlay.opaque'.clone(), value: value}
 return set
}
fn install_opaque_xattr(res &resource.Resource, prepared &XAttrSet) {
 mut tfile := tmpfs_resource_of(res)
 if tfile == unsafe { nil } { free_xattrs(prepared); return }
 tfile.l.acquire()
 defer { tfile.l.release() }
 if tfile.xattrs == unsafe { nil } { tfile.xattrs = unsafe { prepared }; return }
 // The freshly created directory can only have its inherited security label.
 assert tfile.xattrs.entries.len < 256
 tfile.xattrs.entries << prepared.entries[0]
 mut owned := unsafe { prepared }
 owned.entries.clear()
 free_xattrs(owned)
}
