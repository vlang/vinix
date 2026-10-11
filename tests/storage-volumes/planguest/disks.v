// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

// A valid empty participant with no attached physical match. This exercises
// offline membership and the separate live discovery/preflight requirements.
@[direct_array_access]
fn offline_disk_plan() {
	input := C.open(c'/root/member.vmap', C.O_RDONLY)
	mut header := [64]u8{}
	check(input >= 0 && C.read(input, &header[0], 64) == 64 && C.close(input) == 0,
		c'read empty participant template')
	for i in 12 .. 16 {
		header[i] = 0
	}
	header[40] = 0x7b
	mut crc := u32(-1)
	for i in 0 .. 64 {
		crc ^= if i >= 36 && i < 40 { u32(0) } else { u32(header[i]) }
		for _ in 0 .. 8 {
			crc = (crc >> 1) ^ if crc & 1 != 0 { u32(0xedb88320) } else { u32(0) }
		}
	}
	crc = ~crc
	for i in 0 .. 4 {
		header[36 + i] = u8(crc >> (8 * i))
	}
	output := C.open(c'/root/offline.vmap', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
	check(output >= 0 && C.write(output, &header[0], 64) == 64 && C.fsync(output) == 0
		&& C.close(output) == 0, c'write empty offline participant')
}

@[direct_array_access]
fn planned_disks(other &char) {
	unsafe {
		first := status(c'/dev/mapper/vinix2').generation
		second := status(c'/dev/mapper/vinix9').generation
		third := status(c'/dev/mapper/vinix13').generation
		fd := C.open(c'/root/saved.vset', C.O_RDONLY)
		mut original := [6208]u8{}
		size := C.read(fd, &original[0], 6208)
		check(fd >= 0 && size == 352 && C.close(fd) == 0, c'read membership baseline')
		simple(c'save', other, c'/root/member.vmap', 0)
		simple(c'plan-forget', c'/root/saved.vset', c'1', 1)
		simple(c'plan-forget', c'/root/saved.vset', c'2', 1)
		simple(c'plan-enroll', c'/root/saved.vset', c'/root/member.vmap', 1)
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		offline_disk_plan()
		simple(c'plan-enroll', c'/root/saved.vset', c'/root/offline.vmap', 0)
		mut output := [4096]char{}
		preview(c'show-bundle', false, 0, &output[0])
		check(contains(&output[0], c'disk=2 bytes=16777216 sector=512 identity=mbr:1234567b')
			&& contains(&output[0], c'disks=3 mappings=5'), c'inspect appended empty participant')
		preview(c'check-bundle', false, 1, &output[0])
		check(!contains(&output[0], c'action='), c'missing participant prevents all actions')
		simple(c'restore-bundle', c'/root/saved.vset', &char(nil), 1)
		check(status(c'/dev/mapper/vinix2').generation == first
			&& status(c'/dev/mapper/vinix9').generation == second,
			c'missing participant keeps generations')
		simple(c'plan-forget', c'/root/saved.vset', c'2', 0)
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		// Remove desired rows before dropping membership; live views and their
		// descriptors survive, even when the remaining set is explicitly replayed.
		held := C.open(c'/dev/mapper/vinix9', C.O_RDONLY)
		check(held >= 0, c'hold view across disk omission')
		simple(c'plan-remove', c'/root/saved.vset', c'9', 0)
		simple(c'plan-remove', c'/root/saved.vset', c'13', 0)
		simple(c'plan-forget', c'/root/saved.vset', c'1', 0)
		signature(other, 0x1234567a)
		preview(c'check-bundle', false, 0, &output[0])
		check(contains(&output[0], c'checked disks=1 create=0 keep=3 grow=0')
			&& !contains(&output[0], c'slot=9 action='), c'omitted disk no longer required')
		simple(c'restore-bundle', c'/root/saved.vset', &char(nil), 0)
		mut bytes := [4096]u8{}
		check(C.pread(held, &bytes[0], 4096, 0) == 4096 && C.close(held) == 0,
			c'held view reads after membership removal')
		for byte in bytes {
			check(byte == 0xb3, c'disk omission preserves data')
		}
		// Offline import accepts saved identity even while its physical match is
		// absent. It reinstates the exact desired rows, then live checks fail.
		simple(c'plan-enroll', c'/root/saved.vset', c'/root/member.vmap', 0)
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		preview(c'check-bundle', false, 1, &output[0])
		check(!contains(&output[0], c'action='), c'reenrolled absent disk has no actions')
		simple(c'restore-bundle', c'/root/saved.vset', &char(nil), 1)
		signature(other, 0x12345679)
		preview(c'check-bundle', false, 0, &output[0])
		check(contains(&output[0], c'checked disks=2 create=0 keep=5 grow=0'),
			c'reenrollment restores complete replay set')
		simple(c'restore-bundle', c'/root/saved.vset', &char(nil), 0)
		check(status(c'/dev/mapper/vinix2').generation == first
			&& status(c'/dev/mapper/vinix9').generation == second
			&& status(c'/dev/mapper/vinix13').generation == third,
			c'membership roundtrip preserves live generations')
		second_view_data()
		edited_view_data()
		copy_plan(c'/root/saved.vset', c'/etc/vinix/volumes.vset')
		C.printf(c'PLAN DISKS PASSED: offline enrollment, empty removal, missing identity, preserved data and live descriptors\n')
	}
}
