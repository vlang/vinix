// SPDX-License-Identifier: GPL-2.0-or-later
module boottools

import cachecli
import os
import plist
import sourcecommand

pub struct Range {
pub:
	address u64
	size    u64
}

pub struct Adt {
pub:
	data   []u8
	memory map[string][]Range
}

fn ascii(data []u8) string {
	mut text := ''
	for byte in data { text += if byte < 128 { byte.ascii_str() } else { '\ufffd' } }
	return text
}

pub fn node_name(entry plist.Value) string {
	name := entry.fields['name'] or { return (entry.fields['IORegistryEntryName'] or { plist.Value{} }).text }
	if name.kind != .data { return (entry.fields['IORegistryEntryName'] or { plist.Value{} }).text }
	end := name.data.index(u8(0))
	return ascii(name.data[..if end < 0 { name.data.len } else { end }])
}

fn append_number(mut data []u8, value u64, size int, little bool) {
	for index in 0 .. size {
		data << u8(value >> (8 * if little { index } else { size - 1 - index }))
	}
}

fn encode_node(entry plist.Value, path string, mut data []u8, mut memory map[string][]Range, depth int, mask_qemu bool) ! {
	if depth > 256 || entry.kind != .dictionary {
		return error('invalid Apple DeviceTree node/depth')
	}
	children := (entry.fields['IORegistryEntryChildren'] or { plist.Value{ kind: .array } }).values
	mut count := 0
	for key, value in entry.fields {
		if value.kind == .data && key.len < 32 && !key.starts_with('IO') { count++ }
	}
	windows := entry.fields['IODeviceMemory'] or { plist.Value{} }
	if windows.kind == .array {
		mut ranges := []Range{}
		for original in windows.values {
			window := if original.kind == .array && original.values.len > 0 {
				original.values[0]
			} else {
				original
			}
			if window.kind != .dictionary || 'address' !in window.fields { continue }
			address := window.fields['address']!
			length := window.fields['length'] or { return error('IODeviceMemory window has no length') }
			if address.kind != .integer || length.kind != .integer {
				return error('invalid IODeviceMemory integer')
			}
			ranges << Range{u64(address.integer), u64(length.integer)}
		}
		memory[path] = ranges
	}
	append_number(mut data, u64(count), 4, true)
	append_number(mut data, u64(children.len), 4, true)
	for key, value in entry.fields {
		if value.kind != .data || key.len >= 32 || key.starts_with('IO') { continue }
		mut payload := value.data.clone()
		if mask_qemu && path == '/arm-io/wdt' && key == 'name' {
			payload = 'wdt-not-in-qemu\x00'.bytes()
		}
		if mask_qemu && path == '/arm-io/aic' && key == 'compatible' {
			payload = 'aic,not-in-qemu\x00'.bytes()
		}
		data << key.bytes()
		data << []u8{len: 32 - key.len}
		append_number(mut data, u64(payload.len), 4, true)
		data << payload
		data << []u8{len: (4 - payload.len % 4) % 4}
	}
	for child in children {
		child_path := path.trim_right('/') + '/' + node_name(child)
		encode_node(child, child_path, mut data, mut memory, depth + 1, mask_qemu)!
	}
}

pub fn adt_from_plist(bytes []u8, mask_qemu bool) !Adt {
	parsed := plist.parse(bytes)!
	root := if parsed.kind == .array && parsed.values.len > 0 { parsed.values[0] } else { parsed }
	mut data := []u8{}
	mut memory := map[string][]Range{}
	encode_node(root, '/', mut data, mut memory, 0, mask_qemu)!
	return Adt{data, memory}
}

pub fn ioreg(mask_qemu bool) !Adt {
	result := sourcecommand.capture(['ioreg', '-a', '-l', '-p', 'IODeviceTree', '-r', '-d', '0',
		'-n', 'device-tree'], os.environ(), 30, 32 * 1024 * 1024, cachecli.cancelled)!
	if result.status != 0 { return error('ioreg failed: ' + result.stderr) }
	return adt_from_plist(result.stdout.bytes(), mask_qemu)
}

pub struct Node {
pub:
	name   string
	parent int = -1
pub mut:
	properties map[string][]u8
	children   []int
}

pub struct Tree {
pub mut:
	nodes []Node
	root  int
}

fn zero_end(data []u8, start u64, end u64) !u64 {
	if start >= end || end > u64(data.len) { return error('invalid binary string bounds') }
	mut offset := start
	for offset < end && data[int(offset)] != 0 { offset++ }
	if offset == end { return error('unterminated binary string') }
	return offset
}

pub fn parse_fdt(data []u8) !Tree {
	if word(data, 0, 4, false)! != 0xd00dfeed { return error('not an FDT') }
	total := word(data, 4, 4, false)!
	mut offset := word(data, 8, 4, false)!
	strings := word(data, 12, 4, false)!
	if total > u64(data.len) || total < 40 || offset >= total || strings >= total {
		return error('invalid FDT bounds')
	}
	mut nodes := []Node{}
	mut stack := []int{}
	mut root := -1
	for {
		if offset > total - 4 { return error('truncated FDT structure') }
		token := word(data, offset, 4, false)!
		offset += 4
		match token {
			1 {
				end := zero_end(data, offset, total)!
				name := ascii(data[int(offset)..int(end)])
				offset = (end + 4) & ~u64(3)
				parent := if stack.len > 0 { stack.last() } else { -1 }
				index := nodes.len
				nodes << Node{ name: name, parent: parent }
				if parent >= 0 { nodes[parent].children << index } else { root = index }
				stack << index
			}
			2 {
				if stack.len == 0 { return error('unbalanced FDT') }
				stack.pop()
			}
			3 {
				if stack.len == 0 || offset > total - 8 {
					return error('FDT property outside node')
				}
				length := word(data, offset, 4, false)!
				name_offset := word(data, offset + 4, 4, false)!
				offset += 8
				if length > total - offset || name_offset >= total - strings {
					return error('invalid FDT property bounds')
				}
				name_end := zero_end(data, strings + name_offset, total)!
				name := data[int(strings + name_offset)..int(name_end)].bytestr()
				nodes[stack.last()].properties[name] = data[int(offset)..int(offset + length)].clone()
				offset = (offset + length + 3) & ~u64(3)
			}
			4 {}
			9 { break }
			else { return error('bad FDT token ' + token.str()) }
		}
	}
	if root < 0 || stack.len > 0 { return error('unbalanced FDT') }
	return Tree{nodes, root}
}

pub fn (tree Tree) path(index int) string {
	mut names := []string{}
	mut current := index
	for tree.nodes[current].parent >= 0 {
		names << tree.nodes[current].name
		current = tree.nodes[current].parent
	}
	return '/' + names.reverse().join('/')
}

fn (tree Tree) cells(index int, name string) !int {
	value := tree.nodes[index].properties[name] or { return 2 }
	return if value.len < 4 { 2 } else { int(word(value, 0, 4, false)!) }
}

fn read_cells(data []u8, offset int, count int) !u64 {
	if count !in [1, 2] { return error('unsupported cell count ' + count.str()) }
	return word(data, u64(offset), count * 4, false)
}

pub struct Regs {
pub:
	supported bool
	ranges    []Range
}

fn (tree Tree) translate(index int, original u64) !u64 {
	apple := 'vinix,apple-adt' in tree.nodes[tree.root].properties
	mut address := original
	mut bus := tree.nodes[index].parent
	for bus >= 0 {
		parent := tree.nodes[bus].parent
		if parent < 0 { break }
		ranges := tree.nodes[bus].properties['ranges'] or { []u8{} }
		if ranges.len == 0 && apple { break }
		if ranges.len > 0 {
			child_cells := tree.cells(bus, '#address-cells')!
			parent_cells := tree.cells(parent, '#address-cells')!
			size_cells := tree.cells(bus, '#size-cells')!
			if child_cells !in [1, 2] || parent_cells !in [1, 2] || size_cells !in [1, 2] {
				return error('unsupported FDT range cells')
			}
			stride := 4 * (child_cells + parent_cells + size_cells)
			if ranges.len % stride != 0 { return error('invalid FDT range stride') }
			mut matched := false
			for offset := 0; offset < ranges.len; offset += stride {
				child := read_cells(ranges, offset, child_cells)!
				parent_address := read_cells(ranges, offset + 4 * child_cells, parent_cells)!
				size := read_cells(ranges, offset + 4 * (child_cells + parent_cells), size_cells)!
				if address >= child && address - child < size {
					if parent_address > ~u64(0) - (address - child) {
						return error('FDT translation exceeds address width')
					}
					address = parent_address + address - child
					matched = true
					break
				}
			}
			if !matched { return error('no matching FDT range') }
		}
		bus = parent
	}
	return address
}

pub fn (tree Tree) translated_reg(index int) Regs {
	node := tree.nodes[index]
	reg := node.properties['reg'] or { return Regs{} }
	if node.parent < 0 { return Regs{} }
	address_cells := tree.cells(node.parent, '#address-cells') or { return Regs{} }
	size_cells := tree.cells(node.parent, '#size-cells') or { return Regs{} }
	if address_cells !in [1, 2] || size_cells !in [0, 1, 2] { return Regs{} }
	stride := 4 * (address_cells + size_cells)
	if reg.len % stride != 0 { return Regs{} }
	mut ranges := []Range{}
	for offset := 0; offset < reg.len; offset += stride {
		base := read_cells(reg, offset, address_cells) or { return Regs{} }
		size := if size_cells == 0 {
			u64(0)
		} else {
			read_cells(reg, offset + 4 * address_cells, size_cells) or { return Regs{} }
		}
		translated := tree.translate(index, base) or { return Regs{} }
		ranges << Range{translated, size}
	}
	return Regs{true, ranges}
}
