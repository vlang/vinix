// SPDX-License-Identifier: GPL-2.0-or-later
module runtimehost

import gamehost
import os

fn cpio_write(mut file os.File, bytes []u8) ! {
	unsafe { file.write_full_buffer(bytes.data, usize(bytes.len))! }
}

fn cpio_header(mut file os.File, name string, fields []u32) ! {
	header := '070701' + fields.map('${it:08x}').join('')
	assert header.len == 110
	cpio_write(mut file, header.bytes())!
	cpio_write(mut file, name.bytes())!
	cpio_write(mut file, [u8(0)])!
	cpio_write(mut file, []u8{len: (4 - (110 + name.len + 1) % 4) % 4})!
}

// Linux's documented newc format: sorted members, symlink payloads, metadata,
// and one final data-bearing entry for every group of regular hard links.
pub fn cpio(root string, destination string) ! {
	mut paths := gamehost.files(root)!
	paths.sort()
	paths.prepend(root)
	mut last := map[string]string{}
	for path in paths {
		state := os.lstat(path)!
		if state.get_filetype() == .regular && state.nlink > 1 {
			last['${state.dev}:${state.inode}'] = path
		}
	}
	mut file := os.create(destination)!
	defer { file.close() }
	mut buffer := []u8{len: 1024 * 1024}
	for path in paths {
		state := os.lstat(path)!
		kind := state.get_filetype()
		name := if path == root { '.' } else { path[root.trim_right('/').len + 1..] }
		link := if kind == .symbolic_link { os.readlink(path)! } else { '' }
		present := kind == .regular && (state.nlink <= 1 || last['${state.dev}:${state.inode}'] == path)
		size := if present {
			state.size
		} else if kind == .symbolic_link {
			u64(link.len)
		} else {
			u64(0)
		}
		if size > 0xffffffff || name.len >= 0xffffffff {
			return error('newc member exceeds 32-bit size')
		}
		cpio_header(mut file, name, [u32(state.inode), state.mode, state.uid, state.gid,
			u32(state.nlink), u32(state.mtime), u32(size), C.major(state.dev), C.minor(state.dev),
			C.major(state.rdev), C.minor(state.rdev), u32(name.len + 1), u32(0)])!
		if present {
			mut input := os.open(path)!
			defer { input.close() }
			mut remaining := size
			for remaining > 0 {
				capacity := int(if remaining > buffer.len { u64(buffer.len) } else { remaining })
				count := input.read(mut buffer[..capacity])!
				if count == 0 { return error('newc input truncated: ' + path) }
				cpio_write(mut file, buffer[..count])!
				remaining -= u64(count)
			}
		} else if kind == .symbolic_link {
			cpio_write(mut file, link.bytes())!
		}
		cpio_write(mut file, []u8{len: int((4 - size % 4) % 4)})!
	}
	cpio_header(mut file, 'TRAILER!!!', [u32(0), 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 11, 0])!
	file.flush()
	length := os.file_size(destination)
	cpio_write(mut file, []u8{len: int((512 - length % 512) % 512)})!
	file.flush()
}
