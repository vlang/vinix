// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

pub enum AIRStage { vertex fragment kernel }
pub enum AIRAccess { unspecified read write read_write sample }
pub struct AIRArgument {
pub:
	index u32
	type_index int
	node int
	kind string // Strings borrow IRMetadata, not the raw input.
	name string
	type_name string
	has_location bool
	location u32
	location_count u32
	has_address_space bool
	address_space u32
	has_size bool
	size u64
	has_alignment bool
	alignment u64
	has_buffer_size bool
	buffer_size u64
	struct_info int = -1 // Raw metadata tuple; structure layout is not interpreted.
	condition int = -1 // Function-constant predicate; never evaluated here.
	access AIRAccess
	unused bool
	opaque_attributes bool
}
pub struct AIREntry {
pub:
	stage AIRStage
	function int // Index into IRModule.functions; must be a definition.
	node int
	outputs_node int // Retained raw output tuple; output ABI is not lowered.
	arguments_start int
	arguments_count int
	opaque_attributes bool // Additional entry operands, e.g. tessellation metadata.
}
pub struct AIREntries {
pub:
	entries []AIREntry
	arguments []AIRArgument
}
pub fn (entries &AIREntries) free() { unsafe { entries.entries.free(); entries.arguments.free() } }

struct ArgumentBuilder {
mut:
	name string
	type_name string
	flags u32
	location u32
	location_count u32
	address_space u32
	size u64
	alignment u64
	buffer_size u64
	struct_info int = -1
	access AIRAccess
	unused bool
	opaque bool
}
fn (mut b ArgumentBuilder) field(flag u32) ! {
	if b.flags & flag != 0 { return error('AIR entry: duplicate argument property') }
	b.flags |= flag
}
fn (md IRMetadata) argument(ir IRModule, pools IRConstantPools, node int, arity int, signature IRType) !AIRArgument {
	refs := md.tuple(node)!
	if refs.len < 2 { return error('AIR entry: incomplete input argument') }
	index := md.integer(ir, pools, refs[0])!
	if index >= u64(arity) { return error('AIR entry: argument index') }
	mut kind := md.text(refs[1])!
	if !kind.starts_with('air.') { return error('AIR entry: argument semantic') }
	mut b := ArgumentBuilder{}
	mut i := 2
	mut condition := -1
	if kind == 'air.function_constant' {
		if refs.len < 4 { return error('AIR entry: incomplete conditional argument') }
		md.tuple(refs[2])!
		condition = refs[2]
		kind = md.text(refs[3])!
		if !kind.starts_with('air.') || kind == 'air.function_constant' { return error('AIR entry: conditional argument semantic') }
		b.opaque = true; i = 4
	}
	semantic_position := i
	for i < refs.len {
		if refs[i] < 0 || md.nodes[refs[i]].kind != .text { b.opaque = true; break }
		key := md.text(refs[i])!
		i++
		// Fragment linkage has a positional user-semantic string. Retain it in
		// the raw node; interpolation/linkage lowering is outside this profile.
		if kind == 'air.fragment_input' && i == semantic_position + 1 && !key.starts_with('air.') { b.opaque = true; continue }
		if key in ['air.center', 'air.centroid', 'air.no_perspective', 'air.perspective', 'air.flat'] { b.opaque = true; continue }
		flag := match key {
			'air.arg_name' { u32(1) } 'air.arg_type_name' { u32(2) } 'air.location_index' { u32(4) }
			'air.address_space' { u32(8) } 'air.arg_type_size' { u32(16) } 'air.arg_type_align_size' { u32(32) }
			'air.buffer_size' { u32(64) } 'air.struct_type_info' { u32(128) }
			'air.read', 'air.write', 'air.read_write', 'air.sample' { u32(256) }
			'air.arg_unused' { u32(512) }
			else { u32(0) }
		}
		if flag != 0 { b.field(flag)! }
		if key in ['air.read', 'air.write', 'air.read_write', 'air.sample'] {
			b.access = match key { 'air.read' { .read } 'air.write' { .write } 'air.read_write' { .read_write } else { .sample } }
			continue
		}
		if key == 'air.arg_unused' { b.unused = true; continue }
		if flag == 0 {
			// Preserve the entire remaining tail without guessing unknown arities.
			b.opaque = true
			break
		}
		if i >= refs.len { return error('AIR entry: missing argument property value') }
		match key {
			'air.arg_name' { b.name = md.text(refs[i])! }
			'air.arg_type_name' { b.type_name = md.text(refs[i])! }
			'air.struct_type_info' { md.tuple(refs[i])!; b.struct_info = refs[i]; b.opaque = true }
			'air.location_index' {
				if i + 1 >= refs.len { return error('AIR entry: incomplete location range') }
				location := md.integer(ir, pools, refs[i])!
				count := md.integer(ir, pools, refs[i + 1])!
				if location > 0xffffffff || count == 0 || count > 0xffffffff || location + count > 0x100000000 { return error('AIR entry: location range') }
				b.location = u32(location); b.location_count = u32(count); i++
			}
			'air.address_space' {
				space := md.integer(ir, pools, refs[i])!
				if space > 0xffffff { return error('AIR entry: address space') }
				b.address_space = u32(space)
			}
			'air.arg_type_size' { b.size = md.integer(ir, pools, refs[i])! }
			'air.buffer_size' { b.buffer_size = md.integer(ir, pools, refs[i])! }
			'air.arg_type_align_size' {
				alignment := md.integer(ir, pools, refs[i])!
				if alignment == 0 || alignment & (alignment - 1) != 0 { return error('AIR entry: alignment') }
				b.alignment = alignment
			}
			else {}
		}
		i++
	}
	type_index := ir.references[signature.refs_start + 1 + int(index)]
	if b.flags & 8 != 0 && (ir.types[type_index].kind != .pointer_t || ir.types[type_index].address_space != b.address_space) { return error('AIR entry: argument address space/type mismatch') }
	return AIRArgument{u32(index), type_index, node, kind,
		b.name, b.type_name, b.flags & 4 != 0, b.location, b.location_count, b.flags & 8 != 0,
		b.address_space, b.flags & 16 != 0, b.size, b.flags & 32 != 0, b.alignment,
		b.flags & 64 != 0, b.buffer_size, b.struct_info, condition, b.access, b.unused, b.opaque}
}

// Reflect only the classic air.vertex/fragment/kernel profile. Other named roots
// remain in IRMetadata and do not advertise support for additional shader stages.
pub fn (md IRMetadata) air_entries(ir IRModule, pools IRConstantPools) !AIREntries {
	mut functions := map[int]int{}
	defer { unsafe { functions.free() } }
	for i, function in ir.functions { functions[function.record] = i }
	mut seen := []bool{len: ir.functions.len}
	defer { unsafe { seen.free() } }
	mut entries := []AIREntry{}
	mut params := []AIRArgument{}
	entries.flags |= .noslices; params.flags |= .noslices
	mut keep := false
	defer { if !keep { unsafe { entries.free(); params.free() } } }
	for named in md.named {
		if named.name !in ['air.vertex', 'air.fragment', 'air.kernel'] { continue }
		stage := match named.name { 'air.vertex' { AIRStage.vertex } 'air.fragment' { .fragment } else { .kernel } }
		for node in md.edges[named.refs_start..named.refs_start + named.refs_count] {
			refs := md.tuple(node)!
			if refs.len < 3 || refs[0] < 0 || md.nodes[refs[0]].kind != .value { return error('AIR entry: expected function/output/input tuple') }
			value_node := md.nodes[refs[0]]
			value := pools.lookup(0, value_node.value_number)!
			if value.kind != .declaration { return error('AIR entry: function must reference declaration') }
			function_index := functions[value.record] or { return error('AIR entry: value is not a function') }
			function := ir.functions[function_index]
			if function.declaration || seen[function_index] { return error('AIR entry: duplicate entry or missing body') }
			seen[function_index] = true
			pointer := ir.types[value_node.type_index]
			if pointer.kind != .pointer_t || (pointer.refs_count == 1 && ir.references[pointer.refs_start] != function.signature) { return error('AIR entry: function pointer type') }
			signature := ir.types[function.signature]
			if signature.vararg { return error('AIR entry: variadic shader signature') }
			outputs := md.tuple(refs[1])!
			if stage == .kernel && (outputs.len != 0 || ir.types[ir.references[signature.refs_start]].kind != .void_t) { return error('AIR entry: kernel output/return type') }
			for output in outputs {
				fields := md.tuple(output)!
				if fields.len == 0 { return error('AIR entry: empty output') }
				md.text(fields[0])!
			}
			inputs := md.tuple(refs[2])!
			arity := signature.refs_count - 1
			if inputs.len != arity || inputs.len > max_ir_refs - params.len { return error('AIR entry: input arity/expansion limit') }
			mut used := []bool{len: arity}
			defer { unsafe { used.free() } }
			start := params.len
			for input in inputs {
				argument := md.argument(ir, pools, input, arity, signature)!
				if used[int(argument.index)] { return error('AIR entry: duplicate input index') }
				used[int(argument.index)] = true
				// Strings borrow IRMetadata; prevent an implicit deep clone here.
				unsafe { params.push_many(&argument, 1) }
			}
			entries << AIREntry{stage, function_index, node, refs[1], start, inputs.len, refs.len > 3}
		}
	}
	keep = true
	return AIREntries{entries, params}
}
