// SPDX-License-Identifier: GPL-2.0-or-later
// Certificate/key data APIs. Parsing a certificate does not establish trust.
module main

import crypto.sha1
import encoding.utf8

#include <sys/random.h>

fn C.getentropy(bytes voidptr, count usize) i32

struct SecurityDer {
	tag    u8
	start  int
	offset int
	length int
	end    int
}

struct SecurityReader {
	bytes &u8
	limit int
mut:
	pos int
}

// Non-owning cursors never allocate, including malformed input. DER lengths
// and nested bounds are checked before any byte or pointer is accessed.
fn (mut r SecurityReader) next() ?SecurityDer {
	start := r.pos
	if r.pos < 0 || r.pos >= r.limit { return none }
	tag := unsafe { r.bytes[r.pos] }
	r.pos++
	if tag == 0 || tag & 31 == 31 || r.pos >= r.limit { return none }
	first := unsafe { r.bytes[r.pos] }
	r.pos++
	mut length := u64(first)
	if first >= 128 {
		count := int(first & 127)
		if count == 0 || count > 4 || count > r.limit - r.pos || unsafe { r.bytes[r.pos] } == 0 {
			return none
		}
		length = 0
		for _ in 0 .. count {
			length = (length << 8) | unsafe { r.bytes[r.pos] }
			r.pos++
		}
		if length < 128 { return none }
	}
	if length > u64(r.limit - r.pos) { return none }
	field := SecurityDer{tag, start, r.pos, int(length), r.pos + int(length)}
	r.pos = field.end
	return field
}

fn (mut r SecurityReader) expect(tag u8) ?SecurityDer {
	field := r.next() or { return none }
	if field.tag != tag { return none }
	return field
}

fn security_inside(bytes &u8, field SecurityDer) SecurityReader {
	return SecurityReader{ bytes: bytes, limit: field.end, pos: field.offset }
}

fn security_hex_byte(text string, offset int) u8 {
	mut value := u8(0)
	for i in offset .. offset + 2 {
		b := text[i]
		value = (value << 4) | if b >= `A` { b - `A` + 10 } else { b - `0` }
	}
	return value
}

fn security_der_oid(bytes &u8, field SecurityDer, hex string) bool {
	if field.tag != 6 || field.length * 2 != hex.len { return false }
	for i in 0 .. field.length {
		if unsafe { bytes[field.offset + i] } != security_hex_byte(hex, i * 2) { return false }
	}
	return true
}

fn security_der_valid(bytes &u8, field SecurityDer, depth int) bool {
	if depth > 16 { return false }
	if field.tag & 32 != 0 {
		mut nested := security_inside(bytes, field)
		for nested.pos < nested.limit {
			child := nested.next() or { return false }
			if !security_der_valid(bytes, child, depth + 1) { return false }
		}
	} else if field.tag == 2 {
		if field.length == 0 { return false }
		if field.length > 1 {
			a := unsafe { bytes[field.offset] }
			b := unsafe { bytes[field.offset + 1] }
			if (a == 0 && b < 128) || (a == 255 && b >= 128) { return false }
		}
	} else if field.tag == 3 {
		if field.length == 0 { return false }
		unused := unsafe { bytes[field.offset] }
		if unused > 7 || (field.length == 1 && unused != 0) { return false }
		if unused != 0 && unsafe { bytes[field.end - 1] } & u8((u16(1) << unused) - 1) != 0 {
			return false
		}
	} else if field.tag == 5 {
		if field.length != 0 { return false }
	} else if field.tag == 6 {
		if field.length == 0 || unsafe { bytes[field.end - 1] } & 128 != 0 { return false }
		mut start := true
		for i in field.offset .. field.end {
			byte := unsafe { bytes[i] }
			if start && byte == 128 { return false }
			start = byte & 128 == 0
		}
	}
	return true
}

struct SecurityCertificate {
	certificate SecurityDer
	serial      SecurityDer
	issuer      SecurityDer
	not_before  SecurityDer
	not_after   SecurityDer
	subject     SecurityDer
	spki        SecurityDer
	algorithm   SecurityDer
	signature   SecurityDer
	extensions  SecurityDer
	unique_ids  bool
}

fn security_name_valid(bytes &u8, name SecurityDer) bool {
	mut rdns := security_inside(bytes, name)
	for rdns.pos < rdns.limit {
		set := rdns.expect(0x31) or { return false }
		if set.length == 0 { return false }
		mut entries := security_inside(bytes, set)
		for entries.pos < entries.limit {
			entry := entries.expect(0x30) or { return false }
			mut pair := security_inside(bytes, entry)
			pair.expect(6) or { return false }
			pair.next() or { return false }
			if pair.pos != pair.limit { return false }
		}
	}
	return true
}

fn security_algorithm_valid(bytes &u8, algorithm SecurityDer) bool {
	mut fields := security_inside(bytes, algorithm)
	fields.expect(6) or { return false }
	if fields.pos < fields.limit { fields.next() or { return false } }
	return fields.pos == fields.limit
}

fn security_certificate_parse(bytes &u8, count int) ?SecurityCertificate {
	if bytes == unsafe { nil } || count < 1 || count > 16777216 { return none }
	mut input := SecurityReader{ bytes: bytes, limit: count }
	outer := input.expect(0x30) or { return none }
	if !security_der_valid(bytes, outer, 0) { return none }
	mut body := security_inside(bytes, outer)
	tbs := body.expect(0x30) or { return none }
	signature := body.expect(0x30) or { return none }
	bits := body.expect(3) or { return none }
	if body.pos != body.limit || bits.length < 2 || !security_algorithm_valid(bytes, signature) {
		return none
	}
	mut fields := security_inside(bytes, tbs)
	mut serial := fields.next() or { return none }
	if serial.tag == 0xa0 {
		mut version := security_inside(bytes, serial)
		value := version.expect(2) or { return none }
		if version.pos != version.limit || value.length != 1 || unsafe { bytes[value.offset] } > 2 {
			return none
		}
		serial = fields.next() or { return none }
	}
	if serial.tag != 2 { return none }
	algorithm := fields.expect(0x30) or { return none }
	if !security_algorithm_valid(bytes, algorithm) { return none }
	issuer := fields.expect(0x30) or { return none }
	if !security_name_valid(bytes, issuer) { return none }
	validity := fields.expect(0x30) or { return none }
	mut dates := security_inside(bytes, validity)
	not_before := dates.next() or { return none }
	not_after := dates.next() or { return none }
	if not_before.tag !in [u8(23), 24] || not_after.tag !in [u8(23), 24] ||
		not_before.length == 0 || not_after.length == 0 { return none }
	if dates.pos != dates.limit { return none }
	subject := fields.expect(0x30) or { return none }
	if !security_name_valid(bytes, subject) { return none }
	spki := fields.expect(0x30) or { return none }
	mut public := security_inside(bytes, spki)
	key_algorithm := public.expect(0x30) or { return none }
	if !security_algorithm_valid(bytes, key_algorithm) { return none }
	key_bits := public.expect(3) or { return none }
	if public.pos != public.limit || key_bits.length < 2 { return none }
	mut previous := u8(0x80)
	mut extensions := SecurityDer{}
	mut unique_ids := false
	for fields.pos < fields.limit {
		optional := fields.next() or { return none }
		if optional.tag !in [u8(0x81), 0x82, 0xa3] || optional.tag <= previous { return none }
		previous = optional.tag
		if optional.tag == 0xa3 { extensions = optional } else { unique_ids = true }
	}
	return SecurityCertificate{
		certificate: outer, serial: serial, issuer: issuer, not_before: not_before,
		not_after: not_after, subject: subject, spki: spki, algorithm: algorithm,
		signature: signature, extensions: extensions, unique_ids: unique_ids
	}
}

fn sec_certificate_type_id() u64 { return ios_runtime.names['VinixSecCertificate'] }

fn sec_key_type_id() u64 { return ios_runtime.names['VinixSecKey'] }

fn cf_error_type_id() u64 { return ios_runtime.names['VinixCFError'] }

fn sec_certificate_create(allocator u64, data u64) u64 {
	cf_allocator_check(allocator)
	if data == 0 || !objc_is_kind(data, ios_runtime.names['NSData']) { return 0 }
	count := data_length(data)
	if count > 16777216 { return 0 }
	bytes := unsafe { &u8(data_pointer(data)) }
	parsed := security_certificate_parse(bytes, int(count)) or { return 0 }
	object := objc_allocate(sec_certificate_type_id())
	mut header := obj_header(object)
	header.data = []u8{len: parsed.certificate.end}
	header.data.flags |= .noslices
	unsafe { C.memcpy(header.data.data, bytes, usize(header.data.len)) }
	return object
}

fn security_certificate(object u64) ?SecurityCertificate {
	if object == 0 || read64(object) != sec_certificate_type_id() { return none }
	header := obj_header(object)
	return security_certificate_parse(header.data.data, header.data.len)
}

fn sec_certificate_data(object u64) u64 {
	if object == 0 { return 0 }
	security_certificate(object) or { return 0 }
	header := obj_header(object)
	return cf_data_create(0, u64(header.data.data), header.data.len)
}

fn sec_certificate_summary(object u64) u64 {
	parsed := security_certificate(object) or { return 0 }
	bytes := unsafe { &u8(obj_header(object).data.data) }
	mut selected := SecurityDer{}
	mut priority := 0
	mut rdns := security_inside(bytes, parsed.subject)
	for rdns.pos < rdns.limit {
		set := rdns.expect(0x31) or { return 0 }
		mut entries := security_inside(bytes, set)
		for entries.pos < entries.limit {
			entry := entries.expect(0x30) or { return 0 }
			mut pair := security_inside(bytes, entry)
			oid := pair.expect(6) or { return 0 }
			value := pair.next() or { return 0 }
			rank := if security_der_oid(bytes, oid, '550403') {
				3
			} else if security_der_oid(bytes, oid, '55040B') {
				2
			} else if security_der_oid(bytes, oid, '55040A') {
				1
			} else {
				0
			}
			if rank > priority && value.length != 0 {
				priority = rank
				selected = value
			}
		}
	}
	if priority == 0 { return 0 }
	if selected.tag in [u8(12), 19, 22] {
		text := unsafe { tos(bytes + selected.offset, selected.length) }
		if !utf8.validate_str(text) { return 0 }
		return owned_string(text)
	}
	// Other X.509 string encodings require a decoder; do not mislabel bytes UTF-8.
	return 0
}

fn security_decode_error(error_output &u64) {
	security_error(error_output, -26275)
}

fn security_error(error_output &u64, code int) {
	if error_output == unsafe { nil } { return }
	object := objc_allocate(cf_error_type_id())
	mut header := obj_header(object)
	header.number = code
	header.fields[0] = owned_string('NSOSStatusErrorDomain')
	unsafe { *error_output = object }
}

fn cf_error_code(object u64) i64 {
	if object == 0 || read64(object) != cf_error_type_id() {
		panic('iOS: unsupported CFError object')
	}
	return obj_header(object).number
}

fn cf_error_domain(object u64) u64 {
	if object == 0 || read64(object) != cf_error_type_id() {
		panic('iOS: unsupported CFError object')
	}
	return obj_header(object).fields[0]
}

fn sec_certificate_serial(object u64, error_output &u64) u64 {
	parsed := security_certificate(object) or {
		security_decode_error(error_output)
		return 0
	}
	bytes := u64(obj_header(object).data.data) + u64(parsed.serial.offset)
	return cf_data_create(0, bytes, parsed.serial.length)
}

// Fixed-size arithmetic validates public EC points, without hidden allocation
// or accepting arbitrary bytes as a usable public key. These operations handle
// public data only; they are not a signing or private-key implementation.
struct SecurityField {
mut:
	words [17]u32
}

fn security_field_bytes(bytes &u8, count int) SecurityField {
	mut value := SecurityField{}
	for i in 0 .. count {
		value.words[i / 4] |= u32(unsafe { bytes[count - 1 - i] }) << u32((i % 4) * 8)
	}
	return value
}

fn security_field_hex(hex string) SecurityField {
	mut value := SecurityField{}
	for i in 0 .. hex.len / 2 {
		value.words[i / 4] |= u32(security_hex_byte(hex, hex.len - 2 - 2 * i)) << u32((i % 4) * 8)
	}
	return value
}

fn security_field_compare(a SecurityField, b SecurityField) int {
	for i := 16; i >= 0; i-- {
		if a.words[i] != b.words[i] { return if a.words[i] < b.words[i] { -1 } else { 1 } }
	}
	return 0
}

fn security_field_subtract(a SecurityField, b SecurityField) SecurityField {
	mut out := SecurityField{}
	mut borrow := u64(0)
	for i in 0 .. 17 {
		difference := (u64(1) << 32) + u64(a.words[i]) - u64(b.words[i]) - borrow
		out.words[i] = u32(difference)
		borrow = 1 - (difference >> 32)
	}
	return out
}

fn security_field_add(a SecurityField, b SecurityField, prime SecurityField) SecurityField {
	mut out := SecurityField{}
	mut carry := u64(0)
	for i in 0 .. 17 {
		sum := u64(a.words[i]) + u64(b.words[i]) + carry
		out.words[i] = u32(sum)
		carry = sum >> 32
	}
	if security_field_compare(out, prime) >= 0 { return security_field_subtract(out, prime) }
	return out
}

fn security_field_multiply(a SecurityField, b SecurityField, prime SecurityField, bits int) SecurityField {
	mut out := SecurityField{}
	mut doubled := a
	for i in 0 .. bits {
		if b.words[i / 32] & (u32(1) << u32(i % 32)) != 0 {
			out = security_field_add(out, doubled, prime)
		}
		doubled = security_field_add(doubled, doubled, prime)
	}
	return out
}

fn security_ec_point(bytes &u8, count int, bits int) bool {
	width := (bits + 7) / 8
	if count != 1 + width * 2 || unsafe { bytes[0] } != 4 { return false }
	prime := security_field_hex(match bits {
		256 { 'FFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF' }
		384 {
			'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFFFF0000000000000000FFFFFFFF'
		}
		521 {
			'01FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF'
		}
		else { return false }
	})
	constant := security_field_hex(match bits {
		256 { '5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B' }
		384 {
			'B3312FA7E23EE7E4988E056BE3F82D19181D9C6EFE8141120314088F5013875AC656398D8A2ED19D2A85C8EDD3EC2AEF'
		}
		else {
			'0051953EB9618E1C9A1F929A21A0B68540EEA2DA725B99B315F3B8B489918EF109E156193951EC7E937B1652C0BD3BB1BF073573DF883D2C34F1EF451FD46B503F00'
		}
	})
	x := security_field_bytes(unsafe { bytes + 1 }, width)
	y := security_field_bytes(unsafe { bytes + 1 + width }, width)
	if security_field_compare(x, prime) >= 0 || security_field_compare(y, prime) >= 0 {
		return false
	}
	x2 := security_field_multiply(x, x, prime, bits)
	x3 := security_field_multiply(x2, x, prime, bits)
	three_x := security_field_add(security_field_add(x, x, prime), x, prime)
	mut rhs := security_field_add(x3, constant, prime)
	if security_field_compare(rhs, three_x) < 0 {
		rhs = security_field_subtract(prime, security_field_subtract(three_x, rhs))
	} else {
		rhs = security_field_subtract(rhs, three_x)
	}
	return security_field_compare(security_field_multiply(y, y, prime, bits), rhs) == 0
}

fn sec_certificate_key(object u64) u64 {
	parsed := security_certificate(object) or { return 0 }
	bytes := unsafe { &u8(obj_header(object).data.data) }
	mut spki := security_inside(bytes, parsed.spki)
	algorithm := spki.expect(0x30) or { return 0 }
	payload := spki.expect(3) or { return 0 }
	if unsafe { bytes[payload.offset] } != 0 { return 0 }
	mut parameters := security_inside(bytes, algorithm)
	oid := parameters.expect(6) or { return 0 }
	mut bits := 0
	mut key_type := i64(0)
	start := payload.offset + 1
	count := payload.length - 1
	if security_der_oid(bytes, oid, '2A864886F70D010101') {
		if parameters.pos < parameters.limit { parameters.expect(5) or { return 0 } }
		if parameters.pos != parameters.limit { return 0 }
		mut key_der := SecurityReader{ bytes: bytes, pos: start, limit: payload.end }
		sequence := key_der.expect(0x30) or { return 0 }
		if key_der.pos != key_der.limit || !security_der_valid(bytes, sequence, 0) { return 0 }
		mut components := security_inside(bytes, sequence)
		modulus := components.expect(2) or { return 0 }
		exponent := components.expect(2) or { return 0 }
		if components.pos != components.limit || modulus.length < 2 || exponent.length < 1 || exponent.length > 8 {
			return 0
		}
		if unsafe { bytes[modulus.offset] } >= 128 || unsafe { bytes[exponent.offset] } >= 128 {
			return 0
		}
		first := modulus.offset + if unsafe { bytes[modulus.offset] } == 0 { 1 } else { 0 }
		mut leading := unsafe { bytes[first] }
		bits = (modulus.end - first - 1) * 8
		for leading != 0 {
			bits++
			leading >>= 1
		}
		mut e := u64(0)
		for i in exponent.offset .. exponent.end { e = (e << 8) | unsafe { bytes[i] } }
		if bits < 16 || bits > 8192 || e < 3 || e & 1 == 0 || unsafe { bytes[modulus.end - 1] } & 1 == 0 {
			return 0
		}
		key_type = 42
	} else if security_der_oid(bytes, oid, '2A8648CE3D0201') {
		curve := parameters.expect(6) or { return 0 }
		if parameters.pos != parameters.limit { return 0 }
		bits = if security_der_oid(bytes, curve, '2A8648CE3D030107') {
			256
		} else if security_der_oid(bytes, curve, '2B81040022') {
			384
		} else if security_der_oid(bytes, curve, '2B81040023') {
			521
		} else {
			return 0
		}
		if !security_ec_point(unsafe { bytes + start }, count, bits) { return 0 }
		key_type = 73
	} else {
		return 0
	}
	key := objc_allocate(sec_key_type_id())
	mut header := obj_header(key)
	header.number = bits
	header.section = key_type
	header.data = []u8{len: count}
	header.data.flags |= .noslices
	unsafe { C.memcpy(header.data.data, bytes + start, usize(count)) }
	return key
}

fn sec_key_data(key u64, error_output &u64) u64 {
	_ = error_output // Success leaves the caller's error output untouched.
	if key == 0 || read64(key) != sec_key_type_id() { panic('iOS: unsupported SecKey object') }
	header := obj_header(key)
	return cf_data_create(0, u64(header.data.data), header.data.len)
}

fn security_attribute(dictionary u64, name string, value u64) {
	address := security_constant(name) or { panic('iOS: missing Security attribute constant') }
	cf_dictionary_set(dictionary, read64(address), value)
}

fn sec_key_attributes(key u64) u64 {
	if key == 0 || read64(key) != sec_key_type_id() { panic('iOS: unsupported SecKey object') }
	header := obj_header(key)
	dictionary := objc_allocate(ios_runtime.names['NSMutableDictionary'])
	security_attribute(dictionary, '_kSecClass', read64(security_constant('_kSecClassKey') or { panic('iOS: missing Security class') }))
	security_attribute(dictionary, '_kSecAttrKeyClass', read64(security_constant('_kSecAttrKeyClassPublic') or { panic('iOS: missing Security key class') }))
	security_attribute(dictionary, '_kSecAttrKeyType', read64(security_constant(if header.section == 42 {
		'_kSecAttrKeyTypeRSA'
	} else {
		'_kSecAttrKeyTypeECSECPrimeRandom'
	}) or { panic('iOS: missing Security key type') }))
	size := objc_allocate(ios_runtime.names['NSNumber'])
	mut number := obj_header(size)
	number.number = header.number
	security_attribute(dictionary, '_kSecAttrKeySizeInBits', size)
	security_attribute(dictionary, '_kSecAttrEffectiveKeySize', size)
	objc_release(size)
	for name in ['_kSecAttrCanEncrypt', '_kSecAttrCanWrap', '_kSecAttrCanVerify', '_kSecAttrIsPermanent',
		'_kSecAttrIsPrivate', '_kSecAttrIsModifiable', '_kSecAttrIsExtractable']! {
		security_attribute(dictionary, name, framework_object('_kCFBooleanTrue'))
	}
	for name in ['_kSecAttrCanSign', '_kSecAttrCanUnwrap', '_kSecAttrCanDerive', '_kSecAttrIsSensitive',
		'_kSecAttrWasAlwaysSensitive', '_kSecAttrWasNeverExtractable']! {
		security_attribute(dictionary, name, framework_object('_kCFBooleanFalse'))
	}
	security_attribute(dictionary, '_kSecAttrCanDecrypt', framework_object(if header.section == 42 {
		'_kCFBooleanTrue'
	} else {
		'_kCFBooleanFalse'
	}))
	external := sec_key_data(key, unsafe { nil })
	security_attribute(dictionary, '_kSecValueData', external)
	objc_release(external)
	// Apple's application label is SHA-1 of the external public-key bytes. It is
	// an identifier, not a signature or a trust check. Dispose the digest explicitly.
	mut digest := sha1.new()
	digest.write(header.data) or { panic('iOS: SHA-1 input failed') }
	mut label_bytes := [20]u8{}
	mut output := unsafe { (&label_bytes[0]).vbytes(20) }
	digest.checksum_into(mut output)
	unsafe {
		digest.free()
		C.free(digest)
	}
	label := cf_data_create(0, u64(unsafe { &label_bytes[0] }), 20)
	security_attribute(dictionary, '_kSecAttrApplicationLabel', label)
	objc_release(label)
	unsafe { *(&u64(dictionary)) = ios_runtime.names['NSDictionary'] }
	return dictionary
}

fn sec_random_copy(random u64, count u64, bytes &u8) int {
	if random != 0 || count > 16777216 || (bytes == unsafe { nil } && count != 0) { return -50 }
	if count == 0 { return 0 }
	// getentropy fills each bounded chunk completely or fails, using the host
	// OS cryptographic source. No temporary array or error object is allocated.
	mut offset := u64(0)
	for offset < count {
		chunk := if count - offset > 256 { u64(256) } else { count - offset }
		if C.getentropy(unsafe { bytes + offset }, usize(chunk)) != 0 { return -1 }
		offset += chunk
	}
	return 0
}

fn security_symbol(symbol string) ?u64 {
	address := match symbol {
		'_SecTrustGetTypeID' { voidptr(sec_trust_type_id) }
		'_SecTrustCreateWithCertificates' { voidptr(sec_trust_create) }
		'_SecTrustCopyPublicKey', '_SecTrustCopyKey' { voidptr(sec_trust_key) }
		'_SecTrustGetCertificateCount' { voidptr(sec_trust_count) }
		'_SecTrustGetCertificateAtIndex' { voidptr(sec_trust_certificate) }
		'_SecTrustEvaluate' { voidptr(sec_trust_evaluate) }
		'_SecTrustEvaluateWithError' { voidptr(sec_trust_evaluate_error) }
		'_SecTrustGetTrustResult' { voidptr(sec_trust_evaluate) }
		'_SecTrustSetAnchorCertificates' { voidptr(sec_trust_anchors) }
		'_SecTrustSetAnchorCertificatesOnly' { voidptr(sec_trust_anchors_only) }
		'_SecTrustSetVerifyDate' { voidptr(sec_trust_date) }
		'_SecTrustSetPolicies' { voidptr(sec_trust_policies) }
		'_SecTrustCopyPolicies' { voidptr(sec_trust_copy_policies) }
		'_SecTrustSetNetworkFetchAllowed' { voidptr(sec_trust_network_set) }
		'_SecTrustGetNetworkFetchAllowed' { voidptr(sec_trust_network_get) }
		'_SecPolicyGetTypeID' { voidptr(sec_policy_type_id) }
		'_SecPolicyCreateBasicX509' { voidptr(sec_policy_basic) }
		'_SecPolicyCreateSSL' { voidptr(sec_policy_ssl) }
		'_SecPolicyCopyProperties' { voidptr(sec_policy_properties) }
		'_SecItemAdd' { voidptr(sec_item_add) }
		'_SecItemCopyMatching' { voidptr(sec_item_copy) }
		'_SecItemUpdate' { voidptr(sec_item_update) }
		'_SecItemDelete' { voidptr(sec_item_delete) }
		'_SecCertificateGetTypeID' { voidptr(sec_certificate_type_id) }
		'_SecCertificateCreateWithData' { voidptr(sec_certificate_create) }
		'_SecCertificateCopyData' { voidptr(sec_certificate_data) }
		'_SecCertificateCopySubjectSummary' { voidptr(sec_certificate_summary) }
		'_SecCertificateCopySerialNumberData' { voidptr(sec_certificate_serial) }
		'_SecCertificateCopyKey' { voidptr(sec_certificate_key) }
		'_SecKeyGetTypeID' { voidptr(sec_key_type_id) }
		'_SecKeyCopyExternalRepresentation' { voidptr(sec_key_data) }
		'_SecKeyCopyAttributes' { voidptr(sec_key_attributes) }
		'_SecRandomCopyBytes' { voidptr(sec_random_copy) }
		else { unsafe { nil } }
	}
	if address != unsafe { nil } { return u64(address) }
	if symbol == '_kSecRandomDefault' {
		C.ios_objc_initialize_lock()
		defer { C.ios_objc_initialize_unlock() }
		if cell := ios_runtime.framework_data[symbol] { return cell }
		cell := C.calloc(1, 8)
		if cell == unsafe { nil } { panic('iOS: cannot allocate random constant') }
		ios_runtime.framework_data[symbol] = u64(cell)
		return u64(cell)
	}
	return security_constant(symbol)
}

fn security_constant(symbol string) ?u64 {
	value := match symbol {
		'_kSecPolicyOid' { 'SecPolicyOid' }
		'_kSecPolicyName' { 'SecPolicyName' }
		'_kSecPolicyClient' { 'SecPolicyClient' }
		'_kSecPolicyAppleX509Basic' { '1.2.840.113635.100.1.2' }
		'_kSecPolicyAppleSSL' { '1.2.840.113635.100.1.3' }
		'_kSecAttrAccessGroup' { 'agrp' }
		'_kSecAttrAccessible' { 'pdmn' }
		'_kSecAttrAccessibleAfterFirstUnlock' { 'ck' }
		'_kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly' { 'cku' }
		'_kSecAttrAccessibleAlwaysThisDeviceOnly' { 'dku' }
		'_kSecAttrAccount' { 'acct' }
		'_kSecAttrApplicationTag' { 'atag' }
		'_kSecAttrDescription' { 'desc' }
		'_kSecAttrGeneric' { 'gena' }
		'_kSecAttrKeySizeInBits' { 'bsiz' }
		'_kSecAttrKeyType' { 'type' }
		'_kSecAttrKeyTypeECSECPrimeRandom' { '73' }
		'_kSecAttrKeyTypeRSA' { '42' }
		'_kSecAttrService' { 'svce' }
		'_kSecAttrSynchronizable' { 'sync' }
		'_kSecAttrType' { 'type' }
		'_kSecClass' { 'class' }
		'_kSecClassGenericPassword' { 'genp' }
		'_kSecClassKey' { 'keys' }
		'_kSecMatchLimit' { 'm_Limit' }
		'_kSecMatchLimitAll' { 'm_LimitAll' }
		'_kSecMatchLimitOne' { 'm_LimitOne' }
		'_kSecReturnAttributes' { 'r_Attributes' }
		'_kSecReturnData' { 'r_Data' }
		'_kSecUseAuthenticationUI' { 'u_AuthUI' }
		'_kSecUseAuthenticationUISkip' { 'u_AuthUIS' }
		'_kSecUseDataProtectionKeychain' { 'nleg' }
		'_kSecValueData' { 'v_Data' }
		'_kSecAttrKeyClass' { 'kcls' }
		'_kSecAttrKeyClassPublic' { '0' }
		'_kSecAttrCanEncrypt' { 'encr' }
		'_kSecAttrCanDecrypt' { 'decr' }
		'_kSecAttrCanDerive' { 'drve' }
		'_kSecAttrCanSign' { 'sign' }
		'_kSecAttrCanVerify' { 'vrfy' }
		'_kSecAttrCanWrap' { 'wrap' }
		'_kSecAttrCanUnwrap' { 'unwp' }
		'_kSecAttrIsPermanent' { 'perm' }
		'_kSecAttrIsPrivate' { 'priv' }
		'_kSecAttrIsModifiable' { 'modi' }
		'_kSecAttrIsSensitive' { 'sens' }
		'_kSecAttrWasAlwaysSensitive' { 'asen' }
		'_kSecAttrIsExtractable' { 'extr' }
		'_kSecAttrWasNeverExtractable' { 'next' }
		'_kSecAttrEffectiveKeySize' { 'esiz' }
		'_kSecAttrApplicationLabel' { 'klbl' }
		else { return none }
	}
	return framework_string_constant(symbol, value)
}
