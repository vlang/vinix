// SPDX-License-Identifier: GPL-2.0-or-later
// Share the immutable framework archive. The C facade returns process-lived
// const ApkAssets without a release API; resource managers already borrow it.
@[translated]
module atlframework

#include <sys/statvfs.h>

struct C.statvfs {
	f_flag u64
}
fn C.stat(&char, &C.stat) i32
fn C.statvfs(&char, &C.statvfs) i32
fn C.memcmp(voidptr, voidptr, usize) i32

struct WsFrameworkApkStamp {
	device u64
	inode u64
	size i64
	modified i64
	modified_ns i64
	changed i64
	changed_ns i64
}

@[cinit]
__global ws_framework_apk_mutex C.pthread_mutex_t = C.PTHREAD_MUTEX_INITIALIZER
__global ws_framework_apk_handle voidptr
__global ws_framework_apk_stamp WsFrameworkApkStamp
__global ws_framework_apk_reported bool

fn ws_framework_apk_selected(path &char) bool {
	unsafe {
		if ws.root == nil || path == nil { return false }
		length := C.strlen(ws.root)
		if length == 0 || C.strlen(path) <= length { return false }
		return C.memcmp(path, ws.root, length) == 0
			&& C.strcmp(&path[length], c'/usr/lib/java/dex/android_translation_layer/framework-res.apk') == 0
	}
}

fn ws_framework_apk_read_stamp(path &char, output &WsFrameworkApkStamp) bool {
	unsafe {
		mut info := C.stat{}
		mut mount := C.statvfs{}
		if C.stat(path, &info) != 0 || info.st_mode & 0o170000 != 0o100000
			|| info.st_uid != 0 || info.st_size <= 0
			|| C.statvfs(path, &mount) != 0 || mount.f_flag & u64(C.ST_RDONLY) == 0 {
			return false
		}
		mut observed := WsFrameworkApkStamp{device: info.st_dev, inode: info.st_ino, size: info.st_size}
		$if macos {
			observed.modified = info.st_mtimespec.tv_sec
			observed.modified_ns = info.st_mtimespec.tv_nsec
			observed.changed = info.st_ctimespec.tv_sec
			observed.changed_ns = info.st_ctimespec.tv_nsec
		} $else {
			observed.modified = info.st_mtim.tv_sec
			observed.modified_ns = info.st_mtim.tv_nsec
			observed.changed = info.st_ctim.tv_sec
			observed.changed_ns = info.st_ctim.tv_nsec
		}
		*output = observed
		return true
	}
}

fn ws_load_apk_file(path &char) voidptr {
	unsafe {
		// Mutable app/module APKs retain their existing load behavior.
		if !ws_framework_apk_selected(path) { return voidptr(C.ApkAssets_load(path, false)) }
		if C.pthread_mutex_lock(&ws_framework_apk_mutex) != 0 { C.abort() }
		defer { if C.pthread_mutex_unlock(&ws_framework_apk_mutex) != 0 { C.abort() } }
		mut before := WsFrameworkApkStamp{}
		eligible := ws_framework_apk_read_stamp(path, &before)
		if eligible && ws_framework_apk_handle != nil && ws_framework_apk_stamp == before {
			if !ws_framework_apk_reported {
				message := &char(c'ANDROID-FRAMEWORK-APK-CACHE-HIT\n')
				C.write(2, message, C.strlen(message))
				ws_framework_apk_reported = true
			}
			return ws_framework_apk_handle
		}
		handle := voidptr(C.ApkAssets_load(path, false))
		mut after := WsFrameworkApkStamp{}
		if handle != nil && eligible && ws_framework_apk_read_stamp(path, &after) && before == after {
			ws_framework_apk_stamp = after
			ws_framework_apk_handle = handle
		}
		// Old objects remain alive for managers/string pools that still borrow
		// them. Never free one or publish a failed/racing load into the cache.
		return handle
	}
}
