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
