// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

// Prepare the authenticated candidate and erase its plaintext secrets before
// opening the disk. The caller declares the capacity to adopt explicitly.
@[direct_array_access]
fn plan_grow_volume_recovery(device &char, input &char, recovery &char, capacity u64, length u64, destination &char) i32 {
	mut work := unsafe { &VolumeSealFiles(C.alloca(sizeof(VolumeSealFiles))) }
	unsafe { *work = VolumeSealFiles{} }
	defer { close_plan_edit(mut work.edit); erase_key(work, sizeof(VolumeSealFiles)) }
	if !read_recovery_file(input, &work.envelope[0], volume_seal_bytes)
		|| !volume_recovery_header(&work.envelope[0], volume_seal_bytes) { return plan_error(c'invalid volume recovery format or geometry') }
	if !read_recovery_file(recovery, &work.wrapping[0], 64)
		|| !decode_volume_recovery(&work.envelope[0], volume_seal_bytes, &work.wrapping[0], mut work.disk, mut work.request) {
		return plan_error(c'invalid volume recovery configuration or recovery key')
	}
	work.after = work.disk; work.after.bytes = capacity
	if length > u64(0x7fffffffffffffff) || !volume_seal_growth(&work.disk, &work.after, &work.request.data, length) {
		return plan_error(c'recovery growth requires nondecreasing capacity/extent and valid native-sector bounds')
	}
	work.disk = work.after; work.request.data.length = length
	if !recovery_nonce(&work.random[0])
		|| !encode_volume_recovery(&work.disk, &work.request, &work.wrapping[0], &work.random[0], &work.envelope[0]) { return 1 }
	erase_key(&work.wrapping[0], 64); erase_key(&work.request.key[0], 64)
	fd := C.open(device, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 { C.perror(c'vinix-volume: open recovery growth parent'); return 1 }; defer { C.close(fd) }
	if !probe_disk(fd, mut work.after, mut work.status) || !key_matches(&work.disk, &work.after) {
		return plan_error(c'recovery growth disk identity, native sectors or declared capacity do not match')
	}
	if !volume_seal_recheck(fd, mut *work) || !open_plan_destination(destination, mut work.edit, true)
		|| !volume_seal_recheck(fd, mut *work) || !publish_recovery(&work.edit, &work.envelope[0], volume_seal_bytes) { return 1 }
	return finish_bundle_report(C.printf(c'volume recovery growth configuration published\n') >= 0)
}
