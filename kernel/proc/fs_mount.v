// SPDX-License-Identifier: GPL-2.0-or-later
module proc

import lib

// Snapshot the directory and its mount route under one lock. Never retain a
// pointer into shared CLONE_FS state or hold its lock across a VFS path walk.
pub fn snapshot_root_directory(_process &Process, context &lib.MountContext) voidptr {
	if _process == unsafe { nil } { lib.copy_mount_context(context, unsafe { nil }); return unsafe { nil } }
	mut own := thread_fs_of(_process)
	if own != unsafe { nil } {
		own.lock.acquire()
		defer { own.lock.release() }
		lib.copy_mount_context(context, &own.root_mount)
		return own.root_directory
	}
	mut process := unsafe { _process }
	process.fs_lock.acquire()
	defer { process.fs_lock.release() }
	lib.copy_mount_context(context, &process.root_mount)
	return process.root_directory
}

pub fn snapshot_current_directory(_process &Process, context &lib.MountContext) voidptr {
	if _process == unsafe { nil } { lib.copy_mount_context(context, unsafe { nil }); return unsafe { nil } }
	mut own := thread_fs_of(_process)
	if own != unsafe { nil } {
		own.lock.acquire()
		defer { own.lock.release() }
		lib.copy_mount_context(context, &own.current_mount)
		return own.current_directory
	}
	mut process := unsafe { _process }
	process.fs_lock.acquire()
	defer { process.fs_lock.release() }
	lib.copy_mount_context(context, &process.current_mount)
	return process.current_directory
}

pub fn snapshot_executable(_process &Process, context &lib.MountContext) voidptr {
	mut process := unsafe { _process }
	process.fs_lock.acquire()
	defer { process.fs_lock.release() }
	lib.copy_mount_context(context, &process.exe_mount)
	return process.exe_node
}

pub fn set_root_fs(mut process Process, directory voidptr, context &lib.MountContext) {
	mut own := thread_fs_of(process)
	if own != unsafe { nil } {
		own.lock.acquire()
		own.root_directory = directory
		lib.copy_mount_context(&own.root_mount, context)
		own.lock.release()
		return
	}
	process.fs_lock.acquire()
	process.root_directory = directory
	lib.copy_mount_context(&process.root_mount, context)
	process.fs_lock.release()
}

pub fn set_current_fs(mut process Process, directory voidptr, context &lib.MountContext) {
	mut own := thread_fs_of(process)
	if own != unsafe { nil } {
		own.lock.acquire()
		own.current_directory = directory
		lib.copy_mount_context(&own.current_mount, context)
		own.lock.release()
		return
	}
	process.fs_lock.acquire()
	process.current_directory = directory
	lib.copy_mount_context(&process.current_mount, context)
	process.fs_lock.release()
}

pub fn set_executable_fs(mut process Process, node voidptr, context &lib.MountContext) {
	process.fs_lock.acquire()
	process.exe_node = node
	lib.copy_mount_context(&process.exe_mount, context)
	process.fs_lock.release()
}
