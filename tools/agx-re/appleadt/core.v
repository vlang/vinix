module appleadt

import imageextract as image
import g17decode as g
import traceanalysis as j

pub const property_name_bytes = 32
pub const property_length_mask = u32(0xffffff)
pub const pmgr_device_bytes = 48
pub const pmp_soc_device_bytes = 124
pub const pmp_ptd_range_bytes = 32

pub struct PropertySpan {
pub:
	span  image.Span
	flags u8
}

pub struct NodeSpan {
pub:
	properties map[string]PropertySpan
	children   []NodeSpan
}

pub struct Property {
pub:
	data  []u8
	flags u8
}

pub struct Node {
pub:
	properties map[string]Property
	children   []Node
}

// The synchronous ABI returns spans, never foreign pointers. Public native
// consumers receive independent property buffers through parse below.
pub fn parse_spans(data []u8) !NodeSpan {
	root, end := parse_node(data, 0, 0)!
	if end != data.len { return error('${data.len - end} trailing bytes after DeviceTree root') }
	return root
}

fn parse_node(data []u8, initial_offset int, depth int) !(NodeSpan, int) {
	if depth > 128 { return error('DeviceTree nesting exceeds 128 nodes') }
	if initial_offset > data.len - 8 { return error('truncated DeviceTree node header') }
	property_count := image.u32_at(data, initial_offset)
	child_count := image.u32_at(data, initial_offset + 4)
	if property_count > 65536 || child_count > 65536 {
		return error('implausible DeviceTree node counts')
	}
	mut offset := initial_offset + 8
	mut properties := map[string]PropertySpan{}
	for _ in 0 .. property_count {
		if offset > data.len - property_name_bytes - 4 {
			return error('truncated DeviceTree property header')
		}
		name_bytes := data[offset..offset + property_name_bytes]
		terminator := name_bytes.index(u8(0))
		if terminator < 0 { return error('unterminated DeviceTree property name') }
		name := ascii(name_bytes[..terminator], 'DeviceTree property name')!
		encoded_length := image.u32_at(data, offset + property_name_bytes)
		length := int(encoded_length & property_length_mask)
		offset += property_name_bytes + 4
		padded_length := image.align_up(length, 4)
		if padded_length > data.len - offset {
			return error('truncated DeviceTree property ${j.quoted(name)}')
		}
		if name in properties { return error('duplicate DeviceTree property ${j.quoted(name)}') }
		properties[name] = PropertySpan{image.Span{offset, offset + length}, u8(encoded_length >> 24)}
		offset += padded_length
	}
	mut children := []NodeSpan{}
	for _ in 0 .. child_count {
		child, end := parse_node(data, offset, depth + 1)!
		children << child
		offset = end
	}
	return NodeSpan{properties, children}, offset
}

fn owned_node(data []u8, span NodeSpan) Node {
	mut properties := map[string]Property{}
	for name, property in span.properties {
		properties[name] = Property{data[property.span.start..property.span.end].clone(), property.flags}
	}
	mut children := []Node{}
	for child in span.children { children << owned_node(data, child) }
	return Node{properties, children}
}

pub fn parse(data []u8) !Node { return owned_node(data, parse_spans(data)!) }

fn ascii(data []u8, field string) !string {
	for byte in data { if byte >= 128 { return error('non-ASCII ${field}') } }
	return data.bytestr()
}

pub fn decode_cstring(data []u8, field string) !string {
	terminator := data.index(u8(0))
	end := if terminator < 0 { data.len } else { terminator }
	return ascii(data[..end], field)
}

pub fn decode_string_list(data []u8, field string) ![]string {
	if data.len == 0 || data[data.len - 1] != 0 {
		return error('${field} is not a NUL-terminated string list')
	}
	mut result := []string{}
	mut start := 0
	for index, byte in data {
		if byte != 0 { continue }
		result << ascii(data[start..index], field)!
		start = index + 1
	}
	return result
}

pub fn decode_u32_array(data []u8, field string) ![]u32 {
	if data.len % 4 != 0 { return error('${field} length is not a multiple of four') }
	mut result := []u32{cap: data.len / 4}
	for offset := 0; offset < data.len; offset += 4 { result << image.u32_at(data, offset) }
	return result
}

pub fn decode_integer(data []u8, field string) !u64 {
	if data.len == 4 { return u64(image.u32_at(data, 0)) }
	if data.len == 8 { return image.u64_at(data, 0) }
	return error('${field} is neither a 32-bit nor a 64-bit integer')
}

pub struct Region {
pub:
	address u64
	bytes   u64
}

pub fn parse_reg_regions(data []u8, field string) ![]Region {
	if data.len == 0 || data.len % 16 != 0 {
		return error('${field} is not an array of 64-bit address/size pairs')
	}
	mut result := []Region{}
	for offset := 0; offset < data.len; offset += 16 {
		result << Region{image.u64_at(data, offset), image.u64_at(data, offset + 8)}
	}
	return result
}

pub fn node_name(node Node) !string {
	property := node.properties['name'] or { return '<anonymous>' }
	return decode_cstring(property.data, 'node name')
}

pub fn (node Node) property(name string) ![]u8 {
	property := node.properties[name] or { return error('DeviceTree node ${j.quoted(node_name(node)!)} has no ${j.quoted(name)} property') }
	return property.data
}

pub fn compatible_with(node Node, value string) !bool {
	property := node.properties['compatible'] or { return false }
	return value in decode_string_list(property.data, 'compatible')!
}

pub struct Visit {
pub:
	path string
	node Node
}

fn walk(node Node, parent_path string, mut visits []Visit) ! {
	name := node_name(node)!
	path := if parent_path == '' { '/' + name } else { parent_path + '/' + name }
	visits << Visit{path, node}
	for child in node.children { walk(child, path, mut visits)! }
}

pub fn walk_adt(node Node, parent_path string) ![]Visit {
	mut result := []Visit{}
	walk(node, parent_path, mut result)!
	return result
}

pub fn find_one(root Node, description string, predicate fn (Node) bool) !Visit {
	mut matches := []Visit{}
	for visit in walk_adt(root, '')! { if predicate(visit.node) { matches << visit } }
	if matches.len != 1 {
		paths := if matches.len == 0 { 'none' } else { matches.map(it.path).join(', ') }
		return error('expected one ${description}, found: ${paths}')
	}
	return matches[0]
}

pub struct PmgrDevice {
pub:
	index             int
	handle            u16
	name              string
	flags             u8
	pmp_selector      u8
	pmp_virtual_class i8
}

pub fn parse_pmgr_devices(data []u8) ![]PmgrDevice {
	if data.len == 0 || data.len % pmgr_device_bytes != 0 {
		return error('PMGR devices property is not an array of 48-byte records')
	}
	mut result := []PmgrDevice{}
	for offset := 0; offset < data.len; offset += pmgr_device_bytes {
		result << PmgrDevice{offset / pmgr_device_bytes, u16(data[offset + 26]) | (u16(data[offset + 27]) << 8), decode_cstring(data[offset + 32..offset + 48], 'PMGR device name')!, data[offset], data[offset + 3], i8(data[offset + 15])}
	}
	return result
}

pub fn resolve_gate(handle u64, devices []PmgrDevice) !map[string]j.Value {
	mut rows := []j.Value{}
	for device in devices {
		rows << j.Value(map[string]j.Value{
			'index':             j.Value(device.index)
			'handle':            j.Value(u32(device.handle))
			'name':              j.Value(device.name)
			'flags':             j.Value(device.flags)
			'pmp_selector':      j.Value(device.pmp_selector)
			'pmp_virtual_class': j.Value(int(device.pmp_virtual_class))
		})
	}
	return resolve_gate_values(j.Value(handle), rows)
}

// The compatibility boundary also accepts manually constructed device records.
// Their integer fields are not limited to the widths of stored PMGR records.
pub fn resolve_gate_values(handle j.Value, devices []j.Value) !map[string]j.Value {
	number := g.integer(handle)!
	mut matches := []map[string]j.Value{}
	for value in devices {
		row := j.object(value)!
		if g.integer(j.value(row, 'handle'))! == number { matches << row }
	}
	if matches.len != 1 {
		names := if matches.len == 0 {
			'none'
		} else {
			matches.map(j.string_value(j.value(it, 'name'))).join(', ')
		}
		formatted := if number.signum < 0 {
			'-0x' + number.abs().hex()
		} else {
			'0x' + number.hex()
		}
		return error('power handle ${formatted} has non-unique PMGR mapping: ${names}')
	}
	device := matches[0]
	flags := g.integer(j.value(device, 'flags'))!
	class := g.integer(j.value(device, 'pmp_virtual_class'))!
	virtual_bit := if flags.signum >= 0 {
		flags.get_bit(4)
	} else {
		!flags.bitwise_com().get_bit(4)
	}
	emits := if flags.signum >= 0 { flags.get_bit(1) } else { !flags.bitwise_com().get_bit(1) }
	virtual := virtual_bit && class.signum >= 0
	return {
		'handle':       handle
		'name':         j.value(device, 'name')
		'record_index': j.value(device, 'index')
		'pmp_dispatch': j.Value(map[string]j.Value{
			'flags':              j.value(device, 'flags')
			'selector':           j.value(device, 'pmp_selector')
			'virtual_class':      j.value(device, 'pmp_virtual_class')
			'emits_device_state': j.Value(emits)
			'virtual_device':     j.Value(virtual)
			'route_if_emitted':   j.Value(if virtual { 'virtual' } else { 'ordinary' })
		})
	}
}

pub fn parse_pmgr_interrupt_config(data []u8, field string) ![]map[string]j.Value {
	if data.len == 0 || data.len % 20 != 0 {
		return error('${field} is not a whole number of 20-byte records')
	}
	if data.len > 0x13f { return error("${field} exceeds ApplePMGR's 0x13f-byte bound") }
	mut result := []map[string]j.Value{}
	for offset := 0; offset < data.len; offset += 20 {
		if data[offset + 3] >= 16 {
			return error('${field} record kind ${data[offset + 3]} is out of range')
		}
		result << {
			'slot': j.Value(data[offset])
			'kind': j.Value(data[offset + 3])
			'name': j.Value(decode_cstring(data[offset + 4..offset + 20], field)!)
		}
	}
	return result
}

pub fn parse_pmp_soc_devices(data []u8) ![]map[string]j.Value {
	if data.len == 0 || data.len % pmp_soc_device_bytes != 0 {
		return error('PMP soc-device property is not an array of 124-byte records')
	}
	mut result := []map[string]j.Value{}
	for offset := 0; offset < data.len; offset += pmp_soc_device_bytes {
		result << {
			'index':                j.Value(offset / pmp_soc_device_bytes)
			'id':                   j.Value(image.u32_at(data, offset))
			'packet_bytes':         j.Value(image.u32_at(data, offset + 12))
			'state_flags':          j.Value(image.u32_at(data, offset + 8))
			'virtual_state_config': j.Value(image.u32_at(data, offset + 44))
			'name':                 j.Value(decode_cstring(data[offset + 116..offset + 124], 'PMP SoC-device name')!)
		}
	}
	return result
}

pub fn parse_pmp_ptd_ranges(data []u8) ![]map[string]j.Value {
	if data.len == 0 || data.len % pmp_ptd_range_bytes != 0 {
		return error('PMP ptd-range property is not an array of 32-byte records')
	}
	mut result := []map[string]j.Value{}
	for offset := 0; offset < data.len; offset += pmp_ptd_range_bytes {
		result << {
			'index':        j.Value(offset / pmp_ptd_range_bytes)
			'id':           j.Value(image.u32_at(data, offset))
			'entry_offset': j.Value(image.u32_at(data, offset + 4))
			'entry_count':  j.Value(image.u32_at(data, offset + 8))
			'doorbell':     j.Value(image.u32_at(data, offset + 12))
			'name':         j.Value(decode_cstring(data[offset + 16..offset + 32], 'PMP PTD-range name')!)
		}
	}
	return result
}
