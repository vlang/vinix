// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Extended attributes: named values kept with a file, set and read with
// (l|f)setxattr, (l|f)getxattr, (l|f)listxattr and (l|f)removexattr. tmpfs
// keeps them, as Linux's does; every other filesystem answers ENOTSUP, which
// is what one without them says on Linux. Docker's overlay2 storage driver
// marks the directories of a layer that hide what is below them with
// trusted.overlay.opaque, and images carry security.capability on the
// programs they grant capabilities to.
module fs

import errno
import file
import proc
import resource
import stat
import usercopy

const xattr_create = 1
const xattr_replace = 2
const xattr_name_max = 255
const xattr_size_max = 65536

struct XAttr {
mut:
	name  string
	value []u8
}

// The attributes of one file, made when the first is set.
struct XAttrSet {
mut:
	entries []XAttr
}

// The file a call acts on and, when it came by a name or a descriptor that
// has one, the node that names it.
struct XAttrTarget {
mut:
	node &VFSNode           = unsafe { nil }
	res  &resource.Resource = unsafe { nil }
}

fn xattr_target_by_path(_path charptr, follow bool) ?XAttrTarget {
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
// namespace the filesystem keeps. There are no ACLs to keep system.* in.
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
	if !name.starts_with('user.') && !name.starts_with('trusted.')
		&& !name.starts_with('security.') {
		unsafe { name.free() }
		errno.set(errno.enotsup)
		return none
	}
	return name
}

// The tmpfs file behind a resource, or nil: the only kind that keeps
// attributes.
fn tmpfs_resource_of(res &resource.Resource) &TmpFSResource {
	mut r := unsafe { res }
	if r != unsafe { nil } {
		if mut r is TmpFSResource {
			return r
		}
	}
	return unsafe { nil }
}

fn xattr_store(target XAttrTarget) ?&TmpFSResource {
	res := tmpfs_resource_of(target.res)
	if res == unsafe { nil } {
		errno.set(errno.enotsup)
		return none
	}
	return res
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
fn xattr_may_change(target XAttrTarget, res &TmpFSResource, name string) ? {
	if target.node != unsafe { nil } && read_only(target.node) {
		errno.set(errno.erofs)
		return none
	}
	if name.starts_with('trusted.') {
		if !proc.current_has_capability(proc.cap_sys_admin) {
			errno.set(errno.eperm)
			return none
		}
		return
	}
	if name.starts_with('security.') {
		needed := if name == 'security.capability' { proc.cap_setfcap } else { proc.cap_sys_admin }
		if !proc.current_has_capability(needed) {
			errno.set(errno.eperm)
			return none
		}
		return
	}
	// user.* is only for regular files and directories, and whoever may
	// write the file may change them.
	if !stat.isreg(res.stat.mode) && !stat.isdir(res.stat.mode) {
		errno.set(errno.eperm)
		return none
	}
	if target.node != unsafe { nil } {
		require_access(target.node, access_write)?
	} else if !owns_resource(res.stat.uid) {
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
	if flags & ~(xattr_create | xattr_replace) != 0 {
		return errno.err, errno.einval
	}
	if size > xattr_size_max {
		return errno.err, errno.e2big
	}
	name := xattr_name(_name) or { return errno.err, errno.get() }
	target := xattr_target_to_change(given, name) or {
		unsafe { name.free() }
		return errno.err, errno.get()
	}
	mut res := xattr_store(target) or {
		unsafe { name.free() }
		return errno.err, errno.get()
	}
	xattr_may_change(target, res, name) or {
		unsafe { name.free() }
		return errno.err, errno.get()
	}
	mut data := []u8{len: int(size)}
	if size > 0 && !usercopy.copy_from_user(&data[0], u64(value), size) {
		unsafe {
			name.free()
			data.free()
		}
		return errno.err, errno.efault
	}

	res.l.acquire()
	index := xattr_find(res.xattrs, name)
	if index >= 0 && flags & xattr_create != 0 {
		res.l.release()
		unsafe {
			name.free()
			data.free()
		}
		return errno.err, errno.eexist
	}
	if index < 0 && flags & xattr_replace != 0 {
		res.l.release()
		unsafe {
			name.free()
			data.free()
		}
		return errno.err, errno.enodata
	}
	if res.xattrs == unsafe { nil } {
		res.xattrs = &XAttrSet{
			entries: []XAttr{}
		}
	}
	if index >= 0 {
		unsafe {
			res.xattrs.entries[index].value.free()
			name.free()
		}
		res.xattrs.entries[index].value = data
	} else {
		res.xattrs.entries << XAttr{
			name:  name
			value: data
		}
	}
	res.stat.ctim = realtime_clock
	res.l.release()
	if target.node != unsafe { nil } {
		inotify_emit(target.node, '', in_attrib, 0)
	}
	return 0, 0
}

fn xattr_get(target XAttrTarget, _name charptr, value voidptr, size u64) (u64, u64) {
	mut res := xattr_store(target) or { return errno.err, errno.get() }
	name := xattr_name(_name) or { return errno.err, errno.get() }
	defer {
		unsafe { name.free() }
	}
	if !xattr_visible(target, name) {
		return errno.err, errno.enodata
	}
	// Copied out under the lock and to the caller after it: the caller's
	// buffer could be this very file mapped, and faulting it in takes the lock.
	res.l.acquire()
	index := xattr_find(res.xattrs, name)
	if index < 0 {
		res.l.release()
		return errno.err, errno.enodata
	}
	copied := res.xattrs.entries[index].value.clone()
	res.l.release()
	defer {
		unsafe { copied.free() }
	}
	length := u64(copied.len)
	if size == 0 {
		return length, 0
	}
	if size < length {
		return errno.err, errno.erange
	}
	if length > 0 && !usercopy.copy_to_user(u64(value), copied.data, length) {
		return errno.err, errno.efault
	}
	return length, 0
}

// The names, each followed by a NUL, that the caller may see.
fn xattr_list(target XAttrTarget, list voidptr, size u64) (u64, u64) {
	mut res := xattr_store(target) or {
		// A file on a filesystem without attributes has none to list.
		if errno.get() == errno.enotsup {
			return 0, 0
		}
		return errno.err, errno.get()
	}
	mut names := []u8{}
	defer {
		unsafe { names.free() }
	}
	// Gathered under the lock and copied to the caller after it, as in
	// xattr_get().
	res.l.acquire()
	if res.xattrs != unsafe { nil } {
		for entry in res.xattrs.entries {
			if !xattr_visible(target, entry.name) {
				continue
			}
			for c in entry.name {
				names << c
			}
			names << 0
		}
	}
	res.l.release()
	length := u64(names.len)
	if size == 0 {
		return length, 0
	}
	if size < length {
		return errno.err, errno.erange
	}
	if length > 0 && !usercopy.copy_to_user(u64(list), names.data, length) {
		return errno.err, errno.efault
	}
	return length, 0
}

fn xattr_remove(given XAttrTarget, _name charptr) (u64, u64) {
	name := xattr_name(_name) or { return errno.err, errno.get() }
	defer {
		unsafe { name.free() }
	}
	target := xattr_target_to_change(given, name) or { return errno.err, errno.get() }
	mut res := xattr_store(target) or { return errno.err, errno.get() }
	xattr_may_change(target, res, name) or { return errno.err, errno.get() }
	res.l.acquire()
	index := xattr_find(res.xattrs, name)
	if index < 0 {
		res.l.release()
		return errno.err, errno.enodata
	}
	unsafe {
		res.xattrs.entries[index].name.free()
		res.xattrs.entries[index].value.free()
	}
	res.xattrs.entries.delete(index)
	res.stat.ctim = realtime_clock
	res.l.release()
	if target.node != unsafe { nil } {
		inotify_emit(target.node, '', in_attrib, 0)
	}
	return 0, 0
}

// Whether a tmpfs file has the attribute `name` set to `expected`.
fn xattr_equals(res &resource.Resource, name string, expected string) bool {
	mut file := tmpfs_resource_of(res)
	if file == unsafe { nil } {
		return false
	}
	file.l.acquire()
	defer {
		file.l.release()
	}
	index := xattr_find(file.xattrs, name)
	if index < 0 {
		return false
	}
	value := file.xattrs.entries[index].value
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

fn xattr_put_bytes(mut file TmpFSResource, name string, value []u8) {
	if file.xattrs == unsafe { nil } {
		file.xattrs = &XAttrSet{
			entries: []XAttr{}
		}
	}
	index := xattr_find(file.xattrs, name)
	if index >= 0 {
		unsafe { file.xattrs.entries[index].value.free() }
		file.xattrs.entries[index].value = value
		return
	}
	file.xattrs.entries << XAttr{
		name:  name.clone()
		value: value
	}
}

// Set an attribute from inside the kernel, as overlay marks a directory
// opaque. Files that keep none are left alone.
fn xattr_put(res &resource.Resource, name string, value string) {
	mut file := tmpfs_resource_of(res)
	if file == unsafe { nil } {
		return
	}
	file.l.acquire()
	defer {
		file.l.release()
	}
	xattr_put_bytes(mut file, name, value.bytes())
}

// Give `to` the attributes `from` has, but for those whose names start with
// `skip`.
fn copy_xattrs(from &resource.Resource, to &resource.Resource, skip string) {
	mut source := tmpfs_resource_of(from)
	mut dest := tmpfs_resource_of(to)
	if source == unsafe { nil } || dest == unsafe { nil } || source.xattrs == unsafe { nil } {
		return
	}
	mut copied := []XAttr{}
	source.l.acquire()
	for entry in source.xattrs.entries {
		if !entry.name.starts_with(skip) {
			copied << XAttr{
				name:  entry.name
				value: entry.value.clone()
			}
		}
	}
	source.l.release()
	dest.l.acquire()
	for entry in copied {
		xattr_put_bytes(mut dest, entry.name, entry.value)
	}
	dest.l.release()
	unsafe { copied.free() }
}

// Called when a tmpfs file goes.
fn free_xattrs(set &XAttrSet) {
	if set == unsafe { nil } {
		return
	}
	mut owned := unsafe { set }
	for mut entry in owned.entries {
		unsafe {
			entry.name.free()
			entry.value.free()
		}
	}
	unsafe {
		owned.entries.free()
		free(owned)
	}
}

pub fn syscall_setxattr(_ voidptr, _path charptr, _name charptr, value voidptr, size u64, flags int) (u64, u64) {
	target := xattr_target_by_path(_path, true) or { return errno.err, errno.get() }
	return xattr_set(target, _name, value, size, flags)
}

pub fn syscall_lsetxattr(_ voidptr, _path charptr, _name charptr, value voidptr, size u64, flags int) (u64, u64) {
	target := xattr_target_by_path(_path, false) or { return errno.err, errno.get() }
	return xattr_set(target, _name, value, size, flags)
}

pub fn syscall_fsetxattr(_ voidptr, fdnum int, _name charptr, value voidptr, size u64, flags int) (u64, u64) {
	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}
	return xattr_set(xattr_target_of_fd(fd), _name, value, size, flags)
}

pub fn syscall_getxattr(_ voidptr, _path charptr, _name charptr, value voidptr, size u64) (u64, u64) {
	target := xattr_target_by_path(_path, true) or { return errno.err, errno.get() }
	return xattr_get(target, _name, value, size)
}

pub fn syscall_lgetxattr(_ voidptr, _path charptr, _name charptr, value voidptr, size u64) (u64, u64) {
	target := xattr_target_by_path(_path, false) or { return errno.err, errno.get() }
	return xattr_get(target, _name, value, size)
}

pub fn syscall_fgetxattr(_ voidptr, fdnum int, _name charptr, value voidptr, size u64) (u64, u64) {
	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}
	return xattr_get(xattr_target_of_fd(fd), _name, value, size)
}

pub fn syscall_listxattr(_ voidptr, _path charptr, list voidptr, size u64) (u64, u64) {
	target := xattr_target_by_path(_path, true) or { return errno.err, errno.get() }
	return xattr_list(target, list, size)
}

pub fn syscall_llistxattr(_ voidptr, _path charptr, list voidptr, size u64) (u64, u64) {
	target := xattr_target_by_path(_path, false) or { return errno.err, errno.get() }
	return xattr_list(target, list, size)
}

pub fn syscall_flistxattr(_ voidptr, fdnum int, list voidptr, size u64) (u64, u64) {
	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}
	return xattr_list(xattr_target_of_fd(fd), list, size)
}

pub fn syscall_removexattr(_ voidptr, _path charptr, _name charptr) (u64, u64) {
	target := xattr_target_by_path(_path, true) or { return errno.err, errno.get() }
	return xattr_remove(target, _name)
}

pub fn syscall_lremovexattr(_ voidptr, _path charptr, _name charptr) (u64, u64) {
	target := xattr_target_by_path(_path, false) or { return errno.err, errno.get() }
	return xattr_remove(target, _name)
}

pub fn syscall_fremovexattr(_ voidptr, fdnum int, _name charptr) (u64, u64) {
	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
	defer {
		fd.unref()
	}
	return xattr_remove(xattr_target_of_fd(fd), _name)
}
