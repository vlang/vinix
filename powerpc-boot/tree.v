// SPDX-License-Identifier: GPL-2.0-or-later
module main

// A bounded standard FDT v17, independent of firmware handles. The kernel
// can use its existing FDT parser after it stops calling Open Firmware.
const tree_capacity = u32(512 * 1024)
const tree_strings = u32(384 * 1024)

__global tree_buffer &u8
__global tree_cursor u32
__global strings_cursor u32
__global tree_nodes u32

fn tree_u32(at u32, value u32) {
	unsafe {
		tree_buffer[at] = u8(value >> 24)
		tree_buffer[at + 1] = u8(value >> 16)
		tree_buffer[at + 2] = u8(value >> 8)
		tree_buffer[at + 3] = u8(value)
	}
}

fn tree_word(value u32) bool {
	if tree_cursor > tree_strings - 4 { return false }
	tree_u32(tree_cursor, value)
	tree_cursor += 4
	return true
}

fn copy_node(node u32, depth u32) bool {
	if depth >= 64 || tree_nodes >= 4096 { return false }
	tree_nodes++
	discover_pci(node)
	discover_ata(node)
	mut path := [512]u8{}
	mut call := Call{ service: c'package-to-path', nargs: 3, nret: 1 }
	call.cells[0] = node
	call.cells[1] = u32(unsafe { &path[0] })
	call.cells[2] = 511
	if firmware(unsafe { &call }) != 0 { return false }
	length := int(call.cells[3])
	if length <= 0 || length >= 511 { return false }
	mut start := 0
	for i in 0 .. length { if path[i] == `/` { start = i + 1 } }
	if !tree_word(1) { return false } // FDT_BEGIN_NODE
	name_size := u32(length - start + 1)
	if name_size > tree_strings - tree_cursor { return false }
	for i := u32(0); i < name_size; i++ {
		unsafe { tree_buffer[tree_cursor + i] = path[start + int(i)] }
	}
	tree_cursor = (tree_cursor + name_size + 3) & ~u32(3)
	mut property := [256]u8{}
	mut previous := [256]u8{}
	mut property_count := u32(0)
	for {
		call = Call{ service: c'nextprop', nargs: 3, nret: 1 }
		call.cells[0] = node
		call.cells[1] = u32(unsafe { &previous[0] })
		call.cells[2] = u32(unsafe { &property[0] })
		if firmware(unsafe { &call }) != 0 { return false }
		if call.cells[3] == 0 { break }
		if call.cells[3] != 1 || property_count >= 1024 { return false }
		property_count++
		mut name_length := u32(0)
		for name_length < 256 && property[name_length] != 0 { name_length++ }
		if name_length == 0 || name_length == 256 || name_length + 1 > tree_capacity - strings_cursor {
			return false
		}
		name_offset := strings_cursor - tree_strings
		for i := u32(0); i <= name_length; i++ {
			unsafe { tree_buffer[strings_cursor + i] = property[i] }
		}
		strings_cursor += name_length + 1
		call = Call{ service: c'getproplen', nargs: 2, nret: 1 }
		call.cells[0] = node
		call.cells[1] = u32(unsafe { &property[0] })
		if firmware(unsafe { &call }) != 0 { return false }
		property_size := call.cells[2]
		if property_size > tree_strings - tree_cursor || property_size > 256 * 1024 { return false }
		if !tree_word(3) || !tree_word(property_size) || !tree_word(name_offset) { return false }
		if property_size > tree_strings - tree_cursor { return false }
		if get_property(node, unsafe { &char(&property[0]) }, unsafe { &tree_buffer[tree_cursor] }, property_size) != int(property_size) {
			return false
		}
		tree_cursor = (tree_cursor + property_size + 3) & ~u32(3)
		previous = property
	}
	mut child := relation(c'child', node)
	for child != 0 {
		if child == 0xffffffff || !copy_node(child, depth + 1) { return false }
		child = relation(c'peer', child)
	}
	return tree_word(2) // FDT_END_NODE
}

fn copy_device_tree() bool {
	address := claim(tree_capacity)
	if address == 0 || address == 0xffffffff || address > 0xffffffff - tree_capacity {
		return false
	}
	tree_buffer = unsafe { &u8(address) }
	fill_bytes(tree_buffer, 0, uint(tree_capacity))
	// Header + FDT/loader reservations + terminating reservation.
	tree_cursor = 88
	strings_cursor = tree_strings
	tree_nodes = 0
	root := relation(c'peer', 0)
	if root == 0 || root == 0xffffffff || !copy_node(root, 0) || !tree_word(9) { return false }
	tree_u32(0, 0xd00dfeed)
	tree_u32(4, strings_cursor)
	tree_u32(8, 88)
	tree_u32(12, tree_strings)
	tree_u32(16, 40)
	tree_u32(20, 17)
	tree_u32(24, 16)
	tree_u32(28, 0)
	tree_u32(32, strings_cursor - tree_strings)
	tree_u32(36, tree_cursor - 88)
	tree_u32(44, address)
	tree_u32(52, tree_capacity)
	tree_u32(60, 0x01000000)
	tree_u32(68, image_end() - 0x01000000)
	boot_info.tree = address
	boot_info.tree_size = strings_cursor
	puts(c'VINIX-PPC: FDT ')
	hex(address)
	puts(c' size ')
	hex(strings_cursor)
	puts(c' nodes ')
	hex(tree_nodes)
	puts(c'\r\n')
	return true
}
