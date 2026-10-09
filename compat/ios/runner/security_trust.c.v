// SPDX-License-Identifier: GPL-2.0-or-later
// Trust owns immutable snapshots; public-key extraction never implies trust.
// Evaluation supports only a single self-issued CA explicitly supplied as an
// exact DER anchor, basic X.509 policy, and the bounded certificate profile
// below. No issuer signature is needed for a caller-trusted anchor itself.
// System roots, chain building, SSL and other policies return errSecUnimplemented.
module main

fn sec_trust_type_id() u64 { return ios_runtime.names['VinixSecTrust'] }

fn security_trust_valid(trust u64) bool {
	return trust != 0 && read64(trust) == sec_trust_type_id()
}

// Validate before allocating. Even an input CFArray with raw callbacks becomes
// an owned snapshot, so mutation/release of the caller's array cannot affect it.
fn security_trust_snapshot(input u64, type_id u64, single bool, empty bool) u64 {
	if input == 0 { return 0 }
	if single && read64(input) == type_id {
		array := objc_allocate(ios_runtime.names['NSArray'])
		mut header := obj_header(array)
		array_append(mut header, input)
		return array
	}
	if !objc_is_kind(input, ios_runtime.names['NSArray']) { return 0 }
	source := obj_header(input)
	if source.items.len > 64 || (!empty && source.items.len == 0) { return 0 }
	for object in source.items { if object == 0 || read64(object) != type_id { return 0 } }
	array := objc_allocate(ios_runtime.names['NSArray'])
	mut header := obj_header(array)
	for object in source.items { array_append(mut header, object) }
	return array
}

fn sec_trust_create(certificates u64, policies u64, output &u64) int {
	if output == unsafe { nil } { return -50 }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	certs := security_trust_snapshot(certificates, sec_certificate_type_id(), true, false)
	if certs == 0 { return -50 }
	defer { objc_release(certs) }
	default_policy := if policies == 0 { sec_policy_basic() } else { u64(0) }
	defer { objc_release(default_policy) }
	props := security_trust_snapshot(if policies == 0 { default_policy } else { policies }, sec_policy_type_id(), true, false)
	if props == 0 { return -50 }
	defer { objc_release(props) }
	trust := objc_allocate(sec_trust_type_id())
	store_field(trust, 0, certs)
	store_field(trust, 1, props)
	mut header := obj_header(trust)
	header.repeat = true // Custom anchors only, when supplied.
	// Basic X.509 starts with network fetch disabled, as on the Mac. SSL
	// policies permit it by default; this evaluator never fetches certificates.
	header.loaded = true
	for policy in obj_header(props).items {
		properties := obj_header(policy).fields[0]
		oid := cf_dictionary_value(properties, read64(security_constant('_kSecPolicyOid') or { panic('iOS: missing policy OID') }))
		if string_text(oid) == '1.2.840.113635.100.1.2' { header.loaded = false }
	}
	unsafe { *output = trust }
	return 0
}

fn sec_trust_key(trust u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if !security_trust_valid(trust) { return 0 }
	return sec_certificate_key(obj_header(obj_header(trust).fields[0]).items[0])
}

fn sec_trust_count(trust u64) i64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if !security_trust_valid(trust) { return 0 }
	// The chain contains only its leaf in this supported case. Returning an
	// unevaluated input certificate list as a built chain would be misleading.
	if obj_header(obj_header(trust).fields[0]).items.len != 1 {
		panic('iOS: SecTrust certificate chain building is not implemented')
	}
	return 1
}

fn sec_trust_certificate(trust u64, index i64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if !security_trust_valid(trust) { return 0 }
	if index < 0 || index >= sec_trust_count(trust) { panic('iOS: SecTrust certificate index is out of range') }
	return obj_header(obj_header(trust).fields[0]).items[int(index)] // Borrowed.
}

fn sec_trust_anchors(trust u64, certificates u64) int {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if !security_trust_valid(trust) { return -50 }
	anchors := if certificates == 0 { u64(0) } else { security_trust_snapshot(certificates, sec_certificate_type_id(), false, true) }
	if certificates != 0 && anchors == 0 { return -50 }
	store_field(trust, 2, anchors)
	objc_release(anchors)
	mut header := obj_header(trust)
	header.repeat = true
	header.valid = false
	return 0
}

fn sec_trust_anchors_only(trust u64, only u8) int {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if !security_trust_valid(trust) { return -50 }
	mut header := obj_header(trust)
	header.repeat = only != 0
	header.valid = false
	return 0
}

fn sec_trust_date(trust u64, date u64) int {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if !security_trust_valid(trust) || (date != 0 && read64(date) != cf_date_id()) { return -50 }
	if date != 0 {
		unix := cf_date_absolute(date) + 978307200.0
		if !(unix >= -62135596800.0 && unix <= 253402300799.0) { return -50 }
	}
	store_field(trust, 3, date)
	mut header := obj_header(trust)
	header.valid = false
	return 0
}

fn sec_trust_policies(trust u64, policies u64) int {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if !security_trust_valid(trust) { return -50 }
	props := security_trust_snapshot(policies, sec_policy_type_id(), true, false)
	if props == 0 { return -50 }
	store_field(trust, 1, props)
	objc_release(props)
	mut header := obj_header(trust)
	header.valid = false
	return 0
}

fn sec_trust_copy_policies(trust u64, output &u64) int {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if !security_trust_valid(trust) || output == unsafe { nil } { return -50 }
	unsafe { *output = objc_retain(obj_header(trust).fields[1]) }
	return 0
}

fn sec_trust_network_set(trust u64, allowed u8) int {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if !security_trust_valid(trust) { return -50 }
	mut header := obj_header(trust)
	header.loaded = allowed != 0
	header.valid = false
	return 0
}

fn sec_trust_network_get(trust u64, output &u8) int {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if !security_trust_valid(trust) || output == unsafe { nil } { return -50 }
	unsafe { *output = if obj_header(trust).loaded { u8(1) } else { u8(0) } }
	return 0
}

// X.509 UTC/GeneralizedTime in canonical seconds/Z form, converted without
// allocation. Reject impossible dates, offsets, fractions and leap seconds.
fn security_certificate_time(bytes &u8, field SecurityDer) ?i64 {
	if (field.tag == 23 && field.length != 13) || (field.tag == 24 && field.length != 15) || field.tag !in [u8(23), 24] { return none }
	if unsafe { bytes[field.end - 1] } != `Z` { return none }
	mut digits := [14]int{}
	for i in 0 .. field.length - 1 {
		byte := unsafe { bytes[field.offset + i] }
		if byte < `0` || byte > `9` { return none }
		digits[i] = int(byte - `0`)
	}
	base := if field.tag == 23 { 0 } else { 2 }
	mut year := digits[base] * 10 + digits[base + 1]
	if field.tag == 23 { year += if year < 50 { 2000 } else { 1900 } }
	else { year += digits[0] * 1000 + digits[1] * 100 }
	month := digits[base + 2] * 10 + digits[base + 3]
	day := digits[base + 4] * 10 + digits[base + 5]
	hour := digits[base + 6] * 10 + digits[base + 7]
	minute := digits[base + 8] * 10 + digits[base + 9]
	second := digits[base + 10] * 10 + digits[base + 11]
	if year == 0 || month < 1 || month > 12 || day < 1 || hour > 23 || minute > 59 || second > 59 { return none }
	leap := year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
	months := [31, if leap { 29 } else { 28 }, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]!
	if day > months[month - 1] { return none }
	previous := i64(year - 1)
	mut days := previous * 365 + previous / 4 - previous / 100 + previous / 400 - 719162
	for i in 0 .. month - 1 { days += months[i] }
	days += day - 1
	return days * 86400 + hour * 3600 + minute * 60 + second
}

fn security_der_equal(bytes &u8, a SecurityDer, b SecurityDer) bool {
	return a.end - a.start == b.end - b.start && C.memcmp(unsafe { bytes + a.start }, unsafe { bytes + b.start }, usize(a.end - a.start)) == 0
}

// Intentionally narrow CA profile: only basicConstraints CA:true (no path
// length), subjectKeyIdentifier and keyIdentifier-only authorityKeyIdentifier.
// Reject every other extension rather than silently ignoring constraints.
fn security_trust_extensions(bytes &u8, field SecurityDer) bool {
	if field.tag != 0xa3 { return false }
	mut wrapper := security_inside(bytes, field)
	sequence := wrapper.expect(0x30) or { return false }
	if wrapper.pos != wrapper.limit { return false }
	mut extensions := security_inside(bytes, sequence)
	mut seen := u8(0)
	for extensions.pos < extensions.limit {
		extension := extensions.expect(0x30) or { return false }
		mut fields := security_inside(bytes, extension)
		oid := fields.expect(6) or { return false }
		mut value := fields.next() or { return false }
		mut critical := false
		if value.tag == 1 {
			if value.length != 1 || unsafe { bytes[value.offset] } !in [u8(0), 255] { return false }
			critical = unsafe { bytes[value.offset] } != 0
			value = fields.next() or { return false }
		}
		if value.tag != 4 || fields.pos != fields.limit { return false }
		mut payload := security_inside(bytes, value)
		mut bit := u8(0)
		if security_der_oid(bytes, oid, '551D13') {
			bit = 1
			constraints := payload.expect(0x30) or { return false }
			mut ca := security_inside(bytes, constraints)
			flag := ca.expect(1) or { return false }
			if flag.length != 1 || unsafe { bytes[flag.offset] } != 255 || ca.pos != ca.limit { return false }
		} else if security_der_oid(bytes, oid, '551D0E') && !critical {
			bit = 2
			id := payload.expect(4) or { return false }
			if id.length < 1 || id.length > 64 { return false }
		} else if security_der_oid(bytes, oid, '551D23') && !critical {
			bit = 4
			identifier := payload.expect(0x30) or { return false }
			mut authority := security_inside(bytes, identifier)
			id := authority.expect(0x80) or { return false }
			if id.length < 1 || id.length > 64 || authority.pos != authority.limit { return false }
		} else { return false }
		if payload.pos != payload.limit || seen & bit != 0 { return false }
		seen |= bit
	}
	return seen & 1 != 0
}

fn security_trust_update(trust u64) {
	mut header := obj_header(trust)
	if header.valid { return }
	header.valid = true
	header.number = 0 // kSecTrustResultInvalid, with explicit API failure.
	header.section = -4 // errSecUnimplemented
	header.deadline = -4 // OSStatus; distinct from a negative trust decision.
	certs := obj_header(header.fields[0])
	policies := obj_header(header.fields[1])
	if certs.items.len != 1 || policies.items.len != 1 || header.fields[2] == 0 || !header.repeat { return }
	properties := obj_header(policies.items[0]).fields[0]
	oid := cf_dictionary_value(properties, read64(security_constant('_kSecPolicyOid') or { return }))
	if oid == 0 || string_text(oid) != '1.2.840.113635.100.1.2' { return }
	certificate := certs.items[0]
	parsed := security_certificate(certificate) or { return }
	bytes := unsafe { &u8(obj_header(certificate).data.data) }
	if parsed.unique_ids || !security_der_equal(bytes, parsed.issuer, parsed.subject) ||
		!security_der_equal(bytes, parsed.algorithm, parsed.signature) ||
		!security_trust_extensions(bytes, parsed.extensions) { return }
	key := sec_certificate_key(certificate)
	if key == 0 { return }
	objc_release(key)
	before := security_certificate_time(bytes, parsed.not_before) or { return }
	after := security_certificate_time(bytes, parsed.not_after) or { return }
	if before > after { return }
	date := if header.fields[3] == 0 { cf_absolute_time() } else { cf_date_absolute(header.fields[3]) }
	unix := date + 978307200.0
	header.deadline = 0
	header.number = 5 // kSecTrustResultRecoverableTrustFailure
	header.section = -67818 // errSecCertificateExpired (also not-yet-valid).
	if unix < f64(before) || unix > f64(after) { return }
	header.section = -67843 // errSecNotTrusted
	for anchor in obj_header(header.fields[2]).items {
		if object_equal(certificate, anchor) {
			header.number = 4 // kSecTrustResultUnspecified: successfully anchored.
			header.section = 0
			return
		}
	}
}

fn sec_trust_evaluate(trust u64, output &u32) int {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if !security_trust_valid(trust) || output == unsafe { nil } { return -50 }
	security_trust_update(trust)
	header := obj_header(trust)
	unsafe { *output = u32(header.number) }
	return int(header.deadline)
}

fn sec_trust_evaluate_error(trust u64, output &u64) bool {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if !security_trust_valid(trust) { security_error(output, -50); return false }
	security_trust_update(trust)
	code := int(obj_header(trust).section)
	if code != 0 { security_error(output, code); return false }
	if output != unsafe { nil } { unsafe { *output = 0 } }
	return true
}
