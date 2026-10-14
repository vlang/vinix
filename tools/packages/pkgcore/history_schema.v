// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2

fn history_floor_field(key string) bool {
	return key in ['id', 'public_key', 'sequence', 'index_sha256']!
}

fn trust_history_field(parent string, key string) bool {
	return if parent == '' { key in ['format', 'repositories']! }
		else { parent == 'repositories' && history_floor_field(key) }
}

fn release_history_field(parent string, key string) bool {
	return if parent == '' { key in ['format', 'indexes']! }
		else { parent == 'indexes' && history_floor_field(key) }
}

fn history_floor_required(keys []string) ! {
	for key in ['id', 'public_key', 'sequence', 'index_sha256']! {
		if key !in keys { return error('missing required history floor field: ' + key) }
	}
}

fn trust_history_required(parent string, keys []string) ! {
	if parent == '' {
		for key in ['format', 'repositories']! {
			if key !in keys { return error('missing required trust history field: ' + key) }
		}
	} else { history_floor_required(keys)! }
}

fn release_history_required(parent string, keys []string) ! {
	if parent == '' {
		for key in ['format', 'indexes']! {
			if key !in keys { return error('missing required publisher history field: ' + key) }
		}
	} else { history_floor_required(keys)! }
}

fn history_value_type(parent string, key string, token u8) bool {
	if parent == '' && key in ['repositories', 'indexes']! { return token == `[` }
	if key in ['format', 'sequence']! { return token >= `0` && token <= `9` }
	return token == `"`
}

// A present history file is a complete durable record, never a template.
// Missing/null collections must not reset consumer or publisher sequence floors.
fn decode_history(text string, publisher bool) !TrustHistory {
	if text.len > max_metadata { return error('repository history exceeds metadata limit') }
	mut start := 0
	for start < text.len && text[start] in [u8(` `), `\t`, `\r`, `\n`]! { start++ }
	if start == text.len || text[start] != `{` { return error('repository history must be a JSON object') }
	history := if publisher {
		record := json2.decode[ReleaseHistory](text, strict: true)!
		TrustHistory{format: record.format, repositories: record.indexes}
	} else { json2.decode[TrustHistory](text, strict: true)! }
	mut accepted := false
	defer { if !accepted { close_decoded_history(history) } }
	document_keys_schema(text, if publisher { release_history_field } else { trust_history_field },
		if publisher { release_history_required } else { trust_history_required }, history_value_type)!
	if history.format != 1 || history.repositories.len > 4096 { return error('unsupported repository history') }
	mut seen := map[string]bool{}
	defer { unsafe { seen.free() } }
	for floor in history.repositories {
		identity := floor.id + '/' + floor.public_key
		defer { unsafe { identity.free() } }
		if !identifier(floor.id) || !digest_valid(floor.public_key) || !digest_valid(floor.index_sha256)
			|| floor.sequence == 0 || identity in seen { return error('invalid repository history floor') }
		seen[identity] = true
	}
	accepted = true
	return history
}

// Decoded histories and remember_index/history_with_snapshots results own their
// fields. Synthetic histories can borrow fields and must not use this cleanup.
fn close_decoded_history(history TrustHistory) {
	unsafe {
		for floor in history.repositories { floor.id.free(); floor.public_key.free(); floor.index_sha256.free() }
		(&array(&history.repositories)).free()
	}
}
