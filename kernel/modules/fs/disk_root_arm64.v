// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module fs

import stat

// Points the kernel overlays on a disk root. /dev and /proc were mounted while
// the RAM root was still in place -- the block device the volume is read
// through is one of them -- so they move rather than being remounted. /tmp and
// /run are runtime scratch and stay in RAM.
const disk_root_carried = ['dev', 'proc']
const disk_root_scratch = ['tmp', 'run']

// Replace the bootstrap RAM root with a writable on-disk one, so that the whole
// filesystem survives a restart rather than just a home directory mounted into
// it. The initramfs then only has to exist as the fallback this refuses into.
//
// Boot-only transaction: no user process has been started yet, and every
// console descriptor and device resource survives because /dev is reused.
pub fn install_disk_root(mut root VFSNode) bool {
	vfs_lock.acquire()
	defer { vfs_lock.release() }
	if root.resource == unsafe { nil } || root.read_only
		|| !stat.isdir(root.resource.stat.mode) {
		return false
	}
	old_root := vfs_root
	// Absolute paths resolve against vfs_root, so the mounts being carried
	// over have to be found before the root is swapped.
	mut carried := []&VFSNode{}
	mut carried_names := []string{}
	defer {
		unsafe {
			carried.free()
			carried_names.free()
		}
	}
	for name in disk_root_carried {
		existing := get_node(old_root, '/${name}', true) or { continue }
		carried << existing
		carried_names << name
	}
	// Without /dev there is no console and no block device to have read this
	// volume through; that is a kernel that never got far enough to be here.
	if 'dev' !in carried_names {
		return false
	}
	// Every overlay point must be a plain directory the volume itself
	// provides. A symlink or a file there would quietly redirect /dev or /tmp
	// somewhere on disk, and an on-disk image is not trusted to that extent.
	for name in carried_names {
		if !plain_directory_child(root, name) {
			return false
		}
	}
	for name in disk_root_scratch {
		if !plain_directory_child(root, name) {
			return false
		}
	}

	vfs_root = root
	mut committed := false
	defer {
		if !committed {
			vfs_root = old_root
		}
	}

	for name in disk_root_scratch {
		mut scratch := &TmpFS{}
		mut instance := scratch.instantiate()
		mut mounted := instance.mount(root, name, unsafe { nil }) or { return false }
		mounted.create_dotentries(root)
		mounted.resource.stat.mode = (if name == 'tmp' {
			u32(0o1777)
		} else {
			u32(0o755)
		}) | stat.ifdir
		mut target := unsafe { root.children[name] }
		target.mountpoint = mounted
	}
	for index, name in carried_names {
		mut target := unsafe { root.children[name] }
		target.mountpoint = carried[index]
	}

	// Validate after staging the overlays, so /sbin/init cannot resolve to a
	// file that one of them hides, or escape through the old /dev/.. into the
	// initramfs. A volume with no init is refused and the caller keeps the
	// root it already had.
	init := get_node(root, '/sbin/init', true) or { return false }
	if !same_filesystem(root, init) || !stat.isreg(init.resource.stat.mode)
		|| init.resource.stat.mode & 0o111 == 0 || init.resource.stat.size <= 0 {
		return false
	}

	// The only mutation of old-root objects happens after every fallible step.
	for index, _ in carried_names {
		mut existing := carried[index]
		existing.parent = root
		if '..' in existing.children {
			mut dotdot := unsafe { existing.children['..'] }
			dotdot.redir = root
		}
	}
	committed = true
	return true
}

fn plain_directory_child(root &VFSNode, name string) bool {
	if name !in root.children {
		return false
	}
	child := unsafe { root.children[name] }
	return child.resource != unsafe { nil } && stat.isdir(child.resource.stat.mode)
		&& child.symlink_target.len == 0
}
