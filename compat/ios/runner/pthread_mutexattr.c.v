// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn pthread_mutexattr_valid(attributes u64) bool {
	return attributes != 0 && read64(attributes) == 0x4d545841
}

fn darwin_mutexattr_init(attributes u64) i32 {
	if attributes == 0 { return 22 }
	// Measured Darwin ARM64 layout: signature, signed ceiling, packed flags.
	// Initialization preserves the unused high flags. PRIVATE=2, FIRSTFIT=3.
	unsafe { *(&u64(attributes)) = 0x4d545841 }
	write32(attributes + 8, 0)
	write32(attributes + 12, (read32(attributes + 12) & ~u32(0x1ff)) | 0xa0)
	return 0
}

fn darwin_mutexattr_destroy(attributes u64) i32 {
	if !pthread_mutexattr_valid(attributes) { return 22 }
	unsafe { *(&u64(attributes)) = 0 }
	return 0
}

fn pthread_mutexattr_get(attributes u64, output &i32, mask u32, shift u32) i32 {
	if !pthread_mutexattr_valid(attributes) || output == unsafe { nil } { return 22 }
	unsafe { *output = i32((read32(attributes + 12) >> shift) & mask) }
	return 0
}

fn pthread_mutexattr_set(attributes u64, value i32, mask u32, shift u32, lower i32, upper i32) i32 {
	if !pthread_mutexattr_valid(attributes) || value < lower || value > upper { return 22 }
	write32(attributes + 12, (read32(attributes + 12) & ~(mask << shift)) | (u32(value) << shift))
	return 0
}

fn darwin_mutexattr_gettype(attributes u64, output &i32) i32 {
	return pthread_mutexattr_get(attributes, output, 3, 2)
}

fn darwin_mutexattr_type(attributes u64, kind i32) i32 {
	return pthread_mutexattr_set(attributes, kind, 3, 2, 0, 2)
}

fn darwin_mutexattr_getshared(attributes u64, output &i32) i32 {
	return pthread_mutexattr_get(attributes, output, 3, 4)
}

fn darwin_mutexattr_setshared(attributes u64, state i32) i32 {
	return pthread_mutexattr_set(attributes, state, 3, 4, 1, 2)
}

fn darwin_mutexattr_getprotocol(attributes u64, output &i32) i32 {
	return pthread_mutexattr_get(attributes, output, 3, 0)
}

fn darwin_mutexattr_setprotocol(attributes u64, protocol i32) i32 {
	return pthread_mutexattr_set(attributes, protocol, 3, 0, 0, 2)
}

fn darwin_mutexattr_getceiling(attributes u64, output &i32) i32 {
	if !pthread_mutexattr_valid(attributes) || output == unsafe { nil } { return 22 }
	unsafe { *output = i32(read32(attributes + 8)) }
	return 0
}

fn darwin_mutexattr_setceiling(attributes u64, ceiling i32) i32 {
	if !pthread_mutexattr_valid(attributes) || ceiling < -999 || ceiling > 999 { return 22 }
	write32(attributes + 8, u32(ceiling))
	return 0
}

fn darwin_mutexattr_getpolicy(attributes u64, output &i32) i32 {
	if !pthread_mutexattr_valid(attributes) || output == unsafe { nil } { return 22 }
	packed := (read32(attributes + 12) >> 6) & 7
	value := match packed {
		1 { i32(1) }
		2 { i32(3) }
		else { return 22 }
	}
	unsafe { *output = value }
	return 0
}

fn darwin_mutexattr_setpolicy(attributes u64, policy i32) i32 {
	if policy != 1 && policy != 3 { return 22 }
	return pthread_mutexattr_set(attributes, if policy == 1 { i32(1) } else { i32(2) }, 7, 6, 1, 2)
}

fn pthread_mutexattr_symbol(symbol string) ?u64 {
	return match symbol {
		'_pthread_mutexattr_init' { u64(unsafe { voidptr(darwin_mutexattr_init) }) }
		'_pthread_mutexattr_destroy' { u64(unsafe { voidptr(darwin_mutexattr_destroy) }) }
		'_pthread_mutexattr_gettype' { u64(unsafe { voidptr(darwin_mutexattr_gettype) }) }
		'_pthread_mutexattr_settype' { u64(unsafe { voidptr(darwin_mutexattr_type) }) }
		'_pthread_mutexattr_getpshared' { u64(unsafe { voidptr(darwin_mutexattr_getshared) }) }
		'_pthread_mutexattr_setpshared' { u64(unsafe { voidptr(darwin_mutexattr_setshared) }) }
		'_pthread_mutexattr_getprotocol' { u64(unsafe { voidptr(darwin_mutexattr_getprotocol) }) }
		'_pthread_mutexattr_setprotocol' { u64(unsafe { voidptr(darwin_mutexattr_setprotocol) }) }
		'_pthread_mutexattr_getprioceiling' { u64(unsafe { voidptr(darwin_mutexattr_getceiling) }) }
		'_pthread_mutexattr_setprioceiling' { u64(unsafe { voidptr(darwin_mutexattr_setceiling) }) }
		'_pthread_mutexattr_getpolicy_np' { u64(unsafe { voidptr(darwin_mutexattr_getpolicy) }) }
		'_pthread_mutexattr_setpolicy_np' { u64(unsafe { voidptr(darwin_mutexattr_setpolicy) }) }
		else { return none }
	}
}
