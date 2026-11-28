module ext2

import fs

fn tree_fixture(depth int) &EXT2Filesystem {
	mut f := &EXT2Filesystem{
		inodes: []EXT2Inode{len: depth + 4}
		disk: []u8{len: (depth + 4) * 1024}
	}
	for i in 0 .. depth {
		index := i + 2
		f.inodes[index] = EXT2Inode{permissions: 0x41ed, hard_link_cnt: 2, size32l: 1024}
		f.inodes[index].blocks[0] = u32(index)
		p := unsafe { &f.disk[index * 1024] }
		// A single child; the last directory holds a regular file.
		store32(p, 0, u32(index + 1))
		store16(p, 4, 1024)
		unsafe { p[6] = 1; p[7] = if i + 1 == depth { u8(1) } else { u8(2) }; p[8] = `x` }
	}
	f.inodes[depth + 2] = EXT2Inode{permissions: 0x81a4, hard_link_cnt: 1}
	return f
}

fn close_tree_fixture(f &EXT2Filesystem) {
	unsafe { f.inodes.free(); f.disk.free(); free(f.superblock); free(f.l); free(f.box); free(f) }
}

fn free_mounted_tree(root &fs.VFSNode) {
	mut nodes := []&fs.VFSNode{}
	unsafe { nodes.flags |= .noslices }
	nodes << root
	for i := 0; i < nodes.len; i++ {
		n := nodes[i]
		if n.children != unsafe { nil } {
			for key, child in n.children {
				if key == '.' || key == '..' { unsafe { free(child) } } else { nodes << child }
			}
		}
	}
	discard_read_tree(nodes)
	unsafe { nodes.free() }
}

fn test_deep_tree_uses_queue_and_read_only_nodes() {
	mut f := tree_fixture(1024)
	defer { close_tree_fixture(f) }
	root := f.mount_read_tree(unsafe { nil }, '', unsafe { nil })?
	mut node := root
	for _ in 0 .. 1024 {
		assert node.read_only
		node = unsafe { node.children['x'] }
	}
	assert node.read_only && node.resource.stat.mode == 0x81a4
	assert live_resources == 1025
	free_mounted_tree(root)
	assert live_resources == 0
}

fn test_every_read_failure_discards_all_private_resources() {
	for fail in 1 .. 17 {
		mut f := tree_fixture(4)
		f.fail_at = fail
		if root := f.mount_read_tree(unsafe { nil }, '', unsafe { nil }) { free_mounted_tree(root) }
		assert live_resources == 0
		close_tree_fixture(f)
	}
}

fn test_directory_cycle_duplicate_and_bad_symlink_cleanup() {
	for bad in 0 .. 3 {
		mut f := tree_fixture(1)
		if bad == 0 { store32(unsafe { &f.disk[2048] }, 0, 2) } // root cycle
		if bad == 1 { store16(unsafe { &f.disk[2048] }, 4, 12) } // duplicate x
		if bad == 1 {
			unsafe { C.memcpy(&f.disk[2060], &f.disk[2048], 12) }
			store16(unsafe { &f.disk[2060] }, 4, 1012)
		}
		if bad == 2 {
			f.inodes[3].permissions = 0xa1ff
			f.inodes[3].size32l = 4096 // exceeds the supported symlink length
			f.disk[2055] = 7
		}
		if _ := f.mount_read_tree(unsafe { nil }, '', unsafe { nil }) { assert false }
		assert live_resources == 0
		close_tree_fixture(f)
	}
}

fn test_mount_owns_short_and_long_symlink_targets() {
	for target in ['target', 'this/is/a/long/symlink/target/with/more/than/sixty/bytes/to/exercise/extents'] {
		mut f := tree_fixture(1)
		f.inodes[3].permissions = 0xa1ff
		f.inodes[3].size32l = u32(target.len)
		f.disk[2055] = 7
		if target.len <= 60 {
			unsafe { C.memcpy(&f.inodes[3].blocks[0], target.str, target.len) }
		} else {
			f.inodes[3].sector_cnt = 2
			f.inodes[3].blocks[0] = 4
			unsafe { C.memcpy(&f.disk[4096], target.str, target.len) }
		}
		root := f.mount_read_tree(unsafe { nil }, '', unsafe { nil })?
		child := unsafe { root.children['x'] }
		assert child.symlink_target == target
		free_mounted_tree(root)
		assert live_resources == 0
		close_tree_fixture(f)
	}
}
