@[has_globals]
module devicetree

// Flattened Device Tree (FDT) parser
// Parses the DTB blob provided by m1n1/U-Boot via Limine module
// Follows the DTSpec (devicetree.org) binary format

import lib as _
import memory as _

// FDT header magic
const fdt_magic = u32(0xd00dfeed)

// FDT tokens
const fdt_begin_node = u32(1)
const fdt_end_node = u32(2)
const fdt_prop = u32(3)
const fdt_nop = u32(4)
const fdt_end = u32(9)

@[packed]
struct FDTHeader {
mut:
	magic             u32
	totalsize         u32
	off_dt_struct     u32
	off_dt_strings    u32
	off_mem_rsvmap    u32
	version           u32
	last_comp_version u32
	boot_cpuid_phys   u32
	size_dt_strings   u32
	size_dt_struct    u32
}

pub struct DTProperty {
pub:
	name string
	data voidptr
	len  u32
}

@[heap]
pub struct DTNode {
pub mut:
	name       string
	properties []DTProperty
	children   []&DTNode
	parent     &DTNode = unsafe { nil }
}

__global (
	dt_root    &DTNode
	dt_strings voidptr
	dt_struct  voidptr
)

// Returns true if the device tree was successfully parsed.
pub fn is_available() bool {
	return dt_root != unsafe { nil }
}

fn be32(ptr voidptr) u32 {
	p := unsafe { &u8(ptr) }
	return unsafe {
		(u32(p[0]) << 24) | (u32(p[1]) << 16) | (u32(p[2]) << 8) | u32(p[3])
	}
}

fn be64(ptr voidptr) u64 {
	return (u64(be32(ptr)) << 32) | u64(be32(unsafe { voidptr(u64(ptr) + 4) }))
}

fn get_string(offset u32) string {
	cstr := unsafe { &u8(u64(dt_strings) + offset) }
	mut len := 0
	for unsafe { cstr[len] } != 0 {
		len++
	}
	return unsafe { tos(cstr, len) }
}

fn align4(v u32) u32 {
	return (v + 3) & ~u32(3)
}

// Parse a DTB blob at the given address
pub fn parse(dtb_addr voidptr) bool {
	header := unsafe { &FDTHeader(dtb_addr) }

	if be32(voidptr(&header.magic)) != fdt_magic {
		C.printf(c'devicetree: Invalid FDT magic: 0x%x\n', be32(voidptr(&header.magic)))
		return false
	}

	version := be32(voidptr(&header.version))
	totalsize := be32(voidptr(&header.totalsize))

	println('devicetree: FDT version ${version}, size ${totalsize} bytes')

	dt_strings = unsafe { voidptr(u64(dtb_addr) + be32(voidptr(&header.off_dt_strings))) }
	dt_struct = unsafe { voidptr(u64(dtb_addr) + be32(voidptr(&header.off_dt_struct))) }

	mut offset := u32(0)
	dt_root = parse_node(mut &offset, unsafe { nil })

	if dt_root != unsafe { nil } {
		println('devicetree: Parsed root node successfully')
		return true
	}

	return false
}

fn parse_node(mut offset &u32, parent &DTNode) &DTNode {
	for {
		token := be32(unsafe { voidptr(u64(dt_struct) + *offset) })
		unsafe {
			*offset += 4
		}

		match token {
			fdt_begin_node {
				// Node name follows
				name_ptr := unsafe { &u8(u64(dt_struct) + *offset) }
				mut name_len := 0
				for unsafe { name_ptr[name_len] } != 0 {
					name_len++
				}
				name := unsafe { tos(name_ptr, name_len) }
				unsafe {
					*offset += align4(u32(name_len) + 1)
				}

				mut node := &DTNode{
					name:   name
					parent: unsafe { parent }
				}

				// Parse children and properties
				for {
					next := be32(unsafe { voidptr(u64(dt_struct) + *offset) })
					if next == fdt_end_node {
						unsafe {
							*offset += 4
						}
						break
					} else if next == fdt_begin_node {
						child := parse_node(mut offset, node)
						if child != unsafe { nil } {
							node.children << child
						}
					} else if next == fdt_prop {
						unsafe {
							*offset += 4
						}
						prop_len := be32(unsafe { voidptr(u64(dt_struct) + *offset) })
						unsafe {
							*offset += 4
						}
						name_off := be32(unsafe { voidptr(u64(dt_struct) + *offset) })
						unsafe {
							*offset += 4
						}

						mut prop_data := unsafe { nil }
						if prop_len > 0 {
							prop_data = unsafe { voidptr(u64(dt_struct) + *offset) }
						}
						unsafe {
							*offset += align4(prop_len)
						}

						prop := DTProperty{
							name: get_string(name_off)
							data: prop_data
							len:  prop_len
						}
						node.properties << prop
					} else if next == fdt_nop {
						unsafe {
							*offset += 4
						}
					} else {
						break
					}
				}
				return node
			}
			fdt_nop {
				continue
			}
			else {
				return unsafe { nil }
			}
		}
	}
	return unsafe { nil }
}

// Find a node by path (e.g., "/soc/gpu" or just "gpu")
pub fn find_node(path string) ?&DTNode {
	if dt_root == unsafe { nil } {
		return none
	}

	if path == '/' {
		return dt_root
	}

	// Strip leading slash
	search := if path.len > 0 && path[0] == `/` {
		path[1..]
	} else {
		path
	}

	parts := search.split('/')
	mut current := dt_root

	for part in parts {
		mut found := false
		for mut child in current.children {
			// Match full name or just the node-name part (before @)
			child_base := if child.name.contains('@') {
				child.name.all_before('@')
			} else {
				child.name
			}
			if child.name == part || child_base == part {
				current = child
				found = true
				break
			}
		}
		if !found {
			return none
		}
	}

	return current
}

// Find a node by compatible string anywhere in the tree
pub fn find_compatible(compat string) ?&DTNode {
	if dt_root == unsafe { nil } {
		return none
	}
	return find_compatible_in(dt_root, compat)
}

fn find_compatible_in(node &DTNode, compat string) ?&DTNode {
	for prop in node.properties {
		if prop.name == 'compatible' && prop.len > 0 {
			// compatible is a list of null-terminated strings
			mut off := u32(0)
			for off < prop.len {
				s := unsafe { &u8(u64(prop.data) + off) }
				mut slen := 0
				for unsafe { s[slen] } != 0 && off + u32(slen) < prop.len {
					slen++
				}
				val := unsafe { tos(s, slen) }
				if val == compat {
					return node
				}
				off += u32(slen) + 1
			}
		}
	}
	for child in node.children {
		result := find_compatible_in(child, compat) or { continue }
		return result
	}
	return none
}

// Get a property from a node
pub fn get_property(node &DTNode, name string) ?DTProperty {
	for prop in node.properties {
		if prop.name == name {
			return prop
		}
	}
	return none
}

// Get a u32 property value
pub fn get_u32(node &DTNode, name string) ?u32 {
	prop := get_property(node, name) or { return none }
	if prop.len < 4 {
		return none
	}
	return be32(prop.data)
}

// Get a u64 property value
pub fn get_u64(node &DTNode, name string) ?u64 {
	prop := get_property(node, name) or { return none }
	if prop.len < 8 {
		return none
	}
	return be64(prop.data)
}

// Get reg property (base, size pairs)
// Returns array of (base, size) tuples
pub fn get_reg(node &DTNode) ?([]u64) {
	prop := get_property(node, 'reg') or { return none }

	// Determine address/size cells from parent
	addr_cells := if node.parent != unsafe { nil } {
		get_u32(node.parent, '#address-cells') or { u32(2) }
	} else {
		u32(2)
	}
	size_cells := if node.parent != unsafe { nil } {
		get_u32(node.parent, '#size-cells') or { u32(2) }
	} else {
		u32(2)
	}

	entry_size := (addr_cells + size_cells) * 4
	num_entries := prop.len / entry_size

	mut result := []u64{}
	for i := u32(0); i < num_entries; i++ {
		off := i * entry_size
		base := if addr_cells == 2 {
			be64(unsafe { voidptr(u64(prop.data) + off) })
		} else {
			u64(be32(unsafe { voidptr(u64(prop.data) + off) }))
		}
		size_off := off + addr_cells * 4
		size := if size_cells == 2 {
			be64(unsafe { voidptr(u64(prop.data) + size_off) })
		} else {
			u64(be32(unsafe { voidptr(u64(prop.data) + size_off) }))
		}
		result << base
		result << size
	}

	return result
}

// Get a string property value
pub fn get_string_prop(node &DTNode, name string) ?string {
	prop := get_property(node, name) or { return none }
	if prop.len == 0 {
		return none
	}
	s := unsafe { &u8(prop.data) }
	mut slen := 0
	for slen < int(prop.len) && unsafe { s[slen] } != 0 {
		slen++
	}
	return unsafe { tos(s, slen) }
}
