// SPDX-License-Identifier: GPL-2.0-or-later
module airbitcode

// Indexed pointers are currently confined to direct load/store operands.
// Other consumers must not discard the cached argument/stride expression.
fn (p IRTypedProgram) fixed_memory_pointer(pools IRConstantPools, bodies IRFunctionBodies,
	scope int, operand int, count int, pointers []IRMemoryAccess) !IRMemoryAccess {
	access := p.memory_pointer(pools, bodies, scope, operand, count, pointers)!
	if access.indexed() {
		return error('AIR memory execution: indexed pointer flow unsupported')
	}
	return access
}

// Validate current inputs without executing AIR. The returned offsets are
// owned, empty for a static function, and used only for indexed access slots.
fn (profile IRMemoryProfile) checked_memory_offsets(bindings []IRMemoryBinding,
	step_limit int) ![]u64 {
	if step_limit < 1 || step_limit > max_integer_execution_steps {
		return error('AIR memory execution: budget')
	}
	if bindings.len != profile.arguments.len || profile.steps > step_limit {
		return error('AIR memory execution: binding count/budget')
	}
	for i, b in bindings {
		a := profile.arguments[i]
		if a.value_bits != 0 {
			if b.values.len != a.value_lanes || b.data.len != 0 || b.offset != 0 || b.base_alignment != 1 || b.writable {
				return error('AIR memory execution: value binding shape/options')
			}
			continue
		}
		if b.values.len != 0 { return error('AIR memory execution: buffer binding required') }
		if b.data.len > 64 * 1024 * 1024 || b.offset > u64(b.data.len) || b.base_alignment == 0 || b.base_alignment & (b.base_alignment - 1) != 0 || b.base_alignment < a.alignment || b.offset % a.alignment != 0 || a.minimum_size > u64(b.data.len) - b.offset || (a.writable && !b.writable) || (a.address_space == 2 && b.writable) {
			return error('AIR memory execution: bounds/alignment/permission')
		}
	}
	mut offsets := []u64{len: if profile.indexed { profile.accesses.len } else { 0 }}
	mut keep := false
	defer { if !keep { unsafe { offsets.free() } } }
	if profile.indexed {
		values := profile.memory_index_values(bindings)!
		for i, access in profile.accesses {
			if !access.indexed() { continue }
			word := if access.index_expression >= 0 { values[access.index_expression] } else { bindings[access.index_argument].values[0] & constant_mask(access.index_bits) }
			if word & (u64(1) << (access.index_bits - 1)) != 0 {
				return error('AIR memory execution: negative GEP argument outside profile')
			}
			if access.index_stride != 0 && word > (u64(64 * 1024 * 1024) - access.offset) / access.index_stride {
				return error('AIR memory execution: indexed GEP extent limit')
			}
			offset := access.offset + word * access.index_stride
			b := bindings[access.argument]
			span := u64(b.data.len) - b.offset
			if offset > span || u64(access.bytes) > span - offset || offset % access.alignment != 0 {
				return error('AIR memory execution: indexed access bounds/alignment')
			}
			offsets[i] = offset
		}
	}
	// Actual borrowed slices can alias even when their virtual arguments differ.
	// Indexed intrinsic pointers are excluded by preflight, so these are static.
	for access in profile.accesses {
		if !access.disjoint || access.bytes == 0 { continue }
		dest := unsafe { u64(bindings[access.argument].data.data) } + bindings[access.argument].offset + access.offset
		source := unsafe { u64(bindings[access.source_argument].data.data) } + bindings[access.source_argument].offset + access.source_offset
		gap := if dest <= source { source - dest } else { dest - source }
		if gap < u64(access.bytes) {
			return error('AIR memory execution: disjoint memcpy ranges required')
		}
	}
	keep = true
	return offsets
}
