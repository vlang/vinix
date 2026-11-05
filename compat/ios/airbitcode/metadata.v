// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

const max_metadata_nodes = 262144
const max_metadata_edges = 1048576
const max_metadata_text = 4 * 1024 * 1024

pub enum IRMetadataKind { text value tuple opaque }
pub struct IRMetadataNode {
pub:
	kind IRMetadataKind
	text string // Owned; may contain embedded NULs.
	type_index int = -1
	value_number u64
	refs_start int
	refs_count int
	distinct bool
	record int = -1
}
pub struct IRNamedMetadata {
pub:
	name string // Owned.
	refs_start int
	refs_count int
}
pub struct IRMetadata {
pub:
	nodes []IRMetadataNode
	edges []int // Normalized metadata IDs; -1 is a nullable tuple operand.
	named []IRNamedMetadata
}
pub fn (md &IRMetadata) free() {
	unsafe {
		for node in md.nodes { node.text.free() }
		for name in md.named { name.name.free() }
		md.nodes.free(); md.edges.free(); md.named.free()
	}
}
struct MetadataBuilder {
mut:
	nodes []IRMetadataNode
	edges []int
	named []IRNamedMetadata
	text_bytes int
}
fn (b MetadataBuilder) index() IRMetadata { return IRMetadata{b.nodes, b.edges, b.named} }
fn (mut b MetadataBuilder) add(node IRMetadataNode) ! {
	if b.nodes.len >= max_metadata_nodes { return error('AIR metadata: node limit') }
	// Transfer the owned text without V's derived string clone on append.
	unsafe { b.nodes.push_many(&node, 1) }
}
fn (mut b MetadataBuilder) copy_text(values []u64) !string {
	if values.len > 65536 || values.len > max_metadata_text - b.text_bytes { return error('AIR metadata: text limit') }
	mut bytes := []u8{cap: values.len}
	defer { unsafe { bytes.free() } }
	for value in values {
		if value > 255 { return error('AIR metadata: non-byte string') }
		bytes << u8(value)
	}
	b.text_bytes += values.len
	return bytes.bytestr()
}
fn (mut b MetadataBuilder) references(values []u64, nullable bool) ! {
	if values.len > max_metadata_edges - b.edges.len { return error('AIR metadata: edge limit') }
	for value in values {
		if value > u64(max_metadata_nodes) || (!nullable && value == max_metadata_nodes) { return error('AIR metadata: reference limit') }
		b.edges << if nullable { int(value) - 1 } else { int(value) }
	}
}

// This profile indexes one module-level metadata block. Function-local metadata
// stays in Stream. Known debug/legacy nodes keep their slot as opaque records;
// their internal operands are not verified. Unknown allocating codes fail.
pub fn (ir IRModule) module_metadata(data []u8, stream Stream, pools IRConstantPools) !IRMetadata {
	mut block := -1
	for i, entry in stream.blocks {
		if entry.id == 15 && entry.parent >= 0 && stream.blocks[entry.parent].id == 8 {
			if block != -1 { return error('AIR metadata: multiple module metadata blocks') }
			block = i
		}
	}
	mut b := MetadataBuilder{}
	b.nodes.flags |= .noslices; b.edges.flags |= .noslices; b.named.flags |= .noslices
	mut keep := false
	defer { if !keep { b.index().free() } }
	mut pending := ''
	mut pending_name := false
	mut names := map[string]bool{}
	defer { unsafe { pending.free(); names.free() } }
	for index, record in stream.records {
		if record.block != block { continue }
		values := ir_values(stream, record)
		if pending_name && record.code != 10 { return error('AIR metadata: NAME must precede NAMED_NODE') }
		if record.code != 35 && record.has_blob { return error('AIR metadata: unexpected blob') }
		match record.code {
			35 {
				ranges := stream.metadata_strings(data, index)!
				defer { unsafe { ranges.free() } }
				if ranges.len > max_metadata_nodes - b.nodes.len { return error('AIR metadata: expanded string node limit') }
				for range in ranges {
					if range.size > 65536 || range.size > u64(max_metadata_text - b.text_bytes) { return error('AIR metadata: expanded text limit') }
					text := if range.size == 0 { '' } else { unsafe { tos(&data[int(range.offset)], int(range.size)) }.clone() }
					b.text_bytes += int(range.size)
					b.add(IRMetadataNode{kind: .text, text: text, record: index})!
				}
			}
			1 {
				if b.nodes.len >= max_metadata_nodes { return error('AIR metadata: node limit') }
				text := b.copy_text(values)!
				b.add(IRMetadataNode{kind: .text, text: text, record: index})!
			}
			2 {
				if values.len != 2 || values[0] >= u64(ir.types.len) || ir.types[int(values[0])].kind in [.void_t, .metadata_t] { return error('AIR metadata: VALUE type/operands') }
				value := pools.lookup(0, values[1])!
				if value.kind == .constant && value.type_index != int(values[0]) { return error('AIR metadata: VALUE constant type mismatch') }
				b.add(IRMetadataNode{kind: .value, type_index: int(values[0]), value_number: values[1], record: index})!
			}
			3, 5 {
				start := b.edges.len
				b.references(values, true)!
				b.add(IRMetadataNode{kind: .tuple, refs_start: start, refs_count: values.len, distinct: record.code == 5, record: index})!
			}
			4 {
				if b.named.len >= 65536 { return error('AIR metadata: named metadata limit') }
				pending = b.copy_text(values)!
				pending_name = true
				if pending.len == 0 || pending.contains_u8(0) || pending in names { return error('AIR metadata: empty/duplicate/invalid name') }
				names[pending] = true
			}
			10 {
				if !pending_name { return error('AIR metadata: NAMED_NODE without NAME') }
				start := b.edges.len
				b.references(values, false)!
				// Transfer the name, as for node strings, without a derived clone.
				named := IRNamedMetadata{pending, start, values.len}
				unsafe { b.named.push_many(&named, 1) }
				pending = ''; pending_name = false
			}
			6, 11, 36, 38, 39 {} // Non-allocating kind/attachment/index records remain opaque.
			7...9, 12...34, 37, 40, 41, 44...49 {
				b.add(IRMetadataNode{kind: .opaque, record: index})!
			}
			else { return error('AIR metadata: unsupported record code ${record.code}') }
		}
	}
	if pending_name { return error('AIR metadata: unconsumed NAME') }
	for reference in b.edges { if reference >= b.nodes.len { return error('AIR metadata: unresolved reference') } }
	for named in b.named {
		for reference in b.edges[named.refs_start..named.refs_start + named.refs_count] {
			if reference < 0 || b.nodes[reference].kind !in [.tuple, .opaque] { return error('AIR metadata: named operand requires metadata node') }
		}
	}
	keep = true
	return b.index()
}

pub fn (md IRMetadata) tuple(index int) ![]int {
	if index < 0 || index >= md.nodes.len || md.nodes[index].kind != .tuple { return error('AIR metadata: expected tuple') }
	node := md.nodes[index]
	return md.edges[node.refs_start..node.refs_start + node.refs_count]
}
pub fn (md IRMetadata) text(index int) !string {
	if index < 0 || index >= md.nodes.len || md.nodes[index].kind != .text { return error('AIR metadata: expected string') }
	return md.nodes[index].text
}
pub fn (md IRMetadata) integer(ir IRModule, pools IRConstantPools, index int) !u64 {
	if index < 0 || index >= md.nodes.len || md.nodes[index].kind != .value { return error('AIR metadata: expected integer value') }
	node := md.nodes[index]
	typ := ir.types[node.type_index]
	if typ.kind != .integer_t || typ.bits > 64 { return error('AIR metadata: expected integer of at most 64 bits') }
	value := pools.lookup(0, node.value_number)!
	if value.kind != .constant { return error('AIR metadata: integer must reference constant') }
	return pools.scalar_bits(value.constant_index)!
}
