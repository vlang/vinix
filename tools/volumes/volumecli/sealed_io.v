// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

struct SealedFiles {
mut:
	edit PlanEdit
	request EncryptedRequest
	password [1024]u8
	wrapping [64]u8
	envelope [192]u8
	random [28]u8
}

@[direct_array_access]
fn load_sealed_key(envelope &char, password &char, mut work SealedFiles) bool {
	if !read_recovery_file(envelope, &work.envelope[0], sealed_bytes) || !sealed_header(&work.envelope[0], sealed_bytes) {
		plan_error(c'invalid sealed-key format or work profile'); return false
	}
	size := read_private_key_file(password, &work.password[0], 1, 1024)
	if size == 0 || !sealed_derive(&work.password[0], size, &work.envelope[40], &work.wrapping[0]) { return false }
	if !decode_sealed_key(&work.envelope[0], sealed_bytes, &work.wrapping[0], &work.request.key[0]) {
		plan_error(c'invalid sealed key or passphrase'); return false
	}
	return true
}

@[direct_array_access]
fn sealed_key_file(input &char, password &char, destination &char, seal bool) i32 {
	mut work := unsafe { &SealedFiles(C.alloca(sizeof(SealedFiles))) }
	unsafe { *work = SealedFiles{} }
	defer { close_plan_edit(mut work.edit); erase_key(work, sizeof(SealedFiles)) }
	if seal {
		if !read_volume_key(input, &work.request.key[0]) { return 1 }
		size := read_private_key_file(password, &work.password[0], 1, 1024)
		if size == 0 || !key_random_bytes(&work.random[0], 28)
			|| !sealed_derive(&work.password[0], size, &work.random[0], &work.wrapping[0]) { return 1 }
		if !encode_sealed_key(&work.request.key[0], &work.wrapping[0], &work.random[0], &work.envelope[0]) { return plan_error(c'invalid volume or wrapping key') }
	} else if !load_sealed_key(input, password, mut *work) { return 1 }
	if !open_plan_destination(destination, mut work.edit, true) { return 1 }
	if !publish_recovery(&work.edit, if seal { &work.envelope[0] } else { &work.request.key[0] }, if seal { sealed_bytes } else { 64 }) { return 1 }
	return finish_bundle_report(C.printf(if seal { c'sealed key published\n' } else { c'private key unsealed\n' }) >= 0)
}

@[direct_array_access]
fn open_sealed_volume(device &char, envelope &char, password &char, data &Request) i32 {
	mut work := unsafe { &SealedFiles(C.alloca(sizeof(SealedFiles))) }
	unsafe { *work = SealedFiles{request: EncryptedRequest{data: *data}} }
	defer { erase_key(work, sizeof(SealedFiles)) }
	if !load_sealed_key(envelope, password, mut *work) { return 1 }
	return open_encrypted_request(device, &work.request)
}
