// SPDX-License-Identifier: GPL-2.0-or-later
// Android NDK bitmap ABI over native WS's stable CPU pixel storage.
@[translated]
module atlframework

struct WsNdkBitmapInfo {
mut:
	width  u32
	height u32
	stride u32
	format i32
	flags  u32
}

fn ws_bitmap_put_long(e voidptr, bitmap voidptr, name &char, value i64) {
	f := field(e, c'android/graphics/Bitmap', name, c'J')
	if f != unsafe { nil } { unsafe { WsPutLong(slot(e, 110))(e, bitmap, f, value) } }
}

fn ws_bitmap_valid(e voidptr, bitmap voidptr) bool {
	if bitmap == unsafe { nil } || pending(e) { return false }
	if !instance_of(e, bitmap, c'android/graphics/Bitmap') { return false }
	return boolean(e, bitmap, c'android/graphics/Bitmap', c'isRecycled', c'()Z', unsafe { nil }) == 0 && !pending(e)
}

@[export: 'AndroidBitmap_getInfo']
pub fn ndk_bitmap_info(e voidptr, bitmap voidptr, info &WsNdkBitmapInfo) i32 {
	if info == unsafe { nil } || e == unsafe { nil } { return -1 }
	if !ws_bitmap_valid(e, bitmap) { return if pending(e) { i32(-2) } else { i32(-1) } }
	config := get_object(e, bitmap, c'android/graphics/Bitmap', c'config', c'Landroid/graphics/Bitmap$Config;')
	format := get_int(e, config, c'android/graphics/Bitmap$Config', c'android_memory_format')
	unsafe {
		*info = WsNdkBitmapInfo{
			width:  u32(get_int(e, bitmap, c'android/graphics/Bitmap', c'width'))
			height: u32(get_int(e, bitmap, c'android/graphics/Bitmap', c'height'))
			stride: u32(get_int(e, bitmap, c'android/graphics/Bitmap', c'stride'))
			format: format
			flags:  2 // RGBA bytes use straight alpha.
		}
		Drop(slot(e, 23))(e, config)
	}
	return if pending(e) { i32(-2) } else { i32(0) }
}

@[export: 'AndroidBitmap_lockPixels']
pub fn ndk_bitmap_lock(e voidptr, bitmap voidptr, output &voidptr) i32 {
	if e == unsafe { nil } || bitmap == unsafe { nil } || output == unsafe { nil } { return -1 }
	if pending(e) { return -2 }
	unsafe {
		if Monitor(slot(e, 217))(e, bitmap) != 0 { return -2 }
		defer { Monitor(slot(e, 218))(e, bitmap) }
		if !ws_bitmap_valid(e, bitmap) { return if pending(e) { i32(-2) } else { i32(-1) } }
		mut pointer := get_long(e, bitmap, c'android/graphics/Bitmap', c'vinixPixelLock')
		count := get_int(e, bitmap, c'android/graphics/Bitmap', c'vinixPixelLocks')
		if count == 0 {
			m := method(e, c'android/graphics/Bitmap', c'getTexture', c'()J')
			if m == nil { return -2 }
			pointer = WsLongCall(slot(e, 54))(e, bitmap, m, nil)
			if pending(e) { return -2 }
			if pointer == 0 { return -3 }
			ws_bitmap_ref(pointer)
			ws_bitmap_put_long(e, bitmap, c'vinixPixelLock', pointer)
		}
		put_int(e, bitmap, c'android/graphics/Bitmap', c'vinixPixelLocks', count + 1)
		*output = (&WsBitmap(pointer)).rgba
		return 0
	}
}

@[export: 'AndroidBitmap_unlockPixels']
pub fn ndk_bitmap_unlock(e voidptr, bitmap voidptr) i32 {
	if e == unsafe { nil } || bitmap == unsafe { nil } { return -1 }
	if pending(e) { return -2 }
	if !instance_of(e, bitmap, c'android/graphics/Bitmap') { return -1 }
	unsafe {
		if Monitor(slot(e, 217))(e, bitmap) != 0 { return -2 }
		defer { Monitor(slot(e, 218))(e, bitmap) }
		count := get_int(e, bitmap, c'android/graphics/Bitmap', c'vinixPixelLocks')
		if count <= 0 { return -1 }
		put_int(e, bitmap, c'android/graphics/Bitmap', c'vinixPixelLocks', count - 1)
		if count == 1 {
			pointer := get_long(e, bitmap, c'android/graphics/Bitmap', c'vinixPixelLock')
			ws_bitmap_put_long(e, bitmap, c'vinixPixelLock', 0)
			ws_bitmap_unref(pointer)
		}
		return 0
	}
}
