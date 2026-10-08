module t8103adt

import appleadt as a
import imageextract as image
import macinspect as mac
import os
import traceanalysis as j

#include <fnmatch.h>

fn C.fnmatch(&char, &char, i32) i32

pub fn read_file(path string) ![]u8 {
	if path.contains('\x00') { return error('embedded null byte') }
	if !os.exists(path) { return error('[Errno 2] No such file or directory: ${j.quoted(path)}') }
	if os.is_dir(path) { return error('[Errno 21] Is a directory: ${j.quoted(path)}') }
	return os.read_bytes(path)
}

pub fn find_platform_device_tree(preboot string, board string) !string {
	mut candidates := []string{}
	root := path_value(preboot)
	prefix := if root == '.' {
		''
	} else if root.ends_with('/') {
		root
	} else {
		root + '/'
	}
	pattern := 'DeviceTree.' + board + '.im4p'
	if pattern.contains('**') {
		return error("Invalid pattern: '**' can only be an entire path component")
	}
	for child in os.ls(root) or { []string{} } {
		folder := prefix + child + '/restore-staged/Firmware/all_flash'
		for file in os.ls(folder) or { []string{} } {
			if C.fnmatch(&char(pattern.str), &char(file.str), C.FNM_NOESCAPE) == 0 {
				candidate := folder + '/' + file
				if os.is_file(candidate) { candidates << candidate }
			}
		}
	}
	candidates.sort()
	if candidates.len != 1 {
		rendered := if candidates.len == 0 { 'none' } else { candidates.join(', ') }
		return error('expected one ${board} DeviceTree, found: ${rendered}')
	}
	return candidates[0]
}

pub fn load_device_tree(path string) !a.Node {
	data := read_file(path)!
	im4p := image.unwrap_im4p(data)!
	kind := data[im4p.image_type.start..im4p.image_type.end]
	if kind.bytestr() != 'dtre' {
		return error('not a DeviceTree IM4P (type=${image.bytes_repr(kind)})')
	}
	return a.parse(a.decompress(data[im4p.payload.start..im4p.payload.end], 0)!)
}

fn python_type(property mac.Property) string {
	return match property.kind {
		.null { 'NoneType' }
		.array { 'list' }
		.string { 'str' }
		.bytes { 'bytes' }
		.number {
			if property.text.contains_any('.eE') || property.text in ['NaN', 'Infinity', '-Infinity',
				'nan', 'inf', '-inf'] {
				'float'
			} else {
				'int'
			}
		}
		.boolean { 'bool' }
		.opaque {
			if property.text == 'datetime' { 'datetime.datetime' } else { 'UID' }
		}
		.object { 'dict' }
	}
}

fn plist_node(property mac.Property, method string) !map[string]mac.Property {
	mut node := property
	if node.kind == .array {
		if node.array.len == 0 { return error('IndexError: list index out of range') }
		node = node.array[0]
	}
	if node.kind != .object {
		return error("AttributeError: '${python_type(node)}' object has no attribute '${method}'")
	}
	return node.fields
}

pub fn live_sgx_inventory_data(data []u8) !map[string]j.Value {
	node := plist_node(mac.parse_plist(data)!, 'items')!
	mut names := node.keys()
	names.sort()
	mut inventory := map[string]j.Value{}
	for name in names {
		property := node[name]
		if property.kind == .bytes && !name.starts_with('IO') {
			inventory[name] = j.Value(describe_value(property.bytes))
		}
	}
	return inventory
}

pub fn live_sgx_inventory(path string) !map[string]j.Value {
	return live_sgx_inventory_data(read_file(path)!)
}

pub struct PerfStates {
pub:
	present bool
	data    []u8
}

pub fn read_perf_states_data(data []u8) !PerfStates {
	node := plist_node(mac.parse_plist(data)!, 'get')!
	property := node['perf-states'] or { return PerfStates{} }
	return if property.kind == .bytes { PerfStates{true, property.bytes} } else { PerfStates{} }
}

pub fn read_perf_states(path string) !PerfStates {
	return read_perf_states_data(read_file(path)!)
}
