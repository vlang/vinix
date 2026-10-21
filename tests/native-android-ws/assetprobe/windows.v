// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module assetprobe

fn C.alloca(usize) voidptr

struct NativeBuffer {
mut:
	width i32
	height i32
	stride i32
	format i32
	bits voidptr
	reserved [6]u32
}

struct NativeRect {
mut:
	left i32
	top i32
	right i32
	bottom i32
}

struct HardwareDesc {
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

fn C.ANativeWindow_fromSurface(voidptr, voidptr) voidptr
fn C.ANativeWindow_acquire(voidptr)
fn C.ANativeWindow_release(voidptr)
fn C.ANativeWindow_getWidth(voidptr) i32
fn C.ANativeWindow_getHeight(voidptr) i32
fn C.ANativeWindow_getFormat(voidptr) i32
fn C.ANativeWindow_getBuffersDataSpace(voidptr) i32
fn C.ANativeWindow_setBuffersGeometry(voidptr, i32, i32, i32) i32
fn C.ANativeWindow_lock(voidptr, &NativeBuffer, &NativeRect) i32
fn C.ANativeWindow_unlockAndPost(voidptr) i32
fn C.AHardwareBuffer_allocate(&HardwareDesc, &voidptr) i32
fn C.AHardwareBuffer_isSupported(&HardwareDesc) i32
fn C.AHardwareBuffer_acquire(voidptr)
fn C.AHardwareBuffer_release(voidptr)
fn C.AHardwareBuffer_describe(voidptr, &HardwareDesc)
fn C.AHardwareBuffer_lock(voidptr, u64, i32, &NativeRect, &voidptr) i32
fn C.AHardwareBuffer_unlock(voidptr, &i32) i32
fn C.AChoreographer_getInstance() voidptr
fn C.AChoreographer_postFrameCallback64(voidptr, voidptr, voidptr)
fn C.puts(&char) i32
fn C.abort()

__global frame_stage i32
__global frame_time i64

fn frame_callback(time i64, choreographer voidptr) {
	unsafe {
		if time <= frame_time { C.abort() }
		frame_time = time
		frame_stage++
		if frame_stage == 1 {
			C.AChoreographer_postFrameCallback64(choreographer, voidptr(frame_callback), choreographer)
		} else if frame_stage == 2 {
			C.puts(c'BOOTSTRAP-NATIVE-FRAMES-PASS deferred one-shot reschedule monotonic')
		} else { C.abort() }
	}
}

fn hardware_check() bool {
	unsafe {
		mut desc := HardwareDesc{width: 7, height: 3, layers: 1, format: 1, usage: 0x33}
		mut buffer := voidptr(nil)
		if C.AHardwareBuffer_isSupported(&desc) != 1 || C.AHardwareBuffer_allocate(&desc, &buffer) != 0 || buffer == nil { return false }
		defer { C.AHardwareBuffer_release(buffer) }
		C.AHardwareBuffer_acquire(buffer)
		C.AHardwareBuffer_release(buffer)
		mut actual := HardwareDesc{}
		C.AHardwareBuffer_describe(buffer, &actual)
		if actual.width != 7 || actual.height != 3 || actual.layers != 1 || actual.stride != 7 || actual.format != 1 || actual.usage != 0x33 { return false }
		mut pixels := voidptr(nil)
		mut other := voidptr(nil)
		if C.AHardwareBuffer_lock(buffer, 0x30, -1, nil, &pixels) != 0 || pixels == nil { return false }
		(&u8(pixels))[0] = 0x42
		busy := C.AHardwareBuffer_lock(buffer, 3, -1, nil, &other)
		mut fence := i32(55)
		if C.AHardwareBuffer_unlock(buffer, &fence) != 0 || fence != -1 || busy != -16 { return false }
		if C.AHardwareBuffer_lock(buffer, 3, -1, nil, &pixels) != 0 { return false }
		valid := (&u8(pixels))[0] == 0x42
		if C.AHardwareBuffer_unlock(buffer, nil) != 0 || !valid || C.AHardwareBuffer_unlock(buffer, nil) != -22 { return false }
		desc.usage = 0x100 // GPU sampling must not be reported supported.
		return C.AHardwareBuffer_isSupported(&desc) == 0
			&& C.AHardwareBuffer_allocate(&desc, &other) == -22 && other == nil
	}
}

@[export: 'Java_org_vinix_bootstrap_Main_nativeWindow']
pub fn window_check(e voidptr, class voidptr, surface voidptr) u8 {
	unsafe {
		window := C.ANativeWindow_fromSurface(e, surface)
		if window == nil { return 0 }
		defer { C.ANativeWindow_release(window) }
		same := C.ANativeWindow_fromSurface(e, surface)
		if same != window { C.ANativeWindow_release(same); return 0 }
		C.ANativeWindow_release(same)
		C.ANativeWindow_acquire(window)
		C.ANativeWindow_release(window)
		if C.ANativeWindow_getWidth(window) != 32 || C.ANativeWindow_getHeight(window) != 24
			|| C.ANativeWindow_getFormat(window) != 1 || C.ANativeWindow_getBuffersDataSpace(window) != 0 { return 0 }
		if C.ANativeWindow_setBuffersGeometry(window, 8, 4, 1) != 0
			|| C.ANativeWindow_getWidth(window) != 8 || C.ANativeWindow_getHeight(window) != 4
			|| C.ANativeWindow_setBuffersGeometry(window, 8, 0, 1) != -22
			|| C.ANativeWindow_setBuffersGeometry(window, 8, 4, 4) != -22 { return 0 }
		buffer := &NativeBuffer(C.alloca(sizeof(NativeBuffer)))
		other := &NativeBuffer(C.alloca(sizeof(NativeBuffer)))
		*buffer = NativeBuffer{}
		*other = NativeBuffer{}
		mut dirty := NativeRect{right: 1, bottom: 1}
		if C.ANativeWindow_lock(window, buffer, &dirty) != 0 { return 0 }
		valid := buffer.width == 8 && buffer.height == 4 && buffer.stride == 8 && buffer.format == 1
			&& buffer.bits != nil && dirty.left == 0 && dirty.top == 0 && dirty.right == 8 && dirty.bottom == 4
			&& C.ANativeWindow_lock(window, other, nil) == -16
			&& C.ANativeWindow_setBuffersGeometry(window, 32, 24, 1) == -16
		if buffer.bits != nil {
			pixels := &u8(buffer.bits)
			for y := 0; y < 4; y++ {
				for x := 0; x < 8; x++ {
					offset := (y * 8 + x) * 4
					pixels[offset] = u8(x * 32)
					pixels[offset + 1] = u8(y * 64)
					pixels[offset + 2] = 128
					pixels[offset + 3] = 255
				}
			}
		}
		if C.ANativeWindow_unlockAndPost(window) != 0 || !valid
			|| C.ANativeWindow_unlockAndPost(window) != -22
			|| C.ANativeWindow_setBuffersGeometry(window, 0, 0, 0) != 0
			|| C.ANativeWindow_getWidth(window) != 32 || C.ANativeWindow_getHeight(window) != 24 { return 0 }
		if !hardware_check() { return 0 }
		choreographer := C.AChoreographer_getInstance()
		if choreographer == nil { return 0 }
		C.AChoreographer_postFrameCallback64(choreographer, voidptr(frame_callback), choreographer)
		return u8(frame_stage == 0)
	}
}
