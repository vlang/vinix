// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn enrollment_plans(path &char, first &char, second &char, preview bool, expected i32, output &char) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'),
			if preview { &char(c'plan-preview-enroll-batch') } else { &char(c'plan-enroll-batch') },
			path, first, second, &char(nil)]!
		if output == nil { run_utility(&args[0], expected); return }
		fd := C.open(c'/root/enrollment-output', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600))
		check(fd >= 0, c'open enrollment output')
		child := C.fork(); check(child >= 0, c'fork enrollment command')
		if child == 0 {
			if C.dup2(fd, 1) != 1 || C.dup2(fd, 2) != 2 || C.close(fd) != 0 { C._exit(126) }
			C.execv(args[0], &args[0]); C._exit(127)
		}
		mut code := i32(0)
		check(C.close(fd) == 0 && C.waitpid(child, &code, 0) == child && code == expected << 8, c'enrollment command exit')
		input := C.open(c'/root/enrollment-output', C.O_RDONLY)
		count := C.read(input, output, 4095)
		check(input >= 0 && count > 0 && count < 4095 && C.close(input) == 0, c'read enrollment output')
		output[count] = 0
	}
}

@[direct_array_access]
fn enrollment_offline_plan() {
	input := C.open(c'/root/offline.vmap', C.O_RDONLY)
	mut header := [64]u8{}
	check(input >= 0 && C.read(input, &header[0], 64) == 64 && C.close(input) == 0, c'read second offline template')
	header[40] = 0x7c
	mut crc := u32(-1)
	for i in 0 .. 64 {
		crc ^= if i >= 36 && i < 40 { u32(0) } else { u32(header[i]) }
		for _ in 0 .. 8 { crc = (crc >> 1) ^ if crc & 1 != 0 { u32(0xedb88320) } else { u32(0) } }
	}
	crc = ~crc
	for i in 0 .. 4 { header[36 + i] = u8(crc >> (8 * i)) }
	output := C.open(c'/root/offline-second.vmap', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
	check(output >= 0 && C.write(output, &header[0], 64) == 64 && C.fsync(output) == 0 && C.close(output) == 0, c'write second offline participant')
}

@[direct_array_access]
fn planned_enrollment_batch(parent &char, other &char) {
	unsafe {
		simple(c'save', parent, c'/root/enroll-primary.vmap', 0)
		simple(c'save', other, c'/root/enroll-other.vmap', 0)
		enrollment_offline_plan()
		fd := C.open(c'/root/saved.vset', C.O_RDONLY)
		mut original := [8768]u8{}
		size := C.read(fd, &original[0], 8768)
		check(fd >= 0 && size == 432 && C.close(fd) == 0, c'enrollment batch baseline')
		copy_plan(c'/root/saved.vset', c'/root/enrollment-baseline.vset')
		first := status(c'/dev/mapper/vinix12').generation
		second := status(c'/dev/mapper/vinix9').generation
		held := C.open(c'/dev/mapper/vinix12', C.O_RDONLY)
		check(held >= 0, c'hold view across batch enrollment')
		mut output := [4096]char{}
		for preview in [false, true]! {
			enrollment_plans(c'/root/saved.vset', c'/root/offline.vmap', c'/root/bad.vmap', preview, 1, &output[0])
			check(!contains(&output[0], c'action='), c'later bad enrollment has no partial actions')
			enrollment_plans(c'/root/saved.vset', c'/root/offline.vmap', c'/root/offline.vmap', preview, 1, &output[0])
			bundle_unchanged(c'/root/saved.vset', &original[0], size)
		}
		tool(c'plan-grow', c'/root/saved.vset', c'2', c'12288', nil, 0)
		pending_fd := C.open(c'/root/saved.vset', C.O_RDONLY)
		mut pending := [8768]u8{}
		check(pending_fd >= 0 && C.read(pending_fd, &pending[0], 8768) == size && C.close(pending_fd) == 0, c'capture pending enrollment geometry')
		for preview in [false, true]! {
			enrollment_plans(c'/root/saved.vset', c'/root/offline.vmap', c'/root/enroll-primary.vmap', preview, 1, &output[0])
			check(!contains(&output[0], c'action='), c'conflicting existing snapshot has no prefix actions')
			bundle_unchanged(c'/root/saved.vset', &pending[0], size)
		}
		copy_plan(c'/root/enrollment-baseline.vset', c'/root/saved.vset')
		directory := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
		check(directory >= 0 && C.flock(directory, C.LOCK_EX | C.LOCK_NB) == 0, c'hold enrollment writer lock')
		enrollment_plans(c'/root/saved.vset', c'/root/offline.vmap', c'/root/enroll-primary.vmap', false, 1, &output[0])
		enrollment_plans(c'/root/saved.vset', c'/root/offline.vmap', c'/root/enroll-primary.vmap', true, 0, &output[0])
		check(contains(&output[0], c'request=0 disk=2 action=add mappings=0 bytes=16777216 sector=512 identity=mbr:1234567b')
			&& contains(&output[0], c'request=1 disk=0 action=keep mappings=3')
			&& contains(&output[0], c'request=1 disk=0 slot=2 offset=1048576 bytes=8192 readonly=0'), c'complete mixed enrollment preview under writer lock')
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		check(C.close(directory) == 0, c'release enrollment writer lock')
		enrollment_plans(c'/root/saved.vset', c'/root/offline.vmap', c'/root/enroll-primary.vmap', false, 0, nil)
		changed := C.open(c'/root/saved.vset', C.O_RDONLY)
		mut enrolled := [8768]u8{}
		check(changed >= 0 && C.read(changed, &enrolled[0], 8768) == size + 64 && C.close(changed) == 0, c'capture complete mixed enrollment')
		enrollment_plans(c'/root/saved.vset', c'/root/offline.vmap', c'/root/enroll-primary.vmap', false, 0, &output[0])
		check(contains(&output[0], c'request=0 disk=2 action=keep mappings=0') && contains(&output[0], c'request=1 disk=0 action=keep mappings=3'), c'durable exact enrollment retry')
		bundle_unchanged(c'/root/saved.vset', &enrolled[0], size + 64)
		preview(c'check-bundle', false, 1, &output[0]); check(!contains(&output[0], c'action='), c'missing enrolled disk blocks all live actions')
		simple(c'restore-bundle', c'/root/saved.vset', nil, 1)
		simple(c'plan-forget', c'/root/saved.vset', c'2', 0)
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		enrollment_plans(c'/root/saved.vset', c'/root/enroll-other.vmap', c'/root/enroll-primary.vmap', true, 0, &output[0])
		check(contains(&output[0], c'request=0 disk=1 action=keep mappings=2') && contains(&output[0], c'request=1 disk=0 action=keep mappings=3'), c'reverse existing identities retain disk indices')
		enrollment_plans(c'/root/saved.vset', c'/root/enroll-other.vmap', c'/root/enroll-primary.vmap', false, 0, nil)
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		check(status(c'/dev/mapper/vinix12').generation == first && status(c'/dev/mapper/vinix9').generation == second, c'enrollment preserves live generations')
		mut bytes := [4096]u8{}
		check(C.pread(held, &bytes[0], 4096, 0) == 4096 && C.close(held) == 0, c'held enrollment view readable')
		for byte in bytes { check(byte == 0xe7, c'enrollment preserves disk data') }
		check(C.unlink(c'/root/enrollment-baseline.vset') == 0, c'enrollment baseline cleanup')
		C.printf(c'PLAN ENROLLMENT BATCH PASSED: complete imports/previews, whole-set rollback, pinned snapshots, exact retries and retained live views\n')
	}
}

fn enrollment_boot_prepare(parent &char, other &char) {
	fd := C.open(c'/root/saved.vset', C.O_RDONLY)
	mut original := [8768]u8{}
	size := C.read(fd, &original[0], 8768)
	check(fd >= 0 && size == 536 && C.close(fd) == 0, c'boot enrollment baseline')
	second := status(c'/dev/mapper/vinix9').generation
	simple(c'save', parent, c'/root/enroll-primary.vmap', 0)
	simple(c'save', other, c'/root/enroll-other.vmap', 0)
	tool(c'pool-remove', c'/root/saved.vset', c'4', c'0', unsafe { nil }, 0)
	tool(c'pool-remove', c'/root/saved.vset', c'3', c'1', unsafe { nil }, 0)
	mapping_removals(c'/root/saved.vset', c'9', c'13', unsafe { nil }, false, 0, unsafe { nil })
	simple(c'plan-forget', c'/root/saved.vset', c'1', 0)
	enrollment_plans(c'/root/saved.vset', c'/root/enroll-other.vmap', c'/root/enroll-primary.vmap', true, 0, unsafe { nil })
	enrollment_plans(c'/root/saved.vset', c'/root/enroll-other.vmap', c'/root/enroll-primary.vmap', false, 0, unsafe { nil })
	pool_members_batch(c'/root/saved.vset', c'3', c'1', c'6291456', c'6303744', c'0', c'6291456', c'6295552', false, false, 0, unsafe { nil })
	pool_order(c'/root/saved.vset', c'3', c'1', c'0', false, 0, unsafe { nil })
	pool_members_batch(c'/root/saved.vset', c'4', c'0', c'16777216', c'25165824', unsafe { nil }, unsafe { nil }, unsafe { nil }, false, false, 0, unsafe { nil })
	bundle_unchanged(c'/root/saved.vset', &original[0], size)
	check(status(c'/dev/mapper/vinix9').generation == second, c'boot reenrollment retains live generation')
	C.printf(c'PLAN ENROLLMENT BATCH SAVED: real physical member reimported with matching primary before boot replay\n')
}

fn enrollment_boot_check() {
	fd := C.open(c'/etc/vinix/volumes.vset', C.O_RDONLY)
	mut original := [8768]u8{}
	size := C.read(fd, &original[0], 8768)
	check(fd >= 0 && size == 536 && C.close(fd) == 0, c'persistent enrollment bundle')
	mut output := [4096]char{}
	enrollment_plans(c'/etc/vinix/volumes.vset', c'/root/enroll-other.vmap', c'/root/enroll-primary.vmap', true, 0, &output[0])
	check(contains(&output[0], c'request=0 disk=1 action=keep mappings=2 bytes=16777216')
		&& contains(&output[0], c'request=1 disk=0 action=keep mappings=5 bytes=25165824'), c'enrollment disk indices/rows survive reboot')
	enrollment_plans(c'/etc/vinix/volumes.vset', c'/root/enroll-other.vmap', c'/root/enroll-primary.vmap', false, 0, unsafe { nil })
	bundle_unchanged(c'/etc/vinix/volumes.vset', &original[0], size)
	C.printf(c'PLAN ENROLLMENT BATCH BOOT PRESERVED\n')
}
