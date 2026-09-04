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

pub struct DTReg {
pub:
	base u64
	size u64
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

// Apple DeviceTree payloads embedded as vendor properties retain their
// original little-endian scalar encoding when a bootloader wraps them in an
// FDT. Standard FDT cells must continue to use be32()/be64().
fn le32(ptr voidptr) u32 {
	p := unsafe { &u8(ptr) }
	return unsafe {
		u32(p[0]) | (u32(p[1]) << 8) | (u32(p[2]) << 16) | (u32(p[3]) << 24)
	}
}

fn le64(ptr voidptr) u64 {
	return u64(le32(ptr)) | (u64(le32(unsafe { voidptr(u64(ptr) + 4) })) << 32)
}

fn read_cells(ptr voidptr, count u32) ?u64 {
	if count == 1 {
		return u64(be32(ptr))
	}
	if count == 2 {
		return be64(ptr)
	}
	return none
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
					name: name
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
							len: prop_len
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

// Read an Apple vendor scalar without reinterpreting it as a standard
// big-endian FDT cell.
pub fn get_le_u32(node &DTNode, name string) ?u32 {
	prop := get_property(node, name) or { return none }
	if prop.len < 4 {
		return none
	}
	return le32(prop.data)
}

pub fn get_le_u64(node &DTNode, name string) ?u64 {
	prop := get_property(node, name) or { return none }
	if prop.len < 8 {
		return none
	}
	return le64(prop.data)
}

pub fn get_le_u32_array(node &DTNode, name string) ?[]u32 {
	prop := get_property(node, name) or { return none }
	if prop.len == 0 || prop.len % 4 != 0 {
		return none
	}
	mut result := []u32{cap: int(prop.len / 4)}
	for offset := u32(0); offset < prop.len; offset += 4 {
		result << le32(unsafe { voidptr(u64(prop.data) + offset) })
	}
	return result
}

// Apple vendor records also use native little-endian 64-bit words. Keep this
// separate from the standard big-endian FDT cell helpers above.
pub fn get_le_u64_array(node &DTNode, name string) ?[]u64 {
	prop := get_property(node, name) or { return none }
	if prop.len == 0 || prop.len % 8 != 0 {
		return none
	}
	mut result := []u64{cap: int(prop.len / 8)}
	for offset := u32(0); offset < prop.len; offset += 8 {
		result << le64(unsafe { voidptr(u64(prop.data) + offset) })
	}
	return result
}

// Get a list of big-endian u32 cells from a property.
pub fn get_u32_array(node &DTNode, name string) ?[]u32 {
	prop := get_property(node, name) or { return none }
	if prop.len == 0 || prop.len % 4 != 0 {
		return none
	}
	mut result := []u32{cap: int(prop.len / 4)}
	for offset := u32(0); offset < prop.len; offset += 4 {
		result << be32(unsafe { voidptr(u64(prop.data) + offset) })
	}
	return result
}

// Get a NUL-separated string list from a property.
pub fn get_string_list(node &DTNode, name string) ?[]string {
	prop := get_property(node, name) or { return none }
	if prop.len == 0 {
		return none
	}
	mut result := []string{}
	mut offset := u32(0)
	for offset < prop.len {
		value := unsafe { &u8(u64(prop.data) + offset) }
		mut length := 0
		for offset + u32(length) < prop.len && unsafe { value[length] } != 0 {
			length++
		}
		if length > 0 {
			result << unsafe { tos(value, length) }
		}
		offset += u32(length) + 1
	}
	return result
}

fn find_phandle_in(node &DTNode, phandle u32) ?&DTNode {
	value := get_u32(node, 'phandle') or { get_u32(node, 'linux,phandle') or { u32(0) } }
	if value == phandle {
		return node
	}
	for child in node.children {
		found := find_phandle_in(child, phandle) or { continue }
		return found
	}
	return none
}

pub fn find_phandle(phandle u32) ?&DTNode {
	if phandle == 0 || dt_root == unsafe { nil } {
		return none
	}
	return find_phandle_in(dt_root, phandle)
}

// Resolve a phandle-only property entry. This is appropriate for
// memory-region and mailbox providers with zero argument cells.
pub fn get_phandle_node(node &DTNode, property string, index u32) ?&DTNode {
	values := get_u32_array(node, property) or { return none }
	if index >= u32(values.len) {
		return none
	}
	return find_phandle(values[index])
}

pub fn get_named_phandle_node(node &DTNode, property string, names_property string, name string) ?&DTNode {
	names := get_string_list(node, names_property) or { return none }
	for index, candidate in names {
		if candidate == name {
			return get_phandle_node(node, property, u32(index))
		}
	}
	return none
}

fn translate_one_bus(bus &DTNode, address u64) ?u64 {
	if bus.parent == unsafe { nil } {
		return address
	}
	ranges := get_property(bus, 'ranges') or {
		// A missing ranges property is common at the root-facing platform
		// bus. Preserve the address rather than inventing a translation.
		return address
	}
	if ranges.len == 0 {
		return address
	}
	child_cells := get_u32(bus, '#address-cells') or { u32(2) }
	parent_cells := get_u32(bus.parent, '#address-cells') or { u32(2) }
	size_cells := get_u32(bus, '#size-cells') or { u32(2) }
	entry_cells := child_cells + parent_cells + size_cells
	if entry_cells == 0 || ranges.len % (entry_cells * 4) != 0 {
		return none
	}
	for offset := u32(0); offset < ranges.len; offset += entry_cells * 4 {
		child := read_cells(unsafe { voidptr(u64(ranges.data) + offset) }, child_cells) or {
			return none
		}
		parent_offset := offset + child_cells * 4
		parent := read_cells(unsafe { voidptr(u64(ranges.data) + parent_offset) }, parent_cells) or {
			return none
		}
		size_offset := parent_offset + parent_cells * 4
		size := read_cells(unsafe { voidptr(u64(ranges.data) + size_offset) }, size_cells) or {
			return none
		}
		if address >= child && address - child < size {
			return parent + (address - child)
		}
	}
	return none
}

fn translate_address(node &DTNode, input u64) ?u64 {
	mut address := input
	mut bus := node.parent
	for bus != unsafe { nil } {
		address = translate_one_bus(bus, address) or { return none }
		bus = bus.parent
	}
	return address
}

// Parse reg into explicit ranges and translate each base through ancestor
// bus `ranges` properties into the CPU physical address space.
pub fn get_translated_reg_ranges(node &DTNode) ?[]DTReg {
	prop := get_property(node, 'reg') or { return none }
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
	if entry_size == 0 || prop.len % entry_size != 0 {
		return none
	}
	mut result := []DTReg{}
	for offset := u32(0); offset < prop.len; offset += entry_size {
		base := read_cells(unsafe { voidptr(u64(prop.data) + offset) }, addr_cells) or {
			return none
		}
		size := read_cells(unsafe { voidptr(u64(prop.data) + offset + addr_cells * 4) }, size_cells) or {
			return none
		}
		translated := translate_address(node, base) or { return none }
		result << DTReg{ base: translated, size: size }
	}
	return result
}

pub fn get_named_reg(node &DTNode, name string) ?DTReg {
	names := get_string_list(node, 'reg-names') or { return none }
	ranges := get_translated_reg_ranges(node) or { return none }
	for index, candidate in names {
		if candidate == name && index < ranges.len {
			return ranges[index]
		}
	}
	return none
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
