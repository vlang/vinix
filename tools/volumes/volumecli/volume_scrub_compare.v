// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

// Validate both complete findings before committing any caller output. Exact
// embedded references, rather than only their fingerprints, must agree.
@[direct_array_access]
fn compare_volume_ciphertext_scrubs(before &u8, before_size int, after &u8, after_size int, mut disk DiskKey, mut row Request, changed &bool) bool {
	mut candidate := DiskKey{}; mut request := Request{}; mut next_disk := DiskKey{}; mut next_row := Request{}
	if !decode_volume_ciphertext_scrub(before, before_size, mut candidate, mut request)
		|| !decode_volume_ciphertext_scrub(after, after_size, mut next_disk, mut next_row) { return false }
	mut difference := u8(0)
	unsafe {
		for i in 32 .. 160 { if before[i] != after[i] { return false } }
		for i in 160 .. 192 { difference |= before[i] ^ after[i] }
	}
	disk = candidate; row = request; unsafe { *changed = difference != 0 }; return true
}

@[direct_array_access]
fn show_volume_scrub_comparison(before &u8, after &u8, disk &DiskKey, row &Request, changed bool) bool {
	mut identity := [41]char{}; mut expected := [65]char{}; mut old_digest := [65]char{}; mut new_digest := [65]char{}; mut fingerprint := [65]char{}
	disk_identity(disk, &identity[0])
	unsafe { for i in 0 .. 32 {
		if C.snprintf(&expected[i * 2], usize(65 - i * 2), c'%02x', u32(before[112 + i])) != 2
			|| C.snprintf(&old_digest[i * 2], usize(65 - i * 2), c'%02x', u32(before[160 + i])) != 2
			|| C.snprintf(&new_digest[i * 2], usize(65 - i * 2), c'%02x', u32(after[160 + i])) != 2
			|| C.snprintf(&fingerprint[i * 2], usize(65 - i * 2), c'%02x', u32(before[192 + i])) != 2 { return false }
	} }
	old_changed := get_le(before, 16, 4) != 0; new_changed := get_le(after, 16, 4) != 0
	result := if !changed { &char(c'stable') } else if !new_changed { &char(c'restored') }
		else if !old_changed { &char(c'new-change') } else { &char(c'changed-again') }
	return C.printf(c'format=VINIXCS1 operation=compared-ciphertext mappings=1 stable=%lu changed=%lu algorithm=sha256 reference_sha256=%s\n', u64(!changed), u64(changed), &fingerprint[0]) >= 0
		&& C.printf(c'disk_bytes=%lu sector=%lu identity=%s slot=%u offset=%lu bytes=%lu readonly=%lu before=%s after=%s result=%s expected_sha256=%s before_sha256=%s after_sha256=%s\n',
			disk.bytes, disk.sector, &identity[0], row.slot, row.offset, row.length, row.flags,
			if old_changed { &char(c'changed') } else { &char(c'match') }, if new_changed { &char(c'changed') } else { &char(c'match') }, result, &expected[0], &old_digest[0], &new_digest[0]) >= 0
}

// The order is caller-supplied history, not an inferred timestamp. Comparing
// valid changed findings with equal observed digests is a successful stable pair.
@[direct_array_access]
fn compare_volume_scrub_files(before_path &char, after_path &char) i32 {
	mut before := [224]u8{}; mut after := [224]u8{}; mut disk := DiskKey{}; mut row := Request{}; mut changed := false
	if !read_recovery_file(before_path, &before[0], volume_ciphertext_scrub_bytes)
		|| !read_recovery_file(after_path, &after[0], volume_ciphertext_scrub_bytes)
		|| !compare_volume_ciphertext_scrubs(&before[0], volume_ciphertext_scrub_bytes, &after[0], volume_ciphertext_scrub_bytes, mut disk, mut row, unsafe { &changed }) {
		return plan_error(c'invalid private scrub reports or different ciphertext references')
	}
	if finish_bundle_report(show_volume_scrub_comparison(&before[0], &after[0], unsafe { &disk }, unsafe { &row }, changed)) != 0 { return 1 }
	return if changed { 2 } else { 0 }
}
