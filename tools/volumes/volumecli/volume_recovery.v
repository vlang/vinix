// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

// Back up the authenticated configuration without opening a disk or writing a
// raw volume key. Erased credential buffers are reused for the recovery key.
@[direct_array_access]
fn backup_volume_seal(config &char, password &char, recovery &char, destination &char) i32 {
	mut work := unsafe { &VolumeSealFiles(C.alloca(sizeof(VolumeSealFiles))) }
	unsafe { *work = VolumeSealFiles{} }
	defer { close_plan_edit(mut work.edit); erase_key(work, sizeof(VolumeSealFiles)) }
	if !load_volume_seal(config, password, mut *work) { return 1 }
	erase_key(&work.password[0], 1024); erase_key(&work.wrapping[0], 64)
	if !read_recovery_file(recovery, &work.wrapping[0], 64) || !recovery_nonce(&work.random[0]) { return 1 }
	if !encode_volume_recovery(&work.disk, &work.request, &work.wrapping[0], &work.random[0], &work.envelope[0]) {
		return plan_error(c'volume and recovery keys must differ and have distinct halves')
	}
	erase_key(&work.wrapping[0], 64); erase_key(&work.request.key[0], 64)
	if !open_plan_destination(destination, mut work.edit, true)
		|| !publish_recovery(&work.edit, &work.envelope[0], volume_seal_bytes) { return 1 }
	return finish_bundle_report(C.printf(c'volume recovery configuration published\n') >= 0)
}

// Authenticate the recovery domain before accessing the new credential/KDF.
// Restore exact metadata and key into a fresh ordinary VC1 configuration.
@[direct_array_access]
fn recover_volume_seal(backup &char, recovery &char, password &char, destination &char) i32 {
	mut work := unsafe { &VolumeSealFiles(C.alloca(sizeof(VolumeSealFiles))) }
	unsafe { *work = VolumeSealFiles{} }
	defer { close_plan_edit(mut work.edit); erase_key(work, sizeof(VolumeSealFiles)) }
	if !read_recovery_file(backup, &work.envelope[0], volume_seal_bytes)
		|| !volume_recovery_header(&work.envelope[0], volume_seal_bytes) { return plan_error(c'invalid volume recovery format or geometry') }
	if !read_recovery_file(recovery, &work.wrapping[0], 64)
		|| !decode_volume_recovery(&work.envelope[0], volume_seal_bytes, &work.wrapping[0], mut work.disk, mut work.request) {
		return plan_error(c'invalid volume recovery configuration or recovery key')
	}
	erase_key(&work.wrapping[0], 64)
	size := read_private_key_file(password, &work.password[0], 1, 1024)
	if size == 0 || !key_random_bytes(&work.random[0], 28)
		|| !sealed_derive(&work.password[0], size, &work.random[0], &work.wrapping[0])
		|| !encode_volume_seal(&work.disk, &work.request, &work.wrapping[0], &work.random[0], &work.envelope[0]) { return 1 }
	erase_key(&work.password[0], 1024); erase_key(&work.wrapping[0], 64); erase_key(&work.request.key[0], 64)
	if !open_plan_destination(destination, mut work.edit, true)
		|| !publish_recovery(&work.edit, &work.envelope[0], volume_seal_bytes) { return 1 }
	return finish_bundle_report(C.printf(c'recovered sealed volume configuration published\n') >= 0)
}
