// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import stat

// Boot-only transaction: no user process has been started yet. Existing
// console descriptors and device resources survive because /dev is reused.
pub fn install_ssd_root(mut root VFSNode) bool {
	vfs_lock.acquire()
	defer { vfs_lock.release() }
	if root.resource == unsafe { nil } || !root.read_only || !stat.isdir(root.resource.stat.mode) {
		return false
	}
	old_root := vfs_root
	mut devices := get_node(old_root, '/dev', true) or { return false }
	// Reject symlink or missing mountpoint directories; never overlay an
	// unexpected path supplied by an on-disk image.
	for name in ['dev', 'tmp', 'run'] {
		if name !in root.children { return false }
		child := unsafe { root.children[name] }
		if !stat.isdir(child.resource.stat.mode) || child.symlink_target.len != 0 { return false }
	}
	vfs_root = root
	mut committed := false
	defer { if !committed { vfs_root = old_root } }
	// Runtime scratch is RAM-backed, not silently writable SSD-root data.
	for name in ['tmp', 'run'] {
		mut tmp := &TmpFS{}
		mut instance := tmp.instantiate()
		mut mounted := instance.mount(root, name, unsafe { nil }) or { return false }
		mounted.create_dotentries(root)
		mounted.resource.stat.mode = (if name == 'tmp' { u32(0o1777) } else { u32(0o755) }) | stat.ifdir
		mut target := unsafe { root.children[name] }
		target.mountpoint = mounted
	}
	mut dev_target := unsafe { root.children['dev'] }
	dev_target.mountpoint = devices
	// Validate after staging overlays: /sbin/init must not resolve to a file
	// hidden by /tmp or /run, or escape through old /dev/.. into initramfs.
	init := get_node(root, '/sbin/init', true) or { return false }
	if !init.read_only || !same_filesystem(root, init) || !stat.isreg(init.resource.stat.mode)
		|| init.resource.stat.mode & 0o111 == 0 || init.resource.stat.size <= 0 {
		return false
	}
	// The only mutation to old-root objects happens after every fallible step.
	devices.parent = root
	if '..' in devices.children {
		mut dotdot := unsafe { devices.children['..'] }
		dotdot.redir = root
	}
	committed = true
	return true
}
