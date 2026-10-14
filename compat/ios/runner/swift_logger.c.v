// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Logger is resilient, but the installed ARM64 implementation contains one
// ordinary ObjC reference. logObject borrows indirect Self in x20 and returns
// objc_retain(Self.logObject). The initializer consumes two frozen Strings
// and initializes exactly eight bytes through the caller's x8 result.
fn swift_logger_object_checked(value u64) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_logger_retired {
		return error('iOS: Swift Logger outside runtime lifetime')
	}
	if value == 0 { return error('iOS: Swift Logger requires value storage') }
	owner := read64(value)
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	// Check identity before inspecting a foreign or retired referent. Log
	// handles have runtime-owned storage and intentionally no ObjC isa/header.
	if owner != 0 && !os_log_is_handle(owner) && owner !in ios_runtime.objects
		&& owner !in ios_runtime.constants && owner !in ios_runtime.classes {
		return error('iOS: Swift Logger requires a live registered log object')
	}
	return objc_retain(owner)
}
fn swift_logger_object(value u64) u64 {
	return swift_logger_object_checked(value) or { panic(err) }
}

fn swift_logger_label(words SwiftStringWords, scratch u64, output u64) ! {
	bytes := swift_string_bytes(words,scratch)!
	if bytes.count > 255 { return error('iOS: Swift Logger label exceeds 255 UTF-8 bytes') }
	if bytes.count != 0 { C.memcpy(voidptr(output),voidptr(bytes.address),usize(bytes.count)) }
	unsafe { *(&u8(output + bytes.count)) = 0 }
}
fn swift_logger_initialize_checked(first u64, second u64, category_first u64, category_second u64, output u64) ! {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_logger_retired || system_data == unsafe { nil } {
		return error('iOS: Swift Logger initialization outside logging lifetime')
	}
	if output == 0 { return error('iOS: Swift Logger requires result storage') }
	scratch := u64(C.__builtin_alloca(32))
	labels := u64(C.__builtin_alloca(512))
	swift_logger_label(SwiftStringWords{first:first,second:second},scratch,labels)!
	swift_logger_label(SwiftStringWords{first:category_first,second:category_second},scratch + 16,labels + 256)!
	// Validate both labels before creating a handle or consuming either owner.
	// os_log_create copies the bounded strings before the owned inputs retire.
	owner := darwin_os_log_create(unsafe { &char(labels) },unsafe { &char(labels + 256) })
	swift_bridge_release(second)
	swift_bridge_release(category_second)
	unsafe { *(&u64(output)) = owner }
}
fn swift_logger_initialize(first u64, second u64, category_first u64, category_second u64, output u64) {
	swift_logger_initialize_checked(first,second,category_first,category_second,output) or { panic(err) }
}

fn swift_logger_enum_get(value u64, empty_cases u32, metadata u64) u32 {
	if empty_cases == 0 { return 0 }
	return swift_unknown_value_enum_get(value,empty_cases,metadata)
}

fn swift_logger_arena() !u64 {
	$if !arm64 { return error('iOS: Swift Logger requires ARM64') }
	if ios_runtime == unsafe { nil } { return error('iOS: Swift Logger outside runtime lifetime') }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_logger_retired { return error('iOS: Swift Logger outside runtime lifetime') }
	if ios_runtime.swift_logger_arena != 0 { return ios_runtime.swift_logger_arena }
	page := u64(C.getpagesize())
	allocation := C.mmap(unsafe { nil },usize(page * 2),C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0)
	if allocation == unsafe { voidptr(-1) } { return error('iOS: cannot allocate Swift Logger entries') }
	base := u64(allocation)
	data := base + page
	metadata := data + 16
	descriptor := data + 128
	// Complete metadata response, independent of the request in x0.
	write32(base,0x58000080); write32(base + 4,0xd2800001); write32(base + 8,0xd65f03c0)
	unsafe { *(&u64(base + 16)) = metadata }
	// Borrow Self x20; the C bridge performs the one load and owned retain.
	swift_dispatch_bridge(base + 32,0xaa1403e0,0xd503201f,u64(voidptr(swift_logger_object)))
	// Pass the indirect result x8 in the ordinary fifth argument x4.
	swift_dispatch_bridge(base + 64,0xaa0803e4,0xd503201f,u64(voidptr(swift_logger_initialize)))
	unsafe {
		*(&u64(metadata - 8)) = data + 256
		*(&u64(metadata)) = 0x200
		*(&u64(metadata + 8)) = descriptor
	}
	write32(metadata + 16,0) // Packed u32 field offset: logObject at zero.
	// Explicit witnesses need no native compact-layout string. Their ordinary
	// one-reference ownership/layout matches UnknownObject; Logger's enum query
	// additionally returns zero without inspecting storage for zero empty cases.
	C.memcpy(voidptr(data + 256),voidptr(swift_unknown_value_witnesses()),88)
	unsafe { *(&u64(data + 256 + 48)) = u64(voidptr(swift_logger_enum_get)) }
	write32(descriptor,0x51) // Unique nongeneric struct, private reflection profile.
	swift_protocol_relative(descriptor + 4,data + 192)
	swift_protocol_relative(descriptor + 8,data + 224)
	swift_protocol_relative(descriptor + 12,base)
	write32(descriptor + 20,1); write32(descriptor + 24,2)
	swift_protocol_relative(data + 200,data + 216)
	C.memcpy(voidptr(data + 216),c'os',3)
	C.memcpy(voidptr(data + 224),c'Logger',7)
	C.__builtin___clear_cache(allocation,voidptr(base + 88))
	if C.mprotect(allocation,usize(page),C.PROT_READ | C.PROT_EXEC) != 0
		|| C.mprotect(voidptr(data),usize(page),C.PROT_READ) != 0 {
		if C.munmap(allocation,usize(page * 2)) != 0 { panic('iOS: cannot retire unsealed Swift Logger entries') }
		return error('iOS: cannot seal Swift Logger entries')
	}
	ios_runtime.swift_logger_arena = base
	return base
}

fn swift_os_symbol(symbol string) !u64 {
	if symbol == '_$sSo13os_log_type_ta0A0E5errorABvgZ' { return u64(voidptr(swift_os_log_error_type)) }
	if symbol !in ['_$s2os6LoggerV9logObjectSo03OS_a1_C0Cvg','_$s2os6LoggerV9subsystem8categoryACSS_SStcfC','_$s2os6LoggerVMa','_$s2os6LoggerVMn']! {
		return error('iOS: Swift os symbol is not implemented: ${symbol}')
	}
	base := swift_logger_arena()!
	return match symbol {
		'_$s2os6LoggerVMa' { base }
		'_$s2os6LoggerVMn' { base + u64(C.getpagesize()) + 128 }
		'_$s2os6LoggerV9logObjectSo03OS_a1_C0Cvg' { base + 32 }
		else { base + 64 }
	}
}
fn swift_logger_stop() {
	// Array elements and heap owners have drained; retire borrowed entries
	// and metadata before their UnknownObject witnesses and logging handles.
	ios_runtime.swift_logger_retired = true
	if ios_runtime.swift_logger_arena == 0 { return }
	if C.munmap(voidptr(ios_runtime.swift_logger_arena),usize(C.getpagesize()) * 2) != 0 {
		panic('iOS: cannot retire Swift Logger entries')
	}
	ios_runtime.swift_logger_arena = 0
}
