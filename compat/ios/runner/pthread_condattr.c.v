// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn pthread_condattr_valid(attributes u64) bool {
	return attributes != 0 && read64(attributes) == 0x434e4441
}

fn darwin_condattr_init(attributes u64) i32 {
	if attributes == 0 { return 22 }
	// Native Darwin preserves the unused opaque bytes and changes only the
	// signature and the low two sharing-state bits. PRIVATE=2, SHARED=1.
	unsafe { *(&u64(attributes)) = 0x434e4441 }
	write32(attributes + 8, (read32(attributes + 8) & ~u32(3)) | 2)
	return 0
}

fn darwin_condattr_destroy(attributes u64) i32 {
	if attributes == 0 { return 22 }
	// The measured native operation accepts invalid/already-cleared signatures.
	unsafe { *(&u64(attributes)) = 0 }
	return 0
}

fn darwin_condattr_getshared(attributes u64, output &i32) i32 {
	if !pthread_condattr_valid(attributes) || output == unsafe { nil } { return 22 }
	unsafe { *output = i32(read32(attributes + 8) & 3) }
	return 0
}

fn darwin_condattr_setshared(attributes u64, state i32) i32 {
	if !pthread_condattr_valid(attributes) || (state != 1 && state != 2) { return 22 }
	write32(attributes + 8, (read32(attributes + 8) & ~u32(3)) | u32(state))
	return 0
}

fn pthread_condattr_symbol(symbol string) ?u64 {
	return match symbol {
		'_pthread_condattr_init' { u64(unsafe { voidptr(darwin_condattr_init) }) }
		'_pthread_condattr_destroy' { u64(unsafe { voidptr(darwin_condattr_destroy) }) }
		'_pthread_condattr_getpshared' { u64(unsafe { voidptr(darwin_condattr_getshared) }) }
		'_pthread_condattr_setpshared' { u64(unsafe { voidptr(darwin_condattr_setshared) }) }
		else { return none }
	}
}
