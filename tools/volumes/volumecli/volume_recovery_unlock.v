// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

// Rescue access needs only the authenticated backup and recovery credential.
// Keep the decoded volume key until import; erase the whole workspace on exit.
@[direct_array_access]
fn open_volume_recovery_auto(backup &char, recovery &char, readonly bool) i32 {
	mut work := unsafe { &VolumeSealFiles(C.alloca(sizeof(VolumeSealFiles))) }
	unsafe { *work = VolumeSealFiles{} }
	defer { erase_key(work, sizeof(VolumeSealFiles)) }
	if !read_recovery_file(backup, &work.envelope[0], volume_seal_bytes)
		|| !volume_recovery_header(&work.envelope[0], volume_seal_bytes) { return plan_error(c'invalid volume recovery format or geometry') }
	if !read_recovery_file(recovery, &work.wrapping[0], 64)
		|| !decode_volume_recovery(&work.envelope[0], volume_seal_bytes, &work.wrapping[0], mut work.disk, mut work.request) {
		return plan_error(c'invalid volume recovery configuration or recovery key')
	}
	erase_key(&work.wrapping[0], 64)
	return open_loaded_volume_seal_auto(mut *work, readonly)
}
