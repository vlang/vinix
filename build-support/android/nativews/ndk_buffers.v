// SPDX-License-Identifier: GPL-2.0-or-later
// CPU-only NDK hardware buffers. GPU/protected/multi-layer usages are rejected.
@[translated]
module atlframework

struct WsHardwareBufferDesc {
mut:
	width u32
	height u32
	layers u32
	format u32
	usage u64
	stride u32
	rfu0 u32
	rfu1 u64
}

struct WsHardwareBuffer {
mut:
	mutex C.pthread_mutex_t
	references i32
	locked bool
	desc WsHardwareBufferDesc
	bitmap i64
}

struct WsHardwareBufferPlane {
mut:
	data voidptr
	pixel_stride u32
	row_stride u32
}

struct WsHardwareBufferPlanes {
mut:
	count u32
	planes [4]WsHardwareBufferPlane
}

@[export: 'AHardwareBuffer_isSupported']
pub fn ws_hardware_supported(desc &WsHardwareBufferDesc) i32 {
	if desc == unsafe { nil } { return 0 }
	read := desc.usage & 15
	write := desc.usage & 240
	return i32(desc.width > 0 && desc.height > 0 && desc.width <= 8192 && desc.height <= 8192
		&& desc.layers == 1 && desc.format == 1 && desc.usage & ~u64(0xff) == 0
		&& (read == 0 || read == 2 || read == 3) && (write == 0 || write == 32 || write == 48)
		&& desc.rfu0 == 0 && desc.rfu1 == 0)
}

@[export: 'AHardwareBuffer_allocate']
pub fn ws_hardware_allocate(desc &WsHardwareBufferDesc, output &&WsHardwareBuffer) i32 {
	if output == unsafe { nil } { return -22 }
	unsafe {
		*output = nil
		if ws_hardware_supported(desc) == 0 { return -22 }
		buffer := &WsHardwareBuffer(C.calloc(1, sizeof(WsHardwareBuffer)))
		if buffer == nil { return -12 }
		buffer.bitmap = ws_window_bitmap(i32(desc.width), i32(desc.height))
		if buffer.bitmap == 0 { C.free(buffer); return -12 }
		if C.pthread_mutex_init(&buffer.mutex, nil) != 0 {
			ws_bitmap_unref(buffer.bitmap); C.free(buffer); return -12
		}
		buffer.references = 1
		buffer.desc = *desc
		buffer.desc.stride = desc.width
		*output = buffer
		return 0
	}
}

@[export: 'AHardwareBuffer_acquire']
pub fn ws_hardware_acquire(buffer &WsHardwareBuffer) {
	if buffer != unsafe { nil } { C.__atomic_add_fetch(&buffer.references, 1, 5) }
}

@[export: 'AHardwareBuffer_release']
pub fn ws_hardware_release(buffer &WsHardwareBuffer) {
	unsafe {
		if buffer == nil || C.__atomic_sub_fetch(&buffer.references, 1, 5) != 0 { return }
		ws_bitmap_unref(buffer.bitmap)
		C.pthread_mutex_destroy(&buffer.mutex)
		C.free(buffer)
	}
}

@[export: 'AHardwareBuffer_describe']
pub fn ws_hardware_describe(buffer &WsHardwareBuffer, desc &WsHardwareBufferDesc) {
	if buffer != unsafe { nil } && desc != unsafe { nil } { unsafe { *desc = buffer.desc } }
}

@[export: 'AHardwareBuffer_lock']
pub fn ws_hardware_lock(buffer &WsHardwareBuffer, usage u64, fence i32, rect &WsNativeRect, output &voidptr) i32 {
	if buffer == unsafe { nil } || output == unsafe { nil } || usage == 0 || usage & ~u64(0xff) != 0 { return -22 }
	if (usage & 15 != 0 && usage & 15 != 2 && usage & 15 != 3)
		|| (usage & 240 != 0 && usage & 240 != 32 && usage & 240 != 48) { return -22 }
	if fence >= 0 { return -38 }
	if (usage & 15 != 0 && buffer.desc.usage & 15 == 0)
		|| (usage & 240 != 0 && buffer.desc.usage & 240 == 0) { return -22 }
	if rect != unsafe { nil } && (rect.left < 0 || rect.top < 0 || rect.right < rect.left || rect.bottom < rect.top
		|| rect.right > i32(buffer.desc.width) || rect.bottom > i32(buffer.desc.height)) { return -22 }
	C.pthread_mutex_lock(&buffer.mutex)
	defer { C.pthread_mutex_unlock(&buffer.mutex) }
	if buffer.locked { return -16 }
	unsafe {
		buffer.locked = true
		*output = (&WsBitmap(buffer.bitmap)).rgba
	}
	return 0
}

@[export: 'AHardwareBuffer_lockPlanes']
pub fn ws_hardware_lock_planes(buffer &WsHardwareBuffer, usage u64, fence i32, rect &WsNativeRect, output &WsHardwareBufferPlanes) i32 {
	if output == unsafe { nil } { return -22 }
	unsafe { *output = WsHardwareBufferPlanes{} }
	mut pixels := unsafe { voidptr(nil) }
	result := ws_hardware_lock(buffer, usage, fence, rect, &pixels)
	if result != 0 { return result }
	unsafe {
		output.planes[0] = WsHardwareBufferPlane{
			data: pixels
			pixel_stride: 4
			row_stride: buffer.desc.stride * 4
		}
		output.count = 1
	}
	return 0
}

@[export: 'AHardwareBuffer_unlock']
pub fn ws_hardware_unlock(buffer &WsHardwareBuffer, fence &i32) i32 {
	if buffer == unsafe { nil } { return -22 }
	C.pthread_mutex_lock(&buffer.mutex)
	defer { C.pthread_mutex_unlock(&buffer.mutex) }
	if !buffer.locked { return -22 }
	unsafe {
		buffer.locked = false
		if fence != nil { *fence = -1 }
	}
	return 0
}
