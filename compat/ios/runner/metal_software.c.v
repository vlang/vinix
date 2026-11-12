// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Deliberately opt-in until shader execution and presentation are implemented.
// All API state is serialized by the runtime's recursive Objective-C lock.
struct SoftwareMetalCopy { source u64 destination u64 source_offset u64 destination_offset u64 size u64 rows u64 = 1 source_stride u64 destination_stride u64 }
struct SoftwareMetalCommands {
mut:
	ops []SoftwareMetalCopy
	completed []u64
	active bool
	status u64
	finished bool
}
const software_metal_max_buffer = u64(64 * 1024 * 1024)
fn sm_new(name string, owner u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	cls := ios_runtime.names[name] or { panic('iOS: software Metal backend is not enabled') }
	object := objc_allocate(cls)
	obj_header(object).fields[0] = objc_retain(owner)
	return object
}
fn sm_check(object u64, name string) &ObjHeader {
	header := ios_runtime.objects[object] or { panic('iOS: Metal object is not live') }
	if header.cls != ios_runtime.names[name] { panic('iOS: incompatible software Metal object') }
	return header
}
fn software_metal_dispose(mut header ObjHeader) {
	if header.software_metal == unsafe { nil } { return }
	mut state := header.software_metal
	for op in state.ops { objc_release(op.source); objc_release(op.destination) }
	for block in state.completed { block_release(block) }
	unsafe { state.ops.free(); state.completed.free() }
	C.free(state)
	header.software_metal = unsafe { nil }
}
fn sm_new_buffer(device u64, selector &char, length u64, options u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	sm_check(device, 'VinixSoftwareMTLDevice')
	// Only default CPU cache, shared storage and default hazards are supported.
	if length == 0 || length > software_metal_max_buffer || options != 0 { return 0 }
	buffer := sm_new('VinixSoftwareMTLBuffer', device)
	obj_header(buffer).data = []u8{len: int(length)}
	return buffer
}
fn sm_buffer_bytes(device u64, selector &char, bytes u64, length u64, options u64) u64 {
	if bytes == 0 { return 0 }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	buffer := sm_new_buffer(device, selector, length, options)
	if buffer != 0 { C.memcpy(obj_header(buffer).data.data, unsafe { voidptr(bytes) }, usize(length)) }
	return buffer
}
fn sm_new_queue(device u64, selector &char) u64 { return sm_new('VinixSoftwareMTLCommandQueue', device) }
fn sm_command_buffer(queue u64, selector &char) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	sm_check(queue, 'VinixSoftwareMTLCommandQueue')
	command := sm_new('VinixSoftwareMTLCommandBuffer', queue)
	mut state := unsafe { &SoftwareMetalCommands(C.calloc(1, sizeof(SoftwareMetalCommands))) }
	if state == unsafe { nil } { objc_release(command); return 0 }
	state.ops = []SoftwareMetalCopy{}
	state.ops.flags |= .noslices
	state.completed = []u64{}
	state.completed.flags |= .noslices
	obj_header(command).software_metal = state
	return objc_autorelease(command)
}
fn sm_blit_encoder(command u64, selector &char) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut state := sm_check(command, 'VinixSoftwareMTLCommandBuffer').software_metal
	if state.status != 0 || state.active { panic('iOS: Metal encoder requires an uncommitted buffer with no active encoder') }
	state.active = true
	encoder := sm_new('VinixSoftwareMTLBlitCommandEncoder', command)
	obj_header(encoder).valid = true
	return objc_autorelease(encoder)
}
fn sm_range(length u64, offset u64, size u64) bool { return offset <= length && size <= length - offset }
fn sm_copy(encoder u64, selector &char, source u64, source_offset u64, destination u64, destination_offset u64, size u64) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	h := sm_check(encoder, 'VinixSoftwareMTLBlitCommandEncoder')
	mut state := obj_header(h.fields[0]).software_metal
	if !h.valid || !state.active || state.status != 0 { panic('iOS: Metal encoding has ended') }
	src := sm_check(source, 'VinixSoftwareMTLBuffer'); dst := sm_check(destination, 'VinixSoftwareMTLBuffer')
	device := obj_header(obj_header(h.fields[0]).fields[0]).fields[0]
	if src.fields[0] != device || dst.fields[0] != device { panic('iOS: Metal blit resources belong to another device') }
	if !sm_range(u64(src.data.len), source_offset, size) || !sm_range(u64(dst.data.len), destination_offset, size) { panic('iOS: Metal blit range exceeds buffer') }
	if source == destination && size > 0 && source_offset < destination_offset + size && destination_offset < source_offset + size { panic('iOS: overlapping Metal blit ranges') }
	if state.ops.len >= 65536 { panic('iOS: software Metal command limit') }
	state.ops << SoftwareMetalCopy{source: objc_retain(source), destination: objc_retain(destination), source_offset: source_offset, destination_offset: destination_offset, size: size}
}
fn sm_end(encoder u64, selector &char) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut h := sm_check(encoder, 'VinixSoftwareMTLBlitCommandEncoder')
	mut state := obj_header(h.fields[0]).software_metal
	if !h.valid || !state.active || state.status != 0 { panic('iOS: Metal encoder already ended') }
	h.valid = false; state.active = false
}
fn sm_commit(command u64, selector &char) {
	C.ios_objc_initialize_lock()
	mut state := sm_check(command, 'VinixSoftwareMTLCommandBuffer').software_metal
	if state.status != 0 || state.active { panic('iOS: Metal commit requires ended encoders and an uncommitted buffer') }
	objc_retain(command)
	defer { objc_release(command) }
	state.status = 2
	for op in state.ops {
		if op.size == 0 { continue }
		src := obj_header(op.source); dst := obj_header(op.destination)
		for row in u64(0) .. op.rows {
			unsafe { C.memcpy(voidptr(u64(dst.data.data) + op.destination_offset + row * op.destination_stride), voidptr(u64(src.data.data) + op.source_offset + row * op.source_stride), usize(op.size)) }
		}
	}
	state.status = 4 // Completion is synchronous; bytes are visible before return.
	C.ios_objc_initialize_unlock()
	for i in 0 .. state.completed.len {
		block := state.completed[i]
		state.completed[i] = 0
		unsafe { SoftwareMetalCompletion(voidptr(read64(block + 16)))(block, command) }
		block_release(block)
	}
	C.ios_objc_initialize_lock()
	state.finished = true
	C.ios_objc_initialize_unlock()
}
fn sm_wait(command u64, selector &char) {
	objc_retain(command)
	defer { objc_release(command) }
	for {
		C.ios_objc_initialize_lock()
		state := sm_check(command, 'VinixSoftwareMTLCommandBuffer').software_metal
		if state.status == 0 { panic('iOS: Metal wait requires a committed buffer') }
		done := state.finished
		C.ios_objc_initialize_unlock()
		if done { return }
		C.usleep(100)
	}
}
type SoftwareMetalCompletion = fn (u64, u64)
fn sm_add_completed(command u64, selector &char, block u64) {
	if !is_block(block) || read64(block + 16) == 0 { panic('iOS: Metal completion handler requires a block') }
	// Copy helpers may run client code; keep them outside the runtime lock.
	copied := block_copy(block)
	C.ios_objc_initialize_lock()
	mut state := sm_check(command, 'VinixSoftwareMTLCommandBuffer').software_metal
	if state.status != 0 || state.completed.len >= 4096 {
		C.ios_objc_initialize_unlock()
		block_release(copied)
		panic('iOS: Metal handler registration requires uncommitted buffer and at most 4096 handlers')
	}
	state.completed << copied
	C.ios_objc_initialize_unlock()
}
fn sm_get(object u64, selector &char) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	h := obj_header(object)
	return match ctext(u64(selector)) {
		'length' { u64(h.data.len) }
		'contents' { u64(h.data.data) }
		'storageMode', 'cpuCacheMode' { u64(0) }
		'device' { if h.cls == ios_runtime.names['VinixSoftwareMTLBuffer'] || h.cls == ios_runtime.names['VinixSoftwareMTLCommandQueue'] { h.fields[0] } else { obj_header(h.fields[0]).fields[0] } }
		'commandQueue' { h.fields[0] }
		'status' { h.software_metal.status }
		'error' { u64(0) }
		'maxBufferLength' { software_metal_max_buffer }
		else { panic('iOS: unsupported software Metal property') }
	}
}
fn sm_method(cls u64, selector &char, imp u64, types &char) {
	if !objc_add_method(cls, u64(selector), imp, types) { panic('iOS: cannot install software Metal method') }
}
fn software_metal_start() {
	for name in [c'VinixSoftwareMTLDevice', c'VinixSoftwareMTLBuffer', c'VinixSoftwareMTLCommandQueue', c'VinixSoftwareMTLCommandBuffer', c'VinixSoftwareMTLBlitCommandEncoder']! {
		cls := objc_allocate_class(ios_runtime.names['NSObject'], name, 0)
		objc_register_class(cls)
	}
	device := ios_runtime.names['VinixSoftwareMTLDevice']; buffer := ios_runtime.names['VinixSoftwareMTLBuffer']; queue := ios_runtime.names['VinixSoftwareMTLCommandQueue']; command := ios_runtime.names['VinixSoftwareMTLCommandBuffer']; encoder := ios_runtime.names['VinixSoftwareMTLBlitCommandEncoder']
	sm_method(device, c'newBufferWithLength:options:', u64(unsafe { voidptr(sm_new_buffer) }), c'@32@0:8Q16Q24')
	sm_method(device, c'newBufferWithBytes:length:options:', u64(unsafe { voidptr(sm_buffer_bytes) }), c'@40@0:8r^v16Q24Q32')
	sm_method(device, c'newCommandQueue', u64(unsafe { voidptr(sm_new_queue) }), c'@16@0:8')
	sm_method(device, c'maxBufferLength', u64(unsafe { voidptr(sm_get) }), c'Q16@0:8')
	for cls in [buffer, queue, command]! { sm_method(cls, c'device', u64(unsafe { voidptr(sm_get) }), c'@16@0:8') }
	for selector in [c'length', c'storageMode', c'cpuCacheMode']! { sm_method(buffer, selector, u64(unsafe { voidptr(sm_get) }), c'Q16@0:8') }
	sm_method(buffer, c'contents', u64(unsafe { voidptr(sm_get) }), c'^v16@0:8')
	sm_method(queue, c'commandBuffer', u64(unsafe { voidptr(sm_command_buffer) }), c'@16@0:8')
	sm_method(command, c'blitCommandEncoder', u64(unsafe { voidptr(sm_blit_encoder) }), c'@16@0:8')
	sm_method(command, c'commandQueue', u64(unsafe { voidptr(sm_get) }), c'@16@0:8')
	sm_method(command, c'status', u64(unsafe { voidptr(sm_get) }), c'Q16@0:8')
	sm_method(command, c'error', u64(unsafe { voidptr(sm_get) }), c'@16@0:8')
	sm_method(command, c'commit', u64(unsafe { voidptr(sm_commit) }), c'v16@0:8')
	sm_method(command, c'waitUntilCompleted', u64(unsafe { voidptr(sm_wait) }), c'v16@0:8')
	sm_method(command, c'addCompletedHandler:', u64(unsafe { voidptr(sm_add_completed) }), c'v24@0:8@?16')
	sm_method(encoder, c'copyFromBuffer:sourceOffset:toBuffer:destinationOffset:size:', u64(unsafe { voidptr(sm_copy) }), c'v56@0:8@16Q24@32Q40Q48')
	sm_method(encoder, c'endEncoding', u64(unsafe { voidptr(sm_end) }), c'v16@0:8')
	sm_texture_start(device)
	sm_texture_blit_start(encoder)
}
