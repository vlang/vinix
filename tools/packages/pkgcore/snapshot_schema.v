// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2

fn snapshot_field(parent string, key string) bool {
	return if parent == '' { key in ['repository', 'text', 'signature']! }
		else { parent == 'repository' && key in ['id', 'url', 'public_key']! }
}

fn snapshot_required(parent string, keys []string) ! {
	if parent == '' {
		for key in ['repository', 'text', 'signature']! {
			if key !in keys { return error('missing required cached snapshot field: ' + key) }
		}
	} else {
		for key in ['id', 'url', 'public_key']! {
			if key !in keys { return error('missing required cached repository field: ' + key) }
		}
	}
}

fn snapshot_value_type(parent string, key string, token u8) bool {
	return if parent == '' && key == 'repository' { token == `{` } else { token == `"` }
}

// The wrapper preserves exact signed bytes; signature/expiry/floor admission
// stays with verify_index and its callers, including revoked legacy snapshots.
fn decode_snapshots(text string) ![]Snapshot {
	if text.len > max_metadata { return error('cached repository metadata exceeds its size limit') }
	mut start := 0
	for start < text.len && text[start] in [u8(` `), `\t`, `\r`, `\n`]! { start++ }
	if start == text.len || text[start] != `[` { return error('cached repository metadata must be a JSON array') }
	snapshots := json2.decode[[]Snapshot](text, strict: true)!
	mut accepted := false
	defer { if !accepted { close_decoded_snapshots(snapshots) } }
	document_keys_schema(text, snapshot_field, snapshot_required, snapshot_value_type)!
	if snapshots.len > 4096 { return error('cached repository metadata exceeds its identity limit') }
	mut ids := map[string]bool{}
	defer { unsafe { ids.free() } }
	for snapshot in snapshots {
		if !valid_repository(snapshot.repository) || snapshot.repository.id in ids {
			return error('invalid or duplicate cached repository identity')
		}
		if snapshot.text == '' || snapshot.signature == '' || snapshot.signature.len > 256 {
			return error('cached repository snapshot requires signed text and a bounded signature')
		}
		ids[snapshot.repository.id] = true
	}
	accepted = true
	return snapshots
}

// Only independently decoded records own these fields. Refresh/mirror snapshots
// can borrow configuration and signed bytes and must not use this cleanup.
fn close_decoded_snapshots(snapshots []Snapshot) {
	unsafe {
		for snapshot in snapshots {
			snapshot.repository.id.free(); snapshot.repository.url.free(); snapshot.repository.public_key.free()
			snapshot.text.free(); snapshot.signature.free()
		}
		(&array(&snapshots)).free()
	}
}
