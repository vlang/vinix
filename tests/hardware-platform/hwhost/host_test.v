// SPDX-License-Identifier: GPL-2.0-or-later
module hwhost

import os

fn scratch(name string) string {
	path := os.join_path(os.vtmp_dir(), 'hwhost-${name}-${os.getpid()}')
	os.rmdir_all(path) or {}
	os.mkdir_all(path) or { panic(err) }
	return path
}

fn test_a_disk_has_its_size_and_its_header() {
	state := scratch('disk')
	defer {
		os.rmdir_all(state) or {}
	}
	disk := Disk{
		name:     'disk.raw'
		size_mib: 2
		header:   'not blank'
	}
	create_disk(disk, state)!
	path := os.join_path(state, 'disk.raw')
	assert os.file_size(path) == u64(2) << 20
	content := os.read_bytes(path)!
	assert content[..9].bytestr() == 'not blank'
	assert content[9..].all(it == 0)
	check_disk_header(disk, state)!
	// Something formatted the disk.
	mut file := os.open_file(path, 'r+')!
	file.write_to(0, [u8(0xeb), 0x3c, 0x90])!
	file.close()
	check_disk_header(disk, state) or {
		assert err.msg().contains('no longer starts with')
		return
	}
	assert false, 'an overwritten header went unnoticed'
}

fn test_a_disk_without_a_header_is_blank() {
	state := scratch('blank')
	defer {
		os.rmdir_all(state) or {}
	}
	disk := Disk{
		name:     'blank.raw'
		size_mib: 1
	}
	create_disk(disk, state)!
	assert os.read_bytes(os.join_path(state, 'blank.raw'))!.all(it == 0)
	check_disk_header(disk, state)!
}

fn test_the_pattern_is_the_one_the_guest_writes() {
	assert pattern_bytes(0x11, 4) == [u8(0x11), 0x18, 0x1f, 0x26]
	// It wraps, and a whole run of it has every byte value.
	assert pattern_bytes(0x55, 65536)[37] == u8(0x55 + 37 * 7)
	assert pattern_bytes(0xff, 2) == [u8(0xff), 0x06]
}

fn test_a_pattern_is_found_where_it_was_written_and_nowhere_else() {
	state := scratch('pattern')
	defer {
		os.rmdir_all(state) or {}
	}
	disk := Disk{
		name:     'disk.raw'
		size_mib: 1
	}
	create_disk(disk, state)!
	pattern := DiskPattern{
		disk:   'disk.raw'
		offset: 4096
		length: 512
		seed:   0x11
	}
	check_pattern(pattern, state) or {
		assert err.msg().contains('byte 0 is 0x00')
		mut file := os.open_file(os.join_path(state, 'disk.raw'), 'r+')!
		file.write_to(4096, pattern_bytes(0x11, 512))!
		file.close()
		check_pattern(pattern, state)!
		// The same place with another seed, and a place past the end.
		check_pattern(DiskPattern{
			...pattern
			seed: 0x55
		}, state) or {
			assert err.msg().contains('the guest was to write 0x55')
			check_pattern(DiskPattern{
				...pattern
				offset: u64(1) << 20
			}, state) or {
				assert err.msg().contains('read 0 of 512 bytes')
				return
			}
			assert false, 'a pattern was found past the end of the disk'
			return
		}
		assert false, 'another pattern was found in its place'
		return
	}
	assert false, 'a pattern was found on a blank disk'
}

fn test_a_tree_is_removed_without_following_links() {
	state := scratch('tree')
	defer {
		os.rmdir_all(state) or {}
	}
	shared := os.join_path(state, 'shared')
	work := os.join_path(state, 'work')
	os.mkdir_all(os.join_path(work, 'iso'))!
	os.mkdir_all(shared)!
	os.write_file(os.join_path(shared, 'limine.c'), 'kept')!
	os.write_file(os.join_path(work, 'iso', 'file'), 'x')!
	os.symlink(shared, os.join_path(work, 'iso', 'limine'))!
	remove_tree(work)
	assert !os.exists(work)
	assert os.read_file(os.join_path(shared, 'limine.c'))! == 'kept'
	// A link given directly is removed, not what it points to.
	link := os.join_path(state, 'link')
	os.symlink(shared, link)!
	remove_tree(link)
	assert !os.is_link(link)
	assert os.is_file(os.join_path(shared, 'limine.c'))
}

fn test_a_worktree_borrows_from_its_main_checkout() {
	state := scratch('worktree')
	defer {
		os.rmdir_all(state) or {}
	}
	main := os.join_path(state, 'main')
	tree := os.join_path(state, 'tree')
	os.mkdir_all(os.join_path(main, 'build', 'sysroot'))!
	os.mkdir_all(os.join_path(main, '.git', 'worktrees', 'tree'))!
	os.mkdir_all(tree)!
	os.write_file(os.join_path(tree, '.git'), 'gitdir: ${main}/.git/worktrees/tree\n')!
	assert main_checkout(tree) == main
	assert main_checkout(main) == ''
	assert shared_path(tree, 'build/sysroot') == os.join_path(main, 'build/sysroot')
	// Its own copy comes first, and what neither has is named in the tree.
	os.mkdir_all(os.join_path(tree, 'build', 'sysroot'))!
	assert shared_path(tree, 'build/sysroot') == os.join_path(tree, 'build/sysroot')
	assert shared_path(tree, 'missing') == os.join_path(tree, 'missing')
}

fn test_a_writing_must_hold_its_text_to_the_byte() {
	state := os.join_path(os.temp_dir(), 'hwhost-writing-${os.getpid()}')
	os.mkdir_all(state)!
	defer {
		os.rmdir_all(state) or {}
	}
	writing := Writing{
		file: 'said.txt'
		text: 'LS33ls'
	}
	check_writing(writing, state) or { assert err.msg().contains('was not written') }
	os.write_file(os.join_path(state, 'said.txt'), 'LS33ls')!
	check_writing(writing, state)!
	os.write_file(os.join_path(state, 'said.txt'), 'LS33ls!')!
	mut refused := ''
	check_writing(writing, state) or { refused = err.msg() }
	assert refused.contains('holds "LS33ls!", not "LS33ls"')
	// Nothing written is a file that is there and empty.
	os.write_file(os.join_path(state, 'said.txt'), '')!
	check_writing(Writing{ file: 'said.txt', text: '' }, state)!
}
