// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftRawDecodingFailure {}

fn (_ &SwiftRawDecodingFailure) msg() string {
	return 'iOS: unsupported Swift RawRepresentable Int decoding representation'
}

fn (_ &SwiftRawDecodingFailure) code() int { return 1 }

struct SwiftRawDecodingInvalid {}

fn (_ &SwiftRawDecodingInvalid) msg() string {
	return 'iOS: Swift RawRepresentable Int decoding invalid rawValue requires DecodingError.dataCorrupted'
}

fn (_ &SwiftRawDecodingInvalid) code() int { return 1 }

__global swift_raw_decoding_failure_value = SwiftRawDecodingFailure{}
__global swift_raw_decoding_invalid_value = SwiftRawDecodingInvalid{}

fn swift_raw_decoding_failure() IError { return unsafe { &swift_raw_decoding_failure_value } }

type SwiftRawIntegerDecodeCall = fn (u64, u64, u64, u64, u64, u64) u64
type SwiftRawIntegerInitCall = fn (u64, u64, u64, u64, u64)
type SwiftRawIntegerTag = fn (u64, u32, u64) u32
type SwiftRawIntegerTake = fn (u64, u64, u64) u64

// Decoder is consumed, whereas its projection and Self's metadata/table are
// borrowed. Int fixes RawValue's layout; the associated-type slot and the
// Self:Decodable argument are unused. No lock spans an application witness.
fn swift_raw_integer_decoding_checked(decoder u64, metadata u64, _decodable u64,
	raw_table u64, output u64, incoming u64) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired
		|| metadata < 8 || metadata & 7 != 0 {
		return swift_raw_decoding_failure()
	}
	witness := read64(metadata - 8)
	if witness == 0 || witness & 7 != 0 || witness > ~u64(0) - 88 {
		return swift_raw_decoding_failure()
	}
	size := read64(witness + 64)
	stride := read64(witness + 72)
	flags := read32(witness + 80)
	mask := u64(flags & 255)
	if size > 65536 || size > stride || stride == 0 || stride & mask != 0
		|| mask & (mask + 1) != 0 || flags & 0x00400000 != 0 {
		return swift_raw_decoding_failure()
	}
	initialize := swift_raw_encoding_callback_checked(raw_table, 16)!
	get_tag := unsafe { SwiftRawIntegerTag(voidptr(swift_raw_encoding_callback_checked(witness, 48)!)) }
	take := unsafe { SwiftRawIntegerTake(voidptr(swift_raw_encoding_callback_checked(witness, 32)!)) }
	destroy := unsafe { SwiftRawDestroy(voidptr(swift_raw_encoding_callback_checked(witness, 8)!)) }
	decoder_value := swift_raw_encoding_value_checked(decoder)!
	defer { swift_raw_encoding_destroy(decoder, decoder_value) }
	decoder_self := swift_raw_encoding_project_checked(decoder, decoder_value, false)!
	getter := swift_raw_encoding_callback_checked(decoder_value.table, 40)!
	container := u64(C.__builtin_alloca(48))
	integer := u64(C.__builtin_alloca(16))
	call := unsafe { SwiftRawIntegerDecodeCall(voidptr(swift_hash_entry(1216))) }
	mut thrown := call(getter, container, decoder_value.metadata, decoder_value.table, decoder_self, incoming)
	if thrown != 0 { return thrown } // No container was initialized.
	container_value := swift_raw_encoding_value_checked(container)!
	// Native Swift destroys this owned container before init(rawValue:).
	// A lexical block guarantees cleanup on decode and checked-dispatch errors.
	{
		defer { swift_raw_encoding_destroy(container, container_value) }
		container_self := swift_raw_encoding_project_checked(container, container_value, false)!
		decode := swift_raw_encoding_callback_checked(container_value.table, 56)!
		decode_int := unsafe { SwiftRawIntegerDecodeCall(voidptr(swift_hash_entry(1280))) }
		thrown = decode_int(decode, container_value.metadata, container_value.table, container_self, incoming, integer)
	}
	if thrown != 0 { return thrown }
	// Optional<Self> needs at most one extra tag byte. Overallocate for Self's
	// alignment, including boxed/non-POD Self, without constructing metadata.
	storage := u64(C.__builtin_alloca(usize(size + mask + 16)))
	optional := (storage + mask) & ~mask
	init_raw := unsafe { SwiftRawIntegerInitCall(voidptr(swift_hash_entry(1376))) }
	init_raw(initialize, optional, integer, metadata, raw_table)
	tag := get_tag(optional, 1, metadata)
	if tag == 1 {
		// None has no owned payload. Generic Swift error boxes and the
		// DecodingError.Context metadata are not yet implemented: fail explicitly
		// after consuming Decoder, rather than manufacture a different error.
		return unsafe { &swift_raw_decoding_invalid_value }
	}
	if tag != 0 { return swift_raw_decoding_failure() }
	if output == 0 || output & mask != 0 || output > ~u64(0) - size {
		// A successful initializer owns Self even if the caller's output is bad.
		destroy(optional, metadata)
		return swift_raw_decoding_failure()
	}
	take(output, optional, metadata)
	return 0
}

fn swift_raw_integer_decoding(decoder u64, metadata u64, decodable u64,
	raw_table u64, output u64, incoming u64) u64 {
	return swift_raw_integer_decoding_checked(decoder, metadata, decodable, raw_table, output, incoming) or { panic(err) }
}

fn swift_raw_integer_decoding_emit(code u64) {
	// Swift x0..x3 / indirect result x8 / incoming x21 -> ordinary V call.
	for i, op in [u32(0xa9bf7bfd), 0xaa0803e4, 0xaa1503e5, 0x580000b0, 0xd63f0200, 0xaa0003f5,
		0xa8c17bfd, 0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	unsafe { *(&u64(code + 32)) = u64(voidptr(swift_raw_integer_decoding)) }
	// C -> throwing Decoder.singleValueContainer(), indirect result in x8.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0103e8, 0xaa0203e0,
		0xaa0303e1, 0xaa0403f4, 0xaa0503f5, 0xd63f0200, 0xaa1503e0, 0xa9425bf5, 0xa94153f3, 0xa8c37bfd,
		0xd65f03c0]! {
		write32(code + 64 + u64(i * 4), op)
	}
	// C -> throwing decode(Int), returning Int in x0 and owned error in x21.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0503f3, 0xaa0103e0,
		0xaa0203e1, 0xaa0303f4, 0xaa0403f5, 0xd63f0200, 0xf9000260, 0xaa1503e0, 0xa9425bf5, 0xa94153f3,
		0xa8c37bfd, 0xd65f03c0]! {
		write32(code + 128 + u64(i * 4), op)
	}
	// C -> nonthrowing init(rawValue:), indirect Optional<Self> result.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0003f0, 0xaa0103e8, 0xaa0203e0,
		0xaa0303e1, 0xaa0403e2, 0xaa0303f4, 0xd63f0200, 0xa9425bf5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + 224 + u64(i * 4), op)
	}
}

fn swift_raw_integer_decoding_symbol(symbol string) ?u64 {
	if symbol != '_$sSYsSeRzSi8RawValueSYRtzrlE4fromxs7Decoder_p_tKcfC'
		|| ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return none
	}
	return swift_hash_entry(1152)
}
