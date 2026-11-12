// SPDX-License-Identifier: GPL-2.0-or-later
module main

import airbitcode

// An experimental CPU interpreter, never a native Metal/GPU pipeline. Parsed
// indexes borrow the retained library's immutable bytes. Only direct scalar
// buffer arguments, forward constant GEPs and a single invocation are supported.
struct SoftwareMetalKernelArgument {
	slot int
	alignment u64
	minimum_size u64
	writable bool
}
struct SoftwareMetalKernel {
	stream airbitcode.Stream
	ir airbitcode.IRModule
	pools airbitcode.IRConstantPools
	bodies airbitcode.IRFunctionBodies
	program airbitcode.IRTypedProgram
	profile airbitcode.IRMemoryProfile
	function int
	arguments []SoftwareMetalKernelArgument
}
fn (kernel &SoftwareMetalKernel) free() {
	kernel.profile.free(); kernel.program.free(); kernel.bodies.free()
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
	profile := program.memory_function_profile(ir, stream, pools, bodies, function)!
	defer { if !keep { profile.free() } }
	mut arguments := []SoftwareMetalKernelArgument{len: profile.arguments.len}
	defer { if !keep { unsafe { arguments.free() } } }
	mut slots := u32(0)
	for arg in entries.arguments[entry.arguments_start..entry.arguments_start + entry.arguments_count] {
		if arg.kind != 'air.buffer' || arg.opaque_attributes || arg.condition >= 0 || arg.unused || !arg.has_location || arg.location_count != 1 || arg.location >= 31 || !arg.has_address_space || arg.address_space !in [u32(1), 2]! || arg.access !in [.read, .write, .read_write]! || (arg.address_space == 2 && arg.access != .read) { return error('Software Metal requires explicit scalar buffer metadata') }
		if slots & (u32(1) << arg.location) != 0 { return error('Software Metal buffer slots overlap') }
		slots |= u32(1) << arg.location
		a := profile.arguments[int(arg.index)]
		if (a.writable && arg.access == .read) || (a.readable && arg.access == .write) { return error('Software Metal buffer access disagrees with body') }
		alignment := if arg.has_alignment && arg.alignment > a.alignment { arg.alignment } else { a.alignment }
		mut minimum := a.minimum_size
		if arg.has_size && arg.size > minimum { minimum = arg.size }
		if arg.has_buffer_size && arg.buffer_size > minimum { minimum = arg.buffer_size }
		if alignment > 256 || minimum > software_metal_max_buffer { return error('Software Metal buffer requirements exceed profile') }
		arguments[int(arg.index)] = SoftwareMetalKernelArgument{int(arg.location), alignment, minimum, arg.access != .read}
	}
	keep = true
	return SoftwareMetalKernel{stream, ir, pools, bodies, program, profile, function, arguments}
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
		'maxTotalThreadsPerThreadgroup', 'threadExecutionWidth' { u64(1) }
		'staticThreadgroupMemoryLength' { u64(0) }
		else { panic('iOS: unsupported software Metal compute property') }
	}
}
struct SoftwareMetalComputeBindings {
mut:
	pipeline u64
	buffers [31]u64
	offsets [31]u64
}
fn sm_compute_bindings_free(state &SoftwareMetalComputeBindings) {
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
	objc_release(old)
}
fn sm_compute_validate(state &SoftwareMetalComputeBindings) {
	if state.pipeline == 0 { panic('iOS: Metal compute dispatch requires a pipeline') }
	kernel := obj_header(state.pipeline).metal_kernel
	for arg in kernel.arguments {
		if state.buffers[arg.slot] == 0 { panic('iOS: Metal compute dispatch requires every buffer binding') }
		b := obj_header(state.buffers[arg.slot]); offset := state.offsets[arg.slot]
		if !sm_range(sm_buffer_length(b), offset, arg.minimum_size) || offset % arg.alignment != 0 { panic('iOS: Metal compute binding bounds/alignment') }
	}
}
fn sm_compute_dispatch(encoder u64, selector &char, grid SoftwareMetalSize, group SoftwareMetalSize) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	h := sm_compute_active(encoder)
	if grid.width != 1 || grid.height != 1 || grid.depth != 1 || group.width != 1 || group.height != 1 || group.depth != 1 { panic('iOS: software Metal supports one compute invocation per dispatch') }
	sm_compute_validate(h.metal_compute)
	mut command := obj_header(h.fields[0]).software_metal
	if command.ops.len >= 65536 { panic('iOS: software Metal command limit') }
	snapshot := unsafe { &SoftwareMetalComputeBindings(C.malloc(sizeof(SoftwareMetalComputeBindings))) }
	if snapshot == unsafe { nil } { panic('iOS: cannot allocate Metal compute dispatch') }
	unsafe { *snapshot = *h.metal_compute }
	objc_retain(snapshot.pipeline)
	for buffer in snapshot.buffers { objc_retain(buffer) }
	command.ops << SoftwareMetalCopy{compute: snapshot}
}
fn sm_compute_execute(state &SoftwareMetalComputeBindings) ! {
	k := obj_header(state.pipeline).metal_kernel
	mut bindings := []airbitcode.IRMemoryBinding{cap: k.arguments.len}
	defer { unsafe { bindings.free() } }
	for arg in k.arguments {
		buffer := obj_header(state.buffers[arg.slot])
		// vbytes borrows storage; freeing bindings must never free its data.
		bindings << airbitcode.IRMemoryBinding{data: unsafe { (&u8(sm_storage_base(buffer))).vbytes(int(sm_buffer_length(buffer))) }, offset: state.offsets[arg.slot], base_alignment: 256, writable: arg.writable}
	}
	k.program.run_memory_function(k.ir, k.stream, k.pools, k.bodies, k.function, mut bindings, k.profile.steps)!
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
	for selector in [c'dispatchThreadgroups:threadsPerThreadgroup:', c'dispatchThreads:threadsPerThreadgroup:']! { sm_method(encoder, selector, u64(unsafe { voidptr(sm_compute_dispatch) }), c'v64@0:8{MTLSize=QQQ}16{MTLSize=QQQ}40') }
	sm_method(encoder, c'endEncoding', u64(unsafe { voidptr(sm_end) }), c'v16@0:8')
}
