// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.opendir(&char) voidptr
fn C.closedir(voidptr) i32
fn C.ios_readdir_info(voidptr, &char, &u64) i32

struct DarwinDirectory {
mut:
	native voidptr
	// Apple ARM64: ino64, seekoff64, reclen16, namlen16, type8, name[1024].
	entry [1048]u8
}

fn darwin_opendir(path &char) voidptr {
	native := C.opendir(path)
	if native == unsafe { nil } { return native }
	mut directory := unsafe { &DarwinDirectory(C.calloc(1, sizeof(DarwinDirectory))) }
	if directory == unsafe { nil } { C.closedir(native); darwin_set_errno(12); return unsafe { nil } }
	directory.native = native
	return directory
}

fn darwin_readdir(pointer voidptr) voidptr {
	if pointer == unsafe { nil } { darwin_set_errno(9); return unsafe { nil } }
	mut directory := unsafe { &DarwinDirectory(pointer) }
	mut values := [4]u64{}
	base := u64(unsafe { &directory.entry[0] })
	result := C.ios_readdir_info(directory.native, unsafe { &char(base + 21) }, unsafe { &values[0] })
	if result <= 0 {
		if result < 0 { darwin_set_errno(63) }
		return unsafe { nil }
	}
	unsafe {
		*(&u64(base)) = values[0]
		*(&u64(base + 8)) = values[1]
		*(&u16(base + 16)) = u16((21 + values[3] + 1 + 7) & ~u64(7))
		*(&u16(base + 18)) = u16(values[3])
		*(&u8(base + 20)) = u8(values[2])
	}
	return unsafe { voidptr(base) }
}

fn darwin_closedir(pointer voidptr) i32 {
	if pointer == unsafe { nil } { darwin_set_errno(9); return -1 }
	directory := unsafe { &DarwinDirectory(pointer) }
	result := C.closedir(directory.native)
	C.free(pointer)
	return result
}
