// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

// Each Java wrapper owns one native reference. Closing one wrapper must not
// invalidate another wrapper or a reference explicitly acquired by NDK code.
@[export: 'AHardwareBuffer_toHardwareBuffer']
pub fn ws_hardware_to_java(e voidptr, buffer &WsHardwareBuffer) voidptr {
	if e == unsafe { nil } || buffer == unsafe { nil } || pending(e) { return unsafe { nil } }
	c := cls(e, c'android/hardware/HardwareBuffer')
	if c == unsafe { nil } { return unsafe { nil } }
	unsafe {
		defer { Drop(slot(e, 23))(e, c) }
		init := Member(slot(e, 33))(e, c, c'<init>', c'(J)V')
		if init == nil { return nil }
		ws_hardware_acquire(buffer)
		arg := &Value(C.alloca(sizeof(Value)))
		*arg = Value{j: i64(usize(buffer))}
		wrapper := ObjectCall(slot(e, 30))(e, c, init, arg)
		if wrapper == nil || pending(e) {
			ws_hardware_release(buffer)
			return nil
		}
		return wrapper
	}
}

@[export: 'AHardwareBuffer_fromHardwareBuffer']
pub fn ws_hardware_from_java(e voidptr, wrapper voidptr) &WsHardwareBuffer {
	if e == unsafe { nil } || wrapper == unsafe { nil } || pending(e) { return unsafe { nil } }
	if !instance_of(e, wrapper, c'android/hardware/HardwareBuffer') { return unsafe { nil } }
	unsafe {
		if Monitor(slot(e, 217))(e, wrapper) != 0 { return nil }
		defer { Monitor(slot(e, 218))(e, wrapper) }
		// Borrowed pointer: the caller must keep the Java wrapper open, or
		// acquire its own reference before allowing the wrapper to close.
		return &WsHardwareBuffer(get_long(e, wrapper, c'android/hardware/HardwareBuffer', c'vinixBuffer'))
	}
}

fn ws_hardware_java_supported(width i32, height i32, format i32, layers i32, usage i64) bool {
	desc := WsHardwareBufferDesc{width: u32(width), height: u32(height), format: u32(format), layers: u32(layers), usage: u64(usage)}
	return ws_hardware_supported(&desc) == 1
}

fn ws_hardware_java_create(e voidptr, width i32, height i32, format i32, layers i32, usage i64) voidptr {
	desc := WsHardwareBufferDesc{width: u32(width), height: u32(height), format: u32(format), layers: u32(layers), usage: u64(usage)}
	mut buffer := unsafe { &WsHardwareBuffer(nil) }
	result := ws_hardware_allocate(&desc, &buffer)
	if result != 0 {
		throw(e, if result == -12 { c'java/lang/OutOfMemoryError' } else { c'java/lang/IllegalArgumentException' }, c'Cannot allocate requested native WS hardware buffer')
		return unsafe { nil }
	}
	defer { ws_hardware_release(buffer) }
	return ws_hardware_to_java(e, buffer)
}

fn ws_hardware_java_property(pointer i64, property i32) i64 {
	unsafe {
		buffer := &WsHardwareBuffer(pointer)
		if buffer == nil { return 0 }
		return match property {
			0 { i64(buffer.desc.width) }
			1 { i64(buffer.desc.height) }
			2 { i64(buffer.desc.format) }
			3 { i64(buffer.desc.layers) }
			4 { i64(buffer.desc.usage) }
			else { i64(0) }
		}
	}
}
