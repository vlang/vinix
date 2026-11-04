// SPDX-License-Identifier: GPL-2.0-or-later
module metallib

import crypto.sha256
import encoding.utf8

// Container profile: MTLB v2, explicit MDSZ/OFFT/HASH function records. This
// indexes libraries and bounds/checksums their AIR modules; it does not verify
// LLVM IR, compile shaders, or establish GPU capabilities.
// Layout reference: https://github.com/YuAo/MetalLibraryArchive
// Wrapper reference: https://llvm.org/docs/BitCodeFormat.html
pub const max_library_size = 256 * 1024 * 1024
pub const max_functions = 65536
const max_tags = 262144

pub struct Range {
pub:
	offset u64
	size u64
}

pub struct Function {
pub:
	name string // Borrowed UTF-8, excluding its terminating NUL.
	kind u8 // Container types: vertex=0, fragment=1, kernel=2, ... intersection=6.
	versions [4]u16 // AIR major/minor, MSL major/minor.
	public_offset u64
	private_offset u64
	module int
}

pub struct Module {
pub:
	archive Range // Complete HASH/MDSZ range, including the LLVM wrapper/padding.
	bitcode Range // LLVM stream only; bounds/signature checked, IR not verified.
	hash [32]u8
}

pub struct Library {
pub:
	platform u16
	major u16
	minor u16
	kind u8
	target_os u8
	os_major u16
	os_minor u16
	function_list Range // Includes the count, which the header size excludes.
	public_metadata Range
	private_metadata Range
	bitcode_section Range
	extension Range
	functions []Function
	modules []Module
}

// Only the two index arrays are owned. Input bytes, including function names,
// must remain alive and immutable until this index is retired. No input copy.
pub fn (library &Library) free() {
	unsafe { library.functions.free(); library.modules.free() }
}

struct Reader {
	data []u8
mut:
	tags int
}

fn (r Reader) range(offset u64, size u64) !Range {
	if offset > u64(r.data.len) || size > u64(r.data.len) - offset { return error('metallib: range exceeds input') }
	return Range{offset, size}
}

fn (r Reader) number(offset u64, size int) !u64 {
	r.range(offset, u64(size))!
	mut result := u64(0)
	for i in 0 .. size { result |= u64(r.data[int(offset) + i]) << u32(i * 8) }
	return result
}

fn (r Reader) section(offset u64) !Range {
	return r.range(r.number(offset, 8)!, r.number(offset + 8, 8)!)
}

struct Tag {
	name string // Borrowed four-byte tag.
	data Range
}

fn (mut r Reader) tag(start u64, end u64) !Tag {
	mut cursor := start
	if r.tags >= max_tags || cursor > end || end - cursor < 4 { return error('metallib: tag limit or truncated tag') }
	r.tags++
	name := unsafe { tos(&r.data[int(cursor)], 4) }
	cursor += 4
	if name == 'ENDT' {
		if cursor != end { return error('metallib: data after ENDT') }
		return Tag{name: name, data: Range{cursor, 0}}
	}
	if end - cursor < 2 { return error('metallib: missing tag size') }
	size := r.number(cursor, 2)!
	cursor += 2
	if size > end - cursor { return error('metallib: tag exceeds its group') }
	data := Range{cursor, size}
	cursor += size
	return Tag{name, data}
}

fn (r Reader) group(cursor u64, end u64) !Range {
	if cursor > end || end - cursor < 4 { return error('metallib: missing group size') }
	size := r.number(cursor, 4)!
	if size < 8 || size > end - cursor { return error('metallib: invalid group size') }
	result := Range{cursor + 4, size - 4}
	return result
}

fn (mut r Reader) metadata(section Range) !map[u64]bool {
	mut offsets := map[u64]bool{}
	mut keep := false
	defer { if !keep { unsafe { offsets.free() } } }
	mut cursor := section.offset
	end := section.offset + section.size
	for cursor < end {
		offsets[cursor - section.offset] = true
		group := r.group(cursor, end)!
		cursor = group.offset + group.size
		mut tag_cursor := group.offset
		mut ended := false
		for tag_cursor < group.offset + group.size {
			item := r.tag(tag_cursor, group.offset + group.size)!
			tag_cursor = item.data.offset + item.data.size
			if item.name == 'ENDT' { ended = true; break }
		}
		if !ended { return error('metallib: metadata lacks ENDT') }
	}
	keep = true
	return offsets
}

fn disjoint(mut ranges []Range) ! {
	ranges.sort(a.offset < b.offset)
	for i in 1 .. ranges.len {
		if ranges[i].offset < ranges[i - 1].offset + ranges[i - 1].size { return error('metallib: overlapping sections or modules') }
	}
}

fn (r Reader) llvm(module Range) !Range {
	// LLVM IR wrapper fields are LE u32, not native pointer-sized fields.
	if module.size < 4 { return error('metallib: truncated AIR module') }
	magic := r.number(module.offset, 4)!
	mut stream := module
	if magic == 0x0b17c0de {
		if module.size < 20 || r.number(module.offset + 4, 4)! != 0 { return error('metallib: unsupported LLVM wrapper') }
		offset := r.number(module.offset + 8, 4)!
		size := r.number(module.offset + 12, 4)!
		if offset < 20 || offset % 4 != 0 || offset > module.size || size > module.size - offset {
			return error('metallib: LLVM wrapper exceeds module')
		}
		stream = Range{module.offset + offset, size}
	}
	if stream.size < 4 || stream.size % 4 != 0 || r.number(stream.offset, 4)! != 0xdec04342 {
		return error('metallib: missing LLVM IR signature or word alignment')
	}
	return stream
}

pub fn parse(data []u8) !Library {
	if data.len < 88 || data.len > max_library_size { return error('metallib: header or library size limit') }
	mut r := Reader{data: data}
	if r.number(0, 4)! != 0x424c544d || r.number(6, 2)! != 2 { return error('metallib: unsupported magic/version') }
	if r.number(16, 8)! != u64(data.len) { return error('metallib: file size mismatch') }
	mut table := r.section(24)!
	// Header function size excludes the initial u32 entry count.
	if table.size > u64(data.len) - 4 { return error('metallib: function list size overflow') }
	table = r.range(table.offset, table.size + 4)!
	public := r.section(40)!
	private := r.section(56)!
	bits := r.section(72)!
	mut spans := [Range{0, 88}]
	defer { unsafe { spans.free() } }
	spans.flags |= .noslices
	for section in [table, public, private, bits]! { if section.size != 0 { spans << section } }
	disjoint(mut spans)!
	count := r.number(table.offset, 4)!
	if count > max_functions || count > (table.size - 4) / 119 { return error('metallib: function count exceeds profile or table') }
	mut extension_end := u64(data.len)
	for section in [public, private, bits]! {
		if section.offset >= table.offset + table.size && section.offset < extension_end { extension_end = section.offset }
	}
	extension := Range{table.offset + table.size, extension_end - table.offset - table.size}
	if extension.size != 0 {
		spans << extension
		mut cursor := extension.offset
		mut ended := false
		for cursor < extension_end {
			item := r.tag(cursor, extension_end)!
			cursor = item.data.offset + item.data.size
			if item.name == 'ENDT' { ended = true; break }
			if item.name in ['HDYN', 'VLST', 'ILST', 'HSRD', 'HSRC', 'RLST', 'SLST']! {
				if item.data.size != 16 { return error('metallib: invalid extension range tag') }
				section := r.section(item.data.offset)!
				if section.size != 0 { spans << section }
			}
		}
		if !ended { return error('metallib: header extension lacks ENDT') }
	}
	disjoint(mut spans)!
	public_groups := r.metadata(public)!
	defer { unsafe { public_groups.free() } }
	private_groups := r.metadata(private)!
	defer { unsafe { private_groups.free() } }
	mut functions := []Function{cap: int(count)}
	mut modules := []Module{cap: int(count)}
	mut offsets := map[u64]int{}
	defer { unsafe { offsets.free() } }
	mut keep := false
	defer { if !keep { unsafe { functions.free(); modules.free() } } }
	mut cursor := table.offset + 4
	for _ in 0 .. int(count) {
		group := r.group(cursor, table.offset + table.size)!
		cursor = group.offset + group.size
		mut position := group.offset
		mut found := u32(0)
		mut name := ''
		mut kind := u8(0)
		mut versions := [4]u16{}
		mut offt := [3]u64{}
		mut size := u64(0)
		mut expected_hash := [32]u8{}
		mut ended := false
		for position < group.offset + group.size {
			item := r.tag(position, group.offset + group.size)!
			position = item.data.offset + item.data.size
			if item.name == 'ENDT' { ended = true; break }
			index := match item.name { 'NAME' { 0 } 'TYPE' { 1 } 'HASH' { 2 } 'OFFT' { 3 } 'VERS' { 4 } 'MDSZ' { 5 } else { -1 } }
			if index < 0 { continue }
			mask := u32(1) << u32(index)
			if found & mask != 0 { return error('metallib: duplicate function field') }
			found |= mask
			offset := item.data.offset
			length := item.data.size
			match item.name {
				'NAME' {
					if length < 2 || length > 4096 || data[int(offset + length - 1)] != 0 { return error('metallib: invalid function name') }
					name = unsafe { tos(&data[int(offset)], int(length - 1)) }
					if name.contains_u8(0) || !utf8.validate_str(name) { return error('metallib: invalid function name bytes') }
				}
				'TYPE' { if length != 1 || data[int(offset)] > 6 { return error('metallib: invalid function kind') }; kind = data[int(offset)] }
				'HASH' { if length != 32 { return error('metallib: invalid module hash size') }; for i in 0 .. 32 { expected_hash[i] = data[int(offset) + i] } }
				'OFFT' { if length != 24 { return error('metallib: invalid function offsets') }; for i in 0 .. 3 { offt[i] = r.number(offset + u64(i * 8), 8)! } }
				'VERS' { if length != 8 { return error('metallib: invalid AIR/MSL versions') }; for i in 0 .. 4 { versions[i] = u16(r.number(offset + u64(i * 2), 2)!) } }
				'MDSZ' { if length != 8 { return error('metallib: invalid module size field') }; size = r.number(offset, 8)! }
				else {}
			}
		}
		if !ended || found != 63 { return error('metallib: missing required function field or ENDT') }
		if (public.size != 0 && offt[0] !in public_groups) || (public.size == 0 && offt[0] != 0)
			|| (private.size != 0 && offt[1] !in private_groups) || (private.size == 0 && offt[1] != 0) {
			return error('metallib: function metadata offset is not a group boundary')
		}
		if offt[2] > bits.size || size > bits.size - offt[2] { return error('metallib: AIR module exceeds bitcode section') }
		archive := Range{bits.offset + offt[2], size}
		mut module_index := offsets[archive.offset] or { -1 }
		if module_index >= 0 {
			previous := modules[module_index]
			if previous.archive.size != size || previous.hash != expected_hash { return error('metallib: inconsistent shared AIR module') }
		} else {
			stream := r.llvm(archive)!
			module_index = modules.len
			offsets[archive.offset] = module_index
			modules << Module{archive, stream, expected_hash}
		}
		functions << Function{name, kind, versions, offt[0], offt[1], module_index}
	}
	if cursor != table.offset + table.size { return error('metallib: trailing function list data') }
	mut ordered := functions.clone()
	defer { unsafe { ordered.free() } }
	ordered.sort(a.name < b.name)
	for i in 1 .. ordered.len { if ordered[i - 1].name == ordered[i].name { return error('metallib: duplicate function name') } }
	mut module_ranges := modules.map(it.archive)
	defer { unsafe { module_ranges.free() } }
	disjoint(mut module_ranges)!
	// Validate disjoint extents before hashing: shared modules are hashed once,
	// and the total hashing work cannot exceed the bounded input size.
	mut hash := sha256.new()
	defer { unsafe { hash.free(); free(hash) } }
	mut digest := []u8{len: 32}
	defer { unsafe { digest.free() } }
	for item in modules {
		hash.reset()
		hash.write(data[int(item.archive.offset)..int(item.archive.offset + item.archive.size)])!
		hash.checksum_into(mut digest)
		for i in 0 .. 32 { if digest[i] != item.hash[i] { return error('metallib: AIR checksum mismatch') } }
	}
	keep = true
	return Library{platform: u16(r.number(4, 2)!), major: 2, minor: u16(r.number(8, 2)!),
		kind: data[10], target_os: data[11], os_major: u16(r.number(12, 2)!), os_minor: u16(r.number(14, 2)!),
		function_list: table, public_metadata: public, private_metadata: private, bitcode_section: bits,
		extension: extension, functions: functions, modules: modules}
}
