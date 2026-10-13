// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

// Only authenticated metadata and the volume key cross credential stages.
// Reuse the fully erased credential and derived-key buffers; no disk is opened.
@[direct_array_access]
fn rewrap_volume_seal(input &char, old_password &char, new_password &char, destination &char) i32 {
	mut work := unsafe { &VolumeSealFiles(C.alloca(sizeof(VolumeSealFiles))) }
	unsafe { *work = VolumeSealFiles{} }
	defer { close_plan_edit(mut work.edit); erase_key(work, sizeof(VolumeSealFiles)) }
	if !load_volume_seal(input, old_password, mut *work) { return 1 }
	erase_key(&work.password[0], sizeof(work.password))
	erase_key(&work.wrapping[0], sizeof(work.wrapping))
	size := read_private_key_file(new_password, &work.password[0], 1, 1024)
	if size == 0 || !key_random_bytes(&work.random[0], 28)
		|| !sealed_derive(&work.password[0], size, &work.random[0], &work.wrapping[0]) { return 1 }
	if !encode_volume_seal(&work.disk, &work.request, &work.wrapping[0], &work.random[0], &work.envelope[0]) {
		return plan_error(c'invalid authenticated volume or wrapping key')
	}
	if !open_plan_destination(destination, mut work.edit, true)
		|| !publish_recovery(&work.edit, &work.envelope[0], volume_seal_bytes) { return 1 }
	return finish_bundle_report(C.printf(c'sealed volume configuration rewrapped\n') >= 0)
}
