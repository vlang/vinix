// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// LLVM bitstream decoding for extracted AIR. This validates encoding/framing,
// not LLVM IR semantics, AIR operations, or GPU capabilities.
// https://llvm.org/docs/BitCodeFormat.html#bitstream-format
pub const max_input_size = 32 * 1024 * 1024
const max_blocks = 65536
const max_records = 262144
const max_values = 4 * 1024 * 1024
const max_abbrevs = 65536
const max_ops = 262144
const max_refs = 262144

pub struct Blob {
pub:
	offset u64
	size u64
}

pub struct Block {
pub:
	id u64
	parent int // Index into blocks; -1 for the synthetic root (index 0).
	width int
	start_bit u64 // First payload bit, after the block length word.
	end_bit u64
}

pub struct Record {
pub:
	block int
	code u64
	values_start int
	values_count int
	has_blob bool
	blob Blob // Borrowed input bytes; blobs are not expanded into values.
}

pub struct Stream {
pub:
	blocks []Block
	records []Record
	values []u64
}

pub fn (stream &Stream) free() {
	unsafe { stream.blocks.free(); stream.records.free(); stream.values.free() }
}

struct Op {
	literal bool
	value u64
	encoding u8
	width int
}
struct Abbrev { start int; count int }
struct Link {
	abbrev int
mut:
	next int = -1
}

struct Reader {
	data []u8
mut:
	bit u64 = 32
	limit u64
	blocks []Block
	records []Record
	values []u64
	ops []Op
	abbrevs []Abbrev
	links []Link
	heads map[u64]int
	tails map[u64]int
	refs_charged int
}

fn (mut r Reader) bits(width int) !u64 {
	if width < 0 || width > 64 || r.bit > r.limit || u64(width) > r.limit - r.bit {
		return error('AIR bitstream: truncated or invalid fixed-width field')
	}
	mut value := u64(0)
	mut shift := 0
	for shift < width {
		remaining := 8 - int(r.bit & 7)
		take := if width - shift < remaining { width - shift } else { remaining }
		part := (u64(r.data[int(r.bit >> 3)]) >> u32(r.bit & 7)) & ((u64(1) << u32(take)) - 1)
		value |= part << u32(shift)
		r.bit += u64(take)
		shift += take
	}
	return value
}

fn (mut r Reader) vbr(width int) !u64 {
	if width < 2 || width > 32 { return error('AIR bitstream: invalid VBR width') }
	mut value := u64(0)
	mut shift := 0
	for {
		word := r.bits(width)!
		payload := word & ((u64(1) << u32(width - 1)) - 1)
		if shift >= 64 || payload > (~u64(0) >> u32(shift)) { return error('AIR bitstream: VBR overflow') }
		value |= payload << u32(shift)
		if word >> u32(width - 1) == 0 { return value }
		shift += width - 1
	}
	return value
}

fn (mut r Reader) align() ! {
	r.bits(int((32 - (r.bit & 31)) & 31))!
}

fn (mut r Reader) value(value u64) ! {
	if r.values.len >= max_values { return error('AIR bitstream: expanded operand limit') }
	r.values << value
}

fn (mut r Reader) scalar(op Op) !u64 {
	if op.literal { return op.value }
	return match op.encoding {
		1 { r.bits(op.width)! }
		2 { r.vbr(op.width)! }
		4 {
			index := r.bits(6)!
			u64('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._'[int(index)])
		}
		else { return error('AIR bitstream: non-scalar abbreviation operand') }
	}
}

fn (mut r Reader) definition() !int {
	count := r.vbr(5)!
	if count == 0 || count > 256 || r.abbrevs.len >= max_abbrevs || count > u64(max_ops - r.ops.len) {
		return error('AIR bitstream: abbreviation limit')
	}
	start := r.ops.len
	for _ in 0 .. int(count) {
		if r.bits(1)! != 0 {
			r.ops << Op{literal: true, value: r.vbr(8)!}
			continue
		}
		encoding := u8(r.bits(3)!)
		if encoding < 1 || encoding > 5 { return error('AIR bitstream: unknown operand encoding') }
		mut width := 0
		if encoding in [u8(1), 2]! {
			data := r.vbr(5)!
			if data == 0 { r.ops << Op{literal: true}; continue }
			if data > 64 || (encoding == 2 && (data < 2 || data > 32)) { return error('AIR bitstream: invalid abbreviation width') }
			width = int(data)
		}
		r.ops << Op{encoding: encoding, width: width}
	}
	for i in 0 .. int(count) {
		op := r.ops[start + i]
		if op.literal { continue }
		if op.encoding in [u8(3), 5]! && i == 0 { return error('AIR bitstream: non-scalar record code') }
		if op.encoding == 3 {
			if i != int(count) - 2 { return error('AIR bitstream: array must end an abbreviation') }
			element := r.ops[start + i + 1]
			if element.literal || element.encoding !in [u8(1), 2, 4]! { return error('AIR bitstream: invalid array element encoding') }
		}
		if op.encoding == 5 && i != int(count) - 1 { return error('AIR bitstream: blob must end an abbreviation') }
	}
	index := r.abbrevs.len
	r.abbrevs << Abbrev{start, int(count)}
	return index
}

fn (mut r Reader) charge_ref() ! {
	if r.refs_charged >= max_refs { return error('AIR bitstream: abbreviation reference work limit') }
	r.refs_charged++
}

fn (mut r Reader) inherit(id u64) ![]int {
	mut refs := []int{}
	refs.flags |= .noslices
	mut keep := false
	defer { if !keep { unsafe { refs.free() } } }
	mut link := r.heads[id] or { -1 }
	for link >= 0 {
		r.charge_ref()!
		refs << r.links[link].abbrev
		link = r.links[link].next
	}
	keep = true
	return refs
}

fn (mut r Reader) publish(id u64, abbrev int) ! {
	if r.links.len >= max_abbrevs { return error('AIR bitstream: block-info abbreviation limit') }
	index := r.links.len
	r.links << Link{abbrev: abbrev}
	if tail := r.tails[id] {
		mut link := r.links[tail]
		link.next = index
		r.links[tail] = link
	} else { r.heads[id] = index }
	r.tails[id] = index
}

fn (mut r Reader) record(block int, id u64, refs []int) !Record {
	if r.records.len >= max_records { return error('AIR bitstream: record limit') }
	start := r.values.len
	mut code := u64(0)
	mut has_blob := false
	mut blob := Blob{}
	if id == 3 {
		code = r.vbr(6)!
		count := r.vbr(6)!
		if count > u64(max_values - r.values.len) { return error('AIR bitstream: expanded operand limit') }
		for _ in 0 .. int(count) { r.value(r.vbr(6)!)! }
	} else {
		if id < 4 || id - 4 >= u64(refs.len) { return error('AIR bitstream: undefined abbreviation') }
		abbrev := r.abbrevs[refs[int(id - 4)]]
		code = r.scalar(r.ops[abbrev.start])!
		mut i := 1
		for i < abbrev.count {
			op := r.ops[abbrev.start + i]
			if !op.literal && op.encoding == 3 {
				count := r.vbr(6)!
				if count > u64(max_values - r.values.len) { return error('AIR bitstream: expanded operand limit') }
				element := r.ops[abbrev.start + i + 1]
				for _ in 0 .. int(count) { r.value(r.scalar(element)!)! }
				i += 2
			} else if !op.literal && op.encoding == 5 {
				size := r.vbr(6)!
				r.align()!
				if size > (r.limit - r.bit) / 8 { return error('AIR bitstream: blob exceeds block') }
				blob = Blob{r.bit / 8, size}
				has_blob = true
				r.bit += size * 8
				r.align()!
				i++
			} else {
				r.value(r.scalar(op)!)!
				i++
			}
		}
	}
	if code > 0xffffffff { return error('AIR bitstream: record code exceeds 32 bits') }
	result := Record{block, code, start, r.values.len - start, has_blob, blob}
	r.records << result
	return result
}

fn (mut r Reader) block(id u64, parent int, width int, end u64, depth int) ! {
	if depth > 64 || r.blocks.len >= max_blocks { return error('AIR bitstream: block/depth limit') }
	index := r.blocks.len
	r.blocks << Block{id, parent, width, r.bit, end}
	previous := r.limit
	r.limit = end
	defer { r.limit = previous }
	mut refs := if parent == -1 { []int{} } else { r.inherit(id)! }
	refs.flags |= .noslices
	defer { unsafe { refs.free() } }
	mut selected_id := ~u64(0)
	for r.bit < end {
		code := r.bits(width)!
		match code {
			0 {
				if parent == -1 { return error('AIR bitstream: root END_BLOCK') }
				r.align()!
				if r.bit != end { return error('AIR bitstream: premature END_BLOCK') }
				return
			}
			1 {
				child_id := r.vbr(8)!
				child_width := r.vbr(4)!
				if child_id > 0xffffffff || child_width == 0 || child_width > 32 { return error('AIR bitstream: invalid block id/code width') }
				r.align()!
				words := r.bits(32)!
				if words == 0 || words > (r.limit - r.bit) / 32 { return error('AIR bitstream: subblock exceeds parent') }
				r.block(child_id, index, int(child_width), r.bit + words * 32, depth + 1)!
			}
			2 {
				abbrev := r.definition()!
				if id == 0 && parent != -1 {
					if selected_id == ~u64(0) { return error('AIR bitstream: abbreviation before SETBID') }
					r.publish(selected_id, abbrev)!
				} else {
					r.charge_ref()!
					refs << abbrev
				}
			}
			else {
				record := r.record(index, code, refs)!
				if id == 0 && parent != -1 {
					if record.code == 1 {
						if record.has_blob || record.values_count != 1 || r.values[record.values_start] > 0xffffffff { return error('AIR bitstream: invalid SETBID') }
						selected_id = r.values[record.values_start]
					} else if selected_id == ~u64(0) { return error('AIR bitstream: block-info record before SETBID') }
				}
			}
		}
	}
	if parent != -1 { return error('AIR bitstream: missing END_BLOCK') }
}

// Input must be a raw LLVM IR stream (metallib.Module.bitcode). Blob references
// borrow those bytes. Only the three index arrays belong to the returned value.
pub fn parse(data []u8) !Stream {
	if data.len < 4 || data.len > max_input_size || data.len % 4 != 0
		|| data[0] != 0x42 || data[1] != 0x43 || data[2] != 0xc0 || data[3] != 0xde {
		return error('AIR bitstream: invalid LLVM stream signature or size')
	}
	mut r := Reader{data: data, limit: u64(data.len) * 8}
	r.blocks.flags |= .noslices
	r.records.flags |= .noslices
	r.values.flags |= .noslices
	r.ops.flags |= .noslices
	r.abbrevs.flags |= .noslices
	r.links.flags |= .noslices
	mut keep := false
	defer {
		unsafe { r.ops.free(); r.abbrevs.free(); r.links.free(); r.heads.free(); r.tails.free() }
		if !keep { unsafe { r.blocks.free(); r.records.free(); r.values.free() } }
	}
	r.block(~u64(0), -1, 2, u64(data.len) * 8, 0)!
	keep = true
	return Stream{r.blocks, r.records, r.values}
}

// LLVM METADATA_STRINGS records contain a VBR6 length table and concatenated
// string bytes. Return borrowed ranges, not owned strings. This narrow metadata
// decoder still does not validate LLVM references, types or AIR instructions.
pub fn (stream Stream) metadata_strings(data []u8, index int) ![]Blob {
	if index < 0 || index >= stream.records.len { return error('AIR metadata: record index') }
	record := stream.records[index]
	if stream.blocks[record.block].id != 15 || record.code != 35 || !record.has_blob || record.values_count != 2 {
		return error('AIR metadata: expected METADATA_STRINGS')
	}
	count := stream.values[record.values_start]
	offset := stream.values[record.values_start + 1]
	if count > max_records || record.blob.offset > u64(data.len)
		|| record.blob.size > u64(data.len) - record.blob.offset || offset > record.blob.size {
		return error('AIR metadata: string table extent or count')
	}
	mut reader := Reader{data: data, bit: record.blob.offset * 8, limit: (record.blob.offset + offset) * 8}
	mut ranges := []Blob{cap: int(count)}
	mut keep := false
	defer { if !keep { unsafe { ranges.free() } } }
	mut cursor := offset
	for _ in 0 .. int(count) {
		size := reader.vbr(6)!
		if size > record.blob.size - cursor { return error('AIR metadata: string exceeds blob') }
		ranges << Blob{record.blob.offset + cursor, size}
		cursor += size
	}
	if cursor != record.blob.size { return error('AIR metadata: trailing string bytes') }
	keep = true
	return ranges
}
