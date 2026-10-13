// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

struct BootVolumeEntry {
mut:
	disk DiskKey
	request EncryptedRequest
	status Status
	fd i32
}

// Keys remain in caller-owned stack storage until every synchronous import ends.
struct BootVolumeSet {
mut:
	count int
	slots u64
	directory i32 = -1
	opened int
	rows [64]BootVolumeEntry
}

fn boot_volume_filename(name &char) bool {
	length := C.strlen(name)
	return length > 7 && length <= 255 && unsafe { name[0] != char(`.`) && C.strcmp(&name[length - 7], c'.vcrypt') == 0 }
}

@[direct_array_access]
fn boot_volume_collection_valid(volumes &BootVolumeSet) bool {
	if volumes.count < 0 || volumes.count > 64 { return false }
	mut slots := u64(0)
	for i in 0 .. volumes.count {
		row := &volumes.rows[i]
		if !volume_seal_geometry(&row.disk, &row.request.data) { return false }
		data := &row.request.data
		bit := u64(1) << data.slot
		if slots & bit != 0 { return false }; slots |= bit
		for j in 0 .. i {
			prior := &volumes.rows[j]
			if key_matches(&row.disk, &prior.disk) && data.offset < prior.request.data.offset + prior.request.data.length
				&& prior.request.data.offset < data.offset + data.length { return false }
		}
	}
	return slots == volumes.slots
}

@[direct_array_access]
fn append_boot_volume(mut volumes BootVolumeSet, disk &DiskKey, request &EncryptedRequest) bool {
	if !boot_volume_collection_valid(&volumes) || volumes.count == 64 || volumes.opened != 0 || !volume_seal_geometry(disk, &request.data) { return false }
	for i in 0 .. volumes.count {
		row := &volumes.rows[i]
		if row.request.data.slot == request.data.slot || (key_matches(&row.disk, disk)
			&& row.request.data.offset < request.data.offset + request.data.length
			&& request.data.offset < row.request.data.offset + row.request.data.length) { return false }
	}
	volumes.rows[volumes.count].disk = unsafe { *disk }
	volumes.rows[volumes.count].request = unsafe { *request }
	volumes.slots |= u64(1) << request.data.slot; volumes.count++
	return true
}

@[direct_array_access]
fn boot_volumes_plain_compatible(plain &PlanSet, volumes &BootVolumeSet) bool {
	if !boot_volume_collection_valid(volumes) || plain.count < 0 || plain.count > 64
		|| (plain.count == 0 && (plain.regions != 0 || plain.slots != 0))
		|| (plain.count > 0 && !bundle_set_valid(plain)) { return false }
	for i in 0 .. volumes.count {
		row := &volumes.rows[i]
		if !boot_volume_plain_compatible(plain, &row.disk, &row.request.data) { return false }
	}
	return true
}

fn boot_volumes_trusted(etc i32, directory i32, volumes &BootVolumeSet) bool {
	return boot_volume_directories(etc, directory) && (volumes.directory < 0
		|| trusted_directory(volumes.directory, c'boot encrypted set directory must be owned by root and not writable by group or others'))
}

// The caller owns the directory and all successfully appended keys on failures.
@[direct_array_access]
fn load_boot_volumes(etc i32, directory i32, mut volumes BootVolumeSet, mut work VolumeSealFiles) bool {
	if volumes.count != 0 || volumes.slots != 0 || volumes.opened != 0 || volumes.directory != -1 { return false }
	loaded := load_boot_volume(etc, directory, mut work)
	if loaded < 0 { return false }
	if loaded == 1 {
		if !append_boot_volume(mut volumes, &work.disk, &work.request) { return false }
		erase_key(&work.request.key[0], 64)
	}
	volumes.directory = C.openat(directory, c'boot-volumes.d', C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if volumes.directory < 0 {
		if unsafe { C.errno == C.ENOENT } { return true }
		C.perror(c'vinix-volume: boot encrypted set directory'); return false
	}
	copy := C.fcntl(volumes.directory, C.F_DUPFD_CLOEXEC, 0)
	if copy < 0 { C.perror(c'vinix-volume: duplicate encrypted set directory'); return false }
	stream := C.fdopendir(copy)
	if stream == unsafe { nil } { C.close(copy); C.perror(c'vinix-volume: enumerate encrypted set'); return false }
	defer { C.closedir(stream) }
	mut names := [64][256]char{}
	mut count := 0; mut entries := 0
	for {
		unsafe { C.errno = 0 }
		entry := C.readdir(stream)
		if entry == unsafe { nil } { if unsafe { C.errno != 0 } { C.perror(c'vinix-volume: encrypted set enumeration'); return false }; break }
		name := unsafe { &entry.d_name[0] }
		if C.strcmp(name, c'.') == 0 || C.strcmp(name, c'..') == 0 { continue }
		entries++; if entries > 4096 { plan_error(c'encrypted set directory exceeds enumeration limit'); return false }
		if !boot_volume_filename(name) { continue }
		if count >= 64 - volumes.count { plan_error(c'encrypted boot set exceeds 64 mappings'); return false }
		mut at := count
		for at > 0 && C.strcmp(name, &names[at - 1][0]) < 0 { names[at] = names[at - 1]; at-- }
		C.snprintf(&names[at][0], 256, c'%s', name); count++
	}
	if count > 0 && !boot_volumes_trusted(etc, directory, &volumes) { return false }
	for i in 0 .. count {
		mut credential := [256]char{}
		C.memcpy(&credential[0], &names[i][0], 256)
		length := C.strlen(&credential[0])
		unsafe { C.memcpy(&credential[length - 7], c'.pass', 6) }
		if load_named_boot_volume(etc, volumes.directory, &names[i][0], &credential[0], mut work) != 1
			|| !append_boot_volume(mut volumes, &work.disk, &work.request) { return false }
		erase_key(&work.request.key[0], 64)
	}
	return true
}

// Discover the complete authenticated set before plain or encrypted application.
@[direct_array_access]
fn prepare_boot_volumes(mut volumes BootVolumeSet, mut work VolumeSealFiles) bool {
	if !boot_volume_collection_valid(&volumes) || volumes.opened != 0 { return false }
	for i in 0 .. volumes.count {
		row := &volumes.rows[i]
		mut name := [256]char{}
		fd := discover_disk_key(&row.disk, c'/dev', row.request.data.flags == 0, &name[0], mut volumes.rows[i].status)
		if fd < 0 { return false }
		volumes.rows[i].fd = fd; volumes.opened++
	}
	for i in 0 .. volumes.count {
		work.disk = volumes.rows[i].disk; work.status = volumes.rows[i].status
		if !volume_seal_recheck(volumes.rows[i].fd, mut work) { return false }
	}
	return true
}

@[direct_array_access]
fn apply_boot_volumes(etc i32, directory i32, volumes &BootVolumeSet, mut work VolumeSealFiles) i32 {
	if !boot_volume_collection_valid(volumes) || volumes.opened != volumes.count { return 1 }
	for i in 0 .. volumes.count {
		if !boot_volumes_trusted(etc, directory, volumes) { return 1 }
		row := &volumes.rows[i]
		work.disk = row.disk; work.request = row.request; work.status = row.status
		if !volume_seal_recheck(row.fd, mut work) || !volume_seal_recheck(row.fd, mut work) { return 1 }
		if C.ioctl(row.fd, u64(0x56560006), &work.request) != 0 { C.perror(c'vinix-volume: import encrypted boot mapping'); return 1 }
		erase_key(&work.request.key[0], 64)
		if finish_bundle_report(C.printf(c'/dev/mapper/vinix%u\n', row.request.data.slot) >= 0) != 0 { return 1 }
	}
	return 0
}

@[direct_array_access]
fn close_boot_volumes(volumes &BootVolumeSet) {
	for i in 0 .. volumes.opened { C.close(volumes.rows[i].fd) }
	if volumes.directory >= 0 { C.close(volumes.directory) }
}
