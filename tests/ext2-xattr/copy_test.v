// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import errno
import resource

fn test_copy_snapshots_names_values_and_skips_overlay_metadata() {
	mut source := resource.Resource{
		names: 'user.stable\x00trusted.overlay.hidden\x00security.copy\x00'.bytes()
		value: [u8(0), 1, 255, 0, 66]
	}
	mut destination := resource.Resource{}
	copy_xattrs(&source, &destination, 'trusted.overlay.') or { assert false }
	assert destination.copied_names == ['user.stable', 'security.copy']
	assert destination.copied_values[0] == source.value
	source.names[0] = `x`
	source.value[0] = 9
	assert destination.copied_names[0] == 'user.stable'
	assert destination.copied_values[0][0] == 0
}

fn test_copy_skips_attributes_removed_after_listing() {
	mut source := resource.Resource{
		names: 'user.removed\x00user.stable\x00'.bytes()
		value: [u8(42)]
		missing: 'user.removed'
	}
	mut destination := resource.Resource{}
	copy_xattrs(&source, &destination, 'trusted.overlay.') or { assert false }
	assert destination.copied_names == ['user.stable']
	assert destination.copied_values[0] == [u8(42)]
}

fn test_copy_preserves_backend_errors() {
	mut source := resource.Resource{names: 'user.stable\x00'.bytes(), value: [u8(42)]}
	mut destination := resource.Resource{}
	source.list_error = errno.eio
	mut failed := false
	copy_xattrs(&source, &destination, 'trusted.overlay.') or { failed = true }
	assert failed && errno.get() == errno.eio
	source.list_error = 0
	source.get_error = errno.eio
	failed = false
	copy_xattrs(&source, &destination, 'trusted.overlay.') or { failed = true }
	assert failed && errno.get() == errno.eio
	source.get_error = 0
	destination.set_error = errno.enospc
	failed = false
	copy_xattrs(&source, &destination, 'trusted.overlay.') or { failed = true }
	assert failed && errno.get() == errno.enospc
	assert destination.copied_names.len == 0
}

fn test_copy_rejects_malformed_packed_name_list() {
	for names in ['user.missing-terminator', '\x00'] {
		mut source := resource.Resource{names: names.bytes()}
		mut destination := resource.Resource{}
		mut failed := false
		copy_xattrs(&source, &destination, 'trusted.overlay.') or { failed = true }
		assert failed && errno.get() == errno.eio
	}
}
