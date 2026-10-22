// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Frozen StaticString is pointer/scalar, byte count, then one flag byte.
// Three such arguments exceed ARM64's argument registers: file.flags,
// line and reporting flags arrive on the caller's stack. Never is a trap,
// not a successful return. Measured against this Mac's libswiftCore from V;
// Swift's AssertCommon.swift documents the same conversion/report/trap path.
struct SwiftFatalArguments {
	prefix_data u64
	prefix_count u64
	prefix_flags u64
	message_data u64
	message_count u64
	message_flags u64
	file_data u64
	file_count u64
	file_flags u64
	line u64
	flags u64
}

struct SwiftFatalBytes {
	address u64
	count u64
	valid bool
}

fn swift_fatal_bytes(data u64, count u64, flags u64, scalar &u8) SwiftFatalBytes {
	if u8(flags) & 1 == 0 {
		// Swift's reporter takes CInt lengths. Nil is invalid even for an
		// empty StaticString; the default empty value has a real pointer.
		return SwiftFatalBytes{ address: data, count: count, valid: data != 0 && count <= 0x7fffffff }
	}
	if data > 0x10ffff || (data >= 0xd800 && data <= 0xdfff) {
		return SwiftFatalBytes{}
	}
	mut length := u64(1)
	unsafe {
		if data < 0x80 {
			scalar[0] = u8(data)
		} else if data < 0x800 {
			length = 2
			scalar[0] = 0xc0 | u8(data >> 6)
			scalar[1] = 0x80 | u8(data & 63)
		} else if data < 0x10000 {
			length = 3
			scalar[0] = 0xe0 | u8(data >> 12)
			scalar[1] = 0x80 | u8((data >> 6) & 63)
			scalar[2] = 0x80 | u8(data & 63)
		} else {
			length = 4
			scalar[0] = 0xf0 | u8(data >> 18)
			scalar[1] = 0x80 | u8((data >> 12) & 63)
			scalar[2] = 0x80 | u8((data >> 6) & 63)
			scalar[3] = 0x80 | u8(data & 63)
		}
	}
	return SwiftFatalBytes{ address: u64(scalar), count: length, valid: true }
}

fn swift_fatal_write(address u64, count u64) {
	mut done := u64(0)
	for done < count {
		written := C.write(2, unsafe { voidptr(address + done) }, usize(count - done))
		if written < 0 {
			if unsafe { *C.ios_errno_address() } == C.EINTR { continue }
			return // A broken stderr must still reach the trap.
		}
		if written == 0 { return }
		done += u64(written)
	}
}

fn swift_fatal_text(bytes SwiftFatalBytes) {
	// The native reporter uses precision-limited %s, stopping at the first
	// NUL without reading past the supplied count. Preserve that behavior.
	mut length := u64(0)
	for length < bytes.count && unsafe { *(&u8(bytes.address + length)) } != 0 { length++ }
	swift_fatal_write(bytes.address, length)
}

fn swift_fatal_string(first u64, second u64, storage &u8) SwiftFatalBytes {
	if second & (u64(1) << 61) != 0 {
		if second & (u64(1) << 63) == 0 || second & (u64(1) << 60) != 0 { return SwiftFatalBytes{} }
		count := (second >> 56) & 15
		for i in 0 .. int(count) {
			word := if i < 8 { first } else { second }
			unsafe { storage[i] = u8(word >> u32((i % 8) * 8)) }
		}
		return SwiftFatalBytes{ address: u64(storage), count: count, valid: true }
	}
	// The same native-tail/immortal-literal forms as the UTF-8 String getter.
	// Reject foreign/shared storage before dereferencing its object pointer.
	if second & (u64(1) << 60) != 0 || first & (u64(1) << 60) == 0 { return SwiftFatalBytes{} }
	address := (second & swift_address_mask) + 32
	count := first & swift_count_mask
	return SwiftFatalBytes{ address: address, count: count, valid: address != 32 && count <= 0x7fffffff }
}

fn swift_fatal_report(args &SwiftFatalArguments) {
	storage := unsafe { &u8(C.__builtin_alloca(4)) }
	message := swift_fatal_bytes(args.message_data, args.message_count, args.message_flags, storage)
	swift_fatal_report_parts(args, message)
}

fn swift_fatal_report_string(args &SwiftFatalArguments) {
	storage := unsafe { &u8(C.__builtin_alloca(16)) }
	message := swift_fatal_string(args.message_data, args.message_count, storage)
	swift_fatal_report_parts(args, message)
}

fn swift_fatal_report_parts(args &SwiftFatalArguments, message SwiftFatalBytes) {
	// Explicit stack storage prevents V from heap-promoting mutable arrays
	// whose addresses escape into the UTF-8 conversion or write calls.
	storage := unsafe { &u8(C.__builtin_alloca(32)) }
	prefix := swift_fatal_bytes(args.prefix_data, args.prefix_count, args.prefix_flags, storage)
	file := swift_fatal_bytes(args.file_data, args.file_count, args.file_flags,
		unsafe { &u8(u64(storage) + 4) })
	if !prefix.valid || !message.valid || !file.valid || args.line > 0xffffffff {
		// Invalid unsafe inputs/conversion overflow trap too, without reading
		// invalid pointers or silently truncating Swift's checked conversion.
		text := 'Vinix Swift runtime: Fatal error: invalid assertion arguments\n'
		swift_fatal_write(u64(text.str), u64(text.len))
		return
	}
	swift_fatal_text(file)
	colon := ':'
	swift_fatal_write(u64(colon.str), 1)
	mut number := args.line
	mut start := u64(32)
	for {
		start--
		unsafe { *(&u8(u64(storage) + start)) = u8(48 + number % 10) }
		number /= 10
		if number == 0 { break }
	}
	swift_fatal_write(u64(storage) + start, 32 - start)
	swift_fatal_write(u64(c': '), 2)
	swift_fatal_text(prefix)
	if message.count != 0 {
		swift_fatal_write(u64(c': '), 2)
		swift_fatal_text(message)
	}
	newline := '\n'
	swift_fatal_write(u64(newline.str), 1)
	// Native flags 0/1 produce the same stderr diagnostic. Vinix does not
	// implement the host debugger crash-annotation/backtrace integration.
}

fn swift_fatal_emit(code u64, string_message bool) {
	// String-message overload: x3/x4 are String's two words; file uses
	// x5/x6/x7, then line/flags spill at caller sp+0/sp+8. Normalize both
	// layouts into the record consumed by the V diagnostic bodies.
	for i, op in [u32(0xa9b97bfd), // stp x29,x30,[sp,#-112]!
		0x910003fd, // mov x29,sp
		0xa90107e0, 0xa9020fe2, 0xa90317e4, 0xa9041fe6, // capture x0..x7 at sp+16
		0x3941c3e8, 0xf9002be8, // caller sp+0 file flag -> record+64
		0xf9403fe8, 0xf9002fe8, // caller sp+8 line -> record+72
		0xb94083e8, 0xf90033e8, // caller sp+16 UInt32 flags -> record+80
		0x910043e0, // x0 = sp+16 argument record
		0x580000b0, 0xd63f0200, // load V body from +72 and call it
		0xd4200020, 0x17ffffff, // BRK #1; trap again if a handler returns
		0xd503201f]! { write32(code + u64(i * 4), op) }
	if string_message {
		write32(code + 24, 0xf90023e5) // str x5,[sp,#64] file.data
		write32(code + 28, 0xf90027e6) // str x6,[sp,#72] file.count
		write32(code + 32, 0xf9002be7) // str x7,[sp,#80] file.flags
		write32(code + 36, 0xf9403be8) // ldr x8,[sp,#112] line
		write32(code + 40, 0xf9002fe8) // str x8,[sp,#88]
		write32(code + 44, 0xb9407be8) // ldr w8,[sp,#120] flags
		write32(code + 48, 0xf90033e8) // str x8,[sp,#96]
		write32(code + 52, 0x910043e0) // x0 = sp+16
		write32(code + 56, 0x580000d0) // literal at +80
		write32(code + 60, 0xd63f0200)
		write32(code + 64, 0xd4200020)
		write32(code + 68, 0x17ffffff)
		write32(code + 72, 0xd503201f)
		write32(code + 76, 0xd503201f)
		unsafe { *(&u64(code + 80)) = u64(voidptr(swift_fatal_report_string)) }
	} else {
		unsafe { *(&u64(code + 72)) = u64(voidptr(swift_fatal_report)) }
	}
}

// Native swift_deletedMethodError takes no arguments and reports through the
// runtime's abort path, unlike Swift assertion entries that execute BRK.
@[noreturn]
fn swift_deleted_method_failure() {
	text := 'Fatal error: Call of deleted method\n'
	swift_fatal_write(u64(text.str), u64(text.len))
	for { C.abort() }
}

fn swift_fatal_entry(string_message bool) u64 {
	$if arm64 {
		C.ios_objc_initialize_lock()
		defer { C.ios_objc_initialize_unlock() }
		if ios_runtime.swift_fatal_code == 0 {
			page := usize(C.getpagesize())
			code := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE,
				C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
			if code == unsafe { voidptr(-1) } { panic('iOS: cannot allocate Swift assertion entry') }
			swift_fatal_emit(u64(code), false)
			swift_fatal_emit(u64(code) + 96, true)
			swift_dictionary_hashable_emit(u64(code) + 192)
			swift_unexpected_error_emit(u64(code) + 224)
			C.__builtin___clear_cache(code, unsafe { voidptr(u64(code) + 256) })
			if C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) != 0 {
				C.munmap(code, page)
				panic('iOS: cannot seal Swift assertion entry')
			}
			ios_runtime.swift_fatal_code = u64(code)
		}
		return ios_runtime.swift_fatal_code + if string_message { u64(96) } else { u64(0) }
	} $else {
		panic('iOS: Swift assertion ABI requires ARM64')
	}
}

fn swift_fatal_stop() {
	if ios_runtime.swift_fatal_code != 0 {
		if C.munmap(unsafe { voidptr(ios_runtime.swift_fatal_code) }, usize(C.getpagesize())) != 0 {
			panic('iOS: cannot retire Swift assertion entry')
		}
		ios_runtime.swift_fatal_code = 0
	}
}

fn swift_fatal_symbol(symbol string) ?u64 {
	return match symbol {
		'_$ss17_assertionFailure__4file4line5flagss5NeverOs12StaticStringV_A2HSus6UInt32VtF',
		'_$ss18_fatalErrorMessage__4file4line5flagss5NeverOs12StaticStringV_A2HSus6UInt32VtF' { swift_fatal_entry(false) }
		'_$ss17_assertionFailure__4file4line5flagss5NeverOs12StaticStringV_SSAHSus6UInt32VtF' { swift_fatal_entry(true) }
		'_$ss53KEY_TYPE_OF_DICTIONARY_VIOLATES_HASHABLE_REQUIREMENTSys5NeverOypXpF' { swift_fatal_entry(false) + 192 }
		'_swift_unexpectedError' { swift_fatal_entry(false) + 224 }
		'_swift_deletedMethodError' { u64(unsafe { voidptr(swift_deleted_method_failure) }) }
		else { none }
	}
}
