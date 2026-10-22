// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftSharedUTF8Failure {}
fn (_ &SwiftSharedUTF8Failure) msg() string { return 'iOS: unsupported or invalid shared Swift UTF8 storage' }
fn (_ &SwiftSharedUTF8Failure) code() int { return 1 }
__global swift_shared_utf8_failure_value = SwiftSharedUTF8Failure{}
fn swift_shared_utf8_failure() IError { return unsafe { &swift_shared_utf8_failure_value } }
type SwiftSharedCString = fn (u64, &char, bool) u64

// ARM64 borrows Self in x0/x1 and returns start/count in x0/x1. No retain,
// conversion or payload copy occurs. The caller keeps the immutable owner and
// its initialized backing allocation alive for the entire buffer borrow.
fn swift_shared_utf8_checked(first u64, second u64) !SwiftStringBytes {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired
		|| first & ~(swift_count_mask | u64(0xc000000000000000)) != 0 {
		return swift_shared_utf8_failure()
	}
	discriminator := second >> 60
	if discriminator != 0 && discriminator != 4 && discriminator != 12 { return swift_shared_utf8_failure() }
	owner := second & swift_address_mask
	count := first & swift_count_mask
	mut address := u64(0)
	mut imp := u64(0)
	C.ios_objc_initialize_lock()
	if discriminator == 0 {
		// SharedStringStorage's start/count fields differ from tail String
		// storage. Only registered, live Swift allocations of sufficient extent
		// may supply these fields; their initialized payload is caller-owned.
		if storage := ios_runtime.swift_heap[owner] {
			if !storage.deiniting && storage.size >= 40 && read64(owner + 8) & u64(0x100000000) == 0
				&& read64(owner + 32) == first { address = read64(owner + 24) }
		}
	} else if owner in ios_runtime.objects || owner in ios_runtime.constants {
		if objc_is_kind(owner, ios_runtime.names['NSString']) {
			if discriminator == 12 {
				// Constant Cocoa is UTF-8, not the loader's decoded UTF-16 cache.
				if owner in ios_runtime.constants && read32(owner + 8) == 0x7c8
					&& read64(owner + 24) == count { address = read64(owner + 16) }
			} else {
				mut live := !mutable_string_family(read64(owner))
				if header := ios_runtime.objects[owner] {
					// A retain cannot keep a mutable backing buffer stable. Also reject
					// original mutable allocations after an isa replacement.
					live = live && !header.mutable_string_owned && C.ios_ref_change(unsafe { &header.refs }, 0) > 0 && !header.destroying && !header.destroyed
				}
				if live {
					imp = native_method(read64(owner), '_fastCStringContents:')
					if imp == 0 {
						// The ordinary NSString fast path provides stable ASCII. Custom
						// subclasses can implement the selector and supply UTF-8.
						if text := swift_foreign_count_text(owner) {
							mut ascii := true
							for byte in text { if byte >= 128 { ascii = false; break } }
							if ascii && u64(text.len) == count {
								if header := ios_runtime.objects[owner] { address = u64(header.text) }
								else if read32(owner + 8) == 0x7c8 { address = read64(owner + 16) }
							}
						}
					}
				}
			}
		}
	}
	C.ios_objc_initialize_unlock()
	// A subclass callback must be able to reenter lookup on another thread.
	// It returns borrowed, NUL-terminated storage; do not inspect or free it.
	if imp != 0 { address = unsafe { SwiftSharedCString(voidptr(imp))(owner, c'_fastCStringContents:', true) } }
	if address == 0 { return swift_shared_utf8_failure() }
	return SwiftStringBytes{address, count}
}
fn swift_shared_utf8(first u64, second u64) SwiftStringBytes {
	return swift_shared_utf8_checked(first, second) or { panic(err) }
}
fn swift_shared_utf8_start(first u64, second u64) u64 {
	return swift_shared_utf8(first, second).address
}
