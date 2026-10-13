// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

struct VolumeSealFiles {
mut:
	edit PlanEdit
	request EncryptedRequest
	disk DiskKey
	after DiskKey
	status Status
	after_status Status
	password [1024]u8
	wrapping [64]u8
	envelope [320]u8
	random [28]u8
}

@[direct_array_access]
fn load_volume_seal(config &char, password &char, mut work VolumeSealFiles) bool {
	if !read_recovery_file(config, &work.envelope[0], volume_seal_bytes) || !volume_seal_header(&work.envelope[0], volume_seal_bytes) {
		plan_error(c'invalid sealed volume format, geometry or work profile'); return false
	}
	size := read_private_key_file(password, &work.password[0], 1, 1024)
	if size == 0 || !sealed_derive(&work.password[0], size, &work.envelope[40], &work.wrapping[0]) { return false }
	if !decode_volume_seal(&work.envelope[0], volume_seal_bytes, &work.wrapping[0], mut work.disk, mut work.request) {
		plan_error(c'invalid sealed volume or passphrase'); return false
	}
	return true
}

fn volume_seal_recheck(fd i32, mut work VolumeSealFiles) bool {
	if !probe_disk(fd, mut work.after, mut work.after_status) || !key_matches(&work.disk, &work.after)
		|| work.after_status.disk_id != work.status.disk_id || (work.after_status.flags & 1) != (work.status.flags & 1) {
		plan_error(c'volume disk identity or geometry changed before publication or import'); return false
	}
	return true
}

@[direct_array_access]
fn seal_volume_file(device &char, keyfile &char, password &char, destination &char, data &Request) i32 {
	mut work := unsafe { &VolumeSealFiles(C.alloca(sizeof(VolumeSealFiles))) }
	unsafe { *work = VolumeSealFiles{request: EncryptedRequest{data: *data}} }
	defer { close_plan_edit(mut work.edit); erase_key(work, sizeof(VolumeSealFiles)) }
	if !read_volume_key(keyfile, &work.request.key[0]) { return 1 }
	size := read_private_key_file(password, &work.password[0], 1, 1024)
	if size == 0 { return 1 }
	fd := C.open(device, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 { C.perror(c'vinix-volume: open configuration disk'); return 1 }; defer { C.close(fd) }
	if !probe_disk(fd, mut work.disk, mut work.status) || !volume_seal_geometry(&work.disk, &work.request.data) { return plan_error(c'invalid encrypted extent or physical disk') }
	if !key_random_bytes(&work.random[0], 28) || !sealed_derive(&work.password[0], size, &work.random[0], &work.wrapping[0])
		|| !encode_volume_seal(&work.disk, &work.request, &work.wrapping[0], &work.random[0], &work.envelope[0]) { return 1 }
	if !open_plan_destination(destination, mut work.edit, true) || !volume_seal_recheck(fd, mut *work)
		|| !publish_recovery(&work.edit, &work.envelope[0], volume_seal_bytes) { return 1 }
	return finish_bundle_report(C.printf(c'sealed volume configuration published\n') >= 0)
}

@[direct_array_access]
fn open_volume_seal(device &char, config &char, password &char, readonly bool) i32 {
	mut work := unsafe { &VolumeSealFiles(C.alloca(sizeof(VolumeSealFiles))) }
	unsafe { *work = VolumeSealFiles{} }
	defer { erase_key(work, sizeof(VolumeSealFiles)) }
	if !load_volume_seal(config, password, mut *work) { return 1 }
	if readonly { work.request.data.flags = 1 }
	fd := C.open(device, (if work.request.data.flags == 0 { C.O_RDWR } else { C.O_RDONLY }) | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 { C.perror(c'vinix-volume: open configured encrypted parent'); return 1 }; defer { C.close(fd) }
	if !probe_disk(fd, mut work.after, mut work.status) || !key_matches(&work.disk, &work.after) {
		return plan_error(c'sealed volume disk identity or geometry does not match')
	}
	if !volume_seal_recheck(fd, mut *work) { return 1 }
	if C.ioctl(fd, u64(0x56560006), &work.request) != 0 { C.perror(c'vinix-volume: import configured encrypted mapping'); return 1 }
	return finish_bundle_report(C.printf(c'/dev/mapper/vinix%u\n', work.request.data.slot) >= 0)
}

@[direct_array_access]
fn unseal_volume_key(config &char, password &char, destination &char) i32 {
	mut work := unsafe { &VolumeSealFiles(C.alloca(sizeof(VolumeSealFiles))) }
	unsafe { *work = VolumeSealFiles{} }
	defer { close_plan_edit(mut work.edit); erase_key(work, sizeof(VolumeSealFiles)) }
	if !load_volume_seal(config, password, mut *work) || !open_plan_destination(destination, mut work.edit, true)
		|| !publish_recovery(&work.edit, &work.request.key[0], 64) { return 1 }
	return finish_bundle_report(C.printf(c'private volume key unsealed\n') >= 0)
}
