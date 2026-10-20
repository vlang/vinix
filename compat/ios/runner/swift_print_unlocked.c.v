// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.utf8

struct SwiftPrintFailure {}

fn (_ &SwiftPrintFailure) msg() string {
	return 'iOS: unsupported or invalid Swift print value/stream'
}

fn (_ &SwiftPrintFailure) code() int { return 1 }

__global swift_print_failure_value = SwiftPrintFailure{}

fn swift_print_failure() IError { return unsafe { &swift_print_failure_value } }

type SwiftPrintWrite = fn (u64, u64, u64, u64, u64, u64)

fn swift_print_active() ! {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_print_unlocked_retired || ios_runtime.swift_concurrency_retired {
		return swift_print_failure()
	}
}

// Bundled images remain loaded for the process lifetime. Reservations and
// zero-fill gaps do not establish readable metadata; require file-backed R.
fn swift_print_image_range(address u64, size u64) bool {
	if address == 0 || size > ~u64(0) - address || module_runtime == unsafe { nil } || module_runtime.auditing {
		return false
	}
	for loaded in module_runtime.modules {
		for segment in loaded.image.segments {
			if segment.name == '__PAGEZERO' || segment.prot & 1 == 0 { continue }
			start := loaded.base + segment.address - loaded.layout.base
			if address >= start && address - start <= segment.filesize && size <= segment.filesize - (address - start) {
				return true
			}
		}
	}
	return false
}

fn swift_print_relative(field u64) !u64 {
	if field & 3 != 0 || !swift_print_image_range(field, 4) { return swift_print_failure() }
	delta := i64(i32(read32(field)))
	if delta == 0 || (delta < 0 && field < u64(-delta)) || (delta > 0 && field > ~u64(0) - u64(delta)) {
		return swift_print_failure()
	}
	return u64(i64(field) + delta)
}

fn swift_print_image_text(address u64) !string {
	for length in 0 .. 1024 {
		if !swift_print_image_range(address + u64(length), 1) { return swift_print_failure() }
		if unsafe { *(&u8(address + u64(length))) } == 0 {
			return unsafe { tos(&u8(address), length) }
		}
	}
	return swift_print_failure()
}

// Reflection must not override a declared printing conformance. Scan static
// image records for the concrete nominal type; general dynamic conformance
// discovery/dispatch is outside this bounded printing profile.
fn swift_print_enum_custom(descriptor u64) !bool {
	for loaded in module_runtime.modules {
		for segment in loaded.image.segments {
			for section in segment.sections {
				if section.name != '__swift5_proto' { continue }
				start := loaded.base + section.address - loaded.layout.base
				if section.size > 1048576 || section.size & 3 != 0 || !swift_print_image_range(start, section.size) {
					return swift_print_failure()
				}
				for offset in u64(0) .. section.size / 4 {
					conformance := swift_print_relative(start + offset * 4)!
					if conformance & 3 != 0 || !swift_print_image_range(conformance, 16) {
						return swift_print_failure()
					}
					kind := (read32(conformance + 12) >> 3) & 7
					if kind > 1 { continue }
					mut nominal := swift_print_relative(conformance + 4)!
					if kind == 1 {
						if nominal & 7 != 0 || !swift_print_image_range(nominal, 8) {
							return swift_print_failure()
						}
						nominal = read64(nominal)
					}
					if nominal != descriptor { continue }
					mut protocol := swift_print_relative(conformance)!
					if protocol & 1 != 0 {
						protocol &= ~u64(1)
						if protocol & 7 != 0 || !swift_print_image_range(protocol, 8) {
							return swift_print_failure()
						}
						protocol = read64(protocol)
					}
					data := ios_runtime.swift_metadata_arena + u64(C.getpagesize())
					if protocol in [data + 320, data + 352]! { return true }
					if swift_print_image_range(protocol, 24) {
						name := swift_print_image_text(swift_print_relative(protocol + 8)!)!
						if name in ['TextOutputStreamable', 'CustomStringConvertible',
							'CustomDebugStringConvertible']! {
							return true
						}
					}
				}
			}
		}
	}
	return false
}

// A zero-payload, single-case enum has no value bytes to inspect. Its case
// name is sufficient for Swift's non-debug reflection fallback. Validate all
// metadata before touching it, including the zero-size POD witness layout.
fn swift_print_image_enum(metadata u64) !string {
	if metadata & 7 != 0 || metadata < 8 || !swift_print_image_range(metadata - 8, 24) || read64(metadata) != 0x201 {
		return swift_print_failure()
	}
	descriptor := read64(metadata + 8)
	if descriptor & 3 != 0 || !swift_print_image_range(descriptor, 28) || read32(descriptor) != 0x52 || read32(descriptor + 20) != 0 || read32(descriptor + 24) != 1 {
		return swift_print_failure()
	}
	witness := read64(metadata - 8)
	if witness & 7 != 0 || !swift_print_image_range(witness, 88) || read64(witness + 64) != 0 || read64(witness + 72) != 1 || read32(witness + 80) != 0x200000 || read32(witness + 84) != 0 {
		return swift_print_failure()
	}
	if swift_print_enum_custom(descriptor)! { return swift_print_failure() }
	fields := swift_print_relative(descriptor + 16)!
	if fields & 3 != 0 || !swift_print_image_range(fields, 28) || read32(fields + 4) != 0 || read32(fields + 8) != 0x000c0002 || read32(fields + 12) != 1 || read32(fields + 16) != 0 || read32(fields + 20) != 0 {
		return swift_print_failure()
	}
	return swift_print_image_text(swift_print_relative(fields + 24)!)
}

// Make text independent of borrowed pointer/foreign/temporary bytes before a
// stream can retain it or reenter. The caller holds the recursive registry lock.
fn swift_print_bytes(bytes SwiftStringBytes) !SwiftStringWords {
	if bytes.count > 1048576 || (bytes.address == 0 && bytes.count != 0) {
		return swift_print_failure()
	}
	text := unsafe { tos(&u8(bytes.address), int(bytes.count)) }
	if !utf8.validate_str(text) { return swift_print_failure() }
	ascii := swift_replace_ascii(bytes)
	if bytes.count <= 15 {
		return swift_string_literal(unsafe { &u8(bytes.address) }, i64(bytes.count), ascii)
	}
	result := swift_string_storage(bytes.count, bytes.count, ascii)
	C.memcpy(voidptr(result.second + 32), voidptr(bytes.address), usize(bytes.count))
	return result
}

fn swift_print_value_checked(source u64, metadata u64) !SwiftStringWords {
	swift_print_active()!
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	swift_print_active()!
	page := u64(C.getpagesize())
	if ios_runtime.swift_void_arena != 0 && metadata == ios_runtime.swift_void_arena + 8 {
		return swift_string_literal(c'()', 2, true)
	}
	if ios_runtime.swift_merge_error_metadata_arena != 0 && metadata == ios_runtime.swift_merge_error_metadata_arena + page + 16 {
		return swift_string_literal(c'keyCollision', 12, true)
	}
	if ios_runtime.swift_bool_metadata_arena != 0 && metadata == ios_runtime.swift_bool_metadata_arena + page + 16 {
		if source == 0 { return swift_print_failure() }
		value := unsafe { *(&u8(source)) }
		if value > 1 { return swift_print_failure() }
		return if value == 0 {
			swift_string_literal(c'false', 5, true)
		} else {
			swift_string_literal(c'true', 4, true)
		}
	}
	if ios_runtime.swift_integer_arena != 0 && metadata == ios_runtime.swift_integer_arena + page + 16 {
		if source == 0 || source & 7 != 0 { return swift_print_failure() }
		return swift_integer_description_checked(i64(read64(source)))
	}
	if ios_runtime.swift_metadata_arena != 0 && metadata == ios_runtime.swift_metadata_arena + page + 16 {
		// Returned byte spans borrow scratch; explicit stack storage prevents
		// V from heap-promoting an address-escaped fixed array.
		scratch := u64(C.__builtin_alloca(16))
		bytes := swift_replace_bytes(source, scratch)!
		words := unsafe { *(&SwiftStringWords(source)) }
		if words.second & (u64(1) << 60) != 0 { return swift_print_bytes(bytes) }
		swift_bridge_retain(words.second)
		return words
	}
	if ios_runtime.swift_static_string_metadata_arena != 0 && metadata == ios_runtime.swift_static_string_metadata_arena + page + 16 {
		if source == 0 || source & 7 != 0 { return swift_print_failure() }
		flags := unsafe { *(&u8(source + 16)) }
		if flags & ~u8(3) != 0 { return swift_print_failure() }
		scalar := unsafe { &u8(C.__builtin_alloca(4)) }
		bytes := swift_fatal_bytes(read64(source), read64(source + 8), u64(flags), scalar)
		if !bytes.valid { return swift_print_failure() }
		return swift_print_bytes(SwiftStringBytes{bytes.address, bytes.count})
	}
	name := swift_print_image_enum(metadata)!
	return swift_print_bytes(SwiftStringBytes{u64(name.str), u64(name.len)})
}

// Swift generic ABI: borrowed value, inout target, source metadata, target
// metadata and TextOutputStream table in x0...x4. No registry lock crosses write.
fn swift_print_unlocked_checked(source u64, target u64, metadata u64, target_metadata u64, table u64) ! {
	swift_print_active()!
	if ios_runtime.swift_interpolation_arena == 0 || target == 0 || target_metadata == 0 || table == 0 || table & 7 != 0 || table > ~u64(0) - 32 {
		return swift_print_failure()
	}
	words := swift_print_value_checked(source, metadata)!
	defer { swift_bridge_release(words.second) }
	entry := read64(table + 24)
	if entry == 0 { return swift_print_failure() }
	call := unsafe { SwiftPrintWrite(voidptr(ios_runtime.swift_interpolation_arena + 416)) }
	call(words.first, words.second, target_metadata, table, target, entry)
}

fn swift_print_unlocked(source u64, target u64, metadata u64, target_metadata u64, table u64) {
	swift_print_unlocked_checked(source, target, metadata, target_metadata, table) or { panic(err) }
}

fn swift_print_unlocked_symbol(symbol string) ?u64 {
	if symbol != '_$ss15_print_unlockedyyx_q_zts16TextOutputStreamR_r0_lF' { return none }
	swift_print_active() or { return none }
	swift_interpolation_metadata()
	return u64(unsafe { voidptr(swift_print_unlocked) })
}
