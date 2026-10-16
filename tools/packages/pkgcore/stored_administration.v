// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

const stored_policy_document_keys = ['format', 'architecture', 'policy']
const stored_policy_review_keys = ['format', 'architecture', 'generation', 'fingerprint', 'previous', 'proposed', 'rows']
const stored_policy_impact_keys = ['id', 'name', 'version', 'kind', 'license', 'proprietary', 'firmware',
	'repository', 'public_key', 'requested', 'diagnostic_before', 'diagnostic_after']
const stored_policy_pin_required = ['id']

fn require_policy_fields(keys []string, fields []string) ! {
	for field in fields {
		if field !in keys { return error('missing required organization policy field: ' + field) }
	}
}

fn policy_document_required(parent string, keys []string) ! {
	match parent {
		'' { require_policy_fields(keys, stored_policy_document_keys)! }
		'policy' { require_policy_fields(keys, stored_policy_keys)! }
		'pins' { require_policy_fields(keys, stored_policy_pin_required)! }
		else {}
	}
}

fn policy_review_required(parent string, keys []string) ! {
	match parent {
		'' { require_policy_fields(keys, stored_policy_review_keys)! }
		'previous', 'proposed' { require_policy_fields(keys, stored_policy_keys)! }
		'pins' { require_policy_fields(keys, stored_policy_pin_required)! }
		'rows' { require_policy_fields(keys, stored_policy_impact_keys)! }
		else {}
	}
}

fn policy_settings_value_type(key string, token u8) bool {
	return match key {
		'offline', 'allow_firmware' { token in [u8(`t`), `f`]! }
		'reserve_bytes' { token >= `0` && token <= `9` }
		else { token == `[` }
	}
}

fn policy_document_value_type(parent string, key string, token u8) bool {
	if parent == '' {
		return match key { 'format' { token >= `0` && token <= `9` } 'policy' { token == `{` } else { token == `"` } }
	}
	if parent == 'policy' { return policy_settings_value_type(key, token) }
	return token == `"`
}

fn policy_review_value_type(parent string, key string, token u8) bool {
	if parent == '' {
		return match key {
			'format', 'generation' { token >= `0` && token <= `9` }
			'previous', 'proposed' { token == `{` }
			'rows' { token == `[` }
			else { token == `"` }
		}
	}
	if parent in ['previous', 'proposed']! { return policy_settings_value_type(key, token) }
	if parent == 'rows' && key in ['proprietary', 'firmware', 'requested']! { return token in [u8(`t`), `f`]! }
	return token == `"`
}

fn (mut r StoredReader) policy_impact() !PolicyImpact {
	r.expect(`{`)!
	mut row := PolicyImpact{ id: '', name: '', version: '', kind: '', license: '', proprietary: false, firmware: false,
		repository: '', public_key: '', requested: false, diagnostic_before: '', diagnostic_after: '' }
	mut accepted := false
	defer { if !accepted { close_policy_impact(row) } }
	mut seen := u32(0); mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(stored_policy_impact_keys, seen)!; seen |= u32(1) << field
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
	if seen != 4095 { return error('missing required organization policy impact field') }
	accepted = true
	return row
}

fn (mut r StoredReader) policy_impacts() ![]PolicyImpact {
	r.expect(`[` )!
	mut rows := []PolicyImpact{cap: 16}
	unsafe { rows.flags |= .noslices }
	mut accepted := false
	defer { if !accepted { for row in rows { close_policy_impact(row) }; unsafe { rows.free() } } }
	mut first := true
	for r.next(first, `]`)! {
		first = false
		if rows.len == 4096 { return error('organization policy impacts exceed their entry limit') }
		row := r.policy_impact()!
		pointer := unsafe { &row }
		unsafe { rows.push_many(pointer, 1) }
	}
	accepted = true
	return rows
}

fn read_policy_document_input(text string) !PolicyDocument {
	if text.len > max_metadata { return error('organization policy document exceeds metadata limit') }
	document_keys_schema(text, policy_document_field, policy_document_required, policy_document_value_type)!
	mut r := &StoredReader{ text: text }
	defer { unsafe { free(r) } }
	r.expect(`{`)!
	mut document := PolicyDocument{ policy: Policy{ permissions: []string{} } }
	mut accepted := false
	defer { if !accepted { document.close() } }
	mut seen := u32(0); mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(stored_policy_document_keys, seen)!; seen |= u32(1) << field
		match field {
			0 { document = PolicyDocument{ ...document, format: int(r.unsigned(u64(max_i32))!) } }
			1 { document = PolicyDocument{ ...document, architecture: r.quoted(16)! } }
			2 { document = PolicyDocument{ ...document, policy: r.policy_fields(true)! } }
			else {}
		}
	}
	r.spaces()
	if seen != 7 || r.position != text.len { return error('incomplete or trailing organization policy document') }
	accepted = true
	return document
}

fn read_policy_review_input(text string) !PolicyReview {
	if text.len > max_metadata { return error('organization policy review exceeds metadata limit') }
	document_keys_schema(text, policy_review_field, policy_review_required, policy_review_value_type)!
	mut r := &StoredReader{ text: text }
	defer { unsafe { free(r) } }
	r.expect(`{`)!
	mut review := PolicyReview{ format: 0, architecture: '', generation: 0, fingerprint: '', rows: [],
		previous: Policy{ permissions: []string{} }, proposed: Policy{ permissions: []string{} } }
	mut accepted := false
	defer { if !accepted { review.close() } }
	mut seen := u32(0); mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(stored_policy_review_keys, seen)!; seen |= u32(1) << field
		match field {
			0 { review = PolicyReview{ ...review, format: int(r.unsigned(u64(max_i32))!) } }
			1 { review = PolicyReview{ ...review, architecture: r.quoted(16)! } }
			2 { review = PolicyReview{ ...review, generation: r.unsigned(~u64(0))! } }
			3 { review = PolicyReview{ ...review, fingerprint: r.quoted(64)! } }
			4 { review = PolicyReview{ ...review, previous: r.policy_fields(true)! } }
			5 { review = PolicyReview{ ...review, proposed: r.policy_fields(true)! } }
			6 { review = PolicyReview{ ...review, rows: r.policy_impacts()! } }
			else {}
		}
	}
	r.spaces()
	if seen != 127 || r.position != text.len { return error('incomplete or trailing organization policy review') }
	accepted = true
	return review
}
