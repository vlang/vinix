// SPDX-License-Identifier: GPL-2.0-or-later
module main

const refund_entry_symbol = '_$s8StoreKit11TransactionV18beginRefundRequest3for2inAC0eF6StatusOs6UInt64V_So13UIWindowSceneCtYaKFZ'
const refund_descriptor_symbol = '_$s8StoreKit11TransactionV18beginRefundRequest3for2inAC0eF6StatusOs6UInt64V_So13UIWindowSceneCtYaKFZTu'
const refund_status_symbol = '_$s8StoreKit11TransactionV19RefundRequestStatusOMa'

fn refund_unavailable() u64 {
	// A truthful local platform error, not a submitted or user-cancelled refund.
	// CFError's existing Swift Error representation owns its domain/userInfo.
	owner := objc_allocate(cf_error_type_id())
	mut header := obj_header(owner)
	header.number = 19 // SDK SKErrorUnsupportedPlatform.
	header.fields[0] = owned_string('SKErrorDomain')
	info := objc_allocate(ios_runtime.names['NSDictionary'])
	header.fields[1] = info
	mut fields := obj_header(info)
	fields.keys << owned_string('NSLocalizedDescription')
	description := owned_string('Refund requests are unavailable on this platform.')
	array_append(mut fields, description)
	objc_release(description)
	return owner
}

fn refund_status_tag_width(cases u32) u32 {
	if cases <= 254 { return 0 }
	count := cases + u32(1) // Preserve native UInt32 overflow at UINT32_MAX.
	return if count >> 8 < 255 { u32(1) } else if count < 0xffff00 { u32(2) } else { u32(4) }
}

fn refund_status_enum_get(value u64, cases u32, _metadata u64) u32 {
	if cases == 0 { return 0 }
	mut extra := u32(0)
	for i in u32(0) .. refund_status_tag_width(cases) {
		extra |= u32(unsafe { *(&u8(value + 1 + i)) }) << (i * 8)
	}
	byte := u32(unsafe { *(&u8(value)) })
	if extra != 0 { return ((extra - 1) << 8) + byte + 255 }
	return if byte < 2 { u32(0) } else { byte - 1 }
}

fn refund_status_enum_store(value u64, tag u32, cases u32, _metadata u64) {
	extra := if tag <= 254 { u32(0) } else { ((tag - 255) >> 8) + 1 }
	for i in u32(0) .. refund_status_tag_width(cases) {
		unsafe { *(&u8(value + 1 + i)) = u8(extra >> (i * 8)) }
	}
	if tag != 0 { unsafe { *(&u8(value)) = if tag <= 254 { u8(tag + 1) } else { u8(tag - 255) } } }
}

fn refund_symbol(symbol string) ?u64 {
	if symbol != refund_entry_symbol && symbol != refund_descriptor_symbol
		&& symbol != refund_status_symbol && symbol != '_$s8StoreKit11TransactionV19RefundRequestStatusOMn' { return none }
	$if !arm64 { return none }
	if ios_runtime == unsafe { nil } { return none }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.storefront_retired { return none }
	base := storefront_arena_locked() or { return none }
	if symbol == refund_entry_symbol { return base + 128 }
	if symbol == refund_descriptor_symbol { return base + u64(C.getpagesize()) + 352 }
	if symbol == refund_status_symbol { return base + 192 }
	return base + u64(C.getpagesize()) + 544
}

fn refund_emit(code u64, data u64) {
	// x0 is the untouched indirect enum result; x1/x2 are borrowed transaction
	// ID/scene arguments. Return an owned Error in x21 to the same child x22.
	// Restore the C frame before the tail resume, which may free that child.
	for i, op in [u32(0xa9bf7bfd), 0x580000f0, 0xd63f0200, 0xaa0003f5,
		0xa8c17bfd, 0xf94006d0, 0xd61f0200]! { write32(code + 128 + u64(i * 4), op) }
	unsafe { *(&u64(code + 160)) = u64(voidptr(refund_unavailable)) }
	swift_protocol_relative(data + 352, code + 128)
	write32(data + 356, 112) // This profile's context; measured Mac entry uses 112.
	entry := code + 192
	metadata := data + 384
	witness := data + 416
	descriptor := data + 544
	write32(entry, 0x58000080); write32(entry + 4, 0xd2800001); write32(entry + 8, 0xd65f03c0)
	unsafe {
		*(&u64(entry + 16)) = metadata
		*(&u64(metadata - 8)) = witness; *(&u64(metadata)) = 0x201; *(&u64(metadata + 8)) = descriptor
		*(&u64(witness + 64)) = 1; *(&u64(witness + 72)) = 1
		*(&u64(witness + 88)) = u64(voidptr(swift_calendar_identifier_tag))
		*(&u64(witness + 96)) = u64(voidptr(swift_integer_destroy))
		*(&u64(witness + 104)) = u64(voidptr(swift_calendar_identifier_inject))
	}
	for i, function in [u64(unsafe { voidptr(swift_byte_copy) }), u64(unsafe { voidptr(swift_integer_destroy) }),
		u64(unsafe { voidptr(swift_byte_copy) }), u64(unsafe { voidptr(swift_byte_copy) }),
		u64(unsafe { voidptr(swift_byte_copy) }), u64(unsafe { voidptr(swift_byte_copy) }),
		u64(unsafe { voidptr(refund_status_enum_get) }), u64(unsafe { voidptr(refund_status_enum_store) })]! {
		unsafe { *(&u64(witness + u64(i * 8))) = function }
	}
	write32(witness + 80, 0x02200000); write32(witness + 84, 254)
	// Private nested nongeneric nominal descriptors, without reflection flags.
	write32(descriptor, 0x52)
	swift_protocol_relative(descriptor + 4, data + 576)
	swift_protocol_relative(descriptor + 8, data + 656)
	swift_protocol_relative(descriptor + 12, entry)
	write32(descriptor + 24, 2)
	write32(data + 576, 0x51)
	swift_protocol_relative(data + 580, data + 608)
	swift_protocol_relative(data + 584, data + 640)
	swift_protocol_relative(data + 616, data + 624)
	C.memcpy(voidptr(data + 624), c'StoreKit', 9)
	C.memcpy(voidptr(data + 640), c'Transaction', 12)
	C.memcpy(voidptr(data + 656), c'RefundRequestStatus', 20)
}
