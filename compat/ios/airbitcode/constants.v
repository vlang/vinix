// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

const max_constant_words = 4 * 1024 * 1024
const max_constants = 262144
const max_declarations = 262144

pub enum IRConstantKind {
	zero
	undef
	poison
	integer
	floating
	data
	string_data
	aggregate
	opaque // Encoded expression/inline assembly, not evaluated or executable.
}
pub struct IRConstant {
pub:
	kind IRConstantKind
	type_index int
	scope int // 0 = module; function index + 1 otherwise.
	number u32 // LLVM value ID within that scope.
	record int // Raw encoded operands remain in the source Stream.
	bits u32 // Scalar/lane width; 0 for aggregates and non-numeric types.
	splat bool
	words_start int
	words_count int // Integers: little-endian limbs. DATA/strings: element bits.
}
pub struct IRConstantScope {
pub:
	function int = -1
	body_block int = -1
	active bool
	arguments_start int
	arguments_count int
	first int
	count int
	base_id u32 // First constant ID, after declarations/module constants/args.
}
pub enum IRValueKind { declaration argument constant }
pub struct IRValue {
pub:
	kind IRValueKind
	record int = -1 // A declaration's raw MODULE record; schema remains opaque.
	type_index int = -1 // Available for arguments/constants, not declarations.
	constant_index int = -1
}
pub struct IRConstantPools {
pub:
	declarations []int
	scopes []IRConstantScope
	arguments []int
	constants []IRConstant
	words []u64
	module_values u32
}
pub fn (pools &IRConstantPools) free() {
	unsafe { pools.declarations.free(); pools.scopes.free(); pools.arguments.free(); pools.constants.free(); pools.words.free() }
}

pub fn (pools IRConstantPools) lookup(scope int, number u64) !IRValue {
	if scope < 0 || scope >= pools.scopes.len || !pools.scopes[scope].active { return error('AIR constants: invalid value scope') }
	if number < u64(pools.declarations.len) { return IRValue{kind: .declaration, record: pools.declarations[int(number)]} }
	if number < pools.module_values {
		index := int(number) - pools.declarations.len
		return IRValue{kind: .constant, record: pools.constants[index].record, type_index: pools.constants[index].type_index, constant_index: index}
	}
	if scope == 0 { return error('AIR constants: module value ID out of range') }
	entry := pools.scopes[scope]
	if number < entry.base_id {
		return IRValue{kind: .argument, type_index: pools.arguments[entry.arguments_start + int(number - pools.module_values)]}
	}
	if number - entry.base_id >= u64(entry.count) { return error('AIR constants: local value ID out of range (instruction values are not indexed)') }
	index := entry.first + int(number - entry.base_id)
	return IRValue{kind: .constant, record: pools.constants[index].record, type_index: pools.constants[index].type_index, constant_index: index}
}

pub fn (pools IRConstantPools) scalar_bits(index int) !u64 {
	if index < 0 || index >= pools.constants.len { return error('AIR constants: constant index') }
	constant := pools.constants[index]
	if constant.bits == 0 || constant.bits > 64 { return error('AIR constants: not a scalar/lane of at most 64 bits') }
	if constant.kind == .zero { return 0 }
	if constant.kind !in [.integer, .floating] || constant.words_count != 1 { return error('AIR constants: value has no materialized scalar bits') }
	return pools.words[constant.words_start]
}

struct ConstantBuilder {
mut:
	constants []IRConstant
	words []u64
}
fn (mut b ConstantBuilder) word(word u64) ! {
	if b.words.len >= max_constant_words { return error('AIR constants: expanded word limit') }
	b.words << word
}
fn constant_unrotate(encoded u64) u64 {
	if encoded & 1 == 0 { return encoded >> 1 }
	if encoded == 1 { return u64(1) << 63 }
	return u64(0) - (encoded >> 1)
}
fn constant_mask(bits u32) u64 {
	return if bits >= 64 { ~u64(0) } else { (u64(1) << bits) - 1 }
}
fn constant_width(typ IRType) u32 {
	return match typ.kind {
		.integer_t { typ.bits } .half_t, .bfloat_t { 16 } .float_t { 32 }
		.double_t { 64 } .x86_fp80_t { 80 } .fp128_t, .ppc_fp128_t { 128 }
		else { 0 }
	}
}
fn (mut b ConstantBuilder) literal(ir IRModule, record Record, values []u64, typ_index int, scope int, number u32, index int) ! {
	if b.constants.len >= max_constants { return error('AIR constants: constant count limit') }
	typ := ir.types[typ_index]
	if typ.kind in [.void_t, .label_t, .metadata_t, .function_t, .token_t, .opaque_t, .x86_amx_t] { return error('AIR constants: unsupported constant type') }
	splat := typ.kind == .vector_t
	scalar := if splat { ir.types[ir.references[typ.refs_start]] } else { typ }
	bits := constant_width(scalar)
	start := b.words.len
	mut kind := IRConstantKind.opaque
	match record.code {
		2, 3, 26 {
			if values.len != 0 { return error('AIR constants: zero/undef/poison operands') }
			kind = if record.code == 2 { .zero } else if record.code == 3 { .undef } else { .poison }
		}
		4, 5 {
			if scalar.kind != .integer_t || values.len == 0 { return error('AIR constants: integer type/operands') }
			kind = .integer
			count := int((u64(bits) + 63) / 64)
			if record.code == 4 && (values.len != 1 || bits > 64) { return error('AIR constants: scalar integer encoding width') }
			if values.len > count || count > max_constant_words - b.words.len { return error('AIR constants: integer limb count/expansion') }
			for i in 0 .. count {
				word := if i < values.len { constant_unrotate(values[i]) } else { u64(0) }
				b.word(if i == count - 1 && bits % 64 != 0 { word & constant_mask(bits % 64) } else { word })!
			}
		}
		6 {
			if scalar.kind !in [.half_t, .bfloat_t, .float_t, .double_t, .x86_fp80_t, .fp128_t, .ppc_fp128_t] || values.len != (if bits > 64 { 2 } else { 1 }) { return error('AIR constants: float type/operands') }
			kind = .floating
			if scalar.kind == .x86_fp80_t {
				b.word((values[0] << 16) | (values[1] & 0xffff))!
				b.word(values[0] >> 48)!
			} else {
				for word in values { b.word(word & constant_mask(bits))! }
			}
		}
		7 {
			if values.len == 0 || typ.kind !in [.array_t, .vector_t, .struct_t] || typ.scalable { return error('AIR constants: aggregate type/operands') }
			count := if typ.kind == .struct_t { u64(typ.refs_count) } else { typ.count }
			if u64(values.len) != count { return error('AIR constants: aggregate element count') }
			kind = .aggregate
		}
		8, 9 {
			if typ.kind != .array_t || values.len == 0 { return error('AIR constants: string type/operands') }
			element := ir.types[ir.references[typ.refs_start]]
			terminated := record.code == 9
			if element.kind != .integer_t || element.bits != 8 || u64(values.len) + u64(terminated) != typ.count { return error('AIR constants: string element type/count') }
			kind = .string_data
			for word in values {
				if word > 255 { return error('AIR constants: string byte') }
				b.word(word)!
			}
			if terminated { b.word(0)! }
		}
		22 {
			if values.len == 0 || typ.kind !in [.array_t, .vector_t] || typ.scalable || u64(values.len) != typ.count { return error('AIR constants: data element count/type') }
			element := ir.types[ir.references[typ.refs_start]]
			width := constant_width(element)
			if (element.kind == .integer_t && width !in [u32(8), 16, 32, 64]!) || element.kind !in [.integer_t, .half_t, .bfloat_t, .float_t, .double_t] { return error('AIR constants: data element encoding') }
			kind = .data
			for word in values { b.word(word & constant_mask(width))! }
		}
		10...21, 23...25, 27...34 {
			// Known value-producing records. Keep the complete raw record and an
			// explicit opaque tag; neither operands nor expressions are evaluated.
			if values.len == 0 { return error('AIR constants: empty opaque expression') }
		}
		else { return error('AIR constants: unsupported constant code ${record.code}') }
	}
	b.constants << IRConstant{kind, typ_index, scope, number, index, bits, splat && kind in [.integer, .floating], start, b.words.len - start}
}

// Requires this IRModule and Stream to originate from the same immutable input.
// Index declarations, arguments and constant IDs; instruction-result IDs and
// global declaration schemas are not interpreted. Known expressions stay opaque.
pub fn (ir IRModule) constant_pools(stream Stream) !IRConstantPools {
	mut module_block := -1
	for i, block in stream.blocks { if block.id == 8 && block.parent == 0 { module_block = i; break } }
	if module_block == -1 { return error('AIR constants: missing module') }
	mut declarations := []int{}
	declarations.flags |= .noslices
	mut scopes := []IRConstantScope{len: ir.functions.len + 1}
	mut parameter_types := []int{}
	parameter_types.flags |= .noslices
	mut b := ConstantBuilder{}
	b.constants.flags |= .noslices; b.words.flags |= .noslices
	mut keep := false
	defer { if !keep { unsafe { declarations.free(); scopes.free(); parameter_types.free(); b.constants.free(); b.words.free() } } }
	mut block_scopes := []int{len: stream.blocks.len, init: -1}
	mut constant_blocks := []int{len: scopes.len, init: -1}
	mut first_instruction := []int{len: scopes.len, init: stream.records.len}
	mut heads := []int{len: scopes.len, init: -1}
	mut tails := []int{len: scopes.len, init: -1}
	mut next := []int{len: stream.records.len, init: -1}
	defer { unsafe { block_scopes.free(); constant_blocks.free(); first_instruction.free(); heads.free(); tails.free(); next.free() } }
	block_scopes[module_block] = 0
	for i, function in ir.functions {
		if function.declaration { continue }
		block_scopes[function.body_block] = i + 1
		typ := ir.types[function.signature]
		if typ.refs_count - 1 > max_ir_refs - parameter_types.len { return error('AIR constants: argument index limit') }
		scopes[i + 1] = IRConstantScope{function: i, body_block: function.body_block, active: true, arguments_start: parameter_types.len, arguments_count: typ.refs_count - 1}
		for j in 1 .. typ.refs_count { parameter_types << ir.references[typ.refs_start + j] }
	}
	for i, block in stream.blocks {
		if block.id != 11 { continue }
		if block.parent < 0 || block_scopes[block.parent] == -1 { return error('AIR constants: constant block scope') }
		scope := block_scopes[block.parent]
		if constant_blocks[scope] != -1 { return error('AIR constants: duplicate pool in scope') }
		constant_blocks[scope] = i
	}
	mut first_module_constant := stream.records.len
	for index, record in stream.records {
		block := stream.blocks[record.block]
		if block.id == 11 {
			scope := block_scopes[block.parent]
			if heads[scope] == -1 { heads[scope] = index } else { next[tails[scope]] = index }
			tails[scope] = index
		}
		if record.block == constant_blocks[0] && record.code != 1 && index < first_module_constant { first_module_constant = index }
		if record.block == module_block && record.code in [u64(7), 8, 9, 14, 18]! {
			if declarations.len >= max_declarations { return error('AIR constants: declaration count limit') }
			declarations << index
		}
		scope := block_scopes[record.block]
		if scope > 0 && record.code != 1 && first_instruction[scope] == stream.records.len { first_instruction[scope] = index }
	}
	for declaration in declarations { if declaration > first_module_constant { return error('AIR constants: declaration after module constants') } }
	mut default_type := -1
	for i, typ in ir.types { if typ.kind == .integer_t && typ.bits == 32 { default_type = i; break } }
	mut module_values := u32(declarations.len)
	for scope in 0 .. scopes.len {
		if scope != 0 && !scopes[scope].active { continue }
		entry := scopes[scope]
		base := if scope == 0 { u32(declarations.len) } else { module_values + u32(entry.arguments_count) }
		start := b.constants.len
		mut current := default_type
		mut cursor := heads[scope]
		for cursor != -1 {
			index := cursor
			cursor = next[cursor]
			record := stream.records[index]
			if index > first_instruction[scope] && scope > 0 { return error('AIR constants: constants after instructions') }
			if record.has_blob { return error('AIR constants: unexpected blob') }
			values := ir_values(stream, record)
			if record.code == 1 {
				if values.len != 1 || values[0] >= u64(ir.types.len) || ir.types[int(values[0])].kind == .void_t { return error('AIR constants: SETTYPE index/operands') }
				current = int(values[0]); continue
			}
			if current == -1 { return error('AIR constants: missing indexed default i32 type or SETTYPE') }
			b.literal(ir, record, values, current, scope, base + u32(b.constants.len - start), index)!
		}
		scopes[scope] = IRConstantScope{...entry, active: true, first: start, count: b.constants.len - start, base_id: base}
		if scope == 0 { module_values = base + u32(b.constants.len - start) }
	}
	pools := IRConstantPools{declarations, scopes, parameter_types, b.constants, b.words, module_values}
	for constant in pools.constants {
		if constant.kind != .aggregate { continue }
		record := stream.records[constant.record]
		values := ir_values(stream, record)
		typ := ir.types[constant.type_index]
		for i, number in values {
			value := pools.lookup(constant.scope, number)!
			if value.kind == .argument { return error('AIR constants: aggregate references argument') }
			expected := ir.references[typ.refs_start + if typ.kind == .struct_t { i } else { 0 }]
			if (value.kind == .constant && value.type_index != expected) || (value.kind == .declaration && ir.types[expected].kind != .pointer_t) { return error('AIR constants: aggregate element type') }
		}
	}
	keep = true
	return pools
}
