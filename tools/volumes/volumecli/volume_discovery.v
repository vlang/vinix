// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

@[direct_array_access]
fn open_volume_seal_auto(config &char, password &char, readonly bool) i32 {
	mut work := unsafe { &VolumeSealFiles(C.alloca(sizeof(VolumeSealFiles))) }
	unsafe { *work = VolumeSealFiles{} }
	defer { erase_key(work, sizeof(VolumeSealFiles)) }
	if !load_volume_seal(config, password, mut *work) { return 1 }
	// Discovery needs only authenticated metadata and the eventual volume key.
	erase_key(&work.password[0], 1024)
	erase_key(&work.wrapping[0], 64)
	if readonly { work.request.data.flags = 1 }
	mut name := [256]char{}
	fd := discover_disk_key(&work.disk, c'/dev', work.request.data.flags == 0, &name[0], mut work.status)
	if fd < 0 { return 1 }; defer { C.close(fd) }
	if !volume_seal_recheck(fd, mut *work) || !volume_seal_recheck(fd, mut *work) { return 1 }
	if C.ioctl(fd, u64(0x56560006), &work.request) != 0 { C.perror(c'vinix-volume: import discovered encrypted mapping'); return 1 }
	return finish_bundle_report(C.printf(c'/dev/mapper/vinix%u\n', work.request.data.slot) >= 0)
}
