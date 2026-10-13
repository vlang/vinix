// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

// Preview authenticates the same formats but retains only public metadata for
// the explicitly declared candidate. No wrapping, publication or import occurs.
@[direct_array_access]
fn preview_volume_growth(device &char, input &char, credential &char, capacity u64, length u64, recovery bool) i32 {
	mut work := unsafe { &VolumeSealFiles(C.alloca(sizeof(VolumeSealFiles))) }
	unsafe { *work = VolumeSealFiles{} }
	defer { erase_key(work, sizeof(VolumeSealFiles)) }
	if recovery {
		if !read_recovery_file(input, &work.envelope[0], volume_seal_bytes)
			|| !volume_recovery_header(&work.envelope[0], volume_seal_bytes) { return plan_error(c'invalid volume recovery format or geometry') }
		if !read_recovery_file(credential, &work.wrapping[0], 64)
			|| !decode_volume_recovery(&work.envelope[0], volume_seal_bytes, &work.wrapping[0], mut work.disk, mut work.request) {
			return plan_error(c'invalid volume recovery configuration or recovery key')
		}
	} else if !load_volume_seal(input, credential, mut *work) { return 1 }
	erase_key(&work.password[0], 1024); erase_key(&work.wrapping[0], 64); erase_key(&work.request.key[0], 64)
	saved_capacity := work.disk.bytes; saved_length := work.request.data.length
	work.after = work.disk; work.after.bytes = capacity
	if length > u64(0x7fffffffffffffff) || !volume_seal_growth(&work.disk, &work.after, &work.request.data, length) {
		return plan_error(c'growth preview requires nondecreasing capacity/extent and valid native-sector bounds')
	}
	work.disk = work.after; work.request.data.length = length
	fd := C.open(device, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 { C.perror(c'vinix-volume: open growth preview parent'); return 1 }; defer { C.close(fd) }
	if !probe_disk(fd, mut work.after, mut work.status) || !key_matches(&work.disk, &work.after) {
		return plan_error(c'growth preview disk identity, native sectors or declared capacity do not match')
	}
	if !volume_seal_recheck(fd, mut *work) || !volume_seal_recheck(fd, mut *work) { return 1 }
	return finish_bundle_report(show_volume_growth_preview(&work.disk, &work.request.data, saved_capacity, saved_length, recovery))
}

@[direct_array_access]
fn show_volume_growth_preview(disk &DiskKey, row &Request, saved_capacity u64, saved_length u64, recovery bool) bool {
	mut identity := [41]char{}
	disk_identity(disk, &identity[0])
	domain := if recovery { &char(c'recovery') } else { &char(c'volume') }
	capacity_action := if disk.bytes == saved_capacity { &char(c'keep') } else { &char(c'grow') }
	extent_action := if row.length == saved_length { &char(c'keep') } else { &char(c'grow') }
	return C.printf(c'operation=checked-growth format=%s\n', domain) >= 0
		&& C.printf(c'current_disk_bytes=%lu planned_disk_bytes=%lu sector=%lu identity=%s capacity_action=%s\n', saved_capacity, disk.bytes, disk.sector, &identity[0], capacity_action) >= 0
		&& C.printf(c'slot=%u offset=%lu current_bytes=%lu planned_bytes=%lu readonly=%lu extent_action=%s\n', row.slot, row.offset, saved_length, row.length, row.flags, extent_action) >= 0
}
