// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

const bundle_header_bytes = 64
const bundle_max_bytes = 6208 // Header + 64 disk headers + 64 global mappings.

@[direct_array_access]
fn bundle_set_valid(set &PlanSet) bool {
	if set.count <= 0 || set.count > 64 { return false }
	mut slots := u64(0)
	for i := 0; i < set.count; i++ {
		plan := unsafe { &set.plans[i] }
		if !plan_valid(plan) { return false }
		for j := 0; j < i; j++ {
			if key_matches(unsafe { &plan.key }, unsafe { &set.plans[j].key }) { return false }
		}
		for row := u32(0); row < plan.count; row++ {
			bit := u64(1) << plan.rows[row].slot
			if slots & bit != 0 { return false }
			slots |= bit
		}
	}
	return true
}

// A bundle contains complete version-1 disk plans, including their checksums.
// Its outer checksum also covers their order and the complete set header.
@[direct_array_access]
fn encode_bundle(set &PlanSet, output &u8) int {
	if !bundle_set_valid(set) { return 0 }
	unsafe {
		for i in 0 .. bundle_header_bytes {
			output[i] = 0
		}
	}
	mut size := bundle_header_bytes
	mut rows := u32(0)
	for i := 0; i < set.count; i++ {
		size += encode_plan(unsafe { &set.plans[i] }, unsafe { output + size })
		rows += set.plans[i].count
	}
	put_le(output, 0, 8, 0x31535658494e4956) // VINIXVS1
	put_le(output, 8, 4, 1)
	put_le(output, 12, 4, u64(set.count))
	put_le(output, 16, 4, u64(size))
	put_le(output, 20, 4, rows)
	put_le(output, 24, 4, crc32(output, size, 24))
	return size
}

// Append to the existing boot set, rolling back the visible count/slot mask
// on failure. No mapping can be created until every input has been accepted.
@[direct_array_access]
fn decode_bundle(data &u8, size int, mut set PlanSet) bool {
	if size < bundle_header_bytes || size > bundle_max_bytes
		|| get_le(data, 0, 8) != 0x31535658494e4956 || get_le(data, 8, 4) != 1
		|| get_le(data, 16, 4) != u64(size) || get_le(data, 24, 4) != crc32(data, size, 24) {
		return false
	}
	count := get_le(data, 12, 4)
	rows := get_le(data, 20, 4)
	if count == 0 || count > 64 || rows > 64 || set.count < 0 || set.count > 64 - int(count) {
		return false
	}
	unsafe {
		for i in 28 .. bundle_header_bytes {
			if data[i] != 0 { return false }
		}
	}
	original_count := set.count
	original_slots := set.slots
	mut accepted := false
	defer {
		if !accepted {
			set.count = original_count
			set.slots = original_slots
		}
	}
	mut plan := unsafe { &Plan(C.alloca(sizeof(Plan))) }
	unsafe {
		*plan = Plan{}
	}
	mut at := bundle_header_bytes
	mut total_rows := u64(0)
	for _ in 0 .. int(count) {
		if size - at < plan_header_bytes { return false }
		inner_rows := get_le(unsafe { data + at }, 12, 4)
		if inner_rows > 64 || total_rows + inner_rows > 64 { return false }
		length := plan_header_bytes + int(inner_rows) * 32
		if length > size - at || !decode_plan(unsafe { data + at }, length, mut plan)
			|| !append_plan(mut set, plan) {
			return false
		}
		at += length
		total_rows += inner_rows
	}
	if at != size || total_rows != rows { return false }
	accepted = true
	return true
}

@[direct_array_access]
fn read_bundle(fd i32, mut set PlanSet, trusted bool) bool {
	mut info := C.stat{}
	if C.fstat(fd, &info) != 0 {
		C.perror(c'vinix-volume: stat bundle')
		return false
	}
	if C.S_ISREG(info.st_mode) == 0 || info.st_size < bundle_header_bytes
		|| info.st_size > bundle_max_bytes {
		plan_error(c'bundle must be a bounded regular file')
		return false
	}
	if trusted && (info.st_uid != 0 || info.st_mode & 0o022 != 0) {
		plan_error(c'boot bundle must be owned by root and not writable by group or others')
		return false
	}
	mut bytes := [6208]u8{}
	mut done := i64(0)
	for done < info.st_size {
		read := C.read(fd, unsafe { &bytes[done] }, usize(info.st_size - done))
		if read < 0 && unsafe { C.errno == C.EINTR } { continue
		 }
		if read <= 0 {
			plan_error(c'short bundle read')
			return false
		}
		done += read
	}
	mut extra := u8(0)
	for {
		read := C.read(fd, &extra, 1)
		if read < 0 && unsafe { C.errno == C.EINTR } { continue
		 }
		if read != 0 {
			plan_error(c'bundle changed or has trailing bytes')
			return false
		}
		break
	}
	if !decode_bundle(&bytes[0], int(done), mut set) {
		plan_error(c'invalid bundle version, checksum, disk or mapping set')
		return false
	}
	return true
}

fn load_relative_bundle(directory i32, name &char, mut set PlanSet, trusted bool, optional bool) bool {
	fd := C.openat(directory, name, C.O_RDONLY | C.O_NOFOLLOW | C.O_NONBLOCK | C.O_CLOEXEC)
	if fd < 0 {
		if optional && unsafe { C.errno == C.ENOENT } { return true }
		C.perror(c'vinix-volume: open bundle')
		return false
	}
	defer { C.close(fd) }
	return read_bundle(fd, mut set, trusted)
}

fn publish_bundle(path &char, set &PlanSet) bool {
	mut bytes := [6208]u8{}
	size := encode_bundle(set, &bytes[0])
	if size == 0 {
		plan_error(c'invalid volume bundle snapshot')
		return false
	}
	return publish_bytes(path, &bytes[0], size)
}

// Retain all disk descriptors until the final identity pass and publication.
// Administration must be serialized: the kernel has no global mapping snapshot.
@[direct_array_access]
fn save_bundle(path &char, count int, devices &&char) i32 {
	if count <= 0 || count > 64 { return usage() }
	mut set := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	mut plan := unsafe { &Plan(C.alloca(sizeof(Plan))) }
	unsafe {
		*set = PlanSet{}
		*plan = Plan{}
	}
	mut parents := [64]Status{}
	mut fds := [64]i32{}
	mut opened := 0
	defer {
		for i in 0 .. opened {
			C.close(fds[i])
		}
	}
	for i in 0 .. count {
		fd := C.open(unsafe { devices[i] }, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW)
		if fd < 0 {
			C.perror(c'vinix-volume: open bundle disk')
			return 1
		}
		fds[i] = fd
		opened++
		if !snapshot_plan(fd, mut plan, mut parents[i]) || !append_plan(mut set, plan) { return 1 }
		for j in 0 .. i {
			if parents[i].disk_id == parents[j].disk_id {
				return plan_error(c'bundle repeats a physical disk')
			}
		}
	}
	for i in 0 .. count {
		if !verify_restore_disk(fds[i], unsafe { &set.plans[i] }, unsafe { &parents[i] }) {
			return 1
		}
	}
	if !publish_bundle(path, set) { return 1 }
	C.printf(c'saved bundle for %u disks\n', u32(set.count))
	return 0
}

fn restore_bundle(path &char, grow bool) i32 {
	fd := C.open(path, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 {
		C.perror(c'vinix-volume: open bundle')
		return 1
	}
	defer { C.close(fd) }
	mut set := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	unsafe {
		*set = PlanSet{}
	}
	if !read_bundle(fd, mut set, false) { return 1 }
	return restore_plan_set_mode(set, grow)
}

// Edit desired capacity only. Validate the complete set before replacing its
// saved file; no device is opened and no live mapping is changed here.
@[direct_array_access]
fn grow_bundle_plan(path &char, slot u32, length u64) i32 {
	fd := C.open(path, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 { C.perror(c'vinix-volume: open bundle'); return 1 }
	defer { C.close(fd) }
	mut set := unsafe { &PlanSet(C.alloca(sizeof(PlanSet))) }
	unsafe { *set = PlanSet{} }
	if !read_bundle(fd, mut set, false) { return 1 }
	if !bundle_grow_row(mut set, slot, length) || !publish_bundle(path, set) { return 1 }
	C.printf(c'planned slot=%u bytes=%lu\n', slot, length)
	return 0
}

@[direct_array_access]
fn bundle_grow_row(mut set PlanSet, slot u32, length u64) bool {
	if slot >= 64 || !bundle_set_valid(unsafe { &set }) { return false }
	for disk in 0 .. set.count {
		for row := u32(0); row < set.plans[disk].count; row++ {
			if set.plans[disk].rows[row].slot != slot { continue }
			previous := set.plans[disk].rows[row].length
			if length < previous { plan_error(c'planned capacity cannot shrink'); return false }
			set.plans[disk].rows[row].length = length
			if !bundle_set_valid(unsafe { &set }) {
				set.plans[disk].rows[row].length = previous
				plan_error(c'planned capacity is unaligned, out of bounds or overlaps another mapping')
				return false
			}
			return true
		}
	}
	plan_error(c'planned mapping slot is absent'); return false
}
