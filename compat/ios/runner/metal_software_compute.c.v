// SPDX-License-Identifier: GPL-2.0-or-later
module main

import airbitcode

// An experimental CPU interpreter, never a native Metal/GPU pipeline. Parsed
// indexes borrow the retained library's immutable bytes. Buffer pointers and
// uint/uint3 invocation builtins use bounded constant or argument-indexed GEPs.
const software_metal_max_compute_threads = u64(4096)
const software_metal_max_compute_group = u64(256)
const software_metal_max_compute_steps = 1000000

struct SoftwareMetalKernelArgument {
	slot int
	alignment u64
	minimum_size u64
	writable bool
	value_lanes int // Nonzero for a supported invocation builtin.
	builtin u8 // One bit per supported geometry semantic (all eight fit in u8).
}
fn sm_compute_builtin(kind string) u8 {
	return match kind {
		'air.thread_position_in_grid' { u8(1) }
		'air.thread_index_in_threadgroup' { u8(2) }
		'air.threads_per_grid' { u8(4) }
		'air.threads_per_threadgroup' { u8(8) }
		'air.dispatch_threads_per_threadgroup' { u8(16) }
		'air.thread_position_in_threadgroup' { u8(32) }
		'air.threadgroup_position_in_grid' { u8(64) }
		'air.threadgroups_per_grid' { u8(128) }
		else { u8(0) }
	}
}
fn sm_compute_builtin_slot(bit u8) int {
	return match bit { 1 { 0 } 2 { 3 } 4 { 6 } 8 { 9 } 16 { 12 } 32 { 15 } 64 { 18 } 128 { 21 } else { panic('iOS: invalid software Metal builtin') } }
}
fn sm_compute_builtin_type(bits u32, lanes int) string {
	return match bits * 4 + u32(lanes) {
		65 { 'ushort' } 66 { 'ushort2' } 67 { 'ushort3' }
		129 { 'uint' } 130 { 'uint2' } 131 { 'uint3' }
		else { '' }
	}
}
struct SoftwareMetalKernel {
	stream airbitcode.Stream
	ir airbitcode.IRModule
	pools airbitcode.IRConstantPools
	bodies airbitcode.IRFunctionBodies
	program airbitcode.IRTypedProgram
	prepared airbitcode.IRPreparedMemoryFunction
	function int
	arguments []SoftwareMetalKernelArgument
}
fn (kernel &SoftwareMetalKernel) free() {
	kernel.prepared.free(); kernel.program.free(); kernel.bodies.free()
	kernel.pools.free(); kernel.ir.free(); kernel.stream.free()
	unsafe { kernel.arguments.free() }
}
fn sm_kernel(data []u8, name string) !SoftwareMetalKernel {
	stream := airbitcode.parse(data)!
	mut keep := false
	defer { if !keep { stream.free() } }
	ir := stream.ir_module(data)!
	defer { if !keep { ir.free() } }
	pools := ir.constant_pools(stream)!
	defer { if !keep { pools.free() } }
	bodies := ir.function_bodies(stream, pools)!
	defer { if !keep { bodies.free() } }
	program := ir.typed_operands(stream, pools, bodies)!
	defer { if !keep { program.free() } }
	md := ir.module_metadata(data, stream, pools)!
	defer { md.free() }
	entries := md.air_entries(ir, pools)!
	defer { entries.free() }
	mut function := -1
	mut entry_index := -1
	for i, entry in entries.entries {
		if ir.functions[entry.function].name == name && entry.stage == .kernel {
			function = entry.function; entry_index = i; break
		}
	}
	if function < 0 { return error('Software Metal requires an air.kernel entry') }
	entry := entries.entries[entry_index]
	if entry.opaque_attributes { return error('Software Metal does not support extra kernel attributes') }
	prepared := program.prepare_memory_function(ir, stream, pools, bodies, function)!
	defer { if !keep { prepared.free() } }
	mut arguments := []SoftwareMetalKernelArgument{len: prepared.argument_count()}
	defer { if !keep { unsafe { arguments.free() } } }
	mut slots := u32(0)
	mut builtins := u8(0)
	mut grid_lanes := 0
	mut group_lanes := 0
	mut vector_lanes := 0
	mut local_bits := u32(0)
	mut index_bits := u32(0)
	for arg in entries.arguments[entry.arguments_start..entry.arguments_start + entry.arguments_count] {
		a := prepared.argument(int(arg.index))!
		bit := sm_compute_builtin(arg.kind)
		if bit != 0 {
			typ := program.types[arg.type_index]
			vector := typ.kind == .vector_t
			type_name := sm_compute_builtin_type(a.value_bits, a.value_lanes)
			if builtins & bit != 0 || arg.opaque_attributes || arg.condition >= 0 || arg.unused || arg.has_location || arg.has_address_space || arg.has_size || arg.has_alignment || arg.has_buffer_size || arg.access != .unspecified || type_name.len == 0 || (vector && (bit == 2 || a.value_lanes < 2 || a.value_lanes > 3)) || (!vector && (typ.kind != .integer_t || a.value_lanes != 1)) || (arg.type_name.len != 0 && arg.type_name != type_name) { return error('Software Metal requires ushort/uint scalar, pair or triple builtin metadata') }
			// scalar_vector_type admits floating lanes as well; builtins do not.
			if vector {
				element := program.references[typ.refs_start]
				if program.types[element].kind != .integer_t { return error('Software Metal requires integer invocation coordinates') }
				if vector_lanes != 0 && vector_lanes != a.value_lanes { return error('Software Metal geometry vectors must have matching lane counts') }
				vector_lanes = a.value_lanes
			}
			shape := int(a.value_bits) * 4 + a.value_lanes
			if bit == 1 || bit == 4 {
				if grid_lanes != 0 && grid_lanes != shape { return error('Software Metal grid position/size types must match') }
				grid_lanes = shape
			} else if bit == 8 || bit == 16 || bit == 32 {
				if group_lanes != 0 && group_lanes != shape { return error('Software Metal local position/group size types must match') }
				group_lanes = shape
			}
			if bit == 32 { local_bits = a.value_bits }
			if bit == 2 { index_bits = a.value_bits }
			builtins |= bit
			arguments[int(arg.index)] = SoftwareMetalKernelArgument{slot: -1, value_lanes: a.value_lanes, builtin: bit}
			continue
		}
		if arg.kind != 'air.buffer' || arg.opaque_attributes || arg.condition >= 0 || arg.unused || !arg.has_location || arg.location_count != 1 || arg.location >= 31 || !arg.has_address_space || arg.address_space !in [u32(1), 2]! || arg.access !in [.read, .write, .read_write]! || (arg.address_space == 2 && arg.access != .read) { return error('Software Metal requires explicit scalar buffer metadata') }
		if slots & (u32(1) << arg.location) != 0 { return error('Software Metal buffer slots overlap') }
		slots |= u32(1) << arg.location
		if a.value_bits != 0 { return error('Software Metal buffer pointer required') }
		if (a.writable && arg.access == .read) || (a.readable && arg.access == .write) { return error('Software Metal buffer access disagrees with body') }
		alignment := if arg.has_alignment && arg.alignment > a.alignment { arg.alignment } else { a.alignment }
		mut minimum := a.minimum_size
		if arg.has_size && arg.size > minimum { minimum = arg.size }
		if arg.has_buffer_size && arg.buffer_size > minimum { minimum = arg.buffer_size }
		if alignment > 256 || minimum > software_metal_max_buffer { return error('Software Metal buffer requirements exceed profile') }
		arguments[int(arg.index)] = SoftwareMetalKernelArgument{slot: int(arg.location), alignment: alignment, minimum_size: minimum, writable: arg.access != .read}
	}
	if local_bits != 0 && index_bits != 0 && local_bits != index_bits { return error('Software Metal local position/index widths must match') }
	keep = true
	return SoftwareMetalKernel{stream, ir, pools, bodies, program, prepared, function, arguments}
}
fn sm_compute_pipeline(device u64, selector &char, function u64, output &u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	sm_check(device, 'VinixSoftwareMTLDevice')
	f := ios_runtime.objects[function] or { return sm_library_error(output, 1, 'Software Metal requires a live kernel function') }
	if f.cls != ios_runtime.names['VinixSoftwareMTLFunction'] || f.number != 3 { return sm_library_error(output, 1, 'Software Metal requires a kernel function') }
	library := obj_header(f.fields[0])
	if library.fields[0] != device { return sm_library_error(output, 1, 'Software Metal kernel belongs to another device') }
	name := string_text(f.fields[1])
	for indexed in library.metal_library.index.functions {
		if indexed.name != name { continue }
		range := library.metal_library.index.modules[indexed.module].bitcode
		kernel := sm_kernel(library.data[int(range.offset)..int(range.offset + range.size)], name) or { return sm_library_error(output, 3, err.msg()) }
		state := unsafe { &SoftwareMetalKernel(C.malloc(sizeof(SoftwareMetalKernel))) }
		if state == unsafe { nil } { kernel.free(); return sm_library_error(output, 2, 'Cannot allocate software Metal pipeline') }
		unsafe { *state = kernel }
		pipeline := sm_new('VinixSoftwareMTLComputePipelineState', function)
		obj_header(pipeline).metal_kernel = state
		return pipeline
	}
	return sm_library_error(output, 1, 'Software Metal kernel is missing')
}
fn sm_compute_get(pipeline u64, selector &char) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	h := sm_check(pipeline, 'VinixSoftwareMTLComputePipelineState')
	return match ctext(u64(selector)) {
		'device' { obj_header(obj_header(h.fields[0]).fields[0]).fields[0] }
		'maxTotalThreadsPerThreadgroup' { software_metal_max_compute_group }
		'threadExecutionWidth' { u64(1) }
		'staticThreadgroupMemoryLength' { u64(0) }
		else { panic('iOS: unsupported software Metal compute property') }
	}
}
struct SoftwareMetalComputeBindings {
mut:
	pipeline u64
	buffers [31]u64
	offsets [31]u64
	inline_slots u32
	grid_threads u64
	grid_size SoftwareMetalSize
	group_size SoftwareMetalSize
	indirect_buffer u64
	indirect_offset u64
}
fn sm_compute_bindings_free(state &SoftwareMetalComputeBindings) {
	objc_release(state.indirect_buffer)
	objc_release(state.pipeline)
	for buffer in state.buffers { objc_release(buffer) }
	C.free(state)
}
fn sm_compute_dispose(mut h ObjHeader) {
	if h.metal_kernel != unsafe { nil } { h.metal_kernel.free(); C.free(h.metal_kernel); h.metal_kernel = unsafe { nil } }
	if h.metal_compute != unsafe { nil } { sm_compute_bindings_free(h.metal_compute); h.metal_compute = unsafe { nil } }
}
fn sm_compute_encoder(command u64, selector &char) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut state := sm_check(command, 'VinixSoftwareMTLCommandBuffer').software_metal
	if state.status != 0 || state.active { panic('iOS: Metal encoder requires an uncommitted buffer with no active encoder') }
	bindings := unsafe { &SoftwareMetalComputeBindings(C.calloc(1, sizeof(SoftwareMetalComputeBindings))) }
	if bindings == unsafe { nil } { return 0 }
	encoder := sm_new('VinixSoftwareMTLComputeCommandEncoder', command)
	obj_header(encoder).metal_compute = bindings
	obj_header(encoder).valid = true
	state.active = true
	return objc_autorelease(encoder)
}
fn sm_compute_active(encoder u64) &ObjHeader {
	h := sm_check(encoder, 'VinixSoftwareMTLComputeCommandEncoder')
	state := obj_header(h.fields[0]).software_metal
	if !h.valid || !state.active || state.status != 0 { panic('iOS: Metal compute encoding has ended') }
	return h
}
fn sm_compute_set_pipeline(encoder u64, selector &char, pipeline u64) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut h := sm_compute_active(encoder)
	sm_check(pipeline, 'VinixSoftwareMTLComputePipelineState')
	device := obj_header(obj_header(h.fields[0]).fields[0]).fields[0]
	if sm_compute_get(pipeline, c'device') != device { panic('iOS: Metal compute pipeline belongs to another device') }
	old := h.metal_compute.pipeline
	h.metal_compute.pipeline = objc_retain(pipeline)
	objc_release(old)
}
fn sm_compute_set_buffer(encoder u64, selector &char, buffer u64, offset u64, index u64) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut h := sm_compute_active(encoder)
	if index >= 31 { panic('iOS: Metal compute buffer index exceeds profile') }
	if buffer != 0 {
		b := sm_check(buffer, 'VinixSoftwareMTLBuffer')
		device := obj_header(obj_header(h.fields[0]).fields[0]).fields[0]
		if b.fields[0] != device || offset > sm_buffer_length(b) { panic('iOS: invalid Metal compute buffer/offset') }
	}
	old := h.metal_compute.buffers[index]
	h.metal_compute.buffers[index] = objc_retain(buffer)
	h.metal_compute.offsets[index] = offset
	h.metal_compute.inline_slots &= ~(u32(1) << u32(index))
	objc_release(old)
}
fn sm_compute_set_bytes(encoder u64, selector &char, bytes u64, length u64, index u64) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut h := sm_compute_active(encoder)
	if index >= 31 || length == 0 || length > 4096 || bytes == 0 || bytes > ~u64(0) - length { panic('iOS: Metal inline bytes require 1..4096 readable bytes and a valid slot') }
	device := obj_header(obj_header(h.fields[0]).fields[0]).fields[0]
	buffer := sm_buffer_bytes(device, c'newBufferWithBytes:length:options:', bytes, length, 0)
	if buffer == 0 { panic('iOS: cannot allocate Metal inline bytes') }
	// Transfer the owned buffer to the encoder; recorded dispatches retain it
	// independently. Publish everything before releasing reentrant client storage.
	old := h.metal_compute.buffers[index]
	h.metal_compute.buffers[index] = buffer
	h.metal_compute.offsets[index] = 0
	h.metal_compute.inline_slots |= u32(1) << u32(index)
	objc_release(old)
}
fn sm_compute_set_offset(encoder u64, selector &char, offset u64, index u64) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut h := sm_compute_active(encoder)
	if index >= 31 || h.metal_compute.buffers[index] == 0 || h.metal_compute.inline_slots & (u32(1) << u32(index)) != 0 { panic('iOS: Metal offset update requires an explicit buffer binding') }
	b := obj_header(h.metal_compute.buffers[index])
	if offset > sm_buffer_length(b) { panic('iOS: Metal compute offset exceeds buffer') }
	h.metal_compute.offsets[index] = offset
}
fn sm_compute_set_buffers(encoder u64, selector &char, buffers u64, offsets u64, range SoftwareMetalRange) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut h := sm_compute_active(encoder)
	if !sm_range(31, range.location, range.length) { panic('iOS: Metal compute binding range exceeds slots') }
	if range.length == 0 { return }
	size := range.length * 8
	if buffers == 0 || offsets == 0 || buffers > ~u64(0) - size || offsets > ~u64(0) - size { panic('iOS: Metal compute binding arrays are unavailable') }
	mut incoming := [31]u64{}; mut positions := [31]u64{}; mut previous := [31]u64{}
	unsafe { C.memcpy(&incoming[0], voidptr(buffers), usize(size)); C.memcpy(&positions[0], voidptr(offsets), usize(size)) }
	device := obj_header(obj_header(h.fields[0]).fields[0]).fields[0]
	// Validate the complete request, then retain every incoming reference before
	// replacing/releasing any old slot. Swaps and aliases may share sole owners.
	for i in 0 .. int(range.length) {
		if incoming[i] == 0 { continue }
		b := sm_check(incoming[i], 'VinixSoftwareMTLBuffer')
		if b.fields[0] != device || positions[i] > sm_buffer_length(b) { panic('iOS: invalid Metal compute buffer array entry') }
	}
	for i in 0 .. int(range.length) { objc_retain(incoming[i]) }
	for i in 0 .. int(range.length) {
		slot := int(range.location) + i
		previous[i] = h.metal_compute.buffers[slot]
		h.metal_compute.buffers[slot] = incoming[i]
		h.metal_compute.offsets[slot] = positions[i]
		h.metal_compute.inline_slots &= ~(u32(1) << u32(slot))
	}
	// Client no-copy deallocators can reenter here; no encoder state is read
	// after this point, and all slots already expose the completed update.
	for i in 0 .. int(range.length) { objc_release(previous[i]) }
}
fn sm_compute_validate(state &SoftwareMetalComputeBindings) {
	if state.pipeline == 0 { panic('iOS: Metal compute dispatch requires a pipeline') }
	kernel := obj_header(state.pipeline).metal_kernel
	for arg in kernel.arguments {
		if arg.value_lanes != 0 { continue }
		if state.buffers[arg.slot] == 0 { panic('iOS: Metal compute dispatch requires every buffer binding') }
		b := obj_header(state.buffers[arg.slot]); offset := state.offsets[arg.slot]
		if !sm_range(sm_buffer_length(b), offset, arg.minimum_size) || offset % arg.alignment != 0 { panic('iOS: Metal compute binding bounds/alignment') }
	}
}
struct SoftwareMetalComputeGrid {
	threads u64
	grid SoftwareMetalSize
	group SoftwareMetalSize
}
fn sm_compute_volume(size SoftwareMetalSize, limit u64) !u64 {
	mut volume := u64(1)
	for axis in [size.width, size.height, size.depth]! {
		if axis == 0 || axis > limit / volume { return error('software Metal compute dimension product exceeds profile') }
		volume *= axis
	}
	return volume
}
// Check volumes before multiplying any untrusted dimensions. dispatchThreads
// may produce partial groups along any of the three axes.
fn sm_compute_grid_plan(groups bool, grid SoftwareMetalSize, group SoftwareMetalSize, steps int) !SoftwareMetalComputeGrid {
	if grid.width == 0 || grid.height == 0 || grid.depth == 0 || group.width == 0 || group.height == 0 || group.depth == 0 {
		return error('software Metal requires nonempty compute dimensions')
	}
	group_volume := sm_compute_volume(group, software_metal_max_compute_group) or { return error('software Metal compute group limit') }
	grid_volume := sm_compute_volume(grid, software_metal_max_compute_threads) or { return error('software Metal compute invocation limit') }
	if groups && grid_volume > software_metal_max_compute_threads / group_volume { return error('software Metal compute invocation limit') }
	threads := grid_volume * (if groups { group_volume } else { u64(1) })
	if steps < 1 || steps > software_metal_max_compute_steps || threads > u64(software_metal_max_compute_steps / steps) {
		return error('software Metal compute dispatch instruction budget')
	}
	return SoftwareMetalComputeGrid{threads, if groups { SoftwareMetalSize{grid.width * group.width, grid.height * group.height, grid.depth * group.depth} } else { grid }, group}
}
fn sm_compute_grid(groups bool, grid SoftwareMetalSize, group SoftwareMetalSize, steps int) !u64 {
	return sm_compute_grid_plan(groups, grid, group, steps)!.threads
}
// The plan is private, immutable and validated when the dispatch is recorded.
// Local indices use the actual edge-group width/height, with x varying fastest.
fn (plan SoftwareMetalComputeGrid) coordinates(position u64) [4]u64 {
	x := position % plan.grid.width
	y := position / plan.grid.width % plan.grid.height
	z := position / (plan.grid.width * plan.grid.height)
	lx := x % plan.group.width; ly := y % plan.group.height; lz := z % plan.group.depth
	remaining_x := plan.grid.width - (x - lx)
	remaining_y := plan.grid.height - (y - ly)
	sx := if remaining_x < plan.group.width { remaining_x } else { plan.group.width }
	sy := if remaining_y < plan.group.height { remaining_y } else { plan.group.height }
	return [x, y, z, (lz * sy + ly) * sx + lx]!
}
fn (plan SoftwareMetalComputeGrid) builtin_words(position u64) [24]u64 {
	c := plan.coordinates(position)
	rx := plan.grid.width - c[0] / plan.group.width * plan.group.width
	ry := plan.grid.height - c[1] / plan.group.height * plan.group.height
	rz := plan.grid.depth - c[2] / plan.group.depth * plan.group.depth
	sx := if rx < plan.group.width { rx } else { plan.group.width }
	sy := if ry < plan.group.height { ry } else { plan.group.height }
	sz := if rz < plan.group.depth { rz } else { plan.group.depth }
	return [c[0], c[1], c[2], c[3], u64(0), 0,
		plan.grid.width, plan.grid.height, plan.grid.depth, sx, sy, sz,
		plan.group.width, plan.group.height, plan.group.depth,
		c[0] % plan.group.width, c[1] % plan.group.height, c[2] % plan.group.depth,
		c[0] / plan.group.width, c[1] / plan.group.height, c[2] / plan.group.depth,
		(plan.grid.width - 1) / plan.group.width + 1,
		(plan.grid.height - 1) / plan.group.height + 1,
		(plan.grid.depth - 1) / plan.group.depth + 1]!
}
fn sm_compute_dispatch(encoder u64, selector &char, grid SoftwareMetalSize, group SoftwareMetalSize) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	h := sm_compute_active(encoder)
	sm_compute_validate(h.metal_compute)
	plan := sm_compute_grid_plan(ctext(u64(selector)) == 'dispatchThreadgroups:threadsPerThreadgroup:', grid, group, obj_header(h.metal_compute.pipeline).metal_kernel.prepared.steps()) or { panic('iOS: ' + err.msg()) }
	sm_compute_record(h, plan, 0, 0)
}
fn sm_compute_indirect(encoder u64, selector &char, buffer u64, offset u64, group SoftwareMetalSize) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	h := sm_compute_active(encoder)
	sm_compute_validate(h.metal_compute)
	b := sm_check(buffer, 'VinixSoftwareMTLBuffer')
	device := obj_header(obj_header(h.fields[0]).fields[0]).fields[0]
	if b.fields[0] != device || offset % 4 != 0 || !sm_range(sm_buffer_length(b), offset, 12) { panic('iOS: invalid Metal indirect dispatch buffer/offset') }
	// Validate the known group and one-group instruction cost now. Counts remain
	// deferred so earlier copies or compute commands can produce them.
	plan := sm_compute_grid_plan(true, SoftwareMetalSize{1, 1, 1}, group, obj_header(h.metal_compute.pipeline).metal_kernel.prepared.steps()) or { panic('iOS: ' + err.msg()) }
	sm_compute_record(h, plan, buffer, offset)
}
fn sm_compute_record(h &ObjHeader, plan SoftwareMetalComputeGrid, indirect u64, offset u64) {
	mut command := obj_header(h.fields[0]).software_metal
	if command.ops.len >= 65536 { panic('iOS: software Metal command limit') }
	mut snapshot := unsafe { &SoftwareMetalComputeBindings(C.malloc(sizeof(SoftwareMetalComputeBindings))) }
	if snapshot == unsafe { nil } { panic('iOS: cannot allocate Metal compute dispatch') }
	unsafe { *snapshot = *h.metal_compute }
	snapshot.grid_threads = plan.threads
	snapshot.grid_size = plan.grid
	snapshot.group_size = plan.group
	snapshot.indirect_buffer = objc_retain(indirect)
	snapshot.indirect_offset = offset
	objc_retain(snapshot.pipeline)
	for buffer in snapshot.buffers { objc_retain(buffer) }
	command.ops << SoftwareMetalCopy{compute: snapshot}
}
fn sm_compute_execute(state &SoftwareMetalComputeBindings) ! {
	k := obj_header(state.pipeline).metal_kernel
	mut plan := SoftwareMetalComputeGrid{state.grid_threads, state.grid_size, state.group_size}
	if state.indirect_buffer != 0 {
		b := obj_header(state.indirect_buffer)
		mut counts := [3]u32{}
		unsafe { C.memcpy(&counts[0], voidptr(sm_storage_base(b) + state.indirect_offset), 12) }
		if counts[0] == 0 || counts[1] == 0 || counts[2] == 0 { return }
		plan = sm_compute_grid_plan(true, SoftwareMetalSize{u64(counts[0]), u64(counts[1]), u64(counts[2])}, state.group_size, k.prepared.steps())!
	}
	mut bindings := []airbitcode.IRMemoryBinding{cap: k.arguments.len}
	mut has_values := false
	for arg in k.arguments { if arg.value_lanes != 0 { has_values = true } }
	mut builtin_words := []u64{len: if has_values { 24 } else { 0 }}
	defer { unsafe { bindings.free(); builtin_words.free() } }
	for arg in k.arguments {
		if arg.value_lanes != 0 {
			start := sm_compute_builtin_slot(arg.builtin)
			bindings << airbitcode.IRMemoryBinding{values: builtin_words[start..start + arg.value_lanes]}
			continue
		}
		buffer := obj_header(state.buffers[arg.slot])
		// vbytes borrows storage; freeing bindings must never free its data.
		bindings << airbitcode.IRMemoryBinding{data: unsafe { (&u8(sm_storage_base(buffer))).vbytes(int(sm_buffer_length(buffer))) }, offset: state.offsets[arg.slot], base_alignment: 256, writable: arg.writable}
	}
	// All invocation addresses, even in cold blocks or the last partial group,
	// must be valid before the first invocation writes. No AIR value is executed
	// by this pass; arithmetic poison retains ordinary partial-write behavior.
	for pass in 0 .. 2 {
		for position in u64(0) .. plan.threads {
			if has_values {
				words := plan.builtin_words(position)
				for lane in 0 .. 24 { builtin_words[lane] = words[lane] }
			}
			if pass == 0 { k.prepared.validate(bindings, k.prepared.steps())! }
			else { k.prepared.run(mut bindings, k.prepared.steps())! }
		}
	}
}
fn sm_compute_start(device u64, command u64) {
	for name in [c'VinixSoftwareMTLComputePipelineState', c'VinixSoftwareMTLComputeCommandEncoder']! {
		cls := objc_allocate_class(ios_runtime.names['NSObject'], name, 0)
		objc_register_class(cls)
	}
	pipeline := ios_runtime.names['VinixSoftwareMTLComputePipelineState']; encoder := ios_runtime.names['VinixSoftwareMTLComputeCommandEncoder']
	sm_method(device, c'newComputePipelineStateWithFunction:error:', u64(unsafe { voidptr(sm_compute_pipeline) }), c'@32@0:8@16^@24')
	sm_method(pipeline, c'device', u64(unsafe { voidptr(sm_compute_get) }), c'@16@0:8')
	for selector in [c'maxTotalThreadsPerThreadgroup', c'threadExecutionWidth', c'staticThreadgroupMemoryLength']! { sm_method(pipeline, selector, u64(unsafe { voidptr(sm_compute_get) }), c'Q16@0:8') }
	sm_method(command, c'computeCommandEncoder', u64(unsafe { voidptr(sm_compute_encoder) }), c'@16@0:8')
	sm_method(encoder, c'setComputePipelineState:', u64(unsafe { voidptr(sm_compute_set_pipeline) }), c'v24@0:8@16')
	sm_method(encoder, c'setBuffer:offset:atIndex:', u64(unsafe { voidptr(sm_compute_set_buffer) }), c'v40@0:8@16Q24Q32')
	sm_method(encoder, c'setBytes:length:atIndex:', u64(unsafe { voidptr(sm_compute_set_bytes) }), c'v40@0:8r^v16Q24Q32')
	sm_method(encoder, c'setBufferOffset:atIndex:', u64(unsafe { voidptr(sm_compute_set_offset) }), c'v32@0:8Q16Q24')
	sm_method(encoder, c'setBuffers:offsets:withRange:', u64(unsafe { voidptr(sm_compute_set_buffers) }), c'v48@0:8r^@16r^Q24{_NSRange=QQ}32')
	for selector in [c'dispatchThreadgroups:threadsPerThreadgroup:', c'dispatchThreads:threadsPerThreadgroup:']! { sm_method(encoder, selector, u64(unsafe { voidptr(sm_compute_dispatch) }), c'v64@0:8{MTLSize=QQQ}16{MTLSize=QQQ}40') }
	sm_method(encoder, c'dispatchThreadgroupsWithIndirectBuffer:indirectBufferOffset:threadsPerThreadgroup:', u64(unsafe { voidptr(sm_compute_indirect) }), c'v56@0:8@16Q24{MTLSize=QQQ}32')
	sm_method(encoder, c'endEncoding', u64(unsafe { voidptr(sm_end) }), c'v16@0:8')
}
