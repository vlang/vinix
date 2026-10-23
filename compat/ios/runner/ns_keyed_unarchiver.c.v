// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math
import math.bits

// Only known builtin storage is reconstructed. No archive controls a class
// lookup, initWithCoder callback, replacement object or class-name mapping.
struct KeyedDecodeFailure { reason string value int }
fn (failure &KeyedDecodeFailure) msg() string { return failure.reason }
fn (failure &KeyedDecodeFailure) code() int { return failure.value }
const keyed_decode_invalid = KeyedDecodeFailure{reason: 'Invalid or unsupported bounded keyed archive', value: 4864}
const keyed_decode_disallowed = KeyedDecodeFailure{reason: 'Keyed archive class is outside the allowed classes', value: 4864}
const keyed_decode_format = KeyedDecodeFailure{reason: 'Not a supported binary keyed archive', value: 0}
const keyed_decode_root = KeyedDecodeFailure{reason: 'Keyed archive has no root object', value: 4865}
fn keyed_decode_bad() IError { return unsafe { &keyed_decode_invalid } }

fn ns_keyed_unarchiver_metadata() {
	mut info := ios_runtime.classes[ios_runtime.names['NSKeyedUnarchiver']] or { panic('iOS: missing keyed unarchiver class') }
	for i, pair in [
		['_delegate', '@"<NSKeyedUnarchiverDelegate>"']!, ['_flags', 'AQ']!,
		['_objRefMap', '^{__CFDictionary=}']!, ['_replacementMap', '^{__CFDictionary=}']!,
		['_nameClassMap', '^{__CFDictionary=}']!, ['_tmpRefObjMap', '^{__CFDictionary=}']!,
		['_refObjMap', '^{__CFDictionary=}']!, ['_genericKey', 'i']!,
		['_offsetData', '^{?={?=[5C]CCCQQQ}QQ}']!, ['_containers', '^{__CFArray=}']!,
		['_objects', '^{__CFArray=}']!, ['_data', '^{__CFData=}']!, ['_bytes', 'r*']!,
		['_len', 'Q']!, ['_helper', '@"_NSKeyedUnarchiverHelper"']!,
		['_offsetObjMap', '^{__CFDictionary=}']!, ['_pac_signature', 'Q']!,
	]! {
		info.ivars[pair[0]] = &ObjIvar{name: pair[0].clone(), types: pair[1].clone(), offset: i64(8 + i * 8), size: if pair[1] == 'i' { u32(4) } else { u32(8) }}
	}
}

fn keyed_decode_word(bytes []u8, at u64, width int, end u64) !u64 {
	if width < 1 || width > 8 || at > end || u64(width) > end - at { return keyed_decode_bad() }
	mut word := u64(0)
	for i in 0 .. width { word = (word << 8) | bytes[int(at) + i] }
	return word
}

fn (mut store KeyedArchiveWriter) read_add(node KeyedPlistNode) !u64 {
	// The writer's limit error is heap allocated. Malformed input is a repeated
	// reader path, so reject it with a process-lifetime error before that branch.
	size := node.bytes.len + node.refs.len * 8 + 32
	if store.nodes.len >= 65536 || size > keyed_archive_limit - store.charged {
		unsafe { node.bytes.free(); node.refs.free() }
		return keyed_decode_bad()
	}
	return store.add(node)
}

// The writer's node owner also provides bounded storage and explicit disposal
// for parsed records. Binary-plist references and archive UIDs stay separate.
fn keyed_decode_parse(bytes []u8) !(&KeyedArchiveWriter, u64) {
	if bytes.len < 40 || bytes.len > keyed_archive_limit || unsafe { tos(bytes.data, 8) } != 'bplist00' { return keyed_decode_bad() }
	end := u64(bytes.len)
	trailer := end - 32
	count := keyed_decode_word(bytes, trailer + 8, 8, end)!
	top := keyed_decode_word(bytes, trailer + 16, 8, end)!
	table := keyed_decode_word(bytes, trailer + 24, 8, end)!
	offset_width := int(bytes[int(trailer) + 6])
	ref_width := int(bytes[int(trailer) + 7])
	if count == 0 || count > 65536 || top >= count || table < 8 || table > trailer
		|| offset_width !in [1, 2, 4, 8]! || ref_width !in [1, 2, 4, 8]!
		|| count > (trailer - table) / u64(offset_width) { return keyed_decode_bad() }
	mut store := &KeyedArchiveWriter{nodes: []KeyedPlistNode{cap: int(count)}}
	mut complete := false
	defer { if !complete { store.dispose(); unsafe { free(store) } } }
	for i in u64(0) .. count {
		offset := keyed_decode_word(bytes, table + i * u64(offset_width), offset_width, trailer)!
		if offset < 8 || offset >= table { return keyed_decode_bad() }
		marker := bytes[int(offset)]
		kind := marker >> 4
		mut position := offset + 1
		if marker in [u8(8), 9]! {
			store.read_add(KeyedPlistNode{kind: .boolean, word: u64(marker == 9)})!
			continue
		}
		if kind in [u8(1), 2, 8]! {
			width := if kind == 8 { int(marker & 15) + 1 } else { 1 << (marker & 15) }
			if kind == 1 && width == 16 {
				if keyed_decode_word(bytes, position, 8, table)! != 0 { return keyed_decode_bad() }
				store.read_add(KeyedPlistNode{kind: .unsigned, word: keyed_decode_word(bytes, position + 8, 8, table)!})!
			} else {
				word := keyed_decode_word(bytes, position, width, table)!
				if kind == 2 && width !in [4, 8]! { return keyed_decode_bad() }
				store.read_add(KeyedPlistNode{kind: if kind == 8 { KeyedPlistKind.uid } else if kind == 2 { KeyedPlistKind.real } else { KeyedPlistKind.integer }, word: if kind == 2 && width == 4 { bits.f64_bits(f64(bits.f32_from_bits(u32(word)))) } else { word }})!
			}
			continue
		}
		if kind !in [u8(4), 5, 6, 10, 13]! { return keyed_decode_bad() }
		mut length := u64(marker & 15)
		if length == 15 {
			if position >= table || bytes[int(position)] >> 4 != 1 { return keyed_decode_bad() }
			width := 1 << (bytes[int(position)] & 15)
			length = keyed_decode_word(bytes, position + 1, width, table)!
			position += u64(1 + width)
		}
		stride := if kind == 6 { u64(2) } else if kind == 10 { u64(ref_width) } else if kind == 13 { u64(ref_width * 2) } else { u64(1) }
		if position > table || length > u64(keyed_archive_limit) || length > (table - position) / stride { return keyed_decode_bad() }
		if kind in [u8(10), 13]! {
			if length > 65536 { return keyed_decode_bad() }
			nrefs := int(length) * if kind == 13 { 2 } else { 1 }
			mut refs := []u64{cap: nrefs}
			mut transferred := false
			defer { if !transferred { unsafe { refs.free() } } }
			for j in 0 .. nrefs {
				reference := keyed_decode_word(bytes, position + u64(j * ref_width), ref_width, table)!
				if reference >= count { return keyed_decode_bad() }
				refs << reference
			}
			transferred = true
			store.read_add(KeyedPlistNode{kind: if kind == 10 { KeyedPlistKind.array } else { KeyedPlistKind.dictionary }, refs: refs})!
		} else {
			mut payload := []u8{cap: int(length)}
			payload.flags |= .noslices
			mut transferred := false
			defer { if !transferred { unsafe { payload.free() } } }
			if kind == 6 {
				mut j := u64(0)
				for j < length {
					mut code := u32(keyed_decode_word(bytes, position + j * 2, 2, table)!)
					j++
					if code >= 0xd800 && code <= 0xdbff {
						if j == length { return keyed_decode_bad() }
						low := u32(keyed_decode_word(bytes, position + j * 2, 2, table)!)
						if low < 0xdc00 || low > 0xdfff { return keyed_decode_bad() }
						code = 0x10000 + ((code - 0xd800) << 10) + low - 0xdc00
						j++
					}
					json_utf8(mut payload, code) or { return keyed_decode_bad() }
				}
			} else {
				for j in u64(0) .. length {
					byte := bytes[int(position + j)]
					if kind == 5 && byte >= 128 { return keyed_decode_bad() }
					payload << byte
				}
			}
			transferred = true
			store.read_add(KeyedPlistNode{kind: if kind == 4 { KeyedPlistKind.data } else { KeyedPlistKind.string }, bytes: payload})!
		}
	}
	complete = true
	return store, top
}

struct KeyedArchiveDecoder {
	store &KeyedArchiveWriter
	allowed []u64 // Owned snapshot of class pointers, never archive class names.
	secure bool
mut:
	objects []u64
	states []u8
	heights []int
	names []string // Borrowed process-lifetime builtin names.
	decoded []u64 // One owned reference per reconstructed archive UID.
}

fn (mut decoder KeyedArchiveDecoder) dispose() {
	for object in decoder.decoded { objc_release(object) }
	unsafe { decoder.objects.free(); decoder.states.free(); decoder.heights.free(); decoder.names.free(); decoder.decoded.free() }
}

fn keyed_decode_text(node KeyedPlistNode) string {
	if node.bytes.len == 0 { return '' }
	return unsafe { tos(node.bytes.data, node.bytes.len) }
}

fn (decoder &KeyedArchiveDecoder) field(index u64, key string) !u64 {
	node := decoder.store.nodes[int(index)]
	if node.kind != .dictionary || node.refs.len % 2 != 0 || node.refs.len > 8 { return keyed_decode_bad() }
	count := node.refs.len / 2
	mut result := ~u64(0)
	for i in 0 .. count {
		name := decoder.store.nodes[int(node.refs[i])]
		if name.kind != .string { return keyed_decode_bad() }
		for j in 0 .. i { if keyed_decode_text(name) == keyed_decode_text(decoder.store.nodes[int(node.refs[j])]) { return keyed_decode_bad() } }
		if keyed_decode_text(name) == key { result = node.refs[i + count] }
	}
	if result == ~u64(0) { return keyed_decode_bad() }
	return result
}

fn (decoder &KeyedArchiveDecoder) uid(index u64) !u64 {
	node := decoder.store.nodes[int(index)]
	if node.kind != .uid || node.word >= u64(decoder.objects.len) { return keyed_decode_bad() }
	return node.word
}

fn (decoder &KeyedArchiveDecoder) class_name(node u64) !string {
	class_uid := decoder.uid(decoder.field(node, '$class')!)!
	descriptor := decoder.objects[int(class_uid)]
	if decoder.store.nodes[int(descriptor)].refs.len != 4 { return keyed_decode_bad() }
	name_node := decoder.store.nodes[int(decoder.field(descriptor, '$classname')!)]
	if name_node.kind != .string { return keyed_decode_bad() }
	name := keyed_decode_text(name_node)
	if name !in ['NSMutableString', 'NSMutableData', 'NSArray', 'NSMutableArray', 'NSDictionary', 'NSMutableDictionary', 'NSDate', 'NSNull']! { return keyed_decode_bad() }
	chain := decoder.store.nodes[int(decoder.field(descriptor, '$classes')!)]
	mutable := name in ['NSMutableString', 'NSMutableData', 'NSMutableArray', 'NSMutableDictionary']!
	if chain.kind != .array || chain.refs.len != if mutable { 3 } else { 2 } { return keyed_decode_bad() }
	parent := match name { 'NSMutableString' { 'NSString' } 'NSMutableData' { 'NSData' } 'NSMutableArray' { 'NSArray' } 'NSMutableDictionary' { 'NSDictionary' } else { '' } }
	for i, reference in chain.refs {
		entry := decoder.store.nodes[int(reference)]
		if entry.kind != .string || keyed_decode_text(entry) != if i == 0 { name } else if mutable && i == 1 { parent } else { 'NSObject' } { return keyed_decode_bad() }
	}
	// Return a stable literal, not a name borrowed from archive storage.
	return match name { 'NSMutableString' { 'NSMutableString' } 'NSMutableData' { 'NSMutableData' } 'NSArray' { 'NSArray' } 'NSMutableArray' { 'NSMutableArray' } 'NSDictionary' { 'NSDictionary' } 'NSMutableDictionary' { 'NSMutableDictionary' } 'NSDate' { 'NSDate' } else { 'NSNull' } }
}

fn (decoder &KeyedArchiveDecoder) permitted(name string) bool {
	if !decoder.secure || name in ['NSString', 'NSNumber', 'NSData']! { return true }
	mut current := ios_runtime.names[name]
	for _ in 0 .. 128 {
		if current in decoder.allowed { return true }
		info := ios_runtime.classes[current] or { return false }
		current = info.parent
		if current == 0 { return false }
	}
	return false
}

fn (mut decoder KeyedArchiveDecoder) validate(uid u64, depth int) ! {
	if uid == 0 { return }
	if depth > 64 || decoder.states[int(uid)] == 1 { return keyed_decode_bad() }
	if decoder.states[int(uid)] == 2 {
		if depth + decoder.heights[int(uid)] > 64 { return keyed_decode_bad() }
		return
	}
	decoder.states[int(uid)] = 1
	index := decoder.objects[int(uid)]
	node := decoder.store.nodes[int(index)]
	name := match node.kind {
		.string { 'NSString' }
		.data { 'NSData' }
		.integer, .unsigned, .real, .boolean { 'NSNumber' }
		.dictionary { decoder.class_name(index)! }
		else { return keyed_decode_bad() }
	}
	if !decoder.permitted(name) { return unsafe { &keyed_decode_disallowed } }
	decoder.names[int(uid)] = name
	if node.kind == .dictionary {
		match name {
			'NSMutableString', 'NSMutableData' {
				if node.refs.len != 4 { return keyed_decode_bad() }
				leaf := decoder.store.nodes[int(decoder.field(index, if name == 'NSMutableString' { 'NS.string' } else { 'NS.data' })!)]
				if leaf.kind != if name == 'NSMutableString' { KeyedPlistKind.string } else { KeyedPlistKind.data } { return keyed_decode_bad() }
			}
			'NSDate' {
				if node.refs.len != 4 { return keyed_decode_bad() }
				time := decoder.store.nodes[int(decoder.field(index, 'NS.time')!)]
				if time.kind != .real || !math.is_finite(bits.f64_from_bits(time.word)) { return keyed_decode_bad() }
			}
			'NSNull' { if node.refs.len != 2 { return keyed_decode_bad() } }
			else {
				dictionary := name in ['NSDictionary', 'NSMutableDictionary']!
				if node.refs.len != if dictionary { 6 } else { 4 } { return keyed_decode_bad() }
				values := decoder.store.nodes[int(decoder.field(index, 'NS.objects')!)]
				if values.kind != .array { return keyed_decode_bad() }
				for reference in values.refs {
					child := decoder.uid(reference)!
					if child == 0 { return keyed_decode_bad() }
					decoder.validate(child, depth + 1)!
					decoder.heights[int(uid)] = math.max(decoder.heights[int(uid)], decoder.heights[int(child)] + 1)
				}
				if dictionary {
					keys := decoder.store.nodes[int(decoder.field(index, 'NS.keys')!)]
					if keys.kind != .array || keys.refs.len != values.refs.len { return keyed_decode_bad() }
					mut seen := map[string]bool{}
					defer { unsafe { seen.free() } }
					for reference in keys.refs {
						child := decoder.uid(reference)!
						if child == 0 { return keyed_decode_bad() }
						decoder.validate(child, depth + 1)!
						decoder.heights[int(uid)] = math.max(decoder.heights[int(uid)], decoder.heights[int(child)] + 1)
						if decoder.names[int(child)] !in ['NSString', 'NSMutableString']! { return keyed_decode_bad() }
						key_index := decoder.objects[int(child)]
						key_node := decoder.store.nodes[int(if decoder.names[int(child)] == 'NSString' { key_index } else { decoder.field(key_index, 'NS.string')! })]
						key := keyed_decode_text(key_node)
						if key in seen { return keyed_decode_bad() }
						seen[key] = true
					}
				}
			}
		}
	}
	decoder.states[int(uid)] = 2
}

fn keyed_decode_null() u64 {
	C.ios_objc_initialize_lock()
	if ios_runtime.null_object != 0 {
		result := objc_retain(ios_runtime.null_object)
		C.ios_objc_initialize_unlock()
		return result
	}
	C.ios_objc_initialize_unlock()
	// Constructors may join a worker that needs the runtime lock. Publish only
	// a successfully constructed object; a racing winner keeps its cache owner.
	candidate := objc_allocate(ios_runtime.names['NSNull'])
	if candidate == 0 { return 0 }
	C.ios_objc_initialize_lock()
	publish := ios_runtime.null_object == 0
	if publish {
		ios_runtime.null_object = candidate
		ios_runtime.framework_objects << candidate
	}
	result := objc_retain(ios_runtime.null_object)
	C.ios_objc_initialize_unlock()
	if !publish { objc_release(candidate) }
	return result
}

fn (mut decoder KeyedArchiveDecoder) build(uid u64) !u64 {
	if uid == 0 { return 0 }
	if decoder.decoded[int(uid)] != 0 { return decoder.decoded[int(uid)] }
	index := decoder.objects[int(uid)]
	node := decoder.store.nodes[int(index)]
	name := decoder.names[int(uid)]
	mut object := u64(0)
	match name {
		'NSString' { object = owned_string(keyed_decode_text(node)) }
		'NSNumber' {
			object = objc_allocate(ios_runtime.names['NSNumber'])
			if object != 0 {
				mut header := obj_header(object)
				header.number = i64(node.word); header.unsigned_number = node.kind == .unsigned
				header.is_real = node.kind == .real; header.cf_boolean = node.kind == .boolean
				if header.is_real { header.real_number = bits.f64_from_bits(node.word) }
			}
		}
		'NSData', 'NSMutableData' {
			data_index := if name == 'NSData' { index } else { decoder.field(index, 'NS.data')! }
			data := unsafe { &decoder.store.nodes[int(data_index)] }
			object = objc_allocate(ios_runtime.names[name])
			if object != 0 { obj_header(object).data = data.bytes.clone() }
		}
		'NSMutableString' {
			text := decoder.store.nodes[int(decoder.field(index, 'NS.string')!)]
			object = objc_allocate(ios_runtime.names[name])
			if object != 0 { mutable_string_initialize(object, keyed_decode_text(text)) }
		}
		'NSDate' {
			time := decoder.store.nodes[int(decoder.field(index, 'NS.time')!)]
			object = objc_allocate(cf_date_id())
			if object != 0 {
				mut header := obj_header(object)
				header.real_number = bits.f64_from_bits(time.word)
				header.date_initialized = true
			}
		}
		'NSNull' { object = keyed_decode_null() }
		else {
			object = objc_allocate(ios_runtime.names[name])
			if object != 0 {
				// Install the owned cache before children; validation has rejected cycles.
				decoder.decoded[int(uid)] = object
				values := decoder.store.nodes[int(decoder.field(index, 'NS.objects')!)]
				mut header := obj_header(object)
				for reference in values.refs { array_append(mut header, decoder.build(decoder.uid(reference)!)!) }
				if name in ['NSDictionary', 'NSMutableDictionary']! {
					keys := decoder.store.nodes[int(decoder.field(index, 'NS.keys')!)]
					for reference in keys.refs {
						key_uid := decoder.uid(reference)!
						key := decoder.build(key_uid)!
						if decoder.names[int(key_uid)] == 'NSMutableString' {
							copy := owned_string(string_text(key))
							if copy == 0 { return keyed_decode_bad() }
							header.keys << copy
						} else { header.keys << objc_retain(key) }
					}
				}
			}
		}
	}
	if object == 0 { return keyed_decode_bad() }
	decoder.decoded[int(uid)] = object
	return object
}

fn keyed_decode(bytes []u8, allowed []u64, secure bool) !u64 {
	store, top := keyed_decode_parse(bytes) or { return unsafe { &keyed_decode_format } }
	defer { store.dispose(); unsafe { free(store) } }
	mut decoder := &KeyedArchiveDecoder{store: store, allowed: allowed, secure: secure}
	defer { decoder.dispose(); unsafe { free(decoder) } }
	if store.nodes[int(top)].refs.len != 8 { return unsafe { &keyed_decode_format } }
	archiver_index := decoder.field(top, '$archiver') or { return unsafe { &keyed_decode_format } }
	version_index := decoder.field(top, '$version') or { return unsafe { &keyed_decode_format } }
	objects_index := decoder.field(top, '$objects') or { return unsafe { &keyed_decode_format } }
	top_object := decoder.field(top, '$top') or { return unsafe { &keyed_decode_format } }
	archiver := store.nodes[int(archiver_index)]
	version := store.nodes[int(version_index)]
	objects := unsafe { &store.nodes[int(objects_index)] }
	if archiver.kind != .string || keyed_decode_text(archiver) != 'NSKeyedArchiver' || version.kind != .integer || version.word != 100000
		|| objects.kind != .array { return unsafe { &keyed_decode_format } }
	if objects.refs.len == 0 { return keyed_decode_bad() }
	zero := store.nodes[int(objects.refs[0])]
	if zero.kind != .string || keyed_decode_text(zero) != '$null' { return keyed_decode_bad() }
	decoder.objects = objects.refs.clone()
	decoder.states = []u8{len: objects.refs.len}
	decoder.heights = []int{len: objects.refs.len}
	decoder.names = []string{len: objects.refs.len}
	decoder.decoded = []u64{len: objects.refs.len}
	if store.nodes[int(top_object)].kind != .dictionary || store.nodes[int(top_object)].refs.len != 2 { return unsafe { &keyed_decode_root } }
	root_index := decoder.field(top_object, 'root') or { return unsafe { &keyed_decode_root } }
	if store.nodes[int(root_index)].kind != .uid { return unsafe { &keyed_decode_root } }
	root := decoder.uid(root_index)!
	decoder.validate(root, 0)!
	return objc_retain(decoder.build(root)!)
}

fn ns_keyed_unarchiver_types(name string, meta bool, selector string) ?string {
	if name != 'NSKeyedUnarchiver' || !meta { return none }
	return match selector {
		'unarchiveObjectWithData:' { '@24@0:8@16' }
		'unarchiveTopLevelObjectWithData:error:' { '@32@0:8@16^@24' }
		'unarchivedObjectOfClass:fromData:error:' { '@40@0:8#16@24^@32' }
		'unarchivedObjectOfClasses:fromData:error:' { '@40@0:8@16@24^@32' }
		else { return none }
	}
}

fn ns_keyed_unarchiver_unsupported(selector string) bool {
	return ns_keyed_archiver_unsupported(selector) || selector in ['finishDecoding', 'decodingFailurePolicy', 'setDecodingFailurePolicy:', 'unarchiveObjectWithFile:', 'unarchiveTopLevelObjectWithStream:error:', 'unarchivedArrayOfObjectsOfClass:fromData:error:', 'unarchivedDictionaryWithKeysOfClass:objectsOfClass:fromData:error:', 'setClass:forClassName:', 'classForClassName:']!
}

fn keyed_decode_make_error(code int, reason string) !u64 {
	domain := owned_string('NSCocoaErrorDomain')
	defer { objc_release(domain) }
	info := objc_allocate(ios_runtime.names['NSDictionary'])
	defer { objc_release(info) }
	key := owned_string('NSDebugDescription')
	defer { objc_release(key) }
	detail := owned_string(reason)
	defer { objc_release(detail) }
	if domain == 0 || info == 0 || key == 0 || detail == 0 { return keyed_decode_bad() }
	mut header := obj_header(info)
	header.keys << objc_retain(key)
	array_append(mut header, detail)
	object := objc_allocate(ios_runtime.names['NSError'])
	if object == 0 { return keyed_decode_bad() }
	mut record := unsafe { &AbiNSError(object) }
	record.code = i64(code)
	record.domain = objc_retain(domain)
	record.user_info = objc_retain(info)
	return object
}

fn keyed_decode_error(output u64, code int, reason string) {
	if output == 0 { return }
	if code == 0 { unsafe { *(&u64(output)) = 0 }; return }
	object := keyed_decode_make_error(code, reason) or { panic('iOS: keyed unarchive NSError construction failed') }
	unsafe { *(&u64(output)) = objc_autorelease(object) }
}

fn ns_keyed_unarchiver_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	if !ns_keyed_archiver_family(cls) { return false }
	// The shared coder dispatch handles unsupported instance APIs for both coders.
	if ns_keyed_unarchiver_unsupported(selector) { panic('iOS: keyed unarchiver instance, file and custom-class APIs are not implemented') }
	if ns_keyed_unarchiver_types('NSKeyedUnarchiver', meta, selector) == none { return false }
	if object != ios_runtime.names['NSKeyedUnarchiver'] { panic('iOS: custom keyed unarchiver factories are not implemented') }
	secure := selector in ['unarchivedObjectOfClass:fromData:error:', 'unarchivedObjectOfClasses:fromData:error:']!
	input := objc_retain(if secure { frame.x[3] } else { frame.x[2] })
	defer { objc_release(input) }
	allow_input := if secure { objc_retain(frame.x[2]) } else { u64(0) }
	defer { objc_release(allow_input) }
	mut allowed := []u64{cap: 16}
	allowed.flags |= .noslices
	defer { unsafe { allowed.free() } }
	C.ios_objc_initialize_lock()
	if input != 0 {
		name := keyed_archive_class(input) or { C.ios_objc_initialize_unlock(); panic('iOS: keyed unarchive input requires known NSData storage') }
		if name !in ['NSData', '_NSZeroData', '_NSInlineData', 'Foundation.__NSSwiftData', 'NSMutableData']! { C.ios_objc_initialize_unlock(); panic('iOS: keyed unarchive input must be NSData') }
	}
	if secure {
		if selector == 'unarchivedObjectOfClass:fromData:error:' { allowed << allow_input }
		else if allow_input != 0 {
			allow_name := keyed_archive_class(allow_input) or { C.ios_objc_initialize_unlock(); panic('iOS: keyed unarchive requires a known class set') }
			if allow_name !in ['NSSet', 'NSMutableSet']! { C.ios_objc_initialize_unlock(); panic('iOS: keyed unarchive allowed classes must be NSSet') }
			header := ns_set_header(allow_input)
			if header.cf_raw_values || header.items.len > 4096 { C.ios_objc_initialize_unlock(); panic('iOS: keyed unarchive class set exceeds profile') }
			for member in header.items { allowed << member }
		}
		for member in allowed { if member !in ios_runtime.classes || objc_class_meta(member) { C.ios_objc_initialize_unlock(); panic('iOS: keyed unarchive allowed member must be a class') } }
	}
	length := if input == 0 { u64(0) } else { data_length(input) }
	if length > u64(keyed_archive_limit) { C.ios_objc_initialize_unlock(); panic('iOS: keyed unarchive input exceeds size profile') }
	mut bytes := []u8{len: int(length)}
	if length != 0 { unsafe { C.memcpy(bytes.data, voidptr(data_pointer(input)), usize(length)) } }
	C.ios_objc_initialize_unlock()
	defer { unsafe { bytes.free() } }
	error_output := if secure { frame.x[4] } else if selector == 'unarchiveTopLevelObjectWithData:error:' { frame.x[3] } else { u64(0) }
	result := keyed_decode(bytes, allowed, secure) or {
		if selector == 'unarchiveObjectWithData:' { frame.x[0] = 0; return true }
		keyed_decode_error(error_output, if secure && err.code() == 0 { 4864 } else { err.code() }, err.msg())
		frame.x[0] = 0
		return true
	}
	if result == 0 && selector != 'unarchiveObjectWithData:' { keyed_decode_error(error_output, 4865, keyed_decode_root.reason) }
	frame.x[0] = objc_autorelease(result)
	return true
}
