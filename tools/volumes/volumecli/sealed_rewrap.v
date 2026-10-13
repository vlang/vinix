// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

// Authenticate the original before touching the next credential or output.
// Reuse one erased credential/KDF buffer; only the volume key crosses stages.
@[direct_array_access]
fn rewrap_sealed_key(input &char, old_password &char, new_password &char, destination &char) i32 {
	mut work := unsafe { &SealedFiles(C.alloca(sizeof(SealedFiles))) }
	unsafe { *work = SealedFiles{} }
	defer { close_plan_edit(mut work.edit); erase_key(work, sizeof(SealedFiles)) }
	if !load_sealed_key(input, old_password, mut *work) { return 1 }
	erase_key(&work.password[0], sizeof(work.password))
	erase_key(&work.wrapping[0], sizeof(work.wrapping))
	size := read_private_key_file(new_password, &work.password[0], 1, 1024)
	if size == 0 || !key_random_bytes(&work.random[0], 28)
		|| !sealed_derive(&work.password[0], size, &work.random[0], &work.wrapping[0]) { return 1 }
	if !encode_sealed_key(&work.request.key[0], &work.wrapping[0], &work.random[0], &work.envelope[0]) {
		return plan_error(c'invalid volume or wrapping key')
	}
	if !open_plan_destination(destination, mut work.edit, true) || !publish_recovery(&work.edit, &work.envelope[0], sealed_bytes) { return 1 }
	return finish_bundle_report(C.printf(c'sealed key rewrapped\n') >= 0)
}
