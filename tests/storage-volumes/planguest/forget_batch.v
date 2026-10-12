// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn disk_forgets(path &char, first &char, second &char, third &char, preview bool, expected i32, output &char) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'),
			if preview { &char(c'plan-preview-forget-batch') } else { &char(c'plan-forget-batch') },
			path, first, second, third, &char(nil)]!
		if output == nil { run_utility(&args[0], expected); return }
		fd := C.open(c'/root/forget-output', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600))
		check(fd >= 0, c'open forget output')
		child := C.fork(); check(child >= 0, c'fork forget command')
		if child == 0 {
			if C.dup2(fd, 1) != 1 || C.dup2(fd, 2) != 2 || C.close(fd) != 0 { C._exit(126) }
			C.execv(args[0], &args[0]); C._exit(127)
		}
		mut code := i32(0)
		check(C.close(fd) == 0 && C.waitpid(child, &code, 0) == child && code == expected << 8, c'forget command exit')
		input := C.open(c'/root/forget-output', C.O_RDONLY)
		count := C.read(input, output, 4095)
		check(input >= 0 && count > 0 && count < 4095 && C.close(input) == 0, c'read forget output')
		output[count] = 0
	}
}

@[direct_array_access]
fn planned_forget_batch() {
	unsafe {
		fd := C.open(c'/root/saved.vset', C.O_RDONLY)
		mut original := [8768]u8{}
		size := C.read(fd, &original[0], 8768)
		check(fd >= 0 && size == 432 && C.close(fd) == 0, c'forget baseline')
		first := status(c'/dev/mapper/vinix12').generation; second := status(c'/dev/mapper/vinix9').generation
		held := C.open(c'/dev/mapper/vinix12', C.O_RDONLY); check(held >= 0, c'hold view across disk forget')
		enrollment_plans(c'/root/saved.vset', c'/root/offline.vmap', c'/root/offline-second.vmap', false, 0, nil)
		changed := C.open(c'/root/saved.vset', C.O_RDONLY)
		mut enrolled := [8768]u8{}
		check(changed >= 0 && C.read(changed, &enrolled[0], 8768) == size + 128 && C.close(changed) == 0, c'forget expanded baseline')
		mut output := [4096]char{}
		for preview in [false, true]! {
			disk_forgets(c'/root/saved.vset', c'mbr:1234567b', c'mbr:12345679', nil, preview, 1, &output[0])
			check(!contains(&output[0], c'action='), c'later populated disk rejects whole forget batch')
			disk_forgets(c'/root/saved.vset', c'mbr:1234567b', c'mbr:1234567B', nil, preview, 1, &output[0])
			bundle_unchanged(c'/root/saved.vset', &enrolled[0], size + 128)
		}
		pool_add(c'/root/saved.vset', c'4', c'3', c'7340032', c'7348224', c'4096', 0)
		for preview in [false, true]! {
			disk_forgets(c'/root/saved.vset', c'mbr:1234567b', c'mbr:1234567c', nil, preview, 1, &output[0])
			check(!contains(&output[0], c'action='), c'later pool member rejects whole forget batch')
		}
		tool(c'pool-remove', c'/root/saved.vset', c'4', c'3', nil, 0)
		bundle_unchanged(c'/root/saved.vset', &enrolled[0], size + 128)
		directory := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
		check(directory >= 0 && C.flock(directory, C.LOCK_EX | C.LOCK_NB) == 0, c'hold forget writer lock')
		disk_forgets(c'/root/saved.vset', c'mbr:1234567c', c'mbr:1234567d', c'mbr:1234567b', false, 1, &output[0])
		disk_forgets(c'/root/saved.vset', c'mbr:1234567c', c'mbr:1234567d', c'mbr:1234567b', true, 0, &output[0])
		check(contains(&output[0], c'request=0 disk=3 action=forget identity=mbr:1234567c')
			&& contains(&output[0], c'request=1 action=keep identity=mbr:1234567d')
			&& contains(&output[0], c'request=2 disk=2 action=forget identity=mbr:1234567b')
			&& contains(&output[0], c'previous_disk=1 disk=1 action=retain identity=mbr:12345679'), c'complete identity forget preview under writer lock')
		bundle_unchanged(c'/root/saved.vset', &enrolled[0], size + 128)
		check(C.close(directory) == 0, c'release forget writer lock')
		disk_forgets(c'/root/saved.vset', c'mbr:1234567c', c'mbr:1234567d', c'mbr:1234567b', false, 0, nil)
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		disk_forgets(c'/root/saved.vset', c'mbr:1234567c', c'mbr:1234567d', c'mbr:1234567b', false, 0, &output[0])
		check(contains(&output[0], c'request=0 action=keep identity=mbr:1234567c') && contains(&output[0], c'request=2 action=keep identity=mbr:1234567b'), c'absent retry cannot select compacted survivors')
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		simple(c'restore-bundle', c'/root/saved.vset', nil, 0)
		check(status(c'/dev/mapper/vinix12').generation == first && status(c'/dev/mapper/vinix9').generation == second, c'forget preserves live generations')
		mut bytes := [4096]u8{}
		check(C.pread(held, &bytes[0], 4096, 0) == 4096 && C.close(held) == 0, c'held view readable after disk forget')
		for byte in bytes { check(byte == 0xe7, c'forget preserves live data') }
		C.printf(c'PLAN FORGET BATCH PASSED: identity retries, complete previews, later protection rollback and retained live views\n')
	}
}

// Put empty participants before the real secondary disk, then remove them in
// one edit. Its pool reference must move from index 3 to 1 before boot replay.
fn forget_boot_prepare() {
	fd := C.open(c'/root/saved.vset', C.O_RDONLY)
	mut original := [8768]u8{}
	size := C.read(fd, &original[0], 8768)
	check(fd >= 0 && size == 536 && C.close(fd) == 0, c'boot forget baseline')
	second := status(c'/dev/mapper/vinix9').generation
	tool(c'pool-remove', c'/root/saved.vset', c'3', c'1', unsafe { nil }, 0)
	mapping_removals(c'/root/saved.vset', c'9', c'13', unsafe { nil }, false, 0, unsafe { nil })
	simple(c'plan-forget', c'/root/saved.vset', c'1', 0)
	enrollment_plans(c'/root/saved.vset', c'/root/offline.vmap', c'/root/offline-second.vmap', false, 0, unsafe { nil })
	enrollment_plans(c'/root/saved.vset', c'/root/enroll-other.vmap', c'/root/enroll-primary.vmap', false, 0, unsafe { nil })
	tool(c'pool-remove', c'/root/saved.vset', c'4', c'0', unsafe { nil }, 0)
	pool_members_batch(c'/root/saved.vset', c'3', c'3', c'6291456', c'6303744', unsafe { nil }, unsafe { nil }, unsafe { nil }, false, false, 0, unsafe { nil })
	pool_order(c'/root/saved.vset', c'3', c'3', c'0', false, 0, unsafe { nil })
	pool_members_batch(c'/root/saved.vset', c'4', c'0', c'16777216', c'25165824', unsafe { nil }, unsafe { nil }, unsafe { nil }, false, false, 0, unsafe { nil })
	disk_forgets(c'/root/saved.vset', c'mbr:1234567c', c'mbr:1234567b', unsafe { nil }, true, 0, unsafe { nil })
	disk_forgets(c'/root/saved.vset', c'mbr:1234567c', c'mbr:1234567b', unsafe { nil }, false, 0, unsafe { nil })
	bundle_unchanged(c'/root/saved.vset', &original[0], size)
	check(status(c'/dev/mapper/vinix9').generation == second, c'boot forget retains live generation')
	C.printf(c'PLAN FORGET BATCH SAVED: secondary disk and pool references compacted from 3 to 1 before replay\n')
}

fn forget_boot_check() {
	fd := C.open(c'/etc/vinix/volumes.vset', C.O_RDONLY)
	mut original := [8768]u8{}
	size := C.read(fd, &original[0], 8768)
	check(fd >= 0 && size == 536 && C.close(fd) == 0, c'persistent forget bundle')
	mut output := [4096]char{}
	disk_forgets(c'/etc/vinix/volumes.vset', c'mbr:1234567c', c'mbr:1234567b', unsafe { nil }, true, 0, &output[0])
	check(contains(&output[0], c'request=0 action=keep identity=mbr:1234567c')
		&& contains(&output[0], c'request=1 action=keep identity=mbr:1234567b')
		&& contains(&output[0], c'previous_disk=1 disk=1 action=retain identity=mbr:12345679'), c'identity retries and survivor indices persist')
	disk_forgets(c'/etc/vinix/volumes.vset', c'mbr:1234567c', c'mbr:1234567b', unsafe { nil }, false, 0, unsafe { nil })
	bundle_unchanged(c'/etc/vinix/volumes.vset', &original[0], size)
	C.printf(c'PLAN FORGET BATCH BOOT PRESERVED\n')
}
