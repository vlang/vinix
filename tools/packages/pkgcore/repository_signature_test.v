// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import encoding.hex
import tools.packages.signing

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32

// Compatibility oracle only: the production verifier previously used these
// exact trim/hex operations. Their private scratch stays outside measured frames.
fn legacy_signature(input string) ![]u8 {
	trimmed := input.trim_space()
	defer { unsafe { trimmed.free() } }
	decoded := hex.decode(trimmed)!
	if decoded.len != 64 {
		unsafe { decoded.free() }
		return error('fixture: repository signature verification failed; check administrator key enrollment')
	}
	return decoded
}

fn check_signature_compatibility(input string) ! {
	if expected := legacy_signature(input) {
		actual := decode_repository_signature('fixture', input)!
		assert actual == expected
		unsafe { actual.free(); expected.free() }
	} else {
		expected_message := err.msg()
		defer { unsafe { expected_message.free(); err.free() } }
		if actual := decode_repository_signature('fixture', input) { unsafe { actual.free() }; assert false }
		else {
			message := err.msg(); assert message == expected_message
			unsafe { message.free(); err.free() }
		}
	}
}

fn test_signature_reader_preserves_legacy_forms_and_error_positions() {
	base := '0123456789aBcDeF'.repeat(8)
	for input in ['', ' ', '\t\n\v\f\r', '0', 'f', '0x', '0X', '0x0', 'not-hex', base,
		base.to_upper(), base[1..], base[..126], base + '0', base + '00', '0x' + base,
		'0X' + base[1..], ' \n\t\v\f\r0X' + base + '\r\f\v\t\n ', '0x 00', '0y' + base,
		'\u00a0' + base, base + '\u00a0'] { check_signature_compatibility(input)! }
	for position in [0, 1, 63, 126, 127, 128] {
		for prefix in ['', '0x', '0X'] {
			mut bytes := []u8{len: 129, init: `a`}
			bytes[position] = `!`
			text := bytes.bytestr()
			check_signature_compatibility(' \t' + prefix + text + '\n')!
			unsafe { text.free(); bytes.free() }
		}
	}
	// Interior byte coverage includes embedded NUL, all ASCII controls, high
	// bytes and non-ASCII UTF-8 fragments, with the prefix included in offsets.
	for byte in 0 .. 256 {
		mut bytes := []u8{len: 128, init: `a`}
		bytes[17] = u8(byte)
		text := bytes.bytestr()
		check_signature_compatibility('0X' + text)!
		unsafe { text.free(); bytes.free() }
	}
	println('SIGNATURE DECODING legacy case, prefixes, odd leading-zero form, six ASCII whitespace bytes and all 256 interior bytes preserve results and diagnostics PASS')
}

fn signed_signature_fixture() !(Repository, string, string) {
	private := signing.new_key_from_seed([]u8{len: 32, init: 7})
	repository := Repository{ id: 'fixture', public_key: private.public_key().hex() }
	for sequence in 1 .. 129 {
		text := canonical_index(Index{ repository: 'fixture', sequence: u64(sequence), expires: 2000000000 })!
		bytes := text.bytes()
		signature := signing.sign(private, bytes)!
		encoded := signature.hex()
		unsafe { bytes.free(); signature.free() }
		// A leading zero nibble can be omitted without changing signed bytes.
		if encoded[0] == `0` { return repository, text, encoded }
		unsafe { text.free(); encoded.free() }
	}
	return error('deterministic signature fixture did not find a leading zero')
}

fn test_signature_forms_still_authenticate_exact_signed_bytes_and_preserve_admission_order() {
	repository, text, signature := signed_signature_fixture()!
	for input in [signature, signature.to_upper(), '0x' + signature, '0X' + signature.to_upper(),
		signature[1..], '\v\f \t0x' + signature[1..] + '\r\n'] {
		index := verify_index(repository, text, input, 1900000000)!
		assert index.repository == repository.id && index.sequence > 0
		close_decoded_index(index)
		if changed := verify_index(repository, text + ' ', input, 1900000000) { close_decoded_index(changed); assert false }
		else { assert err.msg().contains('signature verification failed') }
	}
	if _ := verify_index(repository, text, signature, 2000000000) { assert false }
	else { assert err.msg().contains('expired') }
	if _ := verify_index(Repository{ ...repository, id: 'other' }, text, signature, 1900000000) { assert false }
	else { assert err.msg().contains('misidentified') }
	if _ := verify_index(repository, 'x'.repeat(max_metadata + 1), '!', 1900000000) { assert false }
	else { assert err.msg().contains('index too large') }
	if _ := verify_index(Repository{ ...repository, public_key: 'bad' }, text, '!', 1900000000) { assert false }
	else { assert err.msg().contains('publisher key') }
	if _ := verify_index(repository, 'not JSON', '0X!', 1900000000) { assert false }
	else { assert err.msg() == 'invalid hex char ! at index 2' }
	println('SIGNATURE DECODING accepted forms authenticate exact bytes; tampering, expiry, identity and size/key/signature precedence remain enforced PASS')
}

fn test_long_signatures_and_whitespace_preserve_borrowed_inputs() {
	base := 'a'.repeat(128)
	oversized := 'a'.repeat(1024 * 1024)
	padding := ' \t\r\n\v\f'.repeat(32 * 1024)
	for input in [oversized, oversized + '!', padding + '0X' + base + padding] {
		check_signature_compatibility(input)!
	}
	assert oversized.len == 1024 * 1024 && oversized[0] == `a` && oversized[oversized.len - 1] == `a`
	assert padding[0] == ` ` && base == 'a'.repeat(128)
	println('SIGNATURE DECODING megabyte wrong-length/late-invalid inputs and long outer whitespace preserve compatibility and source bytes PASS')
}

fn test_repeated_signature_decoding_releases_all_success_and_failure_scratch() {
	$if track_heap ? {
		base := 'a'.repeat(128)
		inputs := [base, '0X' + base.to_upper(), ' \t0x' + base[1..] + '\v\f\r\n',
			'0X!', base + '!', '', 'a'.repeat(1024 * 1024), 'a'.repeat(1024 * 1024) + '!']
		for input in inputs {
			for _ in 0 .. 16 {
				C.vinix_heap_begin()
				if decoded := decode_repository_signature('fixture', input) { unsafe { decoded.free() } }
				else { message := err.msg(); unsafe { message.free(); err.free() } }
				kept := C.vinix_heap_end(); count := C.vinix_heap_count()
				assert kept == 0 && count == 0, '${kept} bytes / ${count} allocations retained'
			}
		}
		println('SIGNATURE DECODING 16 repetitions of accepted, malformed and megabyte oversized inputs retain zero decoder scratch after caller cleanup PASS')
	}
}
