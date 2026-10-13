// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

// Reprotect authenticated recovery metadata without a passphrase, disk access
// or raw key publication. Reuse the old credential buffer only after erasure.
@[direct_array_access]
fn rewrap_volume_recovery(input &char, old_recovery &char, new_recovery &char, destination &char) i32 {
	mut work := unsafe { &VolumeSealFiles(C.alloca(sizeof(VolumeSealFiles))) }
	unsafe { *work = VolumeSealFiles{} }
	defer { close_plan_edit(mut work.edit); erase_key(work, sizeof(VolumeSealFiles)) }
	if !read_recovery_file(input, &work.envelope[0], volume_seal_bytes)
		|| !volume_recovery_header(&work.envelope[0], volume_seal_bytes) { return plan_error(c'invalid volume recovery format or geometry') }
	if !read_recovery_file(old_recovery, &work.wrapping[0], 64)
		|| !decode_volume_recovery(&work.envelope[0], volume_seal_bytes, &work.wrapping[0], mut work.disk, mut work.request) {
		return plan_error(c'invalid volume recovery configuration or recovery key')
	}
	erase_key(&work.wrapping[0], 64)
	if !read_recovery_file(new_recovery, &work.wrapping[0], 64) || !recovery_nonce(&work.random[0]) { return 1 }
	if !encode_volume_recovery(&work.disk, &work.request, &work.wrapping[0], &work.random[0], &work.envelope[0]) {
		return plan_error(c'volume and recovery keys must differ and have distinct halves')
	}
	erase_key(&work.wrapping[0], 64); erase_key(&work.request.key[0], 64)
	if !open_plan_destination(destination, mut work.edit, true)
		|| !publish_recovery(&work.edit, &work.envelope[0], volume_seal_bytes) { return 1 }
	return finish_bundle_report(C.printf(c'volume recovery configuration rewrapped\n') >= 0)
}
