// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math.bits

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getSuperclass(voidptr) voidptr
fn C.class_getClassMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.objc_storeWeak(&u64, voidptr) voidptr

type KeyedArchiveSend = fn (u64, u64, u64, u64, u64, u64) u64
type KeyedArchiveRealSend = fn (u64, u64, f64) u64
struct KeyedArchiveApi { native bool send u64 }
fn (api KeyedArchiveApi) cls(name string) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name.str)) } }
	return ios_runtime.names[name]
}
fn (api KeyedArchiveApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api KeyedArchiveApi) message(object u64, name &char, a u64, b u64, c u64, d u64) u64 {
	return unsafe { KeyedArchiveSend(voidptr(api.send))(object, api.selector(name), a, b, c, d) }
}
fn (api KeyedArchiveApi) real(object u64, name &char, value f64) u64 {
	if !api.native && object == api.cls('NSNumber') {
		number := objc_allocate(object); mut header := obj_header(number)
		header.is_real = true; header.real_number = value
		return objc_autorelease(number)
	}
	return unsafe { KeyedArchiveRealSend(voidptr(api.send))(object, api.selector(name), value) }
}
fn (api KeyedArchiveApi) number(word u64, unsigned bool, boolean bool) u64 {
	if !api.native {
		number := objc_allocate(api.cls('NSNumber')); mut header := obj_header(number)
		header.number = i64(word); header.unsigned_number = unsigned; header.cf_boolean = boolean
		return objc_autorelease(number)
	}
	return api.message(api.cls('NSNumber'), if boolean { c'numberWithBool:' } else if unsigned { c'numberWithUnsignedLongLong:' } else { c'numberWithLongLong:' }, word, 0, 0, 0)
}
fn (api KeyedArchiveApi) string(text string) u64 { return api.message(api.cls('NSString'), c'stringWithUTF8String:', u64(text.str), 0, 0, 0) }
fn (api KeyedArchiveApi) pool() u64 {
	$if macos { if api.native { return api.message(api.cls('NSAutoreleasePool'), c'new', 0, 0, 0, 0) } }
	return objc_pool_push()
}
fn (api KeyedArchiveApi) drain(pool u64) {
	$if macos { if api.native { api.message(pool, c'drain', 0, 0, 0, 0); return } }
	objc_pool_pop(pool)
}
fn (api KeyedArchiveApi) weak(slot &u64, object u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { voidptr(object) }); return } }
	objc_store_weak(slot, object)
}
fn (api KeyedArchiveApi) destroy_weak(slot &u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { nil }); return } }
	objc_destroy_weak(slot)
}
fn (api KeyedArchiveApi) bytes(data u64) []u8 {
	length := api.message(data, c'length', 0, 0, 0, 0)
	pointer := api.message(data, c'bytes', 0, 0, 0, 0)
	return if length == 0 { []u8{} } else { unsafe { (&u8(voidptr(pointer))).vbytes(int(length)).clone() } }
}
fn (api KeyedArchiveApi) array(values []u64, mutable bool) u64 {
	return api.message(api.cls(if mutable { 'NSMutableArray' } else { 'NSArray' }), c'arrayWithObjects:count:', u64(values.data), u64(values.len), 0, 0)
}
fn (api KeyedArchiveApi) dictionary(keys []u64, values []u64, mutable bool) u64 {
	return api.message(api.cls(if mutable { 'NSMutableDictionary' } else { 'NSDictionary' }), c'dictionaryWithObjects:forKeys:count:', u64(values.data), u64(keys.data), u64(keys.len), 0)
}
fn (api KeyedArchiveApi) corpus(name string) u64 {
	numbers := api.cls('NSNumber')
	match name {
		'nil' { return 0 }
		'nul-string' {
			bytes := [u8(97), 0, 98]!
			if !api.native { return objc_autorelease(owned_string(unsafe { tos(&bytes[0], bytes.len) })) }
			value := api.message(api.message(api.cls('NSString'), c'alloc', 0, 0, 0, 0), c'initWithBytes:length:encoding:', u64(unsafe { &bytes[0] }), u64(bytes.len), 4, 0)
			return api.message(value, c'autorelease', 0, 0, 0, 0)
		}
		'string', 'empty-string', 'long-string' { return api.string(if name == 'empty-string' { '' } else if name == 'long-string' { 'ascii'.repeat(300) } else { 'keyed & < 😀 é' }) }
		'mutable-string' {
			value := api.message(api.message(api.cls('NSMutableString'), c'alloc', 0, 0, 0, 0), c'initWithString:', api.string('keyed & < 😀 é'), 0, 0, 0)
			return api.message(value, c'autorelease', 0, 0, 0, 0)
		}
		'false', 'true' { return api.number(u64(name == 'true'), false, true) }
		'zero', 'negative', 'minimum', 'positive', 'unsigned-high', 'unsigned-max' {
			word := match name { 'negative' { u64(i64(-43)) } 'minimum', 'unsigned-high' { u64(1) << 63 } 'positive' { u64(0x123456789) } 'unsigned-max' { ~u64(0) } else { u64(0) } }
			return api.number(word, name.starts_with('unsigned'), false)
		}
		'real', 'negative-zero', 'infinity', 'nan' {
			word := match name { 'negative-zero' { u64(1) << 63 } 'infinity' { u64(0x7ff0000000000000) } 'nan' { u64(0x7ff8000000000000) } else { u64(0x3ff4000000000000) } }
			return api.real(numbers, c'numberWithDouble:', bits.f64_from_bits(word))
		}
		'data', 'empty-data', 'mutable-data', 'large-data' {
			mut bytes := []u8{len: if name == 'empty-data' { 0 } else if name == 'large-data' { 70000 } else { 4 }}
			for i in 0 .. bytes.len { bytes[i] = u8(i * 73 + 17) }
			if !api.native && name == 'mutable-data' {
				data := objc_allocate(api.cls('NSMutableData'))
				obj_header(data).data = bytes.clone()
				return objc_autorelease(data)
			}
			return api.message(api.cls(if name == 'mutable-data' { 'NSMutableData' } else { 'NSData' }), c'dataWithBytes:length:', u64(bytes.data), u64(bytes.len), 0, 0)
		}
		'date' { return api.real(api.cls('NSDate'), c'dateWithTimeIntervalSinceReferenceDate:', -12345.25) }
		'null' { return api.message(api.cls('NSNull'), c'null', 0, 0, 0, 0) }
		'array', 'mutable-array' {
			child := api.string('shared child')
			return api.array([child, api.corpus('negative'), child, api.corpus('null')], name == 'mutable-array')
		}
		'empty-array' { return api.array([]u64{}, false) }
		'dictionary', 'mutable-dictionary' { return api.dictionary([api.string('text'), api.string('array')], [api.string('value'), api.corpus('array')], name == 'mutable-dictionary') }
		'empty-dictionary' { return api.dictionary([]u64{}, []u64{}, false) }
		'distinct-equal' { return api.array([api.corpus('mutable-string'), api.corpus('mutable-string')], false) }
		'wide-references' {
			mut values := []u64{cap: 300}
			for i in 0 .. 300 { values << api.string('distinct-' + i.str()) }
			return api.array(values, false)
		}
		'depth-boundary' { mut root := api.string('leaf'); for _ in 0 .. 64 { root = api.array([root], false) }; return root }
		else { panic('unknown keyed archive corpus ' + name) }
	}
}

// Independent reader: binary object references and archive UID references are
// kept separate. This deliberately does not call the production plist parser.
struct KeyedArchiveTestNode { kind u8 word u64 high u64 text string bytes []u8 refs []int width int }
struct KeyedArchiveTestPlist { nodes []KeyedArchiveTestNode top int ref_width int offset_width int }
fn keyed_test_word(bytes []u8, at int, width int) u64 {
	assert width > 0 && width <= 8 && at >= 0 && at + width <= bytes.len
	mut result := u64(0)
	for byte in bytes[at .. at + width] { result = (result << 8) | u64(byte) }
	return result
}
fn keyed_test_parse(bytes []u8) KeyedArchiveTestPlist {
	assert bytes.len >= 40 && bytes[..8].bytestr() == 'bplist00'
	trailer := bytes.len - 32
	offset_width := int(bytes[trailer + 6]); ref_width := int(bytes[trailer + 7])
	count := int(keyed_test_word(bytes, trailer + 8, 8)); top := int(keyed_test_word(bytes, trailer + 16, 8)); table := int(keyed_test_word(bytes, trailer + 24, 8))
	assert count > 0 && count < 100000 && top >= 0 && top < count && table >= 8 && table + count * offset_width == trailer
	mut nodes := []KeyedArchiveTestNode{cap: count}
	for i in 0 .. count {
		mut at := int(keyed_test_word(bytes, table + i * offset_width, offset_width)); assert at >= 8 && at < table
		marker := bytes[at]; at++; kind := marker >> 4; mut length := int(marker & 15)
		if kind in [u8(4), 5, 6, 10, 13] && length == 15 {
			assert bytes[at] >> 4 == 1
			width := 1 << (bytes[at] & 15); at++; length = int(keyed_test_word(bytes, at, width)); at += width
		}
		mut node := KeyedArchiveTestNode{kind: kind}
		match kind {
			0 { assert marker == 8 || marker == 9; node = KeyedArchiveTestNode{kind: 0, word: u64(marker == 9)} }
			1 {
				width := 1 << length; assert width <= 16
				node = KeyedArchiveTestNode{kind: 1, word: keyed_test_word(bytes, at + if width == 16 { 8 } else { 0 }, if width == 16 { 8 } else { width }), high: if width == 16 { keyed_test_word(bytes, at, 8) } else { 0 }, width: width}
			}
			2 { width := 1 << length; assert width == 4 || width == 8; word := keyed_test_word(bytes, at, width); node = KeyedArchiveTestNode{kind: 2, word: if width == 4 { bits.f64_bits(f64(bits.f32_from_bits(u32(word)))) } else { word }, width: width} }
			4 { assert at + length <= table; node = KeyedArchiveTestNode{kind: 4, bytes: bytes[at .. at + length].clone()} }
			5 { assert at + length <= table; node = KeyedArchiveTestNode{kind: 5, text: bytes[at .. at + length].bytestr()} }
			6 {
				assert at + length * 2 <= table
				mut runes := []rune{cap: length}; mut n := 0
				for n < length {
					first := u32(keyed_test_word(bytes, at + n * 2, 2)); n++
					if first >= 0xd800 && first <= 0xdbff { assert n < length; second := u32(keyed_test_word(bytes, at + n * 2, 2)); n++; assert second >= 0xdc00 && second <= 0xdfff; runes << rune(0x10000 + ((first - 0xd800) << 10) + second - 0xdc00) }
					else { assert first < 0xdc00 || first > 0xdfff; runes << rune(first) }
				}
				node = KeyedArchiveTestNode{kind: 5, text: runes.string()}
			}
			8 { node = KeyedArchiveTestNode{kind: 8, word: keyed_test_word(bytes, at, length + 1)} }
			10, 13 {
				mut refs := []int{cap: length * if kind == 13 { 2 } else { 1 }}
				for n in 0 .. length * if kind == 13 { 2 } else { 1 } { reference := int(keyed_test_word(bytes, at + n * ref_width, ref_width)); assert reference >= 0 && reference < count; refs << reference }
				node = KeyedArchiveTestNode{kind: kind, refs: refs}
			}
			else { panic('unexpected keyed archive plist marker ' + marker.hex()) }
		}
		nodes << node
	}
	return KeyedArchiveTestPlist{nodes: nodes, top: top, ref_width: ref_width, offset_width: offset_width}
}
fn (p KeyedArchiveTestPlist) field(object int, name string) int {
	node := p.nodes[object]; assert node.kind == 13 && node.refs.len % 2 == 0
	for i in 0 .. node.refs.len / 2 { if p.nodes[node.refs[i]].text == name { return node.refs[i + node.refs.len / 2] } }
	panic('missing keyed archive field ' + name)
}
fn (p KeyedArchiveTestPlist) dereference(objects []int, reference int) int {
	node := p.nodes[reference]; assert node.kind == 8 && node.word < u64(objects.len)
	return objects[int(node.word)]
}
fn (p KeyedArchiveTestPlist) class_name(objects []int, object int, expected string) {
	descriptor := p.dereference(objects, p.field(object, '$class'))
	assert p.nodes[p.field(descriptor, '$classname')].text == expected
	chain := p.nodes[p.field(descriptor, '$classes')]; assert chain.kind == 10
	mut names := []string{}
	for reference in chain.refs { names << p.nodes[reference].text }
	assert names == if expected.starts_with('NSMutable') { [expected, expected.replace('NSMutable', 'NS'), 'NSObject'] } else { [expected, 'NSObject'] }
}
fn (p KeyedArchiveTestPlist) array_values(objects []int, object int, class_name string) []int {
	p.class_name(objects, object, class_name)
	array := p.nodes[p.field(object, 'NS.objects')]; assert array.kind == 10
	mut values := []int{cap: array.refs.len}
	for reference in array.refs { values << p.dereference(objects, reference) }
	return values
}
fn keyed_test_validate(bytes []u8, name string) {
	p := keyed_test_parse(bytes)
	assert p.nodes[p.field(p.top, '$archiver')].text == 'NSKeyedArchiver'
	assert p.nodes[p.field(p.top, '$version')].word == 100000
	objects := p.nodes[p.field(p.top, '$objects')]; assert objects.kind == 10 && p.nodes[objects.refs[0]].text == '$null'
	root_ref := p.field(p.field(p.top, '$top'), 'root'); root := p.dereference(objects.refs, root_ref)
	if name == 'nil' { assert p.nodes[root_ref].word == 0 && objects.refs.len == 1; return }
	assert p.nodes[root_ref].word != 0
	mut node := p.nodes[root]
	match name {
		'nul-string' { assert node.kind == 5 && node.text.bytes() == [u8(97), 0, 98] }
		'string', 'empty-string', 'long-string', 'mutable-string' {
			if name == 'mutable-string' { p.class_name(objects.refs, root, 'NSMutableString'); node = p.nodes[p.field(root, 'NS.string')] }
			assert node.kind == 5 && node.text == if name == 'empty-string' { '' } else if name == 'long-string' { 'ascii'.repeat(300) } else { 'keyed & < 😀 é' }
		}
		'false', 'true' { assert node.kind == 0 && node.word == u64(name == 'true') }
		'zero', 'negative', 'minimum', 'positive', 'unsigned-high', 'unsigned-max' {
			word := match name { 'negative' { u64(i64(-43)) } 'minimum', 'unsigned-high' { u64(1) << 63 } 'positive' { u64(0x123456789) } 'unsigned-max' { ~u64(0) } else { u64(0) } }
			assert node.kind == 1 && node.word == word && node.high == 0
			if name.starts_with('unsigned') { assert node.width == 16 }
			if name == 'minimum' || name == 'negative' { assert node.width == 8 }
		}
		'real', 'negative-zero', 'infinity', 'nan' {
			word := match name { 'negative-zero' { u64(1) << 63 } 'infinity' { u64(0x7ff0000000000000) } 'nan' { u64(0x7ff8000000000000) } else { u64(0x3ff4000000000000) } }
			assert node.kind == 2 && node.word == word
		}
		'data', 'empty-data', 'mutable-data', 'large-data' {
			if name == 'mutable-data' { p.class_name(objects.refs, root, 'NSMutableData'); node = p.nodes[p.field(root, 'NS.data')] }
			assert node.kind == 4 && node.bytes.len == if name == 'empty-data' { 0 } else if name == 'large-data' { 70000 } else { 4 }
			for i, byte in node.bytes { assert byte == u8(i * 73 + 17) }
			if name == 'large-data' { assert p.offset_width >= 4 }
		}
		'date' { p.class_name(objects.refs, root, 'NSDate'); time := p.nodes[p.field(root, 'NS.time')]; assert time.kind == 2 && time.word == bits.f64_bits(-12345.25) }
		'null' { p.class_name(objects.refs, root, 'NSNull') }
		'array', 'mutable-array', 'empty-array', 'distinct-equal', 'wide-references' {
			values := p.array_values(objects.refs, root, if name == 'mutable-array' { 'NSMutableArray' } else { 'NSArray' })
			if name == 'empty-array' { assert values.len == 0 }
			else if name == 'distinct-equal' { assert values.len == 2 && values[0] != values[1]; for value in values { p.class_name(objects.refs, value, 'NSMutableString'); assert p.nodes[p.field(value, 'NS.string')].text == 'keyed & < 😀 é' } }
			else if name == 'wide-references' { assert values.len == 300 && p.ref_width >= 2; for i, value in values { assert p.nodes[value].text == 'distinct-' + i.str() } }
			else { assert values.len == 4 && values[0] == values[2] && p.nodes[values[0]].text == 'shared child' && p.nodes[values[1]].word == u64(i64(-43)); p.class_name(objects.refs, values[3], 'NSNull') }
		}
		'dictionary', 'mutable-dictionary', 'empty-dictionary' {
			p.class_name(objects.refs, root, if name == 'mutable-dictionary' { 'NSMutableDictionary' } else { 'NSDictionary' })
			keys := p.nodes[p.field(root, 'NS.keys')]; values := p.nodes[p.field(root, 'NS.objects')]
			assert keys.kind == 10 && values.kind == 10 && keys.refs.len == values.refs.len && keys.refs.len == if name == 'empty-dictionary' { 0 } else { 2 }
			for i, key in keys.refs {
				text := p.nodes[p.dereference(objects.refs, key)].text; value := p.dereference(objects.refs, values.refs[i])
				if text == 'text' { assert p.nodes[value].text == 'value' }
				else { assert text == 'array'; array := p.array_values(objects.refs, value, 'NSArray'); assert array.len == 4 && array[0] == array[2] && p.nodes[array[0]].text == 'shared child' }
			}
		}
		'depth-boundary' {
			mut nested := root
			for _ in 0 .. 64 { children := p.array_values(objects.refs, nested, 'NSArray'); assert children.len == 1; nested = children[0] }
			assert p.nodes[nested].text == 'leaf'
		}
		else { panic('unvalidated keyed archive case ' + name) }
	}
}

fn keyed_archiver_native_api() KeyedArchiveApi {
	$if macos { return KeyedArchiveApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))} }
	return KeyedArchiveApi{}
}
fn keyed_archiver_shared(api KeyedArchiveApi) {
	for name in ['nil', 'string', 'nul-string', 'empty-string', 'long-string', 'mutable-string', 'false', 'true', 'zero', 'negative', 'minimum', 'positive', 'unsigned-high', 'unsigned-max', 'real', 'negative-zero', 'infinity', 'nan', 'data', 'empty-data', 'mutable-data', 'large-data', 'date', 'null', 'array', 'mutable-array', 'empty-array', 'dictionary', 'mutable-dictionary', 'empty-dictionary', 'distinct-equal', 'wide-references', 'depth-boundary']! {
		for mode in 0 .. 3 {
			pool := api.pool(); root := api.corpus(name)
			mut error_slot := [u64(0x1122334455667788), 0x5a5a5a5a5a5a5a5a, 0x8877665544332211]!
			archive := if mode == 0 { api.message(api.cls('NSKeyedArchiver'), c'archivedDataWithRootObject:', root, 0, 0, 0) } else { api.message(api.cls('NSKeyedArchiver'), c'archivedDataWithRootObject:requiringSecureCoding:error:', root, u64(mode == 2), u64(unsafe { &error_slot[1] }), 0) }
			assert archive != 0 && error_slot == [u64(0x1122334455667788), 0x5a5a5a5a5a5a5a5a, 0x8877665544332211]!
			bytes := api.bytes(archive); keyed_test_validate(bytes, name)
			$if macos {
				native := keyed_archiver_native_api(); native_pool := native.pool()
				native_data := native.message(native.cls('NSData'), c'dataWithBytes:length:', u64(bytes.data), u64(bytes.len), 0, 0)
				decoded := native.message(native.cls('NSKeyedUnarchiver'), c'unarchiveObjectWithData:', native_data, 0, 0, 0)
				expected := native.corpus(name)
				assert if name == 'nil' { decoded == 0 } else { native.message(decoded, c'isEqual:', expected, 0, 0, 0) == 1 }, name
				if name in ['mutable-string', 'mutable-data', 'mutable-array', 'mutable-dictionary'] { assert native.message(decoded, c'isKindOfClass:', native.cls(match name { 'mutable-string' { 'NSMutableString' } 'mutable-data' { 'NSMutableData' } 'mutable-array' { 'NSMutableArray' } else { 'NSMutableDictionary' } }), 0, 0, 0) == 1 }
				if name == 'array' { assert native.message(decoded, c'objectAtIndex:', 0, 0, 0, 0) == native.message(decoded, c'objectAtIndex:', 2, 0, 0, 0) }
				native.drain(native_pool)
			}
			api.drain(pool)
		}
	}
	// The archive owns independent bytes and does not keep its input graph alive.
	pool := api.pool(); root := api.corpus('mutable-string')
	mut root_weak := u64(0); mut archive_weak := u64(0)
	api.weak(unsafe { &root_weak }, root)
	archive := api.message(api.cls('NSKeyedArchiver'), c'archivedDataWithRootObject:', root, 0, 0, 0)
	api.message(archive, c'retain', 0, 0, 0, 0); api.weak(unsafe { &archive_weak }, archive)
	api.message(root, c'setString:', api.string('input changed after archiving'), 0, 0, 0)
	keyed_test_validate(api.bytes(archive), 'mutable-string'); api.drain(pool)
	assert root_weak == 0 && archive_weak != 0
	after := api.pool(); keyed_test_validate(api.bytes(archive), 'mutable-string')
	api.message(archive, c'release', 0, 0, 0, 0); api.drain(after); assert archive_weak == 0
	api.destroy_weak(unsafe { &root_weak }); api.destroy_weak(unsafe { &archive_weak })
}
fn test_keyed_archiver_native() {
	$if macos {
		api := keyed_archiver_native_api()
		assert C.class_getInstanceSize(unsafe { voidptr(api.cls('NSCoder')) }) == 8
		assert C.class_getInstanceSize(unsafe { voidptr(api.cls('NSKeyedArchiver')) }) == 136
		assert C.class_getSuperclass(unsafe { voidptr(api.cls('NSKeyedArchiver')) }) == unsafe { voidptr(api.cls('NSCoder')) }
		for name, expected in {'archivedDataWithRootObject:': '@24@0:8@16', 'archivedDataWithRootObject:requiringSecureCoding:error:': '@36@0:8@16B24^@28'} {
			method := C.class_getClassMethod(unsafe { voidptr(api.cls('NSKeyedArchiver')) }, C.sel_registerName(name.str)); assert method != unsafe { nil } && unsafe { C.method_getTypeEncoding(method).vstring() } == expected
		}
		keyed_archiver_shared(api)
		println('IOS-KEYED-ARCHIVER-NATIVE:33 builtin graphs across legacy/insecure/secure factories, UID identity, scalar bits, embedded NUL, mutable class chains, wide references/offsets, depth boundary, unchanged NSError and Apple decode')
	}
}

// Runtime-only fixtures.
__global keyed_archiver_callback_root = u64(0)
__global keyed_archiver_callback_weak = u64(0)
__global keyed_archiver_constructor_fail = false
fn keyed_archiver_runtime_api() KeyedArchiveApi { return KeyedArchiveApi{send: u64(unsafe { voidptr(C.ios_objc_builtin) })} }
fn keyed_archiver_drop_input() {
	pool := objc_pool_push()
	assert string_text(keyed_archiver_callback_root) == 'keyed & < 😀 é'
	other := objc_new(ios_runtime.names['NSObject']); objc_release(other)
	objc_release(keyed_archiver_callback_root); objc_pool_pop(pool)
}
fn keyed_archiver_output_constructor(object u64, selector &char) u64 {
	if keyed_archiver_constructor_fail { return 0 }
	if keyed_archiver_callback_root != 0 { worker := spawn keyed_archiver_drop_input(); worker.wait() }
	return object
}
fn keyed_archiver_only_cached_null() {
	object := ios_runtime.null_object
	assert object != 0 && ios_runtime.live == 1 && ios_runtime.objects.len == 1
	assert object in ios_runtime.objects && ios_runtime.framework_objects == [object]
	assert read64(object) == ios_runtime.names['NSNull'] && obj_header(object).refs == 1
	assert ios_runtime.weak.len == 0
}
fn test_keyed_archiver_runtime() {
	for _ in 0 .. 2 {
		objc_start(); system_data_start()!; api := keyed_archiver_runtime_api()
		for name in ['NSCoder', 'NSKeyedArchiver']! {
			cls := api.cls(name); library := '/System/Library/Frameworks/Foundation.framework/Foundation'
			assert runtime_symbol(library, '_OBJC_CLASS_$_' + name)! == cls && runtime_symbol(library, '_OBJC_METACLASS_$_' + name)! == read64(cls)
		}
		assert objc_class_size(api.cls('NSCoder')) == 8 && objc_class_parent(api.cls('NSCoder')) == api.cls('NSObject')
		assert objc_class_size(api.cls('NSKeyedArchiver')) == 136 && objc_class_parent(api.cls('NSKeyedArchiver')) == api.cls('NSCoder')
		assert ios_runtime.classes[api.cls('NSKeyedArchiver')].ivars.len == 16
		assert objc_responds(api.cls('NSKeyedArchiver'), c'archivedDataWithRootObject:')
		assert objc_responds(api.cls('NSKeyedArchiver'), c'archivedDataWithRootObject:requiringSecureCoding:error:')
		assert !objc_responds(api.cls('NSCoder'), c'archivedDataWithRootObject:')
		for selector in [c'alloc', c'new', c'initForWritingWithMutableData:', c'encodeObject:forKey:', c'encodedData', c'finishEncoding', c'archiveRootObject:toFile:']! {
			assert !objc_responds(api.cls('NSKeyedArchiver'), selector)
		}
		for i, pair in [['_stream', '^v']!, ['_flags', 'AQ']!, ['_delegate', '@"<NSKeyedArchiverDelegate>"']!, ['_containers', '@"NSMutableArray"']!, ['_objects', '@"NSMutableArray"']!, ['_objRefMap', '^{__CFDictionary=}']!, ['_replacementMap', '^{__CFDictionary=}']!, ['_classNameMap', '^{__CFDictionary=}']!, ['_conditionals', '^{__CFDictionary=}']!, ['_classes', '^{__CFDictionary=}']!, ['_genericKey', 'Q']!, ['_cache', 'r^^{__CFKeyedArchiverUID}']!, ['_cacheSize', 'Q']!, ['_estimatedCount', 'Q']!, ['_visited', '^{__CFSet=}']!, ['_pac_signature', 'Q']!]! {
			ivar := objc_find_ivar(api.cls('NSKeyedArchiver'), pair[0].str); assert ivar != 0 && objc_ivar_offset(ivar) == u64(8 + i * 8) && ctext(u64(objc_ivar_types(ivar))) == pair[1]
		}
		for name, expected in {'archivedDataWithRootObject:': '@24@0:8@16', 'archivedDataWithRootObject:requiringSecureCoding:error:': '@36@0:8@16B24^@28'} { assert ctext(u64(objc_method_types(objc_instance_method(read64(api.cls('NSKeyedArchiver')), u64(name.str))))) == expected }
		keyed_archiver_shared(api); keyed_archiver_only_cached_null()
		pool := api.pool()
		// NSDate's CF bridge uses the same measured NS.time archive record.
		bridged := cf_date_create(0, -12345.25)
		bridged_data := api.message(api.cls('NSKeyedArchiver'), c'archivedDataWithRootObject:', bridged, 0, 0, 0)
		keyed_test_validate(api.bytes(bridged_data), 'date'); objc_release(bridged)
		// The output allocation callback may retire the caller's last input owner.
		keyed_archiver_callback_root = owned_string('keyed & < 😀 é')
		objc_store_weak(unsafe { &keyed_archiver_callback_weak }, keyed_archiver_callback_root)
		assert objc_add_method(api.cls('NSData'), u64(c'.cxx_construct'), u64(unsafe { voidptr(keyed_archiver_output_constructor) }), c'@16@0:8')
		result := api.message(api.cls('NSKeyedArchiver'), c'archivedDataWithRootObject:', keyed_archiver_callback_root, 0, 0, 0)
		assert keyed_archiver_callback_weak == 0; objc_destroy_weak(unsafe { &keyed_archiver_callback_weak }); keyed_archiver_callback_root = 0
		keyed_test_validate(api.bytes(result), 'string')
		api.drain(pool); keyed_archiver_only_cached_null()
		objc_stop(); assert ios_runtime.live == 0; system_data_stop()
	}
	println('IOS-KEYED-ARCHIVER: measured metadata,99 builtin factory cases, independent snapshots, CFDate, Apple decode, callback input pin and two drained runtimes')
}
fn keyed_archiver_forbidden_coding(object u64, selector &char, coder u64) { C._exit(19) }
fn test_keyed_archiver_rejections() {
	objc_start(); system_data_start()!; api := keyed_archiver_runtime_api()
	modes := ['alloc', 'allocWithZone:', 'new', 'init', 'initForWritingWithMutableData:', 'initRequiringSecureCoding:', 'encodeObject:forKey:', 'finishEncoding', 'encodedData', 'requiresSecureCoding', 'setRequiresSecureCoding:', 'outputFormat', 'setOutputFormat:', 'delegate', 'setDelegate:', 'error', 'allowsKeyedCoding', 'archiveRootObject:toFile:', 'classNameForClass:', 'setClassName:forClass:', 'copy', 'mutableCopy', 'supportsSecureCoding', 'coder-alloc', 'caller-storage', 'custom-factory', 'custom-object', 'custom-string', 'class-object', 'spoof', 'changed-isa', 'changed-number-isa', 'nonstring-key', 'raw-values', 'raw-keys', 'mismatched-dictionary', 'depth', 'size', 'node-limit', 'invalid-utf8', 'nil-output', 'cycle']!
	for mode in modes {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.ios_fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			mut root := u64(0)
			match mode {
				'coder-alloc' { objc_allocate(api.cls('NSCoder')) }
				'caller-storage' { mut storage := [17]u64{}; objc_construct_instance(api.cls('NSKeyedArchiver'), u64(unsafe { &storage[0] })) }
				'custom-factory' { cls := objc_allocate_class(api.cls('NSKeyedArchiver'), c'VinixUnsupportedArchiver', 0); objc_register_class(cls); api.message(cls, c'archivedDataWithRootObject:', 0, 0, 0, 0) }
				'custom-object', 'custom-string' {
					cls := objc_allocate_class(api.cls(if mode == 'custom-string' { 'NSString' } else { 'NSObject' }), c'VinixUnsupportedCodedObject', 0)
					assert objc_add_method(cls, u64(c'encodeWithCoder:'), u64(unsafe { voidptr(keyed_archiver_forbidden_coding) }), c'v24@0:8@16'); objc_register_class(cls); root = objc_new(cls)
				}
				'class-object' { root = api.cls('NSString') }
				'spoof' { root = objc_new(api.cls('NSObject')); objc_set_class(root, api.cls('NSString')) }
				'changed-isa' { root = owned_string('changed original class'); objc_set_class(root, api.cls('NSMutableString')) }
				'changed-number-isa' { root = owned_string('changed original class'); objc_set_class(root, api.cls('NSNumber')) }
				'nonstring-key' { root = api.dictionary([api.number(42, false, false)], [api.string('value')], false) }
				'raw-values', 'raw-keys', 'mismatched-dictionary' {
					root = api.corpus('dictionary'); mut header := obj_header(root)
					if mode == 'raw-values' { header.cf_raw_values = true } else if mode == 'raw-keys' { header.cf_raw_keys = true } else { header.keys.delete_last() }
				}
				'depth' { root = api.string('leaf'); for _ in 0 .. 65 { root = api.array([root], false) } }
				'cycle' { root = api.array([]u64{}, true); api.message(root, c'addObject:', root, 0, 0, 0) }
				'size' { root = objc_allocate(api.cls('NSData')); obj_header(root).data = []u8{len: 16777216} }
				'node-limit' { mut values := []u64{cap: 34000}; for i in 0 .. 34000 { values << api.string('node-' + i.str()) }; root = api.array(values, false) }
				'invalid-utf8' { invalid := [u8(255)]!; root = owned_string(unsafe { tos(&invalid[0], 1) }) }
				'nil-output' { keyed_archiver_constructor_fail = true; assert objc_add_method(api.cls('NSData'), u64(c'.cxx_construct'), u64(unsafe { voidptr(keyed_archiver_output_constructor) }), c'@16@0:8'); root = api.string('nil allocation') }
				else { api.message(api.cls('NSKeyedArchiver'), mode.str, 0, 0, 0, 0) }
			}
			api.message(api.cls('NSKeyedArchiver'), c'archivedDataWithRootObject:requiringSecureCoding:error:', root, 1, 0, 0)
			C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid
		output := unsafe { tos(&bytes[0], length) }
		assert status == 256 && output.contains('iOS:') && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), mode + ': ' + output
	}
	assert ios_runtime.live == 0; objc_stop(); system_data_stop()
	println('IOS-KEYED-ARCHIVER-REJECT:42 instance/coding/file APIs, custom classes, changed isa, cycles, invalid storage/keys/UTF8, depth/size/node bounds and failed output allocation fail explicitly')
}
