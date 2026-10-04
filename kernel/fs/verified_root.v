// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import stat

// Boot-only handoff to an authenticated, immutable ext2 view. Kernel mounts
// survive the handoff; runtime scratch is explicitly outside that view.
pub fn install_verified_root(mut root VFSNode) bool {
	vfs_lock.acquire()
	defer { vfs_lock.release() }
	if root.resource == unsafe { nil } || !root.read_only || !stat.isdir(root.resource.stat.mode) {
		return false
	}
	old_root := vfs_root
	mut dev := get_node(old_root, '/dev', true) or { return false }
	mut proc := get_node(old_root, '/proc', true) or { return false }
	for name in ['dev', 'proc', 'sys', 'tmp', 'run']! {
		if !plain_directory_child(root, name) { return false }
	}
	// Optional writable runtime trees must also be plain directories in the
	// authenticated filesystem; never follow a supplied symlink mountpoint.
	for name in ['var', 'root']! {
		if name in root.children && !plain_directory_child(root, name) { return false }
	}
	vfs_root = root
	mut committed := false
	defer { if !committed { vfs_root = old_root } }
	for name in ['tmp', 'run', 'var', 'root']! {
		if name !in root.children { continue }
		mut tmp := &TmpFS{}
		mut instance := tmp.instantiate()
		mut mounted := instance.mount(root, name, unsafe { nil }) or { return false }
		mounted.create_dotentries(root)
		mounted.resource.stat.mode = (if name == 'tmp' { u32(0o1777) } else { u32(0o755) }) | stat.ifdir
		mut target := unsafe { root.children[name] }
		target.mountpoint = mounted
	}
	mut dev_target := unsafe { root.children['dev'] }
	mut proc_target := unsafe { root.children['proc'] }
	dev_target.mountpoint = dev
	proc_target.mountpoint = proc
	init := get_node(root, '/sbin/init', true) or { return false }
	if !init.read_only || !same_filesystem(root, init) || !stat.isreg(init.resource.stat.mode)
		|| init.resource.stat.mode & 0o111 == 0 || init.resource.stat.size <= 0 {
		return false
	}
	mut carried := [dev, proc]!
	for mut mounted in carried {
		mounted.parent = root
		if '..' in mounted.children {
			mut dotdot := unsafe { mounted.children['..'] }
			dotdot.redir = root
		}
	}
	committed = true
	record_root_switch(root, 'ext2')
	return true
}
