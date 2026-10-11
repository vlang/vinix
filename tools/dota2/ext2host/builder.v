// SPDX-License-Identifier: GPL-2.0-or-later
module ext2host

import json2
import encoding.hex
import os
import rand

pub struct SourceFile {
pub:
	path     string
	identity []i64
}

pub struct Manifest {
pub:
	version int
	size    i64
	files   []SourceFile
	regions [][]i64
}

struct Run {
	start i64
	count i64
}

struct Builder {
	fd               int
	nodes            []&Node
	groups           int
	inodes_per_group int
	gdt_blocks       int
	table_blocks     int
mut:
	used    []int
	tables  []i64
	group   int
	files   []SourceFile
	regions [][]i64
}

fn builder(nodes []&Node, state string) !Builder {
	mut required := i64(0)
	for node in nodes {
		mut count := rounded(node.info.identity[2], block)
		if is_dir(node.info) { count = directory_data(node).len / block }
		if is_link(node.info) {
			size := os.readlink(node.path)!.len
			count = if size > 60 { rounded(size, block) } else { 0 }
		}
		required += count + pointer_count(count)!
	}
	mut groups := int(rounded(required + 16, group_blocks - 8))
	if groups < 1 { groups = 1 }
	mut ipg := 0
	mut gdt := 0
	mut table := 0
	mut used := []int{}
	mut tables := []i64{}
	for {
		ipg = int(rounded(nodes.len + 9, i64(groups) * 32) * 32)
		if ipg < 32 { ipg = 32 }
		gdt = int(rounded(i64(groups) * 32, block))
		table = ipg * 128 / block
		used = []int{}
		tables = []i64{}
		mut allocated := i64(0)
		for group in 0 .. groups {
			prefix := if backup_group(group) { 1 + gdt } else { 0 }
			value := prefix + 2 + table
			used << value
			tables << i64(group) * group_blocks + prefix + 2
			allocated += value
		}
		if i64(groups) * group_blocks - allocated >= required { break }
		groups++
	}
	if i64(groups) * group_blocks > 0xffffffff || ipg > group_blocks {
		return error("Export exceeds this ext2 layout's limits")
	}
	fd := exclusive(state + '/metadata.ext2', i64(groups) * group_blocks * block)!
	return Builder{
		fd:               fd
		nodes:            nodes
		groups:           groups
		inodes_per_group: ipg
		gdt_blocks:       gdt
		table_blocks:     table
		used:             used
		tables:           tables
	}
}

fn (mut b Builder) allocate(count i64) ![]Run {
	mut runs := []Run{}
	mut remaining := count
	for remaining > 0 {
		if b.group >= b.groups { return error('Export ran out of blocks') }
		available := group_blocks - b.used[b.group]
		if available == 0 {
			b.group++
			continue
		}
		take := if remaining < available { remaining } else { i64(available) }
		runs << Run{i64(b.group) * group_blocks + b.used[b.group], take}
		b.used[b.group] += int(take)
		remaining -= take
	}
	return runs
}

struct Blocks {
	runs []Run
mut:
	run      int
	at       i64
	indirect int
}

fn (mut blocks Blocks) next() !u32 {
	for blocks.run < blocks.runs.len {
		entry := blocks.runs[blocks.run]
		if blocks.at < entry.count {
			result := u32(entry.start + blocks.at)
			blocks.at++
			return result
		}
		blocks.run++
		blocks.at = 0
	}
	return error('Address tree exhausted its data blocks')
}

fn (mut b Builder) address_level(level int, count i64, mut blocks Blocks) !u32 {
	address := u32(b.allocate(1)![0].start)
	blocks.indirect++
	mut data := []u8{len: block}
	if level == 1 {
		for index in 0 .. int(count) { put_le(mut data, index * 4, blocks.next()!, 4) }
	} else {
		mut capacity := i64(1)
		for _ in 0 .. level - 1 { capacity *= pointers }
		mut at := i64(0)
		mut index := 0
		for at < count {
			take := if count - at < capacity { count - at } else { capacity }
			put_le(mut data, index * 4, b.address_level(level - 1, take, mut blocks)!, 4)
			at += take
			index++
		}
	}
	write_at(b.fd, i64(address) * block, data)!
	return address
}

fn (mut b Builder) address_tree(runs []Run) !([]u32, int) {
	mut count := i64(0)
	for run in runs { count += run.count }
	mut blocks := Blocks{ runs: runs }
	mut addresses := []u32{len: 15}
	for index in 0 .. if count < 12 { int(count) } else { 12 } { addresses[index] = blocks.next()! }
	mut remaining := if count > 12 { count - 12 } else { i64(0) }
	mut capacity := i64(1)
	for level in 1 .. 4 {
		capacity *= pointers
		take := if remaining < capacity { remaining } else { capacity }
		if take > 0 { addresses[11 + level] = b.address_level(level, take, mut blocks)! }
		remaining -= take
	}
	return addresses, blocks.indirect
}

fn (mut b Builder) add_node(node &Node) ! {
	mode := node.info.mode & 0xffff & ~u32(0o222)
	mut data := []u8{}
	mut inline := false
	mut size := node.info.identity[2]
	mut links := 1
	if is_dir(node.info) {
		data = directory_data(node)
		size = data.len
		links = 2
		for child in node.children { if is_dir(child.info) { links++ } }
	} else if is_link(node.info) {
		data = os.readlink(node.path)!.bytes()
		size = data.len
		inline = size <= 60
	}
	count := if inline { i64(0) } else { rounded(size, block) }
	runs := b.allocate(count)!
	if data.len > 0 && !inline {
		mut at := 0
		for run in runs {
			end := if i64(at) + run.count * block < data.len {
				at + int(run.count * block)
			} else {
				data.len
			}
			write_at(b.fd, run.start * block, data[at..end])!
			at = end
		}
	} else if is_file(node.info) {
		index := b.files.len
		b.files << SourceFile{node.path, node.info.identity}
		mut position := i64(0)
		for run in runs {
			length := run.count * block
			b.regions << [run.start * block, length, i64(index), position]
			position += length
		}
	}
	addresses, indirect := b.address_tree(runs)!
	mut inode := []u8{len: 128}
	timestamp := if node.info.mtime < 0 {
		u64(0)
	} else if node.info.mtime > 0xffffffff {
		u64(0xffffffff)
	} else {
		u64(node.info.mtime)
	}
	put_le(mut inode, 0, mode, 2)
	put_le(mut inode, 4, u64(size), 4)
	for at in [8, 12, 16] { put_le(mut inode, at, timestamp, 4) }
	put_le(mut inode, 26, u64(links), 2)
	put_le(mut inode, 28, u64((count + indirect) * 8), 4)
	if inline {
		for index, byte in data { inode[40 + index] = byte }
	} else {
		for index, address in addresses { put_le(mut inode, 40 + index * 4, address, 4) }
	}
	group := (node.inode - 1) / b.inodes_per_group
	index := (node.inode - 1) % b.inodes_per_group
	write_at(b.fd, b.tables[group] * block + index * 128, inode)!
}

fn (mut b Builder) finish() !Manifest {
	for node in b.nodes { b.add_node(node)! }
	mut gdt := []u8{len: b.gdt_blocks * block}
	mut directory_counts := []int{len: b.groups}
	for node in b.nodes {
		if is_dir(node.info) { directory_counts[(node.inode - 1) / b.inodes_per_group]++ }
	}
	last_inode := b.nodes.len + 9
	mut free_inodes := i64(0)
	mut used_total := i64(0)
	for group in 0 .. b.groups {
		prefix := if backup_group(group) { 1 + b.gdt_blocks } else { 0 }
		base := i64(group) * group_blocks
		used_inodes := if last_inode - group * b.inodes_per_group < 0 {
			0
		} else if last_inode - group * b.inodes_per_group > b.inodes_per_group {
			b.inodes_per_group
		} else {
			last_inode - group * b.inodes_per_group
		}
		available := b.inodes_per_group - used_inodes
		free_inodes += available
		used_total += b.used[group]
		for index, value in [base + prefix, base + prefix + 1, b.tables[group]] {
			put_le(mut gdt, group * 32 + index * 4, u64(value), 4)
		}
		for index, value in [group_blocks - b.used[group], available, directory_counts[group]] {
			put_le(mut gdt, group * 32 + 12 + index * 2, u64(value), 2)
		}
		mut bitmap := []u8{len: block}
		for index in 0 .. b.used[group] { bitmap[index / 8] |= u8(1 << (index % 8)) }
		write_at(b.fd, (base + prefix) * block, bitmap)!
		bitmap = []u8{len: block, init: 0xff}
		for index in used_inodes .. b.inodes_per_group {
			bitmap[index / 8] &= ~u8(1 << (index % 8))
		}
		write_at(b.fd, (base + prefix + 1) * block, bitmap)!
	}
	mut sb := []u8{len: 1024}
	block_count := i64(b.groups) * group_blocks
	for index, value in [i64(b.groups) * b.inodes_per_group, block_count, 0, block_count - used_total,
		free_inodes, 0, 2, 2, group_blocks, group_blocks, b.inodes_per_group] {
		put_le(mut sb, index * 4, u64(value), 4)
	}
	for index, value in [0, 0xffff, 0xef53, 1, 1, 0] {
		put_le(mut sb, 52 + index * 2, u64(value), 2)
	}
	put_le(mut sb, 76, 1, 4)
	put_le(mut sb, 84, 11, 4)
	put_le(mut sb, 88, 128, 2)
	put_le(mut sb, 96, 2, 4)
	put_le(mut sb, 100, 3, 4)
	uuid := hex.decode(rand.uuid_v4().replace('-', ''))!
	for index in 0 .. 16 { sb[104 + index] = uuid[index] }
	for index, byte in 'Vinix game data\x00'.bytes() { sb[120 + index] = byte }
	for group in 0 .. b.groups {
		if !backup_group(group) { continue }
		put_le(mut sb, 90, u64(group), 2)
		write_at(b.fd, i64(group) * group_blocks * block + if group == 0 { 1024 } else { 0 }, sb)!
		write_at(b.fd, (i64(group) * group_blocks + 1) * block, gdt)!
	}
	if C.fsync(b.fd) != 0 { return io_error('Cannot sync export metadata') }
	b.regions.sort_with_compare(fn (a &[]i64, c &[]i64) int {
		return if (*a)[0] < (*c)[0] {
			-1
		} else if (*a)[0] > (*c)[0] {
			1
		} else {
			0
		}
	})
	return Manifest{ version: 1, size: block_count * block, files: b.files, regions: b.regions }
}

pub fn build(source string, state_argument string, overlays []string) !Manifest {
	state := resolve(state_argument)!
	mut roots := [resolve(source)!]
	for overlay in overlays { roots << resolve(overlay)! }
	for path in roots {
		if !os.is_dir(path) { return error('Export root is not a directory: ' + path) }
		if state == path || state.starts_with(path.trim_right('/') + '/') {
			return error('Metadata directory must be outside every exported root')
		}
	}
	mut root := scan(roots[0], unsafe { nil })!
	for path in roots[1..] { root = scan(path, root)! }
	nodes := flatten(mut root)
	os.mkdir_all(state)!
	if os.exists(state + '/metadata.ext2') || os.exists(state + '/manifest.json') {
		return error('Use a fresh export state directory')
	}
	mut b := builder(nodes, state)!
	defer { C.close(b.fd) }
	manifest := b.finish()!
	fd := exclusive(state + '/manifest.json', 0)!
	defer { C.close(fd) }
	write_at(fd, 0, json2.encode(manifest).bytes())!
	return manifest
}
