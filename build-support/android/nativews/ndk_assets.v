// SPDX-License-Identifier: GPL-2.0-or-later
// NDK asset handles share the same libandroidfw provider as Java resources.
@[translated]
module atlframework

#define _LARGEFILE64_SOURCE
#include "androidfw_c_api.h"

fn C.Asset_openFileDescriptor(voidptr, &i64, &i64) i32

@[export: 'AAssetManager_fromJava']
pub fn ndk_asset_manager(e voidptr, manager voidptr) voidptr {
	if manager == unsafe { nil } || pending(e) { return unsafe { nil } }
	return ws_manager(e, manager)
}

@[export: 'AAssetManager_open']
pub fn ndk_asset_open(manager voidptr, name &char, mode i32) voidptr {
	unsafe {
		if manager == nil || name == nil { return nil }
		length := C.strlen(name) + 8
		path := &char(C.malloc(length))
		if path == nil { return nil }
		C.snprintf(path, length, c'assets/%s', name)
		asset := C.AssetManager_openNonAsset(manager, path, mode)
		C.free(path)
		return asset
	}
}

@[export: 'AAsset_close']
pub fn ndk_asset_close(asset voidptr) { C.Asset_delete(asset) }

@[export: 'AAsset_read']
pub fn ndk_asset_read(asset voidptr, buffer voidptr, count usize) i32 {
	return i32(C.Asset_read(asset, buffer, count))
}

@[export: 'AAsset_seek']
pub fn ndk_asset_seek(asset voidptr, offset i64, whence i32) i64 {
	return C.Asset_seek(asset, offset, whence)
}

@[export: 'AAsset_seek64']
pub fn ndk_asset_seek64(asset voidptr, offset i64, whence i32) i64 {
	return C.Asset_seek(asset, offset, whence)
}

@[export: 'AAsset_getLength']
pub fn ndk_asset_length(asset voidptr) i64 { return i64(C.Asset_getLength(asset)) }

@[export: 'AAsset_getLength64']
pub fn ndk_asset_length64(asset voidptr) i64 { return i64(C.Asset_getLength(asset)) }

@[export: 'AAsset_getRemainingLength']
pub fn ndk_asset_remaining(asset voidptr) i64 { return i64(C.Asset_getRemainingLength(asset)) }

@[export: 'AAsset_getRemainingLength64']
pub fn ndk_asset_remaining64(asset voidptr) i64 { return i64(C.Asset_getRemainingLength(asset)) }

@[export: 'AAsset_getBuffer']
pub fn ndk_asset_buffer(asset voidptr) voidptr { return voidptr(C.Asset_getBuffer(asset, true)) }

@[export: 'AAsset_openFileDescriptor']
pub fn ndk_asset_fd(asset voidptr, start &i64, length &i64) i32 {
	return C.Asset_openFileDescriptor(asset, start, length)
}

@[export: 'AAsset_openFileDescriptor64']
pub fn ndk_asset_fd64(asset voidptr, start &i64, length &i64) i32 {
	return C.Asset_openFileDescriptor(asset, start, length)
}
