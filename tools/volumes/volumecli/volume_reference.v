// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

// Validate both complete records before exposing any decoded output. Canonical
// metadata, including saved mode, must agree; only the recorded digest may differ.
@[direct_array_access]
fn compare_volume_references(before &u8, before_size int, after &u8, after_size int, mut disk DiskKey, mut row Request, changed &bool) bool {
	if before_size != volume_ciphertext_bytes || after_size != volume_ciphertext_bytes { return false }
	mut candidate := DiskKey{}; mut request := Request{}; mut next_disk := DiskKey{}; mut next_row := Request{}
	if !volume_ciphertext_reference_geometry(before, mut candidate, mut request)
		|| !volume_ciphertext_reference_geometry(after, mut next_disk, mut next_row) { return false }
	mut difference := u8(0)
	unsafe {
		for i in 0 .. 80 { if before[i] != after[i] { return false } }
		for i in 80 .. 112 { difference |= before[i] ^ after[i] }
	}
	disk = candidate; row = request; unsafe { *changed = difference != 0 }; return true
}

@[direct_array_access]
fn show_volume_reference(before &u8, after &u8, disk &DiskKey, row &Request, changed bool) bool {
	mut identity := [41]char{}; mut old_digest := [65]char{}; mut new_digest := [65]char{}
	mut old_hash := [32]u8{}; mut new_hash := [32]u8{}; mut old_fingerprint := [65]char{}; mut new_fingerprint := [65]char{}
	if !volume_ciphertext_reference_fingerprint(before, unsafe { &old_hash })
		|| (after != unsafe { nil } && !volume_ciphertext_reference_fingerprint(after, unsafe { &new_hash })) { return false }
	disk_identity(disk, &identity[0])
	unsafe { for i in 0 .. 32 {
		if C.snprintf(&old_digest[i * 2], usize(65 - i * 2), c'%02x', u32(before[80 + i])) != 2
			|| C.snprintf(&old_fingerprint[i * 2], usize(65 - i * 2), c'%02x', u32(old_hash[i])) != 2 { return false }
		if after != nil && (C.snprintf(&new_digest[i * 2], usize(65 - i * 2), c'%02x', u32(after[80 + i])) != 2
			|| C.snprintf(&new_fingerprint[i * 2], usize(65 - i * 2), c'%02x', u32(new_hash[i])) != 2) { return false }
	} }
	if after == unsafe { nil } {
		return C.printf(c'format=VINIXCH1 operation=show-ciphertext-reference mappings=1 algorithm=sha256 reference_sha256=%s\n', &old_fingerprint[0]) >= 0
			&& C.printf(c'disk_bytes=%lu sector=%lu identity=%s slot=%u offset=%lu bytes=%lu readonly=%lu sha256=%s\n',
				disk.bytes, disk.sector, &identity[0], row.slot, row.offset, row.length, row.flags, &old_digest[0]) >= 0
	}
	return C.printf(c'format=VINIXCH1 operation=compared-ciphertext-references mappings=1 stable=%lu changed=%lu algorithm=sha256 before_reference_sha256=%s after_reference_sha256=%s\n', u64(!changed), u64(changed), &old_fingerprint[0], &new_fingerprint[0]) >= 0
		&& C.printf(c'disk_bytes=%lu sector=%lu identity=%s slot=%u offset=%lu bytes=%lu readonly=%lu result=%s before_sha256=%s after_sha256=%s\n',
			disk.bytes, disk.sector, &identity[0], row.slot, row.offset, row.length, row.flags,
			if changed { &char(c'changed') } else { &char(c'stable') }, &old_digest[0], &new_digest[0]) >= 0
}

// References contain public metadata only. This path reads private files and
// prints complete validated records without credentials, physical I/O or locks.
@[direct_array_access]
fn volume_reference_files(before_path &char, after_path &char) i32 {
	mut before := [128]u8{}; mut after := [128]u8{}; mut disk := DiskKey{}; mut row := Request{}; mut changed := false
	if !read_recovery_file(before_path, &before[0], volume_ciphertext_bytes)
		|| (after_path != unsafe { nil } && !read_recovery_file(after_path, &after[0], volume_ciphertext_bytes)) { return plan_error(c'invalid private ciphertext reference input') }
	if after_path == unsafe { nil } {
		if !volume_ciphertext_reference_geometry(&before[0], mut disk, mut row) { return plan_error(c'invalid ciphertext reference') }
	} else if !compare_volume_references(&before[0], volume_ciphertext_bytes, &after[0], volume_ciphertext_bytes, mut disk, mut row, unsafe { &changed }) {
		return plan_error(c'invalid ciphertext references or different saved mapping geometry')
	}
	if finish_bundle_report(show_volume_reference(&before[0], if after_path == unsafe { nil } { unsafe { nil } } else { unsafe { &after[0] } }, unsafe { &disk }, unsafe { &row }, changed)) != 0 { return 1 }
	return if changed { 2 } else { 0 }
}
