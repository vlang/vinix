// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.utf8
import math.bits

const keyed_archive_limit = 16777216

fn ns_keyed_archiver_metadata() {
	mut info := ios_runtime.classes[ios_runtime.names['NSKeyedArchiver']] or { panic('iOS: missing keyed archiver class') }
	for i, pair in [
		['_stream', '^v']!, ['_flags', 'AQ']!, ['_delegate', '@"<NSKeyedArchiverDelegate>"']!,
		['_containers', '@"NSMutableArray"']!, ['_objects', '@"NSMutableArray"']!,
		['_objRefMap', '^{__CFDictionary=}']!, ['_replacementMap', '^{__CFDictionary=}']!,
		['_classNameMap', '^{__CFDictionary=}']!, ['_conditionals', '^{__CFDictionary=}']!,
		['_classes', '^{__CFDictionary=}']!, ['_genericKey', 'Q']!,
		['_cache', 'r^^{__CFKeyedArchiverUID}']!, ['_cacheSize', 'Q']!, ['_estimatedCount', 'Q']!,
		['_visited', '^{__CFSet=}']!, ['_pac_signature', 'Q']!,
	]! {
		info.ivars[pair[0]] = &ObjIvar{name: pair[0].clone(), types: pair[1].clone(), offset: i64(8 + i * 8), size: 8}
	}
}

enum KeyedPlistKind { string data integer unsigned real boolean uid array dictionary }

// References here address the binary plist table. UID payloads address the
// separate $objects array, preserving shared Foundation object identity.
struct KeyedPlistNode {
	kind KeyedPlistKind
	word u64
	bytes []u8
	refs []u64
}

struct KeyedArchiveWriter {
mut:
	nodes []KeyedPlistNode
	objects []u64
	identity map[u64]u64
	classes map[string]u64
	charged int
}

fn (mut writer KeyedArchiveWriter) dispose() {
	for node in writer.nodes { unsafe { node.bytes.free(); node.refs.free() } }
	unsafe { writer.nodes.free(); writer.objects.free(); writer.identity.free(); writer.classes.free() }
}

// Takes ownership even on failure. No node borrows application memory.
fn (mut writer KeyedArchiveWriter) add(node KeyedPlistNode) !u64 {
	size := node.bytes.len + node.refs.len * 8 + 32
	if writer.nodes.len >= 65536 || size > keyed_archive_limit - writer.charged {
		unsafe { node.bytes.free(); node.refs.free() }
		return error('keyed archive exceeds object/size limit')
	}
	writer.charged += size
	index := u64(writer.nodes.len)
	// Struct append clones both arrays, so retire the transferred originals.
	writer.nodes << node
	unsafe { node.bytes.free(); node.refs.free() }
	return index
}

fn (mut writer KeyedArchiveWriter) text(text string) !u64 {
	if text.len > keyed_archive_limit || !utf8.validate_str(text) { return error('invalid keyed archive string') }
	return writer.add(KeyedPlistNode{kind: .string, bytes: text.bytes()})
}

fn (mut writer KeyedArchiveWriter) uid(index u64) !u64 {
	return writer.add(KeyedPlistNode{kind: .uid, word: index})
}

fn (mut writer KeyedArchiveWriter) array(refs []u64) !u64 {
	return writer.add(KeyedPlistNode{kind: .array, refs: refs})
}

fn (mut writer KeyedArchiveWriter) dictionary(keys [4]u64, values [4]u64, count int) !u64 {
	assert count >= 0 && count <= 4
	mut refs := []u64{cap: count * 2}
	refs.flags |= .noslices
	for i in 0 .. count { refs << keys[i] }
	for i in 0 .. count { refs << values[i] }
	return writer.add(KeyedPlistNode{kind: .dictionary, refs: refs})
}

fn (mut writer KeyedArchiveWriter) descriptor(name string, parent string) !u64 {
	if index := writer.classes[name] { return index }
	mut chain := []u64{cap: 3}
	chain.flags |= .noslices
	mut transferred := false
	defer { if !transferred { unsafe { chain.free() } } }
	chain << writer.text(name)!
	if parent != '' { chain << writer.text(parent)! }
	chain << writer.text('NSObject')!
	transferred = true
	classes := writer.array(chain)!
	keys := [writer.text('$classes')!, writer.text('$classname')!, u64(0), u64(0)]!
	values := [classes, writer.text(name)!, u64(0), u64(0)]!
	node := writer.dictionary(keys, values, 2)!
	index := u64(writer.objects.len)
	writer.objects << node
	writer.classes[name] = index
	return index
}

fn keyed_archive_class(object u64) !string {
	if object in ios_runtime.classes { return error('class objects require custom keyed coding') }
	cls := read64(object)
	info := ios_runtime.classes[cls] or { return error('unknown keyed archive class') }
	if info.dynamic { return error('custom keyed coding is not implemented') }
	if object !in ios_runtime.constants {
		header := obj_header(object)
		if header.cls != cls || header.allocation_cls != cls || header.destroyed || header.destroying { return error('keyed archive requires original live object storage') }
	}
	return info.name
}

fn (mut writer KeyedArchiveWriter) value(object u64, depth int) !u64 {
	if object == 0 { return writer.uid(0) }
	if index := writer.identity[object] {
		if writer.objects[int(index)] == ~u64(0) { return error('cyclic keyed archive graphs are not implemented') }
		return writer.uid(index)
	}
	if depth > 64 || writer.objects.len >= 65536 { return error('keyed archive nesting/object limit exceeded') }
	name := keyed_archive_class(object)!
	index := u64(writer.objects.len)
	writer.identity[object] = index
	writer.objects << ~u64(0) // An unfinished reservation detects a backreference.
	mut node := u64(0)
	match name {
		'NSString' { node = writer.text(string_text(object))! }
		'NSNumber', 'NSConstantIntegerNumber' {
			header := obj_header(object)
			node = writer.add(KeyedPlistNode{kind: if header.cf_boolean { KeyedPlistKind.boolean } else if header.is_real { KeyedPlistKind.real } else if header.unsigned_number { KeyedPlistKind.unsigned } else { KeyedPlistKind.integer }, word: if header.is_real { bits.f64_bits(header.real_number) } else { u64(header.number) }})!
		}
		'NSData', '_NSZeroData', '_NSInlineData', 'Foundation.__NSSwiftData', 'NSMutableData' {
			length := data_length(object)
			if length > u64(keyed_archive_limit) { return error('keyed archive data exceeds limit') }
			mut bytes := []u8{len: int(length)}
			if length != 0 { unsafe { C.memcpy(bytes.data, voidptr(data_pointer(object)), usize(length)) } }
			node = writer.add(KeyedPlistNode{kind: .data, bytes: bytes})!
			if name == 'NSMutableData' {
				keys := [writer.text('NS.data')!, writer.text('$class')!, u64(0), u64(0)]!
				values := [node, writer.uid(writer.descriptor('NSMutableData', 'NSData')!)!, u64(0), u64(0)]!
				node = writer.dictionary(keys, values, 2)!
			}
		}
		'NSMutableString' {
			keys := [writer.text('NS.string')!, writer.text('$class')!, u64(0), u64(0)]!
			values := [writer.text(string_text(object))!, writer.uid(writer.descriptor('NSMutableString', 'NSString')!)!, u64(0), u64(0)]!
			node = writer.dictionary(keys, values, 2)!
		}
		'NSArray', 'NSMutableArray', 'NSConstantArray', 'WKNSArray', 'NSDictionary', 'NSMutableDictionary', 'NSConstantDictionary' {
			header := obj_header(object)
			dictionary := name in ['NSDictionary', 'NSMutableDictionary', 'NSConstantDictionary']!
			if header.cf_raw_values || header.cf_raw_keys || header.items.len > 65536
				|| (dictionary && header.keys.len != header.items.len) { return error('unsupported raw/invalid keyed archive collection') }
			mut children := []u64{cap: header.items.len}
			children.flags |= .noslices
			mut transferred := false
			defer { if !transferred { unsafe { children.free() } } }
			for item in header.items { children << writer.value(item, depth + 1)! }
			transferred = true
			values_node := writer.array(children)!
			class_name := if dictionary { if name == 'NSMutableDictionary' { 'NSMutableDictionary' } else { 'NSDictionary' } } else { if name == 'NSMutableArray' { 'NSMutableArray' } else { 'NSArray' } }
			parent := if name == 'NSMutableDictionary' { 'NSDictionary' } else if name == 'NSMutableArray' { 'NSArray' } else { '' }
			class_node := writer.uid(writer.descriptor(class_name, parent)!)!
			if dictionary {
				mut child_keys := []u64{cap: header.keys.len}
				child_keys.flags |= .noslices
				mut keys_transferred := false
				defer { if !keys_transferred { unsafe { child_keys.free() } } }
				for key in header.keys {
					if !objc_is_kind(key, ios_runtime.names['NSString']) { return error('keyed archive dictionary keys must be strings') }
					child_keys << writer.value(key, depth + 1)!
				}
				keys_transferred = true
				keys_node := writer.array(child_keys)!
				keys := [writer.text('NS.keys')!, writer.text('NS.objects')!, writer.text('$class')!, u64(0)]!
				values := [keys_node, values_node, class_node, u64(0)]!
				node = writer.dictionary(keys, values, 3)!
			} else {
				keys := [writer.text('NS.objects')!, writer.text('$class')!, u64(0), u64(0)]!
				values := [values_node, class_node, u64(0), u64(0)]!
				node = writer.dictionary(keys, values, 2)!
			}
		}
		'NSDate', 'VinixCFDate', 'NSNull' {
			class_node := writer.uid(writer.descriptor(if name == 'NSNull' { 'NSNull' } else { 'NSDate' }, '')!)!
			if name == 'NSNull' {
				keys := [writer.text('$class')!, u64(0), u64(0), u64(0)]!
				values := [class_node, u64(0), u64(0), u64(0)]!
				node = writer.dictionary(keys, values, 1)!
			} else {
				time := writer.add(KeyedPlistNode{kind: .real, word: bits.f64_bits(ns_date_state(object).real_number)})!
				keys := [writer.text('NS.time')!, writer.text('$class')!, u64(0), u64(0)]!
				values := [time, class_node, u64(0), u64(0)]!
				node = writer.dictionary(keys, values, 2)!
			}
		}
		else { return error('custom/unsupported keyed archive object type') }
	}
	writer.objects[int(index)] = node
	return writer.uid(index)
}

fn keyed_plist_width(word u64) int {
	return if word <= 255 { 1 } else if word <= 65535 { 2 } else if word <= 0xffffffff { 4 } else { 8 }
}

fn keyed_plist_word(mut bytes []u8, word u64, width int) {
	for i := width - 1; i >= 0; i-- { bytes << u8(word >> (i * 8)) }
}

fn keyed_plist_length(mut bytes []u8, marker u8, length int) {
	bytes << marker | u8(if length < 15 { length } else { 15 })
	if length < 15 { return }
	width := keyed_plist_width(u64(length))
	bytes << u8(0x10 | if width == 1 { 0 } else if width == 2 { 1 } else if width == 4 { 2 } else { 3 })
	keyed_plist_word(mut bytes, u64(length), width)
}

fn (writer &KeyedArchiveWriter) encode(top u64) ![]u8 {
	mut bytes := []u8{cap: 256}
	bytes.flags |= .noslices
	mut complete := false
	defer { if !complete { unsafe { bytes.free() } } }
	for byte in 'bplist00' { bytes << byte }
	mut offsets := []u64{cap: writer.nodes.len}
	defer { unsafe { offsets.free() } }
	width := keyed_plist_width(u64(writer.nodes.len - 1))
	for node in writer.nodes {
		offsets << u64(bytes.len)
		match node.kind {
			.string {
				mut ascii := true
				for byte in node.bytes { if byte >= 128 { ascii = false; break } }
				if ascii { keyed_plist_length(mut bytes, 0x50, node.bytes.len); for byte in node.bytes { bytes << byte } }
				else {
					text := unsafe { tos(node.bytes.data, node.bytes.len) }
					runes := text.runes()
					defer { unsafe { runes.free() } }
					mut count := 0
					for code in runes { count += if code > 0xffff { 2 } else { 1 } }
					keyed_plist_length(mut bytes, 0x60, count)
					for code in runes {
						if code <= 0xffff { keyed_plist_word(mut bytes, u64(code), 2) }
						else { keyed_plist_word(mut bytes, u64(0xd800 + ((u32(code) - 0x10000) >> 10)), 2); keyed_plist_word(mut bytes, u64(0xdc00 + ((u32(code) - 0x10000) & 1023)), 2) }
					}
				}
			}
			.data { keyed_plist_length(mut bytes, 0x40, node.bytes.len); for byte in node.bytes { bytes << byte } }
			.integer, .unsigned {
				if node.kind == .unsigned && node.word > 0x7fffffffffffffff { bytes << u8(0x14); keyed_plist_word(mut bytes, 0, 8); keyed_plist_word(mut bytes, node.word, 8) }
				else {
					integer_width := keyed_plist_width(node.word)
					bytes << u8(0x10 | if integer_width == 1 { 0 } else if integer_width == 2 { 1 } else if integer_width == 4 { 2 } else { 3 })
					keyed_plist_word(mut bytes, node.word, integer_width)
				}
			}
			.real { bytes << u8(0x23); keyed_plist_word(mut bytes, node.word, 8) }
			.boolean { bytes << u8(if node.word == 0 { 8 } else { 9 }) }
			.uid { uid_width := keyed_plist_width(node.word); bytes << u8(0x80 | (uid_width - 1)); keyed_plist_word(mut bytes, node.word, uid_width) }
			.array, .dictionary {
				keyed_plist_length(mut bytes, if node.kind == .array { u8(0xa0) } else { u8(0xd0) }, if node.kind == .array { node.refs.len } else { node.refs.len / 2 })
				for reference in node.refs { keyed_plist_word(mut bytes, reference, width) }
			}
		}
		if bytes.len > keyed_archive_limit { return error('keyed archive output exceeds limit') }
	}
	table := u64(bytes.len)
	offset_width := keyed_plist_width(table)
	for offset in offsets { keyed_plist_word(mut bytes, offset, offset_width) }
	for _ in 0 .. 6 { bytes << u8(0) }
	bytes << u8(offset_width)
	bytes << u8(width)
	keyed_plist_word(mut bytes, u64(writer.nodes.len), 8)
	keyed_plist_word(mut bytes, top, 8)
	keyed_plist_word(mut bytes, table, 8)
	if bytes.len > keyed_archive_limit { return error('keyed archive output exceeds limit') }
	complete = true
	return bytes
}

fn keyed_archive_snapshot(object u64) ![]u8 {
	mut writer := &KeyedArchiveWriter{nodes: []KeyedPlistNode{cap: 64}, objects: []u64{cap: 32}}
	writer.nodes.flags |= .noslices
	writer.objects.flags |= .noslices
	defer { writer.dispose(); unsafe { free(writer) } }
	writer.objects << writer.text('$null')!
	root := writer.value(object, 0)!
	top_keys := [writer.text('root')!, u64(0), u64(0), u64(0)]!
	top_values := [root, u64(0), u64(0), u64(0)]!
	top := writer.dictionary(top_keys, top_values, 1)!
	keys := [writer.text('$archiver')!, writer.text('$version')!, writer.text('$objects')!, writer.text('$top')!]!
	values := [writer.text('NSKeyedArchiver')!, writer.add(KeyedPlistNode{kind: .integer, word: 100000})!, writer.array(writer.objects.clone())!, top]!
	return writer.encode(writer.dictionary(keys, values, 4)!)
}

fn ns_keyed_archiver_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'NSCoder' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic coder superclass chain')
}

fn ns_keyed_archiver_require_class(cls u64) {
	if ns_keyed_archiver_family(cls) { panic('iOS: NSCoder instance construction is not implemented') }
}

fn ns_keyed_archiver_types(name string, meta bool, selector string) ?string {
	if name != 'NSKeyedArchiver' || !meta { return none }
	return match selector {
		'archivedDataWithRootObject:' { '@24@0:8@16' }
		'archivedDataWithRootObject:requiringSecureCoding:error:' { '@36@0:8@16B24^@28' }
		else { return none }
	}
}

fn ns_keyed_archiver_unsupported(selector string) bool {
	return selector in ['alloc', 'allocWithZone:', 'new', 'init', 'copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:', 'description', 'debugDescription', 'archiveRootObject:toFile:', 'classNameForClass:', 'setClassName:forClass:', 'supportsSecureCoding']!
		|| selector.starts_with('initWith') || selector.starts_with('initFor') || selector.starts_with('initRequiring')
		|| selector.starts_with('encode') || selector.starts_with('decode') || selector in ['encodedData', 'requiresSecureCoding', 'setRequiresSecureCoding:', 'outputFormat', 'setOutputFormat:', 'delegate', 'setDelegate:', 'error', 'allowsKeyedCoding', 'finishEncoding']!
}

fn ns_keyed_archiver_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	if !ns_keyed_archiver_family(if meta { object } else { read64(object) }) { return false }
	if ns_keyed_archiver_unsupported(selector) { panic('iOS: NSCoder instances, custom coding and archive file APIs are not implemented') }
	if ns_keyed_archiver_types('NSKeyedArchiver', meta, selector) == none { return false }
	if object != ios_runtime.names['NSKeyedArchiver'] { panic('iOS: custom keyed archiver factories are not implemented') }
	root := objc_retain(frame.x[2])
	defer { objc_release(root) }
	// Snapshot known storage without calling application coding methods. Concurrent
	// mutation of the input graph is outside this profile, as with Foundation.
	C.ios_objc_initialize_lock()
	bytes := keyed_archive_snapshot(root) or { C.ios_objc_initialize_unlock(); panic('iOS: ${err}') }
	C.ios_objc_initialize_unlock()
	defer { unsafe { bytes.free() } }
	data := objc_allocate(ios_runtime.names['NSData'])
	if data == 0 { panic('iOS: keyed archive NSData construction failed') }
	obj_header(data).data = bytes.clone()
	// Both secure-coding values accept exactly the same closed set of builtins.
	// Success leaves a preexisting NSError output untouched.
	frame.x[0] = objc_autorelease(data)
	return true
}
