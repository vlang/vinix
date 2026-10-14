// SPDX-License-Identifier: GPL-2.0-or-later
module main

type SwiftLogWitness = fn (u64, u64, u64, u64) u64
type SwiftLogCopy = fn (u64, u64, u64) u64
type SwiftLogDestroy = fn (u64, u64)

fn swift_foundation_bridge(first u64, second u64) u64 {
	scratch := u64(C.__builtin_alloca(16))
	bytes := swift_string_bytes(SwiftStringWords{ first: first, second: second }, scratch) or { panic(err) }
	if bytes.count > 1024 * 1024 { panic('iOS: Swift Foundation String exceeds limits') }
	return owned_string(unsafe { tos(&u8(bytes.address), int(bytes.count)) })
}

// Optional NSString is borrowed in x0; the two-word String result is owned.
// Copy into native-tail/inline storage rather than exporting Apple's foreign
// NSString-backed representation, which our String operations do not support.
fn swift_foundation_unbridge_checked(source u64) !SwiftStringWords {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return error('iOS: Swift NSString bridge outside runtime lifetime')
	}
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if source == 0 { return SwiftStringWords{ second: u64(0xe000000000000000) } }
	// Registry validation must precede even the isa read. Keep the borrowed
	// bytes protected until the copy has been published; no guest callbacks.
	if source !in ios_runtime.objects && source !in ios_runtime.constants {
		return error('iOS: Swift NSString bridge requires a live registered object')
	}
	if !objc_is_kind(source, ios_runtime.names['NSString']) {
		return error('iOS: Swift NSString bridge requires NSString')
	}
	text := string_text(source)
	if text.len > 1024 * 1024 { return error('iOS: Swift NSString bridge exceeds limits') }
	destination := u64(C.__builtin_alloca(16))
	unsafe { *(&SwiftStringWords(destination)) = SwiftStringWords{ second: u64(0xe000000000000000) } }
	swift_string_append_bytes(destination, u64(text.str), u64(text.len))
	return unsafe { *(&SwiftStringWords(destination)) }
}
fn swift_foundation_unbridge(source u64) SwiftStringWords {
	return swift_foundation_unbridge_checked(source) or { panic(err) }
}
fn swift_foundation_string_encoding(first u64, second u64) u64 {
	object := objc_autorelease(swift_foundation_bridge(first, second))
	return swift_integer_vararg(object)
}

fn swift_foundation_arena() u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_foundation_arena != 0 { return ios_runtime.swift_foundation_arena }
	page := u64(C.getpagesize())
	base := u64(C.mmap(unsafe { nil }, usize(page * 2), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	if base == u64(-1) { panic('iOS: cannot allocate Swift Foundation entries') }
	data := base + page
	// Ordinary (metadata, table, Self, entry) -> borrowed Swift witness Self x20.
	for i, op in [u32(0xa9be57f4), 0xa9017bf6, 0xaa0203f4, 0xaa0303f0,
		0xd63f0200, 0xa9417bf6, 0xa8c257f4, 0xd65f03c0]! { write32(base + u64(i * 4), op) }
	// String's CVarArg encoding getter receives indirect borrowed Self.
	write32(base + 64, 0xa9400680); write32(base + 68, 0x58000070)
	write32(base + 72, 0xd61f0200)
	unsafe { *(&u64(base + 80)) = u64(voidptr(swift_foundation_string_encoding)) }
	// Generic Error getter: x0 metadata, x1 table, indirect borrowed Self x20.
	write32(base + 96, 0xaa1403e2); write32(base + 100, 0x58000070)
	write32(base + 104, 0xd61f0200)
	unsafe { *(&u64(base + 112)) = u64(voidptr(swift_error_description)) }
	// CocoaError.Code is resilient: this static getter returns its one-word
	// rawValue through x8, not x0. No Self/metadata/witness input is read.
	write32(base + 128, 0x52804089) // mov w9, #516
	write32(base + 132, 0xf9000109) // str x9, [x8]
	write32(base + 136, 0xd65f03c0) // ret
	// A concrete specialization of Foundation's retroactive String conformance.
	// The installed descriptor uses a generic witness cache; this implementation
	// supplies its already-specialized table, accepted by normal witness lookup.
	protocol := swift_integer_metadata() - 16 + 560
	string_type := swift_string_metadata()
	table := data + 16; conformance := data + 32; module_descriptor := data + 64
	unsafe { *(&u64(table)) = conformance; *(&u64(table + 8)) = base + 64 }
	swift_protocol_relative(conformance, protocol)
	swift_protocol_relative(conformance + 4, read64(string_type + 8))
	swift_protocol_relative(conformance + 8, table)
	write32(conformance + 12, 0x40)
	swift_protocol_relative(conformance + 16, module_descriptor)
	swift_protocol_relative(module_descriptor + 8, data + 80)
	C.memcpy(unsafe { voidptr(data + 80) }, c'Foundation', 11)
	C.__builtin___clear_cache(unsafe { voidptr(base) }, unsafe { voidptr(base + 140) })
	if C.mprotect(unsafe { voidptr(base) }, usize(page), C.PROT_READ | C.PROT_EXEC) != 0
		|| C.mprotect(unsafe { voidptr(data) }, usize(page), C.PROT_READ) != 0 {
		C.munmap(unsafe { voidptr(base) }, usize(page * 2)); panic('iOS: cannot seal Swift Foundation entries')
	}
	ios_runtime.swift_foundation_arena = base
	return base
}

fn swift_nslog_array(owner u64, encoded bool) !SwiftStringBytes {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if owner != 0 && owner == ios_runtime.swift_empty_array { return SwiftStringBytes{ address: owner + 32 } }
	storage := ios_runtime.swift_arrays[owner] or { return error('iOS: Swift NSLog requires registered value Array storage') }
	if storage.tail != 32 || read64(owner + 16) > storage.capacity || read64(owner + 24) & 1 != 0 {
		return error('iOS: invalid Swift NSLog Array layout')
	}
	if encoded {
		if storage.stride != 8 || storage.element != swift_integer_metadata() { return error('iOS: CVarArg encoding requires owned Array<Int>') }
	} else {
		if storage.stride != 40 || read64(storage.element) != 0x303 || read32(storage.element + 8) != 0x80000001
			|| read32(storage.element + 12) != 1 || read64(storage.element + 16) != swift_integer_metadata() - 16 + 560 {
			return error('iOS: Swift NSLog requires Array<any CVarArg>')
		}
	}
	return SwiftStringBytes{ address: owner + 32, count: read64(owner + 16) }
}

fn swift_nslog_value_witness(metadata u64) !u64 {
	if metadata < 8 || metadata & 7 != 0 { return error('iOS: invalid CVarArg value metadata') }
	if read64(metadata) !in [u64(0x200), 0x201] { return error('iOS: Swift NSLog reference CVarArg values are not implemented') }
	witness := read64(metadata - 8)
	if witness == 0 || read64(witness + 64) > 24 || read32(witness + 80) & 0x20000 != 0
		|| read64(witness + 16) == 0 || read64(witness + 8) == 0 {
		return error('iOS: Swift NSLog boxed CVarArg values are not implemented')
	}
	return witness
}

fn swift_nslog_encode(source u64, destination u64, capacity u64, bridge u64) !u64 {
	metadata := read64(source + 24); table := read64(source + 32)
	witness := swift_nslog_value_witness(metadata)!
	if table < 8 || table & 7 != 0 || read64(table + 8) == 0 { return error('iOS: invalid CVarArg witness table') }
	value := u64(C.__builtin_alloca(24))
	copy_value := unsafe { SwiftLogCopy(voidptr(read64(witness + 16))) }
	destroy := unsafe { SwiftLogDestroy(voidptr(read64(witness + 8))) }
	if copy_value(value, source, metadata) != value { return error('iOS: invalid CVarArg copy result') }
	defer { destroy(value, metadata) }
	call := unsafe { SwiftLogWitness(voidptr(bridge)) }
	owner := call(metadata, table, value, read64(table + 8))
	// Lookup precedes payload reads. The witness's returned Array is owned.
	if owner == 0 { return error('iOS: CVarArg witness returned nil encoding') }
	if !swift_task_registered(owner) {
		C.ios_objc_initialize_lock()
		known := owner == ios_runtime.swift_empty_array || owner in ios_runtime.swift_arrays
		C.ios_objc_initialize_unlock()
		if !known { return error('iOS: CVarArg witness returned foreign encoding') }
	} else { return error('iOS: CVarArg witness returned a task instead of Array<Int>') }
	defer { swift_bridge_release(owner) }
	encoded := swift_nslog_array(owner, true)!
	if encoded.count > capacity { return error('iOS: excessive Swift CVarArg encoding') }
	if encoded.count != 0 { C.memcpy(unsafe { voidptr(destination) }, unsafe { voidptr(encoded.address) }, usize(encoded.count * 8)) }
	return encoded.count
}

// Two passes size and fill one explicitly owned message, preserving UTF-8 and
// embedded NULs in %@ arguments. libc formats scalar words with Darwin's stack
// va_list adapter; unsupported conversions reject before any witness callback.
fn swift_nslog_format_pass(format SwiftStringBytes, stack u64, words u64, output u64, capacity u64) !u64 {
	mut index := u64(0); mut argument := u64(0); mut length := u64(0)
	specifier := u64(C.__builtin_alloca(66))
	for index < format.count {
		byte := unsafe { *(&u8(format.address + index)) }
		if byte != `%` || (index + 1 < format.count && unsafe { *(&u8(format.address + index + 1)) } == `%`) {
			if output != 0 { if length >= capacity { return error('iOS: inconsistent Swift NSLog output size') }; unsafe { *(&u8(output + length)) = byte } }
			length++; index += if byte == `%` { u64(2) } else { u64(1) }; continue
		}
		start := index; index++
		mut magnitude := u64(0)
		for index < format.count {
			flag := unsafe { *(&u8(format.address + index)) }
			if flag !in [`#`, `0`, `-`, ` `, `+`, `.`, `1`, `2`, `3`, `4`, `5`, `6`, `7`, `8`, `9`, `h`, `l`, `z`, `t`, `j`] { break }
			if flag >= `0` && flag <= `9` { magnitude = magnitude * 10 + u64(flag - `0`); if magnitude > 1024 * 1024 { return error('iOS: excessive Swift NSLog width or precision') } }
			else { magnitude = 0 }
			index++
		}
		if index == format.count || index - start > 64 { return error('iOS: invalid Swift NSLog format') }
		conversion := unsafe { *(&u8(format.address + index)) }; index++
		if conversion !in [`@`, `d`, `i`, `u`, `x`, `X`, `o`, `f`, `F`, `e`, `E`, `g`, `G`, `a`, `A`, `c`, `s`, `p`]
			|| (conversion == `@` && index - start != 2) { return error('iOS: Swift NSLog format conversion is not implemented') }
		if stack == 0 { argument++; continue } // Validation before callbacks.
		if argument >= words { return error('iOS: insufficient Swift NSLog argument words') }
		if conversion == `@` {
			object := read64(stack + argument * 8)
			if object != 0 && !objc_is_kind(object, ios_runtime.names['NSString']) { return error('iOS: Swift NSLog object formatting requires NSString') }
			text := if object == 0 { '(null)' } else { string_text(object) }
			if u64(text.len) > 1024 * 1024 - length { return error('iOS: excessive Swift NSLog message') }
			if output != 0 { if u64(text.len) > capacity - length { return error('iOS: inconsistent Swift NSLog output size') }; C.memcpy(unsafe { voidptr(output + length) }, text.str, usize(text.len)) }
			length += u64(text.len)
		} else {
			C.memset(unsafe { voidptr(specifier) }, 0, 66)
			C.memcpy(unsafe { voidptr(specifier) }, unsafe { voidptr(format.address + start) }, usize(index - start))
			count := C.ios_vsnprintf(unsafe { nil }, 0, unsafe { &char(specifier) }, unsafe { voidptr(stack + argument * 8) })
			if count < 0 || u64(count) > 1024 * 1024 - length { return error('iOS: excessive Swift NSLog scalar output') }
			if output != 0 {
				if u64(count) > capacity - length { return error('iOS: inconsistent Swift NSLog output size') }
				if C.ios_vsnprintf(unsafe { &char(output + length) }, usize(capacity - length + 1), unsafe { &char(specifier) }, unsafe { voidptr(stack + argument * 8) }) != count { return error('iOS: inconsistent Swift NSLog scalar output') }
			}
			length += u64(count)
		}
		argument++
	}
	if length > 1024 * 1024 { return error('iOS: excessive Swift NSLog message') }
	return if stack == 0 { argument } else { length }
}

fn swift_nslog_checked(first u64, second u64, arguments u64) ! {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return error('iOS: Swift NSLog outside runtime lifetime') }
	scratch := u64(C.__builtin_alloca(16))
	format := swift_string_bytes(SwiftStringWords{ first: first, second: second }, scratch)!
	if format.count > 1024 * 1024 { return error('iOS: excessive Swift NSLog format') }
	for i in u64(0) .. format.count { if unsafe { *(&u8(format.address + i)) } == 0 { return error('iOS: Swift NSLog format contains NUL') } }
	required := swift_nslog_format_pass(format, 0, 0, 0, 0)!
	array := swift_nslog_array(arguments, false)!
	if array.count > 512 { return error('iOS: excessive Swift NSLog argument count') }
	for i in u64(0) .. array.count { swift_nslog_value_witness(read64(array.address + i * 40 + 24))! }
	swift_bridge_retain(second); defer { swift_bridge_release(second) }
	pool := objc_pool_push(); defer { objc_pool_pop(pool) }
	bridge := swift_foundation_arena()
	stack := u64(C.__builtin_alloca(512 * 8)); mut words := u64(0)
	for i in u64(0) .. array.count { words += swift_nslog_encode(array.address + i * 40, stack + words * 8, 512 - words, bridge)! }
	if required > words { return error('iOS: insufficient Swift NSLog arguments') }
	length := swift_nslog_format_pass(format, stack, words, 0, 0)!
	message := u64(C.malloc(usize(length + 1)))
	if message == 0 { return error('iOS: cannot allocate Swift NSLog message') }
	defer { C.free(unsafe { voidptr(message) }) }
	if swift_nslog_format_pass(format, stack, words, message, length)! != length { return error('iOS: inconsistent Swift NSLog message') }
	unsafe { *(&u8(message + length)) = `\n` }
	if C.fwrite(unsafe { voidptr(message) }, 1, usize(length + 1), C.ios_host_stdio(2)) != usize(length + 1) { return error('iOS: cannot write Swift NSLog message') }
}
fn swift_nslog(first u64, second u64, arguments u64) { swift_nslog_checked(first, second, arguments) or { panic(err) } }

fn swift_foundation_symbol(symbol string) !u64 {
	$if !arm64 { return error('iOS: Swift Foundation requires ARM64') }
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired { return error('iOS: Swift Foundation outside runtime lifetime') }
	return match symbol {
		'_$s10Foundation5NSLogyySS_s7CVarArg_pdtF' { u64(voidptr(swift_nslog)) }
		'_$sSS10FoundationE19_bridgeToObjectiveCSo8NSStringCyF' { u64(voidptr(swift_foundation_bridge)) }
		'_$sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ' { u64(voidptr(swift_foundation_unbridge)) }
		'_$sSh10FoundationE36_unconditionallyBridgeFromObjectiveCyShyxGSo5NSSetCSgFZ' { u64(voidptr(swift_foundation_set_unbridge)) }
		'_$sSSs7CVarArg10FoundationMc' { swift_foundation_arena() + u64(C.getpagesize()) + 32 }
		'_$ss5ErrorP10FoundationE20localizedDescriptionSSvg' { swift_foundation_arena() + 96 }
		'_$s10Foundation10CocoaErrorV19fileWriteFileExistsAC4CodeVvgZ' { swift_foundation_arena() + 128 }
		else { return error('iOS: Swift Foundation symbol is not implemented: ${symbol}') }
	}
}
fn swift_foundation_stop() {
	if ios_runtime.swift_foundation_arena == 0 { return }
	if C.munmap(unsafe { voidptr(ios_runtime.swift_foundation_arena) }, usize(C.getpagesize()) * 2) != 0 { panic('iOS: cannot retire Swift Foundation entries') }
	ios_runtime.swift_foundation_arena = 0
}
