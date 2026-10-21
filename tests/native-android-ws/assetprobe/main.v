// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module assetprobe

fn C.AAssetManager_fromJava(voidptr, voidptr) voidptr
fn C.AAssetManager_open(voidptr, &char, i32) voidptr
fn C.AAsset_getLength64(voidptr) i64
fn C.AAsset_getRemainingLength64(voidptr) i64
fn C.AAsset_read(voidptr, voidptr, usize) i32
fn C.AAsset_seek64(voidptr, i64, i32) i64
fn C.AAsset_close(voidptr)

struct BitmapInfo {
mut:
	width u32
	height u32
	stride u32
	format i32
	flags u32
}

fn C.AndroidBitmap_getInfo(voidptr, voidptr, &BitmapInfo) i32
fn C.AndroidBitmap_lockPixels(voidptr, voidptr, &voidptr) i32
fn C.AndroidBitmap_unlockPixels(voidptr, voidptr) i32
fn C.eglGetCurrentDisplay() voidptr
fn C.eglGetCurrentContext() voidptr
fn C.eglGetCurrentSurface(i32) voidptr
fn C.eglGetProcAddress(&char) voidptr
fn C.eglGetError() i32
fn C.eglInitialize(voidptr, &i32, &i32) u32

@[export: 'Java_org_vinix_bootstrap_Main_nativeGraphics']
pub fn graphics_check(e voidptr, class voidptr) u8 {
	unsafe {
		if C.eglGetCurrentDisplay() != nil || C.eglGetCurrentContext() != nil
			|| C.eglGetCurrentSurface(0x3059) != nil || C.eglGetError() != 0x3000 { return 0 }
		if C.eglGetProcAddress(c'glCreateShader') == nil
			|| C.eglGetProcAddress(c'glEGLImageTargetTexture2DOES') == nil { return 0 }
		C.eglGetCurrentSurface(0)
		if C.eglGetError() != 0x300c || C.eglGetError() != 0x3000 { return 0 }
		mut major, mut minor := i32(-9), i32(-8)
		if C.eglInitialize(nil, &major, &minor) != 0 || C.eglGetError() != 0x3008
			|| major != -9 || minor != -8 || C.eglGetError() != 0x3000 { return 0 }
		return 1
	}
}

@[export: 'Java_org_vinix_bootstrap_Main_nativeBitmap']
pub fn bitmap_check(e voidptr, class voidptr, bitmap voidptr) u8 {
	unsafe {
		mut info := BitmapInfo{}
		if C.AndroidBitmap_getInfo(e, bitmap, &info) != 0 || info.width != 2
			|| info.height != 1 || info.stride != 8 || info.format != 1 || info.flags != 2 { return 0 }
		mut first := voidptr(nil)
		mut second := voidptr(nil)
		if C.AndroidBitmap_lockPixels(e, bitmap, &first) != 0 { return 0 }
		if C.AndroidBitmap_lockPixels(e, bitmap, &second) != 0 {
			C.AndroidBitmap_unlockPixels(e, bitmap)
			return 0
		}
		pixels := &u8(first)
		valid := first == second && pixels[0] == 255 && pixels[1] == 0
			&& pixels[2] == 0 && pixels[3] == 255 && pixels[4] == 0
			&& pixels[5] == 255 && pixels[6] == 0 && pixels[7] == 255
		one := C.AndroidBitmap_unlockPixels(e, bitmap)
		two := C.AndroidBitmap_unlockPixels(e, bitmap)
		extra := C.AndroidBitmap_unlockPixels(e, bitmap)
		return u8(valid && one == 0 && two == 0 && extra == -1)
	}
}

@[export: 'Java_org_vinix_bootstrap_Main_nativeCheck']
pub fn check(e voidptr, class voidptr, java_assets voidptr) u8 {
	unsafe {
		manager := C.AAssetManager_fromJava(e, java_assets)
		asset := C.AAssetManager_open(manager, c'probe.txt', 2)
		if asset == nil { return 0 }
		mut bytes := [16]u8{}
		valid := C.AAsset_getLength64(asset) == 15
			&& C.AAsset_read(asset, &bytes[0], 5) == 5
			&& bytes[0] == `V` && bytes[4] == `X`
			&& C.AAsset_getRemainingLength64(asset) == 10
			&& C.AAsset_seek64(asset, -3, 2) == 12
			&& C.AAsset_read(asset, &bytes[0], 16) == 3
			&& bytes[0] == `O` && bytes[1] == `K` && bytes[2] == `\n`
			&& C.AAsset_read(asset, &bytes[0], 1) == 0
		C.AAsset_close(asset)
		return u8(valid)
	}
}
