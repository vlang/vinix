// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

// The existing loader owns the bounded KDF allocation and erases/releases it.
// Queries retain only authenticated metadata after erasing the decoded secrets.
@[direct_array_access]
fn inspect_volume_seal(config &char, password &char, online bool) i32 {
	mut work := unsafe { &VolumeSealFiles(C.alloca(sizeof(VolumeSealFiles))) }
	unsafe { *work = VolumeSealFiles{} }
	defer { erase_key(work, sizeof(VolumeSealFiles)) }
	if !load_volume_seal(config, password, mut *work) { return 1 }
	erase_key(&work.password[0], 1024); erase_key(&work.wrapping[0], 64); erase_key(&work.request.key[0], 64)
	mut name := [256]char{}
	if !online { return finish_bundle_report(show_sealed_volume(&work.disk, &work.request.data, &name[0], false)) }
	fd := discover_disk_key(&work.disk, c'/dev', false, &name[0], mut work.status)
	if fd < 0 { return 1 }; defer { C.close(fd) }
	if !volume_seal_recheck(fd, mut *work) || !volume_seal_recheck(fd, mut *work) { return 1 }
	return finish_bundle_report(show_sealed_volume(&work.disk, &work.request.data, &name[0], true))
}

@[direct_array_access]
fn show_sealed_volume(disk &DiskKey, row &Request, name &char, online bool) bool {
	mut identity := [41]char{}
	disk_identity(disk, &identity[0])
	if online {
		if C.printf(c'operation=discovered-volume device=/dev/%s\n', name) < 0 { return false }
	} else if C.printf(c'operation=authenticated-volume\n') < 0 { return false }
	return C.printf(c'disk_bytes=%lu sector=%lu identity=%s\n', disk.bytes, disk.sector, &identity[0]) >= 0
		&& C.printf(c'slot=%u offset=%lu bytes=%lu readonly=%lu\n', row.slot, row.offset, row.length, row.flags) >= 0
}
