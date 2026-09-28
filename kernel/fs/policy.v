// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Where pledge(2) and unveil(2) meet the filesystem. Every syscall that names
// a file checks the access it asks for once the name is resolved, against the
// node the operation then goes on to use: judging a path string ahead of the
// lookup would let a symbolic link swapped in between send the operation
// somewhere the check never looked. A name about to be made is judged by its
// directory and its last component. The checks are made by the syscalls
// rather than by walk_path(), which the kernel's own lookups -- an ELF
// interpreter, an overlay's lower layer -- go through as well.
//
// The syscalls themselves are here too; the syscall tables install them. See
// proc/pledge.v and proc/unveil.v for the rules.
module fs

import errno
import lib
import proc
import resource
import stat
import usercopy

// The path unveil(2) judges a file by: from the system root, through the
// caller's mounts. The process's own root would do for a process that never
// moves it, but a chroot(2) after unveiling would then rename every file
// under an unveiled path.
fn policy_path(node &VFSNode) string {
	return path_from_root(node, vfs_root) or { global_pathname(node) }
}

// Built in one buffer: `directory + '/' + name` made a string for the first
// `+` that nothing freed. Callers free the result.
fn join_policy_path(directory string, name string) string {
	mut text := lib.new_text(directory.len + name.len + 1)
	if directory != '/' {
		text.add(directory)
	}
	text.add_byte(`/`)
	text.add(name)
	return text.str()
}

@[inline]
fn policy_restricted(process &proc.Process) bool {
	return process.pledge != 0 || process.unveil != unsafe { nil }
}

// `name_path` is set for a name that does not exist yet, which the node its
// directory is judged by stands in for.
fn policy_check_impl(node &VFSNode, name string, access u32) bool {
	process := proc.current_thread().process
	mut skip_unveil := false
	if process.pledge & proc.pledge_set != 0 {
		promises := process.pledge & ~proc.pledge_set
		if proc.pledge_path_promises(access) & ~promises != 0 {
			// The whitelist names files as the process itself sees them,
			// chroot and all.
			directory := pathname(node)
			path := if name == '' { directory } else { join_policy_path(directory, name) }
			code, skip := proc.pledge_path_verdict(process, path, access)
			if name != '' {
				unsafe { path.free() }
			}
			unsafe { directory.free() }
			if code != 0 {
				errno.set(code)
				return false
			}
			skip_unveil = skip
		}
	}
	if skip_unveil || process.unveil == unsafe { nil } {
		return true
	}
	directory := policy_path(node)
	mut is_dir := false
	path := if name == '' {
		if node.resource != unsafe { nil } {
			is_dir = stat.isdir(node.resource.stat.mode)
		}
		directory
	} else {
		join_policy_path(directory, name)
	}
	code := proc.unveil_verdict(process, path, access, is_dir)
	if name != '' {
		unsafe { path.free() }
	}
	unsafe { directory.free() }
	if code != 0 {
		errno.set(code)
		return false
	}
	return true
}

// Whether the calling process may make `access` (proc.policy_*) to `node`,
// the file a lookup ended at. Sets errno when it may not.
pub fn policy_check(node &VFSNode, access u32) bool {
	if !policy_restricted(proc.current_thread().process) {
		return true
	}
	if node == unsafe { nil } {
		errno.set(errno.enoent)
		return false
	}
	return policy_check_impl(node, '', access)
}

// Whether the calling process may make `access` to the name `name` in
// `directory`, which it is about to create or remove.
pub fn policy_check_name(directory &VFSNode, name string, access u32) bool {
	if !policy_restricted(proc.current_thread().process) {
		return true
	}
	if directory == unsafe { nil } {
		errno.set(errno.enoent)
		return false
	}
	return policy_check_impl(directory, name, access)
}

// The access open(2) asks of a file with `flags`.
pub fn policy_open_access(flags int) u32 {
	if flags & resource.o_path != 0 {
		return proc.policy_inspect
	}
	mut access := u32(0)
	accmode := flags & 3
	if accmode == resource.o_rdonly || accmode == resource.o_rdwr {
		access |= proc.policy_read
	}
	if accmode == resource.o_wronly || accmode == resource.o_rdwr
		|| flags & resource.o_trunc != 0 {
		access |= proc.policy_write
	}
	// OpenBSD asks for "cpath" and unveil's "c" whenever O_CREAT is given,
	// whether or not the file is there already: fopen(path, "w") needs both.
	if flags & resource.o_creat != 0 {
		access |= proc.policy_create
	}
	return access
}

// mount(2), umount(2) and pivot_root(2) could change what an unveiled path
// names, so a process that has unveiled anything may not make them. pledge(2)
// refuses them already: no promise covers them. chroot(2) is harmless, since
// unveiled paths are judged from the system root.
pub fn policy_may_change_mounts() bool {
	if proc.current_thread().process.unveil != unsafe { nil } {
		errno.set(errno.eperm)
		return false
	}
	return true
}

fn optional_policy_string(address u64, limit int) ?(bool, string) {
	if address == 0 {
		return false, ''
	}
	text := usercopy.copy_cstring_from_user(address, limit) or {
		if errno.get() == errno.enametoolong {
			errno.set(errno.e2big)
		}
		return none
	}
	return true, text
}

// pledge(promises, execpromises). Either may be NULL to leave that set as it
// is; a promise once given up cannot be taken back.
pub fn syscall_pledge(_ voidptr, promises_ptr u64, execpromises_ptr u64) (u64, u64) {
	has_promises, promises_text := optional_policy_string(promises_ptr, proc.pledge_max_text) or {
		return errno.err, errno.get()
	}
	defer {
		unsafe { promises_text.free() }
	}
	has_exec, exec_text := optional_policy_string(execpromises_ptr, proc.pledge_max_text) or {
		return errno.err, errno.get()
	}
	defer {
		unsafe { exec_text.free() }
	}
	mut promises := u64(0)
	if has_promises {
		promises = proc.pledge_parse(promises_text) or { return errno.err, errno.einval }
	}
	mut execpromises := u64(0)
	if has_exec {
		execpromises = proc.pledge_parse(exec_text) or { return errno.err, errno.einval }
	}
	mut process := proc.current_thread().process
	code := proc.pledge_apply(mut process, has_promises, promises, has_exec, execpromises)
	if code != 0 {
		return errno.err, code
	}
	return 0, 0
}

// unveil(path, permissions), and unveil(NULL, NULL) to lock the view. The
// path is resolved from the working directory, following a final symbolic
// link; it need not exist yet if the directory it would be made in does.
// unveil(2) itself is never refused by the view it builds -- until locked, it
// can reach anywhere to show more.
pub fn syscall_unveil(_ voidptr, path_ptr u64, perms_ptr u64) (u64, u64) {
	mut process := proc.current_thread().process
	if path_ptr == 0 && perms_ptr == 0 {
		proc.unveil_lock(mut process)
		return 0, 0
	}
	if path_ptr == 0 || perms_ptr == 0 {
		return errno.err, errno.einval
	}
	if proc.unveil_is_locked(process) {
		return errno.err, errno.eperm
	}
	perms_text := usercopy.copy_cstring_from_user(perms_ptr, 16) or {
		return errno.err, errno.get()
	}
	perms := proc.unveil_parse(perms_text) or {
		unsafe { perms_text.free() }
		return errno.err, errno.einval
	}
	unsafe { perms_text.free() }
	path := usercopy.copy_cstring_from_user(path_ptr, 4096) or { return errno.err, errno.get() }
	defer {
		unsafe { path.free() }
	}
	if path.len == 0 {
		return errno.err, errno.enoent
	}
	parent := get_parent_dir(at_fdcwd, path) or { return errno.err, errno.get() }
	directory, found, name := walk_path(parent, path, 0, true)
	mut resolved := ''
	if found != unsafe { nil } {
		node := reduce_node(found, true)
		if node == unsafe { nil } {
			return errno.err, errno.get()
		}
		resolved = policy_path(node)
	} else {
		if directory == unsafe { nil } || errno.get() != errno.enoent || name == ''
			|| name == '.' || name == '..' {
			return errno.err, errno.get()
		}
		directory_path := policy_path(directory)
		resolved = join_policy_path(directory_path, name)
		unsafe { directory_path.free() }
	}
	code := proc.unveil_add(mut process, resolved, perms)
	unsafe { resolved.free() }
	if code != 0 {
		return errno.err, code
	}
	return 0, 0
}

// link(2) of `target` as `name` in `directory`. The new name is made, so the
// caller needs "c" there, and the file is one it has to be able to read
// already. Under unveil(2) the new name may not grant more than the old one
// did, either: a hard link from a read-only directory into a writable one
// would otherwise make the file writable.
pub fn policy_check_link(target &VFSNode, directory &VFSNode, name string) bool {
	process := proc.current_thread().process
	if !policy_restricted(process) {
		return true
	}
	if !policy_check(target, proc.policy_read)
		|| !policy_check_name(directory, name, proc.policy_create) {
		return false
	}
	if process.unveil == unsafe { nil } {
		return true
	}
	target_path := policy_path(target)
	directory_path := policy_path(directory)
	new_path := join_policy_path(directory_path, name)
	code := proc.unveil_link_verdict(process, target_path, new_path)
	unsafe {
		target_path.free()
		directory_path.free()
		new_path.free()
	}
	if code != 0 {
		errno.set(code)
		return false
	}
	return true
}
