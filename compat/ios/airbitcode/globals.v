// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

const max_global_variables = 65536
pub struct IRGlobalVariable {
pub:
	number u32 // Original module value ID, including holes for other declarations.
	record int
	name string // Borrows raw input STRTAB; never freed by IRGlobalVariables.
	type_index int // Storage element, not the global's pointer type.
	address_space u32
	is_constant bool
	has_initializer bool
	initializer_number u32 // Original module value ID, valid only when present.
	initializer int = -1 // Pool constant index; direct declaration references stay -1.
	linkage u32 // Original bitcode encoding; linking is not implemented.
	alignment u64 // Explicit byte alignment; 0 preserves the ABI-default request.
	thread_local u32 // Original mode 0..4; no TLS storage is allocated.
	externally_initialized bool
	opaque_properties bool // Other nonzero fields or unknown record extensions.
}
pub struct IRGlobalVariables {
pub:
	entries []IRGlobalVariable
}
pub fn (g &IRGlobalVariables) free() { unsafe { g.entries.free() } }
fn global_strtab(data []u8, stream Stream) !Blob {
	mut result := Blob{}
	mut found := false
	for block_index, block in stream.blocks {
		if block.id != 23 { continue }
		if block.parent != 0 { return error('AIR globals: string table scope') }
		for record in stream.records {
			if record.block != block_index { continue }
			if found || record.code != 1 || !record.has_blob || record.values_count != 0 { return error('AIR globals: string table record/count') }
			result = record.blob; found = true
		}
	}
	if result.offset > u64(data.len) || result.size > u64(data.len) - result.offset { return error('AIR globals: string table extent') }
	return result
}

// Module-v2 descriptors only. Requires the same immutable data/Stream/IR/pools.
// Names borrow data; all raw property records remain available in Stream.
pub fn (ir IRModule) global_variables(data []u8, stream Stream, pools IRConstantPools) !IRGlobalVariables {
	if pools.declarations.len > max_declarations { return error('AIR globals: declaration limit') }
	strtab := global_strtab(data, stream)!
	mut entries := []IRGlobalVariable{}
	entries.flags |= .noslices
	mut names := map[string]bool{}
	for f in ir.functions { if f.name.len > 0 { names[f.name] = true } }
	mut keep := false
	defer { unsafe { names.free() }; if !keep { unsafe { entries.free() } } }
	mut text_size := 0
	for number, record_index in pools.declarations {
		if record_index < 0 || record_index >= stream.records.len { return error('AIR globals: declaration record index') }
		r := stream.records[record_index]
		if r.code != 7 { continue } // Function, alias and ifunc IDs remain untouched.
		if entries.len >= max_global_variables || r.has_blob || r.block < 0 || r.block >= stream.blocks.len || stream.blocks[r.block].id != 8 || stream.blocks[r.block].parent != 0 { return error('AIR globals: global record/scope/limit') }
		if r.values_start < 0 || r.values_count < 8 || r.values_start > stream.values.len || r.values_count > stream.values.len - r.values_start { return error('AIR globals: global operand range') }
		v := ir_values(stream, r)
		offset := v[0]; size := v[1]
		if size > 4096 || offset > strtab.size || size > strtab.size - offset || size > u64(max_ir_text - text_size) { return error('AIR globals: global name extent/limit') }
		text_size += int(size)
		name := if size == 0 { '' } else { unsafe { tos(&data[int(strtab.offset + offset)], int(size)) } }
		if name.contains_u8(0) || (name.len > 0 && name in names) { return error('AIR globals: duplicate/invalid global name') }
		if name.len > 0 { names[name] = true }
		if v[2] >= u64(ir.types.len) { return error('AIR globals: storage type index') }
		mut typ := int(v[2]); mut space := u64(0)
		if v[3] & 2 != 0 { space = v[3] >> 2 }
		else {
			pointer := ir.types[typ]
			if v[3] > 1 || pointer.kind != .pointer_t || pointer.refs_count != 1 || pointer.refs_start < 0 || pointer.refs_start >= ir.references.len { return error('AIR globals: legacy typed pointer required') }
			typ = ir.references[pointer.refs_start]; space = pointer.address_space
		}
		if space > 0xffffff || typ < 0 || typ >= ir.types.len || ir.types[typ].kind in [.void_t, .function_t, .label_t, .metadata_t, .token_t, .x86_amx_t] { return error('AIR globals: storage type/address space') }
		mut initializer := -1
		mut initializer_number := u32(0)
		if v[4] != 0 {
			if v[4] > pools.module_values { return error('AIR globals: initializer value ID') }
			value := pools.lookup(0, v[4] - 1)!
			if value.kind == .constant {
				if value.type_index != typ { return error('AIR globals: initializer constant type') }
				initializer = value.constant_index
			} else if value.kind != .declaration || ir.types[typ].kind != .pointer_t { return error('AIR globals: initializer is not a matching module value') }
			initializer_number = u32(v[4] - 1)
		}
		if v[5] > 0xffffffff || (v.len > 9 && v[9] > 4) || (v.len > 11 && v[11] > 1) { return error('AIR globals: linkage/TLS/initialization fields') }
		alignment := operand_alignment(v[6])!
		mut opaque := v.len > 20
		for i in 7 .. v.len { if i !in [9, 11]! && v[i] != 0 { opaque = true } }
		entry := IRGlobalVariable{
			number: u32(number), record: record_index, name: name, type_index: typ, address_space: u32(space), is_constant: v[3] & 1 != 0,
			has_initializer: v[4] != 0, initializer_number: initializer_number, initializer: initializer, linkage: u32(v[5]), alignment: alignment, thread_local: if v.len > 9 { u32(v[9]) } else { 0 },
			externally_initialized: v.len > 11 && v[11] != 0, opaque_properties: opaque
		}
		unsafe { entries.push_many(&entry, 1) } // Copy the borrowed string header, not its bytes.
	}
	keep = true
	return IRGlobalVariables{entries: entries}
}

// A declared initializer template only: no linking, TLS, external initialization
// or guest storage installation occurs, even when the returned image is complete.
pub fn (g IRGlobalVariables) initializer_image(ir IRModule, stream Stream, pools IRConstantPools, layouts IRTypeLayouts, index int) !IRConstantImage {
	if index < 0 || index >= g.entries.len { return error('AIR globals: image global index') }
	entry := g.entries[index]
	if entry.initializer < 0 { return IRConstantImage{reason: .relocation} }
	return pools.constant_image(ir, stream, layouts, entry.initializer)!
}
