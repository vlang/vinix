// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

const policy_document_keys = ['format', 'architecture', 'policy']
const policy_review_keys = ['format', 'architecture', 'generation', 'fingerprint', 'previous', 'proposed', 'rows']
const policy_settings_keys = ['offline', 'allowed', 'pins', 'permissions', 'licenses', 'allow_firmware', 'reserve_bytes']
const policy_pin_keys = ['id', 'minimum', 'before']
const policy_impact_keys = ['id', 'name', 'version', 'kind', 'license', 'proprietary', 'firmware', 'repository', 'public_key', 'requested', 'diagnostic_before', 'diagnostic_after']

fn (mut r MetadataReader) unsigned(maximum u64) !u64 {
	r.spaces()
	start := r.position
	mut value := u64(0)
	for r.position < r.text.len && r.text[r.position] >= `0` && r.text[r.position] <= `9` {
		digit := u64(r.text[r.position] - `0`)
		if (r.position > start && r.text[start] == `0`) || value > maximum / 10
			|| (value == maximum / 10 && digit > maximum % 10) { return error('package metadata integer exceeds its canonical bound') }
		value = value * 10 + digit
		r.position++
	}
	if r.position == start { return error('package metadata requires an unsigned integer') }
	return value
}

fn (mut r MetadataReader) policy_strings(limit int, maximum int) ![]string {
	r.expect(`[` )!
	mut values := []string{cap: 16}
	unsafe { values.flags |= .noslices }
	mut accepted := false
	defer { if !accepted { unsafe { for value in values { value.free() }; (&array(&values)).free() } } }
	mut first := true
	for r.next(first, `]`)! {
		first = false
		if values.len == maximum { return error('policy array exceeds its entry limit') }
		values << r.quoted(limit)!
	}
	accepted = true
	return values
}

fn (mut r MetadataReader) policy_pin() !PolicyPin {
	r.expect(`{`)!
	mut pin := PolicyPin{}
	mut accepted := false
	defer { if !accepted { unsafe { pin.id.free(); pin.minimum.free(); pin.before.free() } } }
	mut seen := u16(0)
	mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(policy_pin_keys, seen)!
		seen |= u16(1) << field
		match field {
			0 { pin = PolicyPin{ ...pin, id: r.quoted(128)! } }
			1 { pin = PolicyPin{ ...pin, minimum: r.quoted(29)! } }
			2 { pin = PolicyPin{ ...pin, before: r.quoted(29)! } }
			else {}
		}
	}
	if seen != 7 { return error('missing policy pin field') }
	accepted = true
	return pin
}

fn (mut r MetadataReader) policy_pins() ![]PolicyPin {
	r.expect(`[` )!
	mut values := []PolicyPin{cap: 16}
	unsafe { values.flags |= .noslices }
	mut accepted := false
	defer {
		if !accepted {
			mut discarded := PolicySettings{ pins: values }; discarded.close()
		}
	}
	mut first := true
	for r.next(first, `]`)! {
		first = false
		if values.len == 4096 { return error('policy pins exceed their entry limit') }
		pin := r.policy_pin()!
		pointer := unsafe { &pin }
		unsafe { values.push_many(pointer, 1) }
	}
	accepted = true
	return values
}

fn (mut r MetadataReader) policy_settings() !PolicySettings {
	r.expect(`{`)!
	mut policy := PolicySettings{}
	mut accepted := false
	defer { if !accepted { policy.close() } }
	mut seen := u16(0)
	mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(policy_settings_keys, seen)!
		seen |= u16(1) << field
		match field {
			0 { policy = PolicySettings{ ...policy, offline: r.boolean()! } }
			1 { policy = PolicySettings{ ...policy, allowed: r.policy_strings(128, 4096)! } }
			2 { policy = PolicySettings{ ...policy, pins: r.policy_pins()! } }
			3 { policy = PolicySettings{ ...policy, permissions: r.policy_strings(16, 5)! } }
			4 { policy = PolicySettings{ ...policy, licenses: r.policy_strings(256, 4096)! } }
			5 { policy = PolicySettings{ ...policy, allow_firmware: r.boolean()! } }
			6 { policy = PolicySettings{ ...policy, reserve_bytes: r.unsigned(u64(1) << 40)! } }
			else {}
		}
	}
	if seen != 127 { return error('missing policy settings field') }
	policy.validate()!
	accepted = true
	return policy
}

fn (mut r MetadataReader) policy_impact() !PolicyImpact {
	r.expect(`{`)!
	mut row := PolicyImpact{}
	mut accepted := false
	defer {
		if !accepted {
			unsafe {
				row.id.free(); row.name.free(); row.version.free(); row.kind.free(); row.license.free()
				row.repository.free(); row.public_key.free(); row.diagnostic_before.free(); row.diagnostic_after.free()
			}
		}
	}
	mut seen := u16(0)
	mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(policy_impact_keys, seen)!
		seen |= u16(1) << field
		match field {
			0 { row = PolicyImpact{ ...row, id: r.quoted(128)! } }
			1 { row = PolicyImpact{ ...row, name: r.quoted(256)! } }
			2 { row = PolicyImpact{ ...row, version: r.quoted(29)! } }
			3 { row = PolicyImpact{ ...row, kind: r.quoted(16)! } }
			4 { row = PolicyImpact{ ...row, license: r.quoted(256)! } }
			5 { row = PolicyImpact{ ...row, proprietary: r.boolean()! } }
			6 { row = PolicyImpact{ ...row, firmware: r.boolean()! } }
			7 { row = PolicyImpact{ ...row, repository: r.quoted(128)! } }
			8 { row = PolicyImpact{ ...row, public_key: r.quoted(64)! } }
			9 { row = PolicyImpact{ ...row, requested: r.boolean()! } }
			10 { row = PolicyImpact{ ...row, diagnostic_before: r.quoted(4096)! } }
			11 { row = PolicyImpact{ ...row, diagnostic_after: r.quoted(4096)! } }
			else {}
		}
	}
	if seen != 4095 { return error('missing installed policy impact field') }
	accepted = true
	return row
}

fn (mut r MetadataReader) policy_impacts() ![]PolicyImpact {
	r.expect(`[` )!
	mut values := []PolicyImpact{cap: 16}
	unsafe { values.flags |= .noslices }
	mut accepted := false
	defer { if !accepted { close_policy_impacts(values) } }
	mut first := true
	for r.next(first, `]`)! {
		first = false
		if values.len == 4096 { return error('policy impacts exceed their entry limit') }
		row := r.policy_impact()!
		pointer := unsafe { &row }
		unsafe { values.push_many(pointer, 1) }
	}
	accepted = true
	return values
}

pub fn decode_policy_document(text string) !PolicyDocument {
	if text.len > 8 * 1024 * 1024 { return error('policy document exceeds metadata limit') }
	mut reader := &MetadataReader{ text: text }
	defer { unsafe { free(reader) } }
	reader.expect(`{`)!
	mut document := PolicyDocument{}
	mut accepted := false
	defer { if !accepted { document.close() } }
	mut seen := u16(0)
	mut first := true
	for reader.next(first, `}`)! {
		first = false
		field := reader.member(policy_document_keys, seen)!
		seen |= u16(1) << field
		match field {
			0 { reader.expect(`1`)!; document = PolicyDocument{ ...document, format: 1 } }
			1 { document = PolicyDocument{ ...document, architecture: reader.quoted(16)! } }
			2 { document = PolicyDocument{ ...document, policy: reader.policy_settings()! } }
			else {}
		}
	}
	reader.spaces()
	if seen != 7 || reader.position != text.len { return error('incomplete or trailing policy document') }
	document.validate()!
	accepted = true
	return document
}

pub fn decode_policy_review(text string) !PolicyReview {
	if text.len > 8 * 1024 * 1024 { return error('policy review exceeds metadata limit') }
	mut reader := &MetadataReader{ text: text }
	defer { unsafe { free(reader) } }
	reader.expect(`{`)!
	mut review := PolicyReview{}
	mut accepted := false
	defer { if !accepted { review.close() } }
	mut seen := u16(0)
	mut first := true
	for reader.next(first, `}`)! {
		first = false
		field := reader.member(policy_review_keys, seen)!
		seen |= u16(1) << field
		match field {
			0 { reader.expect(`1`)!; review = PolicyReview{ ...review, format: 1 } }
			1 { review = PolicyReview{ ...review, architecture: reader.quoted(16)! } }
			2 { review = PolicyReview{ ...review, generation: reader.unsigned(~u64(0))! } }
			3 { review = PolicyReview{ ...review, fingerprint: reader.quoted(64)! } }
			4 { review = PolicyReview{ ...review, previous: reader.policy_settings()! } }
			5 { review = PolicyReview{ ...review, proposed: reader.policy_settings()! } }
			6 { review = PolicyReview{ ...review, rows: reader.policy_impacts()! } }
			else {}
		}
	}
	reader.spaces()
	if seen != 127 || reader.position != text.len { return error('incomplete or trailing policy review') }
	review.validate()!
	accepted = true
	return review
}
