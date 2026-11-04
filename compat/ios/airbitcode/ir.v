// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// A bounded type/signature index, not an LLVM IR verifier or AIR interpreter.
const max_ir_types = 65536
const max_ir_refs = 262144
const max_ir_functions = 65536
const max_ir_text = 4 * 1024 * 1024

pub enum IRKind {
	void_t
	float_t
	double_t
	label_t
	opaque_t
	integer_t
	pointer_t
	half_t
	array_t
	vector_t
	x86_fp80_t
	fp128_t
	ppc_fp128_t
	metadata_t
	x86_mmx_t
	struct_t
	function_t
	token_t
	bfloat_t
	x86_amx_t
}

pub struct IRType {
pub:
	kind IRKind
	name string // Owned; only identified structs have names.
	bits u32
	count u64
	address_space u32
	packed bool
	vararg bool
	scalable bool
	refs_start int
	refs_count int // Function refs: return type followed by parameter types.
	record int
}

pub struct IRFunction {
pub:
	name string // Borrows the raw input's STRTAB bytes.
	signature int // Index into IRModule.types (always function_t).
	calling_convention u32
	linkage u32 // Encoded value; other function attributes remain opaque.
	declaration bool
	record int
	body_block int = -1 // Index into the source Stream.blocks, or -1.
	basic_blocks u32
}

pub struct IRModule {
pub:
	triple string
	data_layout string
	source_filename string
	types []IRType
	references []int
	functions []IRFunction
}

struct IRBuilder {
mut:
	triple string
	data_layout string
	source_filename string
	types []IRType
	references []int
	functions []IRFunction
}

fn (ir IRBuilder) index() IRModule {
	return IRModule{ir.triple, ir.data_layout, ir.source_filename, ir.types, ir.references, ir.functions}
}

pub fn (ir &IRModule) free() {
	unsafe {
		ir.triple.free(); ir.data_layout.free(); ir.source_filename.free()
		for typ in ir.types { typ.name.free() }
		ir.types.free(); ir.references.free(); ir.functions.free()
	}
}

fn ir_text(values []u64, budget int) !string {
	if values.len > 65536 || values.len > max_ir_text - budget { return error('AIR IR: text limit') }
	mut bytes := []u8{cap: values.len}
	defer { unsafe { bytes.free() } }
	for value in values {
		if value == 0 || value > 255 { return error('AIR IR: invalid text byte') }
		bytes << u8(value)
	}
	return bytes.bytestr()
}

fn ir_values(stream Stream, record Record) []u64 {
	return stream.values[record.values_start..record.values_start + record.values_count]
}

fn ir_type(record Record, values []u64, name string, start int, index int) !IRType {
	mut kind := IRKind.void_t
	mut bits := u32(0)
	mut count := u64(0)
	mut space := u32(0)
	mut packed := false
	mut vararg := false
	mut scalable := false
	mut refs := 0
	match record.code {
		2, 3, 4, 5, 10, 13, 14, 15, 16, 17, 22, 23, 24 {
			if values.len != 0 { return error('AIR IR: scalar type operands') }
			kind = match record.code {
				2 { .void_t } 3 { .float_t } 4 { .double_t } 5 { .label_t }
				10 { .half_t } 13 { .x86_fp80_t } 14 { .fp128_t } 15 { .ppc_fp128_t }
				16 { .metadata_t } 17 { .x86_mmx_t } 22 { .token_t } 23 { .bfloat_t }
				else { .x86_amx_t }
			}
		}
		6 {
			if values.len != 1 || values[0] != 0 || name.len == 0 { return error('AIR IR: opaque identified struct') }
			kind = .opaque_t
		}
		7 {
			if values.len != 1 || values[0] == 0 || values[0] > 1 << 23 { return error('AIR IR: integer width') }
			kind = .integer_t; bits = u32(values[0])
		}
		8 {
			if values.len < 1 || values.len > 2 || (values.len == 2 && values[1] > 0xffffff) { return error('AIR IR: typed pointer operands') }
			kind = .pointer_t; refs = 1
			if values.len == 2 { space = u32(values[1]) }
		}
		25 {
			if values.len != 1 || values[0] > 0xffffff { return error('AIR IR: opaque pointer address space') }
			kind = .pointer_t; space = u32(values[0])
		}
		11, 12 {
			if values.len < 2 || values.len > (if record.code == 12 { 3 } else { 2 }) { return error('AIR IR: aggregate operands') }
			kind = if record.code == 11 { .array_t } else { .vector_t }
			count = values[0]; refs = 1
			if record.code == 12 {
				if count == 0 || count > 0xffffffff || (values.len == 3 && values[2] > 1) { return error('AIR IR: vector length/scalability') }
				scalable = values.len == 3 && values[2] != 0
			}
		}
		18, 20 {
			if values.len < 1 || values[0] > 1 || (record.code == 20 && name.len == 0) { return error('AIR IR: struct operands/name') }
			kind = .struct_t; packed = values[0] != 0; refs = values.len - 1
		}
		21 {
			if values.len < 2 || values[0] > 1 { return error('AIR IR: function type operands') }
			kind = .function_t; vararg = values[0] != 0; refs = values.len - 1
		}
		else { return error('AIR IR: unsupported type record ${record.code}') }
	}
	return IRType{kind, name, bits, count, space, packed, vararg, scalable, start, refs, index}
}

fn ir_validate_types(types []IRType, refs []int) ! {
	for i, typ in types {
		for j, target in refs[typ.refs_start..typ.refs_start + typ.refs_count] {
			if target < 0 || target >= types.len { return error('AIR IR: invalid type reference') }
			child := types[target]
			if target >= i && (child.kind !in [.struct_t, .opaque_t] || child.name.len == 0) { return error('AIR IR: forward reference requires identified struct') }
			match typ.kind {
				.pointer_t {
					if child.kind in [.void_t, .label_t, .metadata_t, .token_t, .x86_amx_t] { return error('AIR IR: invalid pointer element') }
				}
				.vector_t {
					if child.kind !in [.integer_t, .pointer_t, .half_t, .bfloat_t, .float_t, .double_t, .x86_fp80_t, .fp128_t, .ppc_fp128_t] { return error('AIR IR: invalid vector element') }
				}
				.array_t, .struct_t {
					if child.kind in [.void_t, .label_t, .metadata_t, .function_t, .token_t, .x86_amx_t] { return error('AIR IR: invalid aggregate element') }
				}
				.function_t {
					if child.kind in [.function_t, .label_t] || (j == 0 && child.kind == .metadata_t) || (j > 0 && child.kind == .void_t) { return error('AIR IR: invalid return/argument type') }
				}
				else {}
			}
		}
	}
}

// Use only with a Stream returned by parse(data), and the same immutable input.
// This supports module version 2 names and a strict subset of LLVM type records.
// Instruction operands, constants, metadata references and attributes are not
// verified. The caller owns both this index and the original Stream separately.
pub fn (stream Stream) ir_module(data []u8) !IRModule {
	mut module_block := -1
	mut type_block := -1
	mut strtab_block := -1
	mut bodies := []int{}
	bodies.flags |= .noslices
	defer { unsafe { bodies.free() } }
	for i, block in stream.blocks {
		if block.id == 8 {
			if module_block != -1 || block.parent != 0 { return error('AIR IR: expected one top-level module') }
			module_block = i
		}
	}
	if module_block == -1 { return error('AIR IR: missing module') }
	for i, block in stream.blocks {
		if block.id == 17 {
			if type_block != -1 || block.parent != module_block { return error('AIR IR: type table scope/count') }
			type_block = i
		}
		if block.id == 23 {
			if strtab_block != -1 || block.parent != 0 { return error('AIR IR: string table scope/count') }
			strtab_block = i
		}
		if block.id == 12 && block.parent == module_block { bodies << i }
	}
	if type_block == -1 { return error('AIR IR: missing type table') }
	mut version := -1
	mut strtab := Blob{}
	mut strtab_seen := false
	mut ir := IRBuilder{}
	ir.types.flags |= .noslices
	ir.references.flags |= .noslices
	ir.functions.flags |= .noslices
	mut keep := false
	defer { if !keep { ir.index().free() } }
	mut budget := 0
	mut headers := u8(0)
	for record in stream.records {
		values := ir_values(stream, record)
		if record.block == strtab_block {
			if strtab_seen || record.code != 1 || !record.has_blob || values.len != 0 { return error('AIR IR: string table record') }
			strtab = record.blob; strtab_seen = true
			if strtab.offset > u64(data.len) || strtab.size > u64(data.len) - strtab.offset { return error('AIR IR: string table extent') }
		}
		if record.block != module_block { continue }
		if record.has_blob { return error('AIR IR: unexpected module blob') }
		if record.code == 1 {
			if version != -1 || values.len != 1 || values[0] != 2 { return error('AIR IR: unsupported/duplicate module version') }
			version = 2
		}
		if record.code in [u64(2), 3, 16]! {
			flag := if record.code == 2 { u8(1) } else if record.code == 3 { u8(2) } else { u8(4) }
			if headers & flag != 0 { return error('AIR IR: duplicate module text') }
			headers |= flag
			text := ir_text(values, budget)!
			budget += values.len
			match record.code {
				2 { ir.triple = text } 3 { ir.data_layout = text } else { ir.source_filename = text }
			}
		}
	}
	if version != 2 { return error('AIR IR: missing module version') }
	mut declared := -1
	mut pending := ''
	mut names := map[string]bool{}
	defer { unsafe { pending.free(); names.free() } }
	for index, record in stream.records {
		if record.block != type_block { continue }
		if record.has_blob { return error('AIR IR: unexpected type blob') }
		values := ir_values(stream, record)
		if record.code == 1 {
			if declared != -1 || values.len != 1 || values[0] > max_ir_types { return error('AIR IR: type count limit/record') }
			declared = int(values[0]); continue
		}
		if declared == -1 { return error('AIR IR: type before NUMENTRY') }
		if record.code == 19 {
			if pending.len != 0 { return error('AIR IR: unconsumed struct name') }
			pending = ir_text(values, budget)!
			budget += values.len
			if pending.len == 0 || pending in names { return error('AIR IR: empty/duplicate struct name') }
			names[pending] = true
			continue
		}
		if pending.len != 0 && record.code !in [u64(6), 20]! { return error('AIR IR: struct name scope') }
		if ir.types.len >= declared { return error('AIR IR: extra type') }
		typ := ir_type(record, values, pending, ir.references.len, index)!
		if typ.refs_count > max_ir_refs - ir.references.len { return error('AIR IR: type reference limit') }
		ref_values := if record.code == 8 { values[..1] } else if typ.refs_count > 0 { values[1..1 + typ.refs_count] } else { []u64{} }
		for value in ref_values {
			if value >= u64(declared) { return error('AIR IR: invalid type reference') }
			ir.references << int(value)
		}
		ir.types << typ
		pending = '' // Name ownership transferred into types.
	}
	if declared == -1 || ir.types.len != declared || pending.len != 0 { return error('AIR IR: incomplete type table') }
	ir_validate_types(ir.types, ir.references)!
	mut body_counts := []u32{len: stream.blocks.len}
	defer { unsafe { body_counts.free() } }
	for record in stream.records {
		block := stream.blocks[record.block]
		if block.id != 12 || block.parent != module_block { continue }
		if record.code == 1 || body_counts[record.block] == 0 {
			values := ir_values(stream, record)
			if record.has_blob || record.code != 1 || body_counts[record.block] != 0 || values.len != 1 || values[0] == 0 || values[0] > 65536 { return error('AIR IR: function DECLAREBLOCKS') }
			body_counts[record.block] = u32(values[0])
		}
	}
	mut body_cursor := 0
	mut function_names := map[string]bool{}
	defer { unsafe { function_names.free() } }
	for index, record in stream.records {
		if record.block != module_block || record.code != 8 { continue }
		values := ir_values(stream, record)
		if ir.functions.len >= max_ir_functions || values.len < 10 || !strtab_seen { return error('AIR IR: function record/limit') }
		offset := values[0]; size := values[1]
		if size == 0 || size > 4096 || offset > strtab.size || size > strtab.size - offset || size > u64(max_ir_text - budget) { return error('AIR IR: function name extent/limit') }
		budget += int(size)
		name := unsafe { tos(&data[int(strtab.offset + offset)], int(size)) }
		if name.contains_u8(0) || name in function_names { return error('AIR IR: invalid/duplicate function name') }
		function_names[name] = true
		if values[2] >= u64(ir.types.len) || values[3] > 1023 || values[4] > 1 || values[5] > 0xffffffff { return error('AIR IR: function type/convention/declaration') }
		mut signature := int(values[2])
		typ := ir.types[signature]
		if typ.kind == .pointer_t && typ.refs_count == 1 { signature = ir.references[typ.refs_start] }
		if ir.types[signature].kind != .function_t { return error('AIR IR: function requires function type') }
		mut body := -1
		mut count := u32(0)
		if values[4] == 0 {
			if body_cursor >= bodies.len { return error('AIR IR: missing function body') }
			body = bodies[body_cursor]; body_cursor++
			count = body_counts[body]
			if count == 0 { return error('AIR IR: missing DECLAREBLOCKS') }
		}
		ir.functions << IRFunction{name, signature, u32(values[3]), u32(values[5]), values[4] != 0, index, body, count}
	}
	if body_cursor != bodies.len { return error('AIR IR: unclaimed function body') }
	keep = true
	return ir.index()
}
