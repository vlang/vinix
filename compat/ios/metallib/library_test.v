// SPDX-License-Identifier: GPL-2.0-or-later
module metallib

import crypto.sha256

fn put(mut data []u8, offset int, size int, value u64) {
	for i in 0 .. size { data[offset + i] = u8(value >> u32(i * 8)) }
}

fn append_number(mut data []u8, size int, value u64) {
	start := data.len
	for _ in 0 .. size { data << u8(0) }
	put(mut data, start, size, value)
}

fn append_tag(mut data []u8, name string, payload []u8) {
	data << name.bytes()
	append_number(mut data, 2, u64(payload.len))
	data << payload
}

fn checksum(data []u8) []u8 {
	mut hash := sha256.new()
	defer { unsafe { hash.free(); free(hash) } }
	hash.write(data) or { panic(err) }
	return hash.sum([]u8{})
}

// Intentionally small containers, not executable LLVM programs. Real AIR is
// checked separately against native Metal and llvm-bcanalyzer by the inspector.
fn fixture(names []string, wrapped bool, aliased bool) []u8 {
	mut code := []u8{}
	code.flags |= .noslices
	if wrapped {
		for value in [u64(0x0b17c0de), 0, 20, 8, 0xffffffff]! { append_number(mut code, 4, value) }
	}
	code << [u8(0x42), 0x43, 0xc0, 0xde, 0, 0, 0, 0]
	if wrapped { code << [u8(0), 0, 0, 0] }
	defer { unsafe { code.free() } }
	digest := checksum(code)
	defer { unsafe { digest.free() } }
	mut data := []u8{len: 88}
	data.flags |= .noslices
	for i, b in 'MTLB'.bytes() { data[i] = b }
	put(mut data, 4, 2, 1); put(mut data, 6, 2, 2); put(mut data, 8, 2, 7)
	data[11] = 0x82
	put(mut data, 12, 2, 16)
	append_number(mut data, 4, u64(names.len))
	for i, name in names {
		start := data.len
		append_number(mut data, 4, 0)
		mut text := name.bytes(); text << u8(0)
		append_tag(mut data, 'NAME', text)
		unsafe { text.free() }
		append_tag(mut data, 'TYPE', [u8(i % 3)])
		append_tag(mut data, 'HASH', digest)
		mut offsets := []u8{len: 24}
		put(mut offsets, 0, 8, u64(i * 8)); put(mut offsets, 8, 8, u64(i * 8))
		put(mut offsets, 16, 8, if aliased { u64(0) } else { u64(i * code.len) })
		append_tag(mut data, 'OFFT', offsets)
		unsafe { offsets.free() }
		append_tag(mut data, 'VERS', [u8(2), 0, 7, 0, 3, 0, 0, 0])
		mut size := []u8{len: 8}; put(mut size, 0, 8, u64(code.len))
		append_tag(mut data, 'MDSZ', size)
		unsafe { size.free() }
		append_tag(mut data, 'TST0', [u8(1), 2, 3])
		data << 'ENDT'.bytes()
		put(mut data, start, 4, u64(data.len - start))
	}
	put(mut data, 24, 8, 88); put(mut data, 32, 8, u64(data.len - 92))
	append_tag(mut data, 'UUID', []u8{len: 16})
	data << 'ENDT'.bytes()
	for field in [40, 56]! {
		put(mut data, field, 8, u64(data.len)); put(mut data, field + 8, 8, u64(names.len * 8))
		for _ in names { append_number(mut data, 4, 8); data << 'ENDT'.bytes() }
	}
	put(mut data, 72, 8, u64(data.len))
	module_count := if aliased && names.len != 0 { 1 } else { names.len }
	for _ in 0 .. module_count { data << code }
	bits_start := Reader{data: data}.number(72, 8) or { panic(err) }
	put(mut data, 80, 8, u64(data.len) - bits_start)
	put(mut data, 16, 8, u64(data.len))
	return data
}

fn locate(data []u8, tag string, start int) int {
	for i in start .. data.len - 3 {
		if data[i] == tag[0] && data[i + 1] == tag[1] && data[i + 2] == tag[2] && data[i + 3] == tag[3] { return i }
	}
	panic('fixture tag missing: ' + tag)
}

fn reject(data []u8, reason string) {
	if library := parse(data) { library.free(); assert false, 'accepted ' + reason }
}

fn test_library_index_borrows_names_checksums_and_shared_modules() {
	for wrapped in [false, true]! {
		for aliased in [false, true]! {
			data := fixture(['vertex', 'fragment', 'kernel'], wrapped, aliased)
			before := data.clone()
			library := parse(data)!
			assert library.platform == 1 && library.target_os == 0x82 && library.major == 2 && library.minor == 7
			assert library.functions.len == 3 && library.modules.len == if aliased { 1 } else { 3 }
			for i, function in library.functions {
				assert function.name == ['vertex', 'fragment', 'kernel'][i]
				assert function.kind == u8(i) && function.module == if aliased { 0 } else { i }
				assert function.versions == [u16(2), 7, 3, 0]!
				assert u64(function.name.str) >= u64(data.data) && u64(function.name.str) < u64(data.data) + u64(data.len)
			}
			for module in library.modules {
				assert module.bitcode.size == 8
				assert module.bitcode.offset == module.archive.offset + if wrapped { u64(20) } else { u64(0) }
			}
			assert data == before
			library.free()
			unsafe { before.free(); data.free() }
		}
	}
	empty := fixture([]string{}, false, false)
	library := parse(empty)!
	assert library.functions.len == 0 && library.modules.len == 0
	library.free(); unsafe { empty.free() }
	println('METALLIB-INDEX: raw/wrapped AIR, independent/shared modules, borrowed names, immutable input and empty library PASS')
}

fn test_truncations_counts_ranges_and_function_fields() {
	base := fixture(['sample'], true, false)
	defer { unsafe { base.free() } }
	for size in 0 .. base.len { reject(base[..size], 'truncated library') }
	for field in [24, 32, 40, 48, 56, 64, 72, 80]! {
		mut data := base.clone()
		put(mut data, field, 8, ~u64(0))
		reject(data, 'overflowed header range')
		unsafe { data.free() }
	}
	for mode in ['magic', 'major', 'file-size', 'count', 'count-trailing', 'section-overlap', 'group-size', 'group-end', 'tag-size',
		'name-nul', 'name-utf8', 'name-empty', 'type', 'hash-length', 'hash-content', 'module-size',
		'public-offset', 'private-offset', 'code-offset', 'duplicate-field', 'metadata-size', 'extension-overlap',
		'wrapper-version', 'wrapper-offset', 'wrapper-size', 'llvm-magic', 'llvm-alignment', 'padding-hash',
		'missing-field', 'premature-end'] {
		mut data := base.clone()
		name := locate(data, 'NAME', 88)
		hash := locate(data, 'HASH', 88)
		offt := locate(data, 'OFFT', 88)
		bits := int(Reader{data: data}.number(72, 8)!)
		match mode {
			'magic' { data[0] = 0 }
			'major' { put(mut data, 6, 2, 3) }
			'file-size' { put(mut data, 16, 8, u64(data.len - 1)) }
			'count' { put(mut data, 88, 4, max_functions + 1) }
			'count-trailing' { put(mut data, 88, 4, 0) }
			'section-overlap' { put(mut data, 72, 8, Reader{data: data}.number(40, 8)!) }
			'group-size' { put(mut data, 92, 4, 0) }
			'group-end' { data[locate(data, 'ENDT', name)] = u8(`X`) }
			'tag-size' { put(mut data, name + 4, 2, 65535) }
			'name-nul' { data[name + 7] = 0 }
			'name-utf8' { data[name + 6] = 0xff }
			'name-empty' { put(mut data, name + 4, 2, 1) }
			'type' { data[locate(data, 'TYPE', name) + 6] = 7 }
			'hash-length' { put(mut data, hash + 4, 2, 31) }
			'hash-content' { data[hash + 6] ^= 1 }
			'module-size' { put(mut data, locate(data, 'MDSZ', name) + 6, 8, ~u64(0)) }
			'public-offset' { put(mut data, offt + 6, 8, 1) }
			'private-offset' { put(mut data, offt + 14, 8, 1) }
			'code-offset' { put(mut data, offt + 22, 8, ~u64(0)) }
			'duplicate-field' { offset := locate(data, 'TST0', name); for i, b in 'NAME'.bytes() { data[offset + i] = b } }
			'metadata-size' { offset := int(Reader{data: data}.number(40, 8)!); put(mut data, offset, 4, 0) }
			'extension-overlap' {
				offset := locate(data, 'UUID', name)
				for i, b in 'HDYN'.bytes() { data[offset + i] = b }
				put(mut data, offset + 6, 8, u64(bits)); put(mut data, offset + 14, 8, 1)
			}
			'wrapper-version' { put(mut data, bits + 4, 4, 1) }
			'wrapper-offset' { put(mut data, bits + 8, 4, 0xfffffffc) }
			'wrapper-size' { put(mut data, bits + 12, 4, 0xffffffff) }
			'llvm-magic' { data[bits + 20] = 0 }
			'llvm-alignment' { put(mut data, bits + 12, 4, 5) }
			'padding-hash' { data[data.len - 1] ^= 1 }
			'missing-field' { offset := locate(data, 'TYPE', name); for i, b in 'XXXX'.bytes() { data[offset + i] = b } }
			'premature-end' { offset := locate(data, 'TST0', name); for i, b in 'ENDT'.bytes() { data[offset + i] = b } }
			else { assert false }
		}
		reject(data, mode)
		unsafe { data.free() }
	}
	duplicate := fixture(['same', 'same'], true, true)
	reject(duplicate, 'duplicate function names'); unsafe { duplicate.free() }
	println('METALLIB-REJECT: ${base.len} truncations, header ranges, counts, tags, names, metadata, LLVM wrappers and full padded-module checksum PASS')
}

fn test_aliases_partial_overlaps_and_tag_work_limit() {
	mut alias := fixture(['first', 'second'], true, true)
	size1 := locate(alias, 'MDSZ', 88)
	size2 := locate(alias, 'MDSZ', size1 + 4)
	put(mut alias, size2 + 6, 8, 28)
	reject(alias, 'inconsistent shared module'); unsafe { alias.free() }
	mut overlap := fixture(['first', 'second'], false, false)
	bits := int(Reader{data: overlap}.number(72, 8)!)
	put(mut overlap, locate(overlap, 'MDSZ', 88) + 6, 8, 16)
	digest := checksum(overlap[bits..bits + 16])
	start := locate(overlap, 'HASH', 88) + 6
	for i, b in digest { overlap[start + i] = b }
	reject(overlap, 'partially overlapping modules')
	unsafe { digest.free(); overlap.free() }
	mut tags := []u8{len: 92}
	tags.flags |= .noslices
	for i, b in 'MTLB'.bytes() { tags[i] = b }
	put(mut tags, 6, 2, 2); put(mut tags, 24, 8, 88)
	for _ in 0 .. max_tags + 1 { append_tag(mut tags, 'XXXX', []u8{}) }
	tags << 'ENDT'.bytes()
	for field in [40, 56, 72]! { put(mut tags, field, 8, u64(tags.len)) }
	put(mut tags, 16, 8, u64(tags.len))
	reject(tags, 'tag work limit'); unsafe { tags.free() }
	println('METALLIB-LIMITS: shared-module consistency, partial overlap and tag work limit PASS')
}

fn test_single_bit_mutations_are_bounded_and_do_not_mutate_the_input() {
	mut data := fixture(['sample'], true, false)
	defer { unsafe { data.free() } }
	for offset in 0 .. data.len {
		for bit in 0 .. 8 {
			data[offset] ^= u8(1) << u8(bit)
			before := data.clone()
			if library := parse(data) {
				for module in library.modules {
					assert module.archive.offset + module.archive.size <= u64(data.len)
					assert module.bitcode.offset >= module.archive.offset
					assert module.bitcode.offset + module.bitcode.size <= module.archive.offset + module.archive.size
				}
				library.free()
			}
			assert data == before
			unsafe { before.free() }
			data[offset] ^= u8(1) << u8(bit)
		}
	}
	println('METALLIB-MUTATIONS: ${data.len * 8} single-bit mutations preserve input and bounded successful indexes PASS')
}
