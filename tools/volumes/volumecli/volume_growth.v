// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

@[direct_array_access]
fn volume_seal_growth(saved &DiskKey, observed &DiskKey, row &Request, length u64) bool {
	if !volume_seal_geometry(saved, row) || !key_valid(observed) || observed.bytes < saved.bytes
		|| observed.sector != saved.sector || observed.kind != saved.kind || length < row.length { return false }
	for i in 0 .. 16 { if observed.id[i] != saved.id[i] { return false } }
	mut next := *row; next.length = length
	return volume_seal_geometry(observed, &next)
}

@[direct_array_access]
fn plan_grow_volume_seal(device &char, config &char, password &char, length u64, destination &char) i32 {
	mut work := unsafe { &VolumeSealFiles(C.alloca(sizeof(VolumeSealFiles))) }
	unsafe { *work = VolumeSealFiles{} }
	defer { close_plan_edit(mut work.edit); erase_key(work, sizeof(VolumeSealFiles)) }
	size := load_volume_seal_credentials(config, password, mut *work)
	if size == 0 { return 1 }
	erase_key(&work.wrapping[0], 64)
	if length < work.request.data.length { return plan_error(c'encrypted configuration growth cannot shrink the extent') }
	fd := C.open(device, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 { C.perror(c'vinix-volume: open encrypted growth parent'); return 1 }; defer { C.close(fd) }
	if !probe_disk(fd, mut work.after, mut work.status)
		|| !volume_seal_growth(&work.disk, &work.after, &work.request.data, length) {
		return plan_error(c'encrypted growth requires the same physical identity/sectors, nondecreasing capacity and a valid extent')
	}
	work.disk = work.after; work.request.data.length = length
	if !volume_seal_recheck(fd, mut *work) || !key_random_bytes(&work.random[0], 28)
		|| !sealed_derive(&work.password[0], size, &work.random[0], &work.wrapping[0])
		|| !encode_volume_seal(&work.disk, &work.request, &work.wrapping[0], &work.random[0], &work.envelope[0]) { return 1 }
	// Publication uses only the authenticated envelope and disk metadata.
	erase_key(&work.password[0], 1024); erase_key(&work.wrapping[0], 64); erase_key(&work.request.key[0], 64)
	if !open_plan_destination(destination, mut work.edit, true) || !volume_seal_recheck(fd, mut *work)
		|| !publish_recovery(&work.edit, &work.envelope[0], volume_seal_bytes) { return 1 }
	return finish_bundle_report(C.printf(c'encrypted volume growth configuration published\n') >= 0)
}
