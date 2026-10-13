// SPDX-License-Identifier: GPL-2.0-or-later
module ioshost

import encoding.binary
import gamehost
import hosttest
import os

pub fn images(original []u8) !map[string][]u8 {
	if original.len < 12 || u64(original.len) > u64(0xffffffff) {
		return error('calculator image is too short or large')
	}
	mut arm64e := original.clone()
	binary.little_endian_put_u32(mut arm64e[8..12], 2)
	second_wide := (u64(4096) + u64(original.len) + 4095) & ~u64(4095)
	if second_wide + u64(original.len) > u64(0x7fffffff) {
		return error('universal image exceeds 2 GiB')
	}
	second := int(second_wide)
	mut fat := []u8{len: second + original.len}
	for index, value in [u32(0xcafebabe), 2, 0x100000c, 2, 4096, u32(arm64e.len), 12, 0x100000c,
		0, u32(second), u32(original.len), 12] {
		binary.big_endian_put_u32(mut fat[index * 4..index * 4 + 4], value)
	}
	copy(mut fat[4096..4096 + arm64e.len], arm64e)
	copy(mut fat[second..], original)
	return {
		'calculator-arm64e': arm64e
		'truncated':         original[..if original.len < 31 { original.len } else { 31 }].clone()
		'calculator-fat':    fat
	}
}

pub fn prepare_images(fixtures string, destination string) ! {
	for name, value in images(os.read_bytes(fixtures + '/calculator')!)! {
		os.write_file_array(destination + '/' + name, value)!
	}
}

pub fn asset_file(source string, destination string) ! {
	if C.link(source.str, destination.str) == 0 { return }
	copy_file(source, destination)!
}

// copy2 follows source links; the dependency-tree copy is separately allowed
// to preserve links. Do not apply gamehost.copy_file's link-preserving policy.
pub fn copy_file(source string, destination string) ! {
	gamehost.mkdir(gamehost.parent(destination))!
	if os.exists(destination) || os.is_link(destination) { os.rm(destination)! }
	hosttest.module_copy_file_preserving_stat(source, destination)!
}

pub fn asset_tree(source string, destination string) ! {
	gamehost.mkdir(destination)!
	for name in os.ls(source)! {
		from, to := source + '/' + name, destination + '/' + name
		if os.is_dir(from) { asset_tree(from, to)! } else { asset_file(from, to)! }
	}
	hosttest.module_copy_directory_stat(source, destination)!
}

// shutil.copytree(symlinks=True) copies both directory and link metadata.
pub fn dependency_tree(source string, destination string) ! {
	gamehost.mkdir(destination)!
	for name in os.ls(source)! {
		from, to := source + '/' + name, destination + '/' + name
		if os.is_link(from) {
			os.symlink(os.readlink(from)!, to)!
			hosttest.module_copy_link_stat(from, to)!
		} else if os.is_dir(from) {
			dependency_tree(from, to)!
		} else {
			copy_file(from, to)!
		}
	}
	hosttest.module_copy_directory_stat(source, destination)!
}
