// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

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
	return read_stored_snapshots(text)
}

fn close_decoded_snapshot(snapshot Snapshot) {
	unsafe {
		snapshot.repository.id.free(); snapshot.repository.url.free(); snapshot.repository.public_key.free()
		snapshot.text.free(); snapshot.signature.free()
	}
}

// Only independently decoded records own these fields. Refresh/mirror snapshots
// can borrow configuration and signed bytes and must not use this cleanup.
fn close_decoded_snapshots(snapshots []Snapshot) {
	unsafe {
		for snapshot in snapshots { close_decoded_snapshot(snapshot) }
		(&array(&snapshots)).free()
	}
}
