// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

fn boot_volume_directories(etc i32, directory i32) bool {
	return trusted_directory(etc, c'boot configuration directory must be owned by root and not writable by group or others')
		&& trusted_directory(directory, c'boot encrypted directory must be owned by root and not writable by group or others')
}

// 0 means disabled, 1 authenticated, -1 rejected. No input path is reopened.
@[direct_array_access]
fn load_boot_volume(etc i32, directory i32, mut work VolumeSealFiles) i32 {
	return load_named_boot_volume(etc, directory, c'boot-volume.vcrypt', c'boot-volume.pass', mut work)
}

@[direct_array_access]
fn load_named_boot_volume(etc i32, directory i32, name &char, credential &char, mut work VolumeSealFiles) i32 {
	config := C.openat(directory, name, C.O_RDONLY | C.O_NOFOLLOW | C.O_NONBLOCK | C.O_CLOEXEC)
	if config < 0 {
		if unsafe { C.errno == C.ENOENT } { return 0 }
		C.perror(c'vinix-volume: boot encrypted configuration'); return -1
	}
	defer { C.close(config) }
	if C.geteuid() != 0 { plan_error(c'boot encrypted unlock requires root'); return -1 }
	if !boot_volume_directories(etc, directory) { return -1 }
	if read_private_key_fd(config, &work.envelope[0], volume_seal_bytes, volume_seal_bytes) != volume_seal_bytes
		|| !volume_seal_header(&work.envelope[0], volume_seal_bytes) { plan_error(c'invalid boot encrypted configuration'); return -1 }
	password := C.openat(directory, credential, C.O_RDONLY | C.O_NOFOLLOW | C.O_NONBLOCK | C.O_CLOEXEC)
	if password < 0 { C.perror(c'vinix-volume: boot encrypted credential'); return -1 }
	defer { C.close(password) }
	size := read_private_key_fd(password, &work.password[0], 1, 1024)
	if size == 0 || !sealed_derive(&work.password[0], size, &work.envelope[40], &work.wrapping[0])
		|| !decode_volume_seal(&work.envelope[0], volume_seal_bytes, &work.wrapping[0], mut work.disk, mut work.request) {
		plan_error(c'invalid boot encrypted configuration or credential'); return -1
	}
	erase_key(&work.password[0], 1024); erase_key(&work.wrapping[0], 64)
	return if boot_volume_directories(etc, directory) { 1 } else { -1 }
}

@[direct_array_access]
fn boot_volume_set_compatible(set &PlanSet, work &VolumeSealFiles) bool {
	return boot_volume_plain_compatible(set, &work.disk, &work.request.data)
}

@[direct_array_access]
fn boot_volume_plain_compatible(set &PlanSet, disk &DiskKey, data &Request) bool {
	if set.count < 0 || set.count > 64 || !volume_seal_geometry(disk, data)
		|| (set.count == 0 && set.regions != 0) || (set.count != 0 && !bundle_set_valid(set))
		|| set.slots & (u64(1) << data.slot) != 0 { return false }
	mut slots := u64(0)
	for i in 0 .. set.count {
		for j in 0 .. set.plans[i].count {
			row := &set.plans[i].rows[j]
			slots |= u64(1) << row.slot
			if row.slot == data.slot { return false }
			if key_matches(&set.plans[i].key, disk) && row.offset < data.offset + data.length
				&& data.offset < row.offset + row.length { return false }
		}
	}
	return slots == set.slots
}

// Automatic unlock alone uses the same opt-in files as boot-restore.
fn boot_unlock_volume() i32 {
	etc := C.open(c'/etc', C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if etc < 0 { if unsafe { C.errno == C.ENOENT } { return 0 }; C.perror(c'vinix-volume: boot configuration directory'); return 1 }
	defer { C.close(etc) }
	directory := C.openat(etc, c'vinix', C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if directory < 0 { if unsafe { C.errno == C.ENOENT } { return 0 }; C.perror(c'vinix-volume: boot encrypted directory'); return 1 }
	defer { C.close(directory) }
	mut work := unsafe { &VolumeSealFiles(C.alloca(sizeof(VolumeSealFiles))) }
	unsafe { *work = VolumeSealFiles{} }
	defer { erase_key(work, sizeof(VolumeSealFiles)) }
	mut volumes := unsafe { &BootVolumeSet(C.alloca(sizeof(BootVolumeSet))) }
	unsafe { *volumes = BootVolumeSet{} }
	defer { close_boot_volumes(volumes); erase_key(volumes, sizeof(BootVolumeSet)) }
	if !load_boot_volumes(etc, directory, mut *volumes, mut *work) { return 1 }
	if volumes.count == 0 { return 0 }
	if !boot_volumes_trusted(etc, directory, volumes) || !prepare_boot_volumes(mut *volumes, mut *work) { return 1 }
	return apply_boot_volumes(etc, directory, volumes, mut *work)
}
