// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

fn C.fstatat(directory i32, const_name &char, info &C.stat, flags i32) i32

// Inspect without opening special files or following symlinks. The directory
// lock coordinates other saved-state writers throughout the operation.
fn data_destination_valid(destination &PlanEdit) bool {
	mut info := C.stat{}
	if C.fstatat(destination.directory, unsafe { &destination.name[0] }, &info, C.AT_SYMLINK_NOFOLLOW) != 0 {
		return unsafe { C.errno == C.ENOENT }
	}
	if C.S_ISREG(info.st_mode) == 0 { plan_error(c'checksum destination must be absent or a regular file'); return false }
	return true
}

struct DataDevices {
mut:
	count int
	disks [64]u32
	paths [64]&char
}

struct DataPins {
mut:
	count int
	descriptors [64]i32
	disks [64]u32
	ids [64]u64
}

@[direct_array_access]
fn data_devices_valid(set &PlanSet, devices &DataDevices) bool {
	if !data_ranges_valid(set) || devices.count != set.count { return false }
	mut seen := u64(0)
	for i in 0 .. devices.count {
		if devices.disks[i] >= u32(set.count) || devices.paths[i] == unsafe { nil } || unsafe { devices.paths[i][0] == 0 } { return false }
		bit := u64(1) << devices.disks[i]; if seen & bit != 0 { return false }; seen |= bit
	}
	return true
}

@[direct_array_access]
fn close_data_pins(mut pins DataPins) {
	for i in 0 .. pins.count { C.close(pins.descriptors[i]) }
	pins.count = 0
}

@[direct_array_access]
fn open_data_pins(set &PlanSet, devices &DataDevices, mut pins DataPins) bool {
	if pins.count != 0 || !data_devices_valid(set, devices) { return false }
	mut key := DiskKey{}
	for i in 0 .. devices.count {
		fd := C.open(devices.paths[i], C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
		if fd < 0 { C.perror(c'vinix-volume: open checksum disk'); return false }
		pins.descriptors[i] = fd; pins.disks[i] = devices.disks[i]; pins.count++
		mut status := Status{}
		if !probe_disk(fd, mut key, mut status) || !key_matches(unsafe { &set.plans[devices.disks[i]].key }, unsafe { &key }) {
			plan_error(c'checksum disk identity or geometry does not match'); return false
		}
		pins.ids[i] = status.disk_id
		for earlier in 0 .. i { if pins.ids[earlier] == status.disk_id { plan_error(c'checksum participants repeat a physical disk'); return false } }
	}
	return true
}

@[direct_array_access]
fn recheck_data_pins(set &PlanSet, pins &DataPins) bool {
	if pins.count != set.count { return false }
	mut key := DiskKey{}
	for i in 0 .. pins.count {
		mut status := Status{}
		if !probe_disk(pins.descriptors[i], mut key, mut status) || status.disk_id != pins.ids[i]
			|| !key_matches(unsafe { &set.plans[pins.disks[i]].key }, unsafe { &key }) {
			plan_error(c'checksum disk identity or geometry changed'); return false
		}
	}
	return true
}

// Reuse one fixed workspace for all rows. Accept interrupted and sector-aligned
// short reads; invalid/empty/oversized transfers never produce partial results.
@[direct_array_access]
fn read_data_digests(set &PlanSet, pins &DataPins, expected &DataDigests, mut digests DataDigests) bool {
	if !data_ranges_valid(set) || pins.count != set.count { return false }
	mut result := unsafe { &DataDigests(C.alloca(sizeof(DataDigests))) }; unsafe { *result = DataDigests{} }
	mut workspace := [65536]u8{}; mut context := unsafe { &DataSha256(C.alloca(sizeof(DataSha256))) }; unsafe { *context = DataSha256{} }
	for disk in 0 .. set.count {
		mut fd := i32(-1)
		for i in 0 .. pins.count { if pins.disks[i] == u32(disk) { fd = pins.descriptors[i]; break } }
		if fd < 0 { return false }
		for at := u32(0); at < set.plans[disk].count; at++ {
			row := set.plans[disk].rows[at]; data_sha_init(mut context); mut done := u64(0)
			for done < row.length {
				wanted := if row.length - done > 65536 { usize(65536) } else { usize(row.length - done) }
				read := C.pread(fd, &workspace[0], wanted, i64(row.offset + done))
				if read < 0 && unsafe { C.errno == C.EINTR } { continue }
				if read <= 0 || u64(read) > u64(wanted) || u64(read) % set.plans[disk].key.sector != 0 {
					plan_error(c'checksum data read failed or returned an invalid short transfer'); return false
				}
				if !data_sha_update(mut context, &workspace[0], usize(read)) { return false }; done += u64(read)
			}
			i := result.count
			if !data_sha_finish(context, unsafe { &result.values[i] }) { return false }
			result.disks[i] = u32(disk); result.slots[i] = row.slot
			if expected != unsafe { nil } {
				if i >= expected.count || expected.disks[i] != u32(disk) || expected.slots[i] != row.slot { return false }
				for byte in 0 .. 32 { if result.values[i][byte] != expected.values[i][byte] { plan_error(c'mapping data does not match recorded SHA-256'); return false } }
			}
			result.count++
		}
	}
	if expected != unsafe { nil } && result.count != expected.count { return false }
	digests = unsafe { *result }; return true
}

// Compare pinned directories and basenames, covering lexical aliases without
// forbidding distinct hard-linked entries that atomic replacement separates.
fn distinct_data_destination(source &PlanEdit, destination &PlanEdit) bool {
	mut input := C.stat{}; mut output := C.stat{}
	if C.fstat(source.directory, &input) != 0 || C.fstat(destination.directory, &output) != 0 { return false }
	return input.st_dev != output.st_dev || input.st_ino != output.st_ino || C.strcmp(unsafe { &source.name[0] }, unsafe { &destination.name[0] }) != 0
}

@[direct_array_access]
fn show_data_digests(manifest &DataManifest, operation &char) bool {
	mut ok := C.printf(c'operation=%s disks=%d mappings=%d algorithm=sha256\n', operation, manifest.set.count, manifest.digests.count) >= 0
	mut record := 0
	for disk in 0 .. manifest.set.count { for at := u32(0); at < manifest.set.plans[disk].count; at++ {
		row := manifest.set.plans[disk].rows[at]; mut text := [65]char{}
		for byte in 0 .. 32 { C.snprintf(unsafe { &text[byte * 2] }, usize(65 - byte * 2), c'%02x', u32(manifest.digests.values[record][byte])) }
		if C.printf(c'disk=%u slot=%u offset=%lu bytes=%lu readonly=%lu sha256=%s\n', u32(disk), row.slot, row.offset, row.length, row.flags, &text[0]) < 0 { ok = false }
		record++
	} }
	return ok
}

@[direct_array_access]
fn hash_bundle_data(bundle &char, path &char, devices &DataDevices) i32 {
	mut source := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }; mut destination := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }
	mut manifest := unsafe { &DataManifest(C.alloca(sizeof(DataManifest))) }; mut pins := unsafe { &DataPins(C.alloca(sizeof(DataPins))) }
	unsafe { *source = PlanEdit{}; *destination = PlanEdit{}; *manifest = DataManifest{}; *pins = DataPins{} }
	defer { close_plan_edit(mut destination) }; defer { close_plan_edit(mut source) }; defer { close_data_pins(mut pins) }
	if !open_plan_destination(path, mut destination, true) || !data_destination_valid(destination) || !open_plan_edit(bundle, mut source, false)
		|| !distinct_data_destination(source, destination) || !read_bundle(source.source, mut manifest.set, false)
		|| !data_devices_valid(unsafe { &manifest.set }, devices) { return 1 }
	if !open_data_pins(unsafe { &manifest.set }, devices, mut pins) || !recheck_data_pins(unsafe { &manifest.set }, pins)
		|| !read_data_digests(unsafe { &manifest.set }, pins, unsafe { nil }, mut manifest.digests)
		|| !recheck_data_pins(unsafe { &manifest.set }, pins) { return 1 }
	mut bytes := [11392]u8{}; size := encode_data_manifest(manifest, &bytes[0])
	if size == 0 || !data_destination_valid(destination) || !publish_edit_bytes(destination, &bytes[0], size) { return 1 }
	return finish_bundle_report(show_data_digests(manifest, c'recorded-data'))
}

@[direct_array_access]
fn verify_manifest_data(path &char, devices &DataDevices, inspect bool) i32 {
	mut source := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }; mut manifest := unsafe { &DataManifest(C.alloca(sizeof(DataManifest))) }
	mut pins := unsafe { &DataPins(C.alloca(sizeof(DataPins))) }; mut digests := DataDigests{}
	unsafe { *source = PlanEdit{}; *manifest = DataManifest{}; *pins = DataPins{} }
	defer { close_plan_edit(mut source) }; defer { close_data_pins(mut pins) }
	if !open_plan_edit(path, mut source, false) || !read_data_manifest(source.source, mut manifest) { return 1 }
	if inspect { return finish_bundle_report(show_data_digests(manifest, c'manifest-data')) }
	if !data_devices_valid(unsafe { &manifest.set }, devices) || !open_data_pins(unsafe { &manifest.set }, devices, mut pins)
		|| !recheck_data_pins(unsafe { &manifest.set }, pins) || !read_data_digests(unsafe { &manifest.set }, pins, unsafe { &manifest.digests }, mut digests)
		|| !recheck_data_pins(unsafe { &manifest.set }, pins) { return 1 }
	return finish_bundle_report(show_data_digests(manifest, c'verified-data'))
}
