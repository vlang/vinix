// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftRawEncodingFailure {}

fn (_ &SwiftRawEncodingFailure) msg() string {
	return 'iOS: unsupported Swift RawRepresentable Int encoding representation'
}

fn (_ &SwiftRawEncodingFailure) code() int { return 1 }

__global swift_raw_encoding_failure_value = SwiftRawEncodingFailure{}

fn swift_raw_encoding_failure() IError { return unsafe { &swift_raw_encoding_failure_value } }

struct SwiftRawEncodingValue {
	metadata u64
	table    u64
	destroy  u64
	size     u64
	mask     u64
	boxed    bool
}

type SwiftRawIntegerEncodeCall = fn (u64, u64, u64, u64, u64, u64) u64

// Borrowed readable ABI records. Separate value layout validation from
// protocol dispatch so an owned container is destroyed even if dispatch fails.
fn swift_raw_encoding_value_checked(value u64) !SwiftRawEncodingValue {
	if value == 0 || value & 7 != 0 || value > ~u64(0) - 40 { return swift_raw_encoding_failure() }
	metadata := read64(value + 24)
	if metadata < 8 || metadata & 7 != 0 { return swift_raw_encoding_failure() }
	witness := read64(metadata - 8)
	if witness == 0 || witness & 7 != 0 || witness > ~u64(0) - 88 {
		return swift_raw_encoding_failure()
	}
	size := read64(witness + 64)
	stride := read64(witness + 72)
	flags := read32(witness + 80)
	mask := u64(flags & 255)
	destroy := read64(witness + 8)
	boxed := flags & 0x20000 != 0
	if size > 65536 || size > stride || stride == 0 || stride & mask != 0
		|| mask & (mask + 1) != 0 || flags & 0x00400000 != 0
		|| destroy == 0 || destroy & 3 != 0 || (!boxed && (size > 24 || mask > 7)) {
		return swift_raw_encoding_failure()
	}
	return SwiftRawEncodingValue{
		metadata: metadata
		table:    read64(value + 32)
		destroy:  destroy
		size:     size
		mask:     mask
		boxed:    boxed
	}
}

fn swift_raw_encoding_project_checked(value u64, layout SwiftRawEncodingValue, mutable bool) !u64 {
	if !layout.boxed { return value }
	// Borrowed Encoder boxes require no uniqueness check. Mutating a shared
	// container needs copy-on-write support before this profile can admit it.
	if mutable { return swift_raw_encoding_failure() }
	owner := read64(value)
	offset := (16 + layout.mask) & ~layout.mask
	if owner == 0 || owner & 7 != 0 || owner > ~u64(0) - offset - layout.size {
		return swift_raw_encoding_failure()
	}
	return owner + offset
}

fn swift_raw_encoding_callback_checked(table u64, offset u64) !u64 {
	if table == 0 || table & 7 != 0 || table > ~u64(0) - offset - 8 {
		return swift_raw_encoding_failure()
	}
	callback := read64(table + offset)
	if callback == 0 || callback & 3 != 0 { return swift_raw_encoding_failure() }
	return callback
}

fn swift_raw_encoding_destroy(value u64, layout SwiftRawEncodingValue) {
	if layout.boxed {
		swift_release(read64(value))
		return
	}
	destroy := unsafe { SwiftRawDestroy(voidptr(layout.destroy)) }
	destroy(value, layout.metadata)
}

// Encoder x0, Self metadata x1, unused Self:Encodable x2, RawRepresentable
// x3, borrowed Self x20. The RawValue == Int constraint fixes the getter's
// eight-byte result; no associated-type lookup or Int destruction is needed.
fn swift_raw_integer_encoding_checked(encoder u64, metadata u64, _encodable u64,
	raw_table u64, receiver u64, incoming u64) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired
		|| metadata < 8 || metadata & 7 != 0 || receiver == 0 {
		return swift_raw_encoding_failure()
	}
	raw_getter := swift_raw_encoding_callback_checked(raw_table, 24)!
	encoder_value := swift_raw_encoding_value_checked(encoder)!
	encoder_self := swift_raw_encoding_project_checked(encoder, encoder_value, false)!
	container_getter := swift_raw_encoding_callback_checked(encoder_value.table, 40)!
	container := u64(C.__builtin_alloca(48))
	integer := u64(C.__builtin_alloca(16))
	get := unsafe { SwiftRawGetterCall(voidptr(swift_hash_entry(960))) }
	get(container_getter, container, encoder_value.metadata, encoder_value.table, encoder_self)
	container_value := swift_raw_encoding_value_checked(container)!
	defer { swift_raw_encoding_destroy(container, container_value) }
	get(raw_getter, integer, metadata, raw_table, receiver)
	container_self := swift_raw_encoding_project_checked(container, container_value, true)!
	encode := swift_raw_encoding_callback_checked(container_value.table, 56)!
	call := unsafe { SwiftRawIntegerEncodeCall(voidptr(swift_hash_entry(1024))) }
	return call(encode, read64(integer), container_value.metadata, container_value.table, container_self, incoming)
}

fn swift_raw_integer_encoding(encoder u64, metadata u64, encodable u64,
	raw_table u64, receiver u64, incoming u64) u64 {
	return swift_raw_integer_encoding_checked(encoder, metadata, encodable, raw_table, receiver, incoming) or { panic(err) }
}

fn swift_raw_integer_encoding_emit(code u64) {
	for i, op in [u32(0xa9bf7bfd), 0xaa1403e4, 0xaa1503e5, 0x580000b0, 0xd63f0200, 0xaa0003f5,
		0xa8c17bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	unsafe { *(&u64(code + 32)) = u64(voidptr(swift_raw_integer_encoding)) }
	// C -> nonthrowing Swift getter; preserve C's context and x21 even if
	// the witness uses Swift's error register as a temporary.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0103e8, 0xaa0203e0,
		0xaa0303e1, 0xaa0403f4, 0xd63f0200, 0xa9425bf5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + 64 + u64(i * 4), op)
	}
	// C -> throwing SingleValueEncodingContainer.encode(Int). Forward the
	// original incoming error and return the exact owned x21 error to C.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0103e0, 0xaa0203e1,
		0xaa0303e2, 0xaa0403f4, 0xaa0503f5, 0xd63f0200, 0xaa1503e0, 0xa9425bf5, 0xa94153f3, 0xa8c37bfd,
		0xd65f03c0]! {
		write32(code + 128 + u64(i * 4), op)
	}
}

fn swift_raw_integer_encoding_symbol(symbol string) ?u64 {
	if symbol != '_$sSYsSERzSi8RawValueSYRtzrlE6encode2toys7Encoder_p_tKF'
		|| ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return none
	}
	return swift_hash_entry(896)
}
