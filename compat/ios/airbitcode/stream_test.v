// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

struct Frame { length_byte int; payload_bit int; parent_width int }
struct Writer {
mut:
	data []u8
	bit int = 32
	width int = 2
	frames []Frame
}

fn writer() Writer {
	mut w := Writer{data: [u8(0x42), 0x43, 0xc0, 0xde]}
	w.data.flags |= .noslices
	w.frames.flags |= .noslices
	return w
}
fn (mut w Writer) free() { unsafe { w.data.free(); w.frames.free() } }
fn (mut w Writer) bits(width int, value u64) {
	for i in 0 .. width {
		if w.bit / 8 == w.data.len { w.data << u8(0) }
		w.data[w.bit / 8] |= u8((value >> u32(i)) & 1) << u8(w.bit % 8)
		w.bit++
	}
}
fn (mut w Writer) patch(bit int, width int, value u64) {
	for i in 0 .. width {
		mask := u8(1) << u8((bit + i) % 8)
		w.data[(bit + i) / 8] = (w.data[(bit + i) / 8] & ~mask) | (u8((value >> u32(i)) & 1) << u8((bit + i) % 8))
	}
}
fn (mut w Writer) vbr(width int, value u64) {
	mut rest := value
	for {
		word := rest & ((u64(1) << u32(width - 1)) - 1)
		rest >>= u32(width - 1)
		w.bits(width, word | if rest == 0 { u64(0) } else { u64(1) << u32(width - 1) })
		if rest == 0 { return }
	}
}
fn (mut w Writer) align() { w.bits((32 - w.bit % 32) % 32, 0) }
fn (mut w Writer) enter(id u64, width int) Frame {
	w.bits(w.width, 1); w.vbr(8, id); w.vbr(4, u64(width)); w.align()
	frame := Frame{w.bit / 8, w.bit + 32, w.width}
	w.bits(32, 0); w.frames << frame; w.width = width
	return frame
}
fn (mut w Writer) end() {
	w.bits(w.width, 0); w.align()
	frame := w.frames.pop()
	w.patch(frame.length_byte * 8, 32, u64((w.bit - frame.payload_bit) / 32))
	w.width = frame.parent_width
}
fn (mut w Writer) record(code u64, values []u64) {
	w.bits(w.width, 3); w.vbr(6, code); w.vbr(6, u64(values.len))
	for value in values { w.vbr(6, value) }
}
fn lit(value u64) Op { return Op{literal: true, value: value} }
fn enc(kind u8, width int) Op { return Op{encoding: kind, width: width} }
fn (mut w Writer) abbrev(ops []Op) {
	w.bits(w.width, 2); w.vbr(5, u64(ops.len))
	for op in ops {
		w.bits(1, u64(op.literal))
		if op.literal { w.vbr(8, op.value) } else {
			w.bits(3, op.encoding)
			if op.encoding in [u8(1), 2]! { w.vbr(5, u64(op.width)) }
		}
	}
}
fn (mut w Writer) blob(data []u8) {
	w.vbr(6, u64(data.len)); w.align()
	for byte in data { w.bits(8, byte) }
	w.align()
}
fn reject(data []u8) {
	if stream := parse(data) { stream.free(); assert false, 'accepted malformed bitstream' }
}

fn test_unabbreviated_fixed_vbr_char6_arrays_blobs_and_zero_width() {
	mut w := writer()
	defer { w.free() }
	w.enter(100, 4)
	w.record(1, [u64(0), 31, 32, ~u64(0)])
	w.abbrev([lit(10), enc(1, 0), enc(2, 6), enc(4, 0), enc(3, 0), enc(1, 8)])
	w.bits(4, 4); w.vbr(6, ~u64(0)); w.bits(6, 63); w.vbr(6, 3)
	for byte in [u64(1), 2, 255]! { w.bits(8, byte) }
	w.abbrev([lit(11), enc(5, 0)])
	w.bits(4, 5); w.blob([u8(0), 9, 10, 39, 92])
	w.abbrev([enc(1, 6), lit(99), enc(1, 64)])
	w.bits(4, 6); w.bits(6, 45); w.bits(64, ~u64(0))
	w.abbrev([lit(12), enc(2, 0)])
	w.bits(4, 7)
	w.abbrev([lit(13), enc(5, 0)])
	w.bits(4, 8); w.blob([]u8{})
	w.end()
	before := w.data.clone()
	stream := parse(w.data)!
	assert w.data == before && stream.blocks.len == 2 && stream.blocks[1].id == 100
	assert stream.records.len == 6
	assert stream.values == [u64(0), 31, 32, ~u64(0), 0, ~u64(0), 95, 1, 2, 255, 99, ~u64(0), 0]
	assert stream.records[1].code == 10 && stream.records[3].code == 45
	assert stream.records[5].has_blob && stream.records[5].blob.size == 0
	blob := stream.records[2].blob
	assert stream.records[2].has_blob && w.data[int(blob.offset)..int(blob.offset + blob.size)] == [u8(0), 9, 10, 39, 92]
	stream.free(); unsafe { before.free() }
	println('AIR-ENCODINGS: fixed/VBR64, literal/zero-width, Char6, arrays, borrowed blobs and immutable input PASS')
}

fn inherited(leak bool) []u8 {
	mut w := writer()
	w.enter(0, 2)
	w.record(1, [u64(100)])
	w.abbrev([lit(7), enc(3, 0), enc(4, 0)])
	w.record(1, [u64(101)])
	w.abbrev([lit(8), enc(1, 4)])
	w.end()
	w.enter(100, 3)
	w.bits(3, 4); w.vbr(6, 5)
	for value in [u64(0), 51, 61, 62, 63]! { w.bits(6, value) }
	w.abbrev([lit(9), lit(77)])
	w.bits(3, 5)
	w.enter(101, 3); w.bits(3, 4); w.bits(4, 13); w.end()
	w.bits(3, 4); w.vbr(6, 1); w.bits(6, 1)
	w.end()
	w.enter(100, 3)
	if leak { w.bits(3, 5) } else { w.bits(3, 4); w.vbr(6, 1); w.bits(6, 2) }
	w.end()
	unsafe { w.frames.free() }
	return w.data
}

fn test_blockinfo_inheritance_nested_restore_and_no_sibling_leaks() {
	data := inherited(false)
	stream := parse(data)!
	assert stream.blocks.len == 5 && stream.records.len == 7
	assert stream.values == [u64(100), 101, 97, 90, 57, 46, 95, 77, 13, 98, 99]
	assert stream.records[4].block == 3 && stream.records[4].code == 8
	assert stream.records[5].code == 7 && stream.records[6].code == 7
	stream.free(); unsafe { data.free() }
	bad := inherited(true); reject(bad); unsafe { bad.free() }
	println('AIR-SCOPES: BLOCKINFO inheritance, nested restoration and sibling isolation PASS')
}

fn test_invalid_abbreviations_framing_and_vbr_overflow() {
	for ops in [
		[]Op{}, [enc(u8(0), 0)], [enc(u8(1), 65)], [enc(u8(2), 1)], [enc(u8(2), 33)],
		[enc(u8(3), 0), enc(u8(1), 8)], [lit(1), enc(u8(3), 0)],
		[lit(1), enc(u8(3), 0), lit(0)], [lit(1), enc(u8(3), 0), enc(u8(5), 0)],
		[lit(1), enc(u8(5), 0), lit(0)], [lit(1), enc(u8(3), 0), enc(u8(1), 8), lit(0)]
	] {
		mut w := writer(); w.enter(100, 3); w.abbrev(ops); w.end(); reject(w.data); w.free()
	}
	for mode in ['undefined', 'overflow', 'early-end', 'missing-end', 'zero-words', 'long-words', 'zero-width', 'info-abbrev', 'info-record', 'info-id', 'oversized-code', 'deep', 'blob', 'operand-count'] {
		mut w := writer()
		frame := w.enter(if mode.starts_with('info') { u64(0) } else { u64(100) }, 3)
		match mode {
			'undefined' { w.bits(3, 7) }
			'overflow' { w.bits(3, 3); w.vbr(6, 1); w.vbr(6, 1); for _ in 0 .. 13 { w.bits(6, 63) } }
			'early-end' { w.bits(3, 0); w.align(); w.bits(32, 0) }
			'missing-end' { w.abbrev([lit(1)]); for _ in 0 .. 5 { w.bits(3, 4) } }
			'info-abbrev' { w.abbrev([lit(1)]) }
			'info-record' { w.record(2, [u64(1)]) }
			'info-id' { w.record(1, [u64(1), 2]) }
			'oversized-code' { w.record(0x100000000, []u64{}) }
			'deep' { for _ in 0 .. 65 { w.enter(100, 2) }; for _ in 0 .. 65 { w.end() } }
			'blob' { w.abbrev([lit(1), enc(5, 0)]); w.bits(3, 4); w.vbr(6, ~u64(0)) }
			'operand-count' { w.bits(3, 3); w.vbr(6, 1); w.vbr(6, max_values + 1) }
			else {}
		}
		w.end()
		if mode == 'missing-end' {
			// Definition and five records occupy exactly one word; remove END.
			for _ in 0 .. 4 { w.data.pop() }
			w.patch(frame.length_byte * 8, 32, 1)
		}
		if mode == 'zero-words' { w.patch(frame.length_byte * 8, 32, 0) }
		if mode == 'long-words' { w.patch(frame.length_byte * 8, 32, 0xffffffff) }
		if mode == 'zero-width' { w.patch(42, 4, 0) }
		reject(w.data); w.free()
	}
	println('AIR-REJECT: abbreviation grammar, scope, framing/depth, oversized lengths and VBR overflow PASS')
}

fn table(count u64, offset u64, lengths []u64, text []u8) []u8 {
	mut blob := Writer{bit: 0}
	blob.data.flags |= .noslices
	for size in lengths { blob.vbr(6, size) }
	blob.align()
	for byte in text { blob.bits(8, byte) }
	mut w := writer()
	w.enter(15, 3); w.abbrev([lit(35), enc(2, 6), enc(2, 6), enc(5, 0)])
	w.bits(3, 4); w.vbr(6, count); w.vbr(6, offset); w.blob(blob.data); w.end()
	blob.free(); unsafe { w.frames.free() }
	return w.data
}

fn test_metadata_strings_and_resource_limits() {
	data := table(3, 4, [u64(0), 3, 4], 'abcXYZ_'.bytes())
	stream := parse(data)!
	ranges := stream.metadata_strings(data, 0)!
	assert ranges.len == 3 && ranges[0].size == 0
	assert data[int(ranges[1].offset)..int(ranges[1].offset + ranges[1].size)] == 'abc'.bytes()
	assert data[int(ranges[2].offset)..int(ranges[2].offset + ranges[2].size)] == 'XYZ_'.bytes()
	unsafe { ranges.free() }; stream.free(); unsafe { data.free() }
	for mode in ['count', 'offset', 'length', 'trailing', 'truncated-vbr'] {
		bad := table(if mode == 'count' { u64(max_records + 1) } else { u64(1) },
			if mode == 'offset' { u64(99) } else if mode == 'truncated-vbr' { u64(0) } else { u64(4) },
			[u64(if mode == 'length' { 100 } else { 0 })], 'a'.bytes())
		s := parse(bad)!
		if result := s.metadata_strings(bad, 0) { unsafe { result.free() }; assert false }
		s.free(); unsafe { bad.free() }
	}
	mut reader := Reader{values: []u64{len: max_values}}
	if _ := reader.value(0) { assert false }
	unsafe { reader.values.free() }
	reader = Reader{records: []Record{len: max_records}}
	if _ := reader.record(0, 3, []int{}) { assert false }
	unsafe { reader.records.free() }
	reader = Reader{blocks: []Block{len: max_blocks}}
	if _ := reader.block(0, -1, 2, 0, 0) { assert false }
	unsafe { reader.blocks.free() }
	reader = Reader{refs_charged: max_refs}
	if _ := reader.charge_ref() { assert false }
	reader = Reader{data: [u8(2)], limit: 8, abbrevs: []Abbrev{len: max_abbrevs}}
	if _ := reader.definition() { assert false }
	unsafe { reader.data.free(); reader.abbrevs.free() }
	reader = Reader{data: [u8(2)], limit: 8, ops: []Op{len: max_ops}}
	if _ := reader.definition() { assert false }
	unsafe { reader.data.free(); reader.ops.free() }
	println('AIR-METADATA-LIMITS: borrowed string ranges, malformed tables and output/ref/block caps PASS')
}

fn test_truncations_and_mutations() {
	mut w := writer(); defer { w.free() }
	empty := parse(w.data)!
	assert empty.blocks.len == 1 && empty.records.len == 0 && empty.values.len == 0
	empty.free()
	w.enter(100, 3); w.abbrev([lit(7), enc(3, 0), enc(4, 0)])
	w.bits(3, 4); w.vbr(6, 3); w.bits(6, 0); w.bits(6, 1); w.bits(6, 2); w.end()
	for size in 0 .. w.data.len { if size != 4 { reject(w.data[..size]) } }
	for offset in 0 .. w.data.len {
		for bit in 0 .. 8 {
			w.data[offset] ^= u8(1) << u8(bit)
			before := w.data.clone()
			if stream := parse(w.data) {
				for block in stream.blocks { assert block.start_bit <= block.end_bit && block.end_bit <= u64(w.data.len * 8) }
				for record in stream.records {
					assert record.values_start + record.values_count <= stream.values.len
					if record.has_blob { assert record.blob.offset + record.blob.size <= u64(w.data.len) }
				}
				stream.free()
			}
			assert w.data == before
			unsafe { before.free() }
			w.data[offset] ^= u8(1) << u8(bit)
		}
	}
	println('AIR-MUTATIONS: ${w.data.len - 1} rejected prefixes (magic-only stream allowed), ${w.data.len * 8} bit mutations PASS')
}
