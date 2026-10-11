// SPDX-License-Identifier: GPL-2.0-or-later
module ext2host

import os

pub struct Node {
pub mut:
	path     string
	info     FileInfo
	children []&Node
	inode    int
	parent   int
}

pub fn scan(path string, existing &Node) !&Node {
	info := inspect(path)!
	if is_dir(info) {
		mut node := if existing != unsafe { nil } && is_dir(existing.info) {
			existing
		} else {
			&Node{}
		}
		node.path = path
		node.info = info
		mut entries := os.ls(path)!
		entries.sort()
		for name in entries {
			if name.len == 0 || name.len > 255 {
				return error('Invalid ext2 filename: ' + path + '/' + name)
			}
			mut found := -1
			for index, child in node.children {
				if os.file_name(child.path) == name {
					found = index
					break
				}
			}
			child := scan(path + '/' + name, if found >= 0 {
				node.children[found]
			} else {
				unsafe { nil }
			})!
			if found >= 0 { node.children[found] = child } else { node.children << child }
		}
		return node
	}
	if is_file(info) && info.identity[2] > 0xffffffff {
		return error('Vinix cannot read a file larger than 4 GiB: ' + path)
	}
	if !is_file(info) && !is_link(info) {
		return error('Only directories, regular files and symlinks can be exported: ' + path)
	}
	return &Node{ path: path, info: info }
}

fn visit(mut parent Node, mut nodes []&Node) {
	for mut child in parent.children {
		child.inode = nodes.len + 10
		child.parent = parent.inode
		nodes << child
		visit(mut child, mut nodes)
	}
}

pub fn flatten(mut root Node) []&Node {
	root.inode = 2
	root.parent = 2
	mut nodes := [&root]
	visit(mut root, mut nodes)
	return nodes
}

struct DirectoryEntry {
	inode int
	name  string
	kind  u8
}

pub fn directory_data(node &Node) []u8 {
	mut entries := [DirectoryEntry{node.inode, '.', 2}, DirectoryEntry{node.parent, '..', 2}]
	for child in node.children {
		entries << DirectoryEntry{child.inode, os.file_name(child.path), if is_dir(child.info) {
			u8(2)
		} else if is_link(child.info) {
			u8(7)
		} else {
			u8(1)
		}}
	}
	mut output := []u8{}
	mut data := []u8{len: block}
	mut at := 0
	mut previous := 0
	for entry in entries {
		length := int(rounded(8 + entry.name.len, 4) * 4)
		if at + length > block {
			put_le(mut data, previous + 4, u64(block - previous), 2)
			output << data
			data = []u8{len: block}
			at = 0
		}
		put_le(mut data, at, u64(entry.inode), 4)
		put_le(mut data, at + 4, u64(length), 2)
		data[at + 6] = u8(entry.name.len)
		data[at + 7] = entry.kind
		for index, byte in entry.name.bytes() { data[at + 8 + index] = byte }
		previous = at
		at += length
	}
	put_le(mut data, previous + 4, u64(block - previous), 2)
	output << data
	return output
}

pub fn pointer_count(count i64) !i64 {
	mut remaining := if count > 12 { count - 12 } else { i64(0) }
	mut total := i64(0)
	mut capacity := i64(1)
	for level in 1 .. 4 {
		capacity *= pointers
		covered := if remaining < capacity { remaining } else { capacity }
		mut unit := i64(1)
		for _ in 0 .. level {
			unit *= pointers
			total += rounded(covered, unit)
		}
		remaining -= covered
	}
	if remaining != 0 { return error("File exceeds ext2's triple-indirect addressing") }
	return total
}

pub fn backup_group(group int) bool {
	if group in [0, 1] { return true }
	for base in [3, 5, 7] {
		mut value := group
		for value != 0 && value % base == 0 { value /= base }
		if value == 1 { return true }
	}
	return false
}
