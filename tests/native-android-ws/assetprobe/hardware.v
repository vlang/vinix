// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module assetprobe

struct HardwarePlane {
mut:
	data voidptr
	pixel_stride u32
	row_stride u32
}

struct HardwarePlanes {
mut:
	count u32
	planes [4]HardwarePlane
}

union HardwareValue {
mut:
	l voidptr
	i i32
	j i64
}

type HardwareLookup = fn (voidptr, &char) voidptr
type HardwareMember = fn (voidptr, voidptr, &char, &char) voidptr
type HardwareIntCall = fn (voidptr, voidptr, voidptr, &HardwareValue) i32
type HardwareLongCall = fn (voidptr, voidptr, voidptr, &HardwareValue) i64
type HardwareBoolCall = fn (voidptr, voidptr, voidptr, &HardwareValue) u8
type HardwareObjectCall = fn (voidptr, voidptr, voidptr, &HardwareValue) voidptr
type HardwareVoidCall = fn (voidptr, voidptr, voidptr, &HardwareValue)
type HardwareDrop = fn (voidptr, voidptr)
type HardwareClear = fn (voidptr)
type HardwareException = fn (voidptr) voidptr
type HardwareInstance = fn (voidptr, voidptr, voidptr) u8

fn C.AHardwareBuffer_lockPlanes(voidptr, u64, i32, &NativeRect, &HardwarePlanes) i32
fn C.AHardwareBuffer_toHardwareBuffer(voidptr, voidptr) voidptr
fn C.AHardwareBuffer_fromHardwareBuffer(voidptr, voidptr) voidptr

fn hardware_slot(e voidptr, index int) voidptr {
	unsafe { return (&voidptr(*(&voidptr(e))))[index] }
}

fn hardware_close(e voidptr, class voidptr, wrapper voidptr) {
	unsafe {
		if wrapper == nil { return }
		close := HardwareMember(hardware_slot(e, 33))(e, class, c'close', c'()V')
		HardwareVoidCall(hardware_slot(e, 63))(e, wrapper, close, nil)
		HardwareDrop(hardware_slot(e, 23))(e, wrapper)
	}
}

fn hardware_exception(e voidptr, name &char) bool {
	unsafe {
		ex := HardwareException(hardware_slot(e, 15))(e)
		if ex == nil { return false }
		HardwareClear(hardware_slot(e, 17))(e)
		class := HardwareLookup(hardware_slot(e, 6))(e, name)
		valid := class != nil && HardwareInstance(hardware_slot(e, 32))(e, ex, class) != 0
		HardwareDrop(hardware_slot(e, 23))(e, ex)
		if class != nil { HardwareDrop(hardware_slot(e, 23))(e, class) }
		return valid
	}
}

fn hardware_planes_check(buffer voidptr) bool {
	unsafe {
		planes := &HardwarePlanes(C.alloca(sizeof(HardwarePlanes)))
		*planes = HardwarePlanes{count: 99}
		if sizeof(HardwarePlane) != 16 || sizeof(HardwarePlanes) != 72 { return false }
		mut rect := NativeRect{left: 2, top: 1, right: 6, bottom: 3}
		if C.AHardwareBuffer_lockPlanes(buffer, 0x30, -2, &rect, planes) != 0
			|| planes.count != 1 || planes.planes[0].data == nil
			|| planes.planes[0].pixel_stride != 4 || planes.planes[0].row_stride != 28
			|| planes.planes[1].data != nil { return false }
		pixels := &u8(planes.planes[0].data)
		pixels[0] = 0x42
		pixels[2 * 28 + 6 * 4 + 3] = 0xa7
		busy := &HardwarePlanes(C.alloca(sizeof(HardwarePlanes)))
		*busy = HardwarePlanes{count: 99}
		if C.AHardwareBuffer_lockPlanes(buffer, 3, -1, nil, busy) != -16 || busy.count != 0 { return false }
		mut fence := i32(99)
		if C.AHardwareBuffer_unlock(buffer, &fence) != 0 || fence != -1 { return false }
		rect.right = 8
		planes.count = 99
		if C.AHardwareBuffer_lockPlanes(buffer, 3, -1, &rect, planes) != -22 || planes.count != 0 { return false }
		planes.count = 99
		if C.AHardwareBuffer_lockPlanes(buffer, 3, 0, nil, planes) != -38 || planes.count != 0 { return false }
		if C.AHardwareBuffer_lockPlanes(buffer, 0x100, -1, nil, planes) != -22 || planes.count != 0 { return false }
		mut raw := voidptr(nil)
		if C.AHardwareBuffer_lock(buffer, 3, -1, nil, &raw) != 0 { return false }
		valid := (&u8(raw))[0] == 0x42 && (&u8(raw))[2 * 28 + 6 * 4 + 3] == 0xa7
		return C.AHardwareBuffer_unlock(buffer, nil) == 0 && valid
	}
}

fn hardware_java_check(e voidptr, wrong_type voidptr) bool {
	unsafe {
		class := HardwareLookup(hardware_slot(e, 6))(e, c'android/hardware/HardwareBuffer')
		if class == nil { return false }
		defer { HardwareDrop(hardware_slot(e, 23))(e, class) }
		width := HardwareMember(hardware_slot(e, 33))(e, class, c'getWidth', c'()I')
		height := HardwareMember(hardware_slot(e, 33))(e, class, c'getHeight', c'()I')
		format := HardwareMember(hardware_slot(e, 33))(e, class, c'getFormat', c'()I')
		layers := HardwareMember(hardware_slot(e, 33))(e, class, c'getLayers', c'()I')
		usage := HardwareMember(hardware_slot(e, 33))(e, class, c'getUsage', c'()J')
		closed := HardwareMember(hardware_slot(e, 33))(e, class, c'isClosed', c'()Z')
		close := HardwareMember(hardware_slot(e, 33))(e, class, c'close', c'()V')
		create := HardwareMember(hardware_slot(e, 113))(e, class, c'create', c'(IIIIJ)Landroid/hardware/HardwareBuffer;')
		supported := HardwareMember(hardware_slot(e, 113))(e, class, c'isSupported', c'(IIIIJ)Z')
		if width == nil || height == nil || format == nil || layers == nil || usage == nil
			|| closed == nil || close == nil || create == nil || supported == nil { return false }
		if C.AHardwareBuffer_fromHardwareBuffer(e, nil) != nil
			|| C.AHardwareBuffer_fromHardwareBuffer(e, wrong_type) != nil
			|| C.AHardwareBuffer_toHardwareBuffer(e, nil) != nil { return false }
		mut desc := HardwareDesc{width: 7, height: 3, format: 1, layers: 1, usage: 0x33}
		mut owner := voidptr(nil)
		if C.AHardwareBuffer_allocate(&desc, &owner) != 0 { return false }
		defer { if owner != nil { C.AHardwareBuffer_release(owner) } }
		if !hardware_planes_check(owner) { return false }
		first := C.AHardwareBuffer_toHardwareBuffer(e, owner)
		if first == nil { return false }
		defer { hardware_close(e, class, first) }
		second := C.AHardwareBuffer_toHardwareBuffer(e, owner)
		if second == nil { return false }
		defer { hardware_close(e, class, second) }
		if C.AHardwareBuffer_fromHardwareBuffer(e, first) != owner
			|| C.AHardwareBuffer_fromHardwareBuffer(e, second) != owner { return false }
		C.AHardwareBuffer_release(owner)
		owner = nil // Only the two Java wrappers now own the allocation.
		if HardwareIntCall(hardware_slot(e, 51))(e, first, width, nil) != 7
			|| HardwareIntCall(hardware_slot(e, 51))(e, first, height, nil) != 3
			|| HardwareIntCall(hardware_slot(e, 51))(e, first, format, nil) != 1
			|| HardwareIntCall(hardware_slot(e, 51))(e, first, layers, nil) != 1
			|| HardwareLongCall(hardware_slot(e, 54))(e, first, usage, nil) != 0x33
			|| HardwareBoolCall(hardware_slot(e, 39))(e, first, closed, nil) != 0 { return false }
		HardwareVoidCall(hardware_slot(e, 63))(e, first, close, nil)
		HardwareVoidCall(hardware_slot(e, 63))(e, first, close, nil)
		if HardwareBoolCall(hardware_slot(e, 39))(e, first, closed, nil) != 1
			|| C.AHardwareBuffer_fromHardwareBuffer(e, first) != nil
			|| HardwareIntCall(hardware_slot(e, 51))(e, second, width, nil) != 7 { return false }
		HardwareIntCall(hardware_slot(e, 51))(e, first, width, nil)
		if !hardware_exception(e, c'java/lang/IllegalStateException') { return false }
		borrowed := C.AHardwareBuffer_fromHardwareBuffer(e, second)
		if borrowed == nil { return false }
		C.AHardwareBuffer_acquire(borrowed)
		defer { C.AHardwareBuffer_release(borrowed) }
		HardwareVoidCall(hardware_slot(e, 63))(e, second, close, nil)
		mut pixels := voidptr(nil)
		if C.AHardwareBuffer_lock(borrowed, 3, -1, nil, &pixels) != 0 { return false }
		valid := (&u8(pixels))[0] == 0x42 && (&u8(pixels))[2 * 28 + 6 * 4 + 3] == 0xa7
		if C.AHardwareBuffer_unlock(borrowed, nil) != 0 || !valid { return false }
		mut args := [HardwareValue{i: 7}, HardwareValue{i: 3}, HardwareValue{i: 1}, HardwareValue{i: 1}, HardwareValue{j: 0x33}]!
		if HardwareBoolCall(hardware_slot(e, 119))(e, class, supported, &args[0]) != 1 { return false }
		created := HardwareObjectCall(hardware_slot(e, 116))(e, class, create, &args[0])
		if created == nil { return false }
		defer { hardware_close(e, class, created) }
		native := C.AHardwareBuffer_fromHardwareBuffer(e, created)
		if native == nil { return false }
		C.AHardwareBuffer_describe(native, &desc)
		if desc.width != 7 || desc.height != 3 || desc.usage != 0x33 { return false }
		args[4].j = 0x100 // Unsupported GPU allocation must fail, never fake success.
		if HardwareBoolCall(hardware_slot(e, 119))(e, class, supported, &args[0]) != 0
			|| HardwareObjectCall(hardware_slot(e, 116))(e, class, create, &args[0]) != nil
			|| !hardware_exception(e, c'java/lang/IllegalArgumentException') { return false }
		args[0].i = -1
		args[4].j = 0x33
		if HardwareObjectCall(hardware_slot(e, 116))(e, class, create, &args[0]) != nil
			|| !hardware_exception(e, c'java/lang/IllegalArgumentException') { return false }
		C.puts(c'BOOTSTRAP-HARDWARE-BUFFER-PASS planes strides shared-pixels Java NDK close acquired-lifetime')
		return true
	}
}
