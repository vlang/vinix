// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftPointerDeinitFailure {}
fn (_ &SwiftPointerDeinitFailure) msg() string { return 'iOS: unsupported Swift pointer destruction layout' }
fn (_ &SwiftPointerDeinitFailure) code() int { return 1 }
__global swift_pointer_deinit_failure_value = SwiftPointerDeinitFailure{}
fn swift_pointer_deinit_failure() IError { return unsafe { &swift_pointer_deinit_failure_value } }

// Ordinary ARM64 runtime entry: pointer x0, unsigned count x1, Element x2.
// Zero count reads nothing; POD values read no payload or destroy witness.
// Other types require only size/stride/alignment and a callable destroy slot,
// including noncopyable types with no usable copy/take/enum-tag operations.
fn swift_array_destroy_elements_checked(pointer u64, count u64, metadata u64) ! {
	if count == 0 { return }
	if metadata < 8 || metadata & 7 != 0 { return swift_pointer_deinit_failure() }
	witness := read64(metadata - 8)
	if witness == 0 || witness & 7 != 0 { return swift_pointer_deinit_failure() }
	flags := read32(witness + 80)
	if flags & 0x00400000 != 0 { return swift_pointer_deinit_failure() }
	if flags & 0x10000 == 0 { return }
	size := read64(witness + 64); stride := read64(witness + 72)
	alignment := u64(flags & 255) + 1; destroy := read64(witness + 8)
	if stride == 0 || size > stride || alignment & (alignment - 1) != 0
		|| stride & (alignment - 1) != 0 || destroy == 0 || destroy & 3 != 0
		|| pointer == 0 || pointer & (alignment - 1) != 0
		|| pointer > u64(-1) - size || count - 1 > (u64(-1) - pointer - size) / stride {
		return swift_pointer_deinit_failure()
	}
	call := unsafe { SwiftElementDestroy(voidptr(destroy)) }
	for i in u64(0) .. count { call(pointer + i * stride, metadata) }
}

fn swift_array_destroy_elements(pointer u64, count u64, metadata u64) {
	swift_array_destroy_elements_checked(pointer, count, metadata) or { panic(err) }
}

// Swift method: signed count x0, raw Self x1, Pointee metadata x2. Return the
// same raw pointer in x0; destruction neither zeroes nor frees its storage.
fn swift_pointer_deinitialize_checked(count i64, pointer u64, metadata u64) !u64 {
	if count < 0 { return swift_pointer_deinit_failure() }
	swift_array_destroy_elements_checked(pointer, u64(count), metadata)!
	return pointer
}
fn swift_pointer_deinitialize(count i64, pointer u64, metadata u64) u64 {
	return swift_pointer_deinitialize_checked(count, pointer, metadata) or { panic(err) }
}
