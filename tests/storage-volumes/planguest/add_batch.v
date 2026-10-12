// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn run_additions(arguments &&char, expected i32, output &char) {
	unsafe {
		if output == nil { run_utility(arguments, expected); return }
		fd := C.open(c'/root/addition-output', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600))
		check(fd >= 0, c'open addition output')
		child := C.fork(); check(child >= 0, c'fork addition command')
		if child == 0 {
			if C.dup2(fd, 1) != 1 || C.dup2(fd, 2) != 2 || C.close(fd) != 0 { C._exit(126) }
			C.execv(arguments[0], arguments); C._exit(127)
		}
		mut code := i32(0)
		check(C.close(fd) == 0 && C.waitpid(child, &code, 0) == child && code == expected << 8, c'addition command exit')
		input := C.open(c'/root/addition-output', C.O_RDONLY)
		count := C.read(input, output, 4095)
		check(input >= 0 && count > 0 && count < 4095 && C.close(input) == 0, c'read addition output')
		output[count] = 0
	}
}

fn mapping_additions(path &char, first &char, slot &char, offset &char, length &char, mode &char,
	second &char, next_slot &char, next_offset &char, next_length &char, next_mode &char,
	preview bool, expected i32, output &char) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'),
			if preview { &char(c'plan-preview-add-batch') } else { &char(c'plan-add-batch') }, path,
			first, slot, offset, length, mode, second, next_slot, next_offset, next_length, next_mode, &char(nil)]!
		run_additions(&args[0], expected, output)
	}
}

@[direct_array_access]
fn planned_addition_batch(parent &char, other &char) {
	unsafe {
		fd := C.open(c'/root/saved.vset', C.O_RDONLY)
		mut original := [8768]u8{}
		size := C.read(fd, &original[0], 8768)
		check(fd >= 0 && size == 432 && C.close(fd) == 0, c'addition baseline')
		first := status(c'/dev/mapper/vinix12').generation; second := status(c'/dev/mapper/vinix9').generation
		held := C.open(c'/dev/mapper/vinix12', C.O_RDONLY); check(held >= 0, c'hold view across additions')
		mut output := [4096]char{}
		for preview in [false, true]! {
			mapping_additions(c'/root/saved.vset', c'mbr:12345678', c'19', c'8388608', c'4096', c'rw',
				c'mbr:12345679', c'12', c'4194304', c'4096', c'ro', preview, 1, &output[0])
			check(!contains(&output[0], c'action='), c'later wrong identity has no prefix actions')
			mapping_additions(c'/root/saved.vset', c'mbr:12345678', c'19', c'8388608', c'4096', c'rw',
				c'mbr:12345679', c'20', c'8388609', c'4096', c'ro', preview, 1, &output[0])
			bundle_unchanged(c'/root/saved.vset', &original[0], size)
		}
		directory := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
		check(directory >= 0 && C.flock(directory, C.LOCK_EX | C.LOCK_NB) == 0, c'hold addition writer lock')
		mapping_additions(c'/root/saved.vset', c'mbr:12345678', c'19', c'8388608', c'4096', c'rw',
			c'mbr:12345679', c'13', c'3145728', c'4096', c'rw', false, 1, &output[0])
		mapping_additions(c'/root/saved.vset', c'mbr:12345678', c'19', c'8388608', c'4096', c'rw',
			c'mbr:12345679', c'13', c'3145728', c'4096', c'rw', true, 0, &output[0])
		check(contains(&output[0], c'request=0 disk=0 slot=19 action=add offset=8388608 bytes=4096 readonly=0 identity=mbr:12345678')
			&& contains(&output[0], c'request=1 disk=1 slot=13 action=keep offset=3145728 bytes=4096 readonly=0 identity=mbr:12345679'), c'complete mixed addition preview under lock')
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		check(C.close(directory) == 0, c'release addition writer lock')
		for target in [parent, other]! {
			raw := C.open(target, C.O_RDWR); mut bytes := [4096]u8{}
			for i in 0 .. 4096 { bytes[i] = if target == parent { u8(0xd9) } else { u8(0xda) } }
			check(raw >= 0 && C.pwrite(raw, &bytes[0], 4096, 8388608) == 4096 && C.fsync(raw) == 0 && C.close(raw) == 0, c'prepare explicit addition data')
		}
		mapping_additions(c'/root/saved.vset', c'mbr:12345678', c'19', c'8388608', c'4096', c'rw',
			c'mbr:12345679', c'13', c'3145728', c'4096', c'rw', false, 0, nil)
		mapping_additions(c'/root/saved.vset', c'mbr:12345679', c'20', c'8388608', c'4096', c'ro',
			c'mbr:12345678', c'19', c'8388608', c'4096', c'rw', false, 0, nil)
		changed := C.open(c'/root/saved.vset', C.O_RDONLY); mut desired := [8768]u8{}
		check(changed >= 0 && C.read(changed, &desired[0], 8768) == size + 64 && C.close(changed) == 0, c'capture complete additions')
		mapping_additions(c'/root/saved.vset', c'mbr:12345679', c'20', c'8388608', c'4096', c'ro',
			c'mbr:12345678', c'19', c'8388608', c'4096', c'rw', false, 0, &output[0])
		check(contains(&output[0], c'slot=20 action=keep') && contains(&output[0], c'slot=19 action=keep'), c'durable exact addition retry')
		bundle_unchanged(c'/root/saved.vset', &desired[0], size + 64)
		missing(c'/dev/mapper/vinix19'); missing(c'/dev/mapper/vinix20')
		tool(c'create', other, c'20', c'10485760', c'4096', 0)
		preview(c'check-bundle', false, 1, &output[0]); check(!contains(&output[0], c'action='), c'later live conflict blocks all explicit additions')
		simple(c'restore-bundle', c'/root/saved.vset', nil, 1); missing(c'/dev/mapper/vinix19')
		simple(c'remove', c'/dev/mapper/vinix20', nil, 0)
		simple(c'restore-bundle', c'/root/saved.vset', nil, 0)
		for index, slot in [&char(c'/dev/mapper/vinix19'), &char(c'/dev/mapper/vinix20')]! {
			input := C.open(slot, C.O_RDONLY); mut bytes := [4096]u8{}
			check(input >= 0 && C.pread(input, &bytes[0], 4096, 0) == 4096 && C.close(input) == 0, c'read explicitly added mapping')
			expected_byte := if index == 0 { u8(0xd9) } else { u8(0xda) }
			for byte in bytes { check(byte == expected_byte, c'explicit addition preserves raw extent data') }
		}
		check(C.open(c'/dev/mapper/vinix20', C.O_RDWR) < 0 && C.errno == C.EROFS, c'explicit read-only mapping refuses writes')
		view := C.open(c'/dev/mapper/vinix19', C.O_RDONLY); generation := status(c'/dev/mapper/vinix19').generation
		mapping_removals(c'/root/saved.vset', c'20', c'19', nil, false, 0, nil)
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		simple(c'restore-bundle', c'/root/saved.vset', nil, 0)
		mut bytes := [4096]u8{}
		check(view >= 0 && C.pread(view, &bytes[0], 4096, 0) == 4096 && C.close(view) == 0
			&& status(c'/dev/mapper/vinix19').generation == generation, c'held added view survives desired omission')
		for byte in bytes { check(byte == 0xd9, c'held added data survives') }
		simple(c'remove', c'/dev/mapper/vinix19', nil, 0); simple(c'remove', c'/dev/mapper/vinix20', nil, 0)
		check(status(c'/dev/mapper/vinix12').generation == first && status(c'/dev/mapper/vinix9').generation == second, c'additions preserve existing generations')
		check(C.pread(held, &bytes[0], 4096, 0) == 4096 && C.close(held) == 0, c'held original view readable')
		for byte in bytes { check(byte == 0xe7, c'original read-only data survives additions') }
		C.printf(c'PLAN ADDITION BATCH PASSED: identity placement, mixed previews/retries, rollback, explicit live preflight and retained views\n')
	}
}

fn addition_boot_rows(path &char, preview bool, output &char) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'), if preview { &char(c'plan-preview-add-batch') } else { &char(c'plan-add-batch') }, path,
			&char(c'mbr:12345679'), &char(c'9'), &char(c'1048576'), &char(c'8192'), &char(c'rw'),
			&char(c'mbr:12345678'), &char(c'2'), &char(c'1048576'), &char(c'8192'), &char(c'rw'),
			&char(c'mbr:12345678'), &char(c'5'), &char(c'2097152'), &char(c'12288'), &char(c'ro'),
			&char(c'mbr:12345679'), &char(c'13'), &char(c'3145728'), &char(c'4096'), &char(c'rw'),
			&char(c'mbr:12345678'), &char(c'12'), &char(c'4194304'), &char(c'4096'), &char(c'ro'),
			&char(c'mbr:12345678'), &char(c'14'), &char(c'16777216'), &char(c'8192'), &char(c'rw'),
			&char(c'mbr:12345678'), &char(c'18'), &char(c'16785408'), &char(c'8192'), &char(c'ro'), &char(nil)]!
		run_additions(&args[0], 0, output)
	}
}

fn addition_boot_prepare() {
	unsafe {
		fd := C.open(c'/root/saved.vset', C.O_RDONLY); mut original := [8768]u8{}
		size := C.read(fd, &original[0], 8768)
		check(fd >= 0 && size == 536 && C.close(fd) == 0, c'boot addition baseline')
		first := status(c'/dev/mapper/vinix12').generation; second := status(c'/dev/mapper/vinix9').generation
		removals := [&char(c'/usr/sbin/vinix-volume'), &char(c'plan-remove-batch'), &char(c'/root/saved.vset'),
			&char(c'2'), &char(c'5'), &char(c'12'), &char(c'14'), &char(c'18'), &char(c'9'), &char(c'13'), &char(nil)]!
		run_utility(&removals[0], 0)
		addition_boot_rows(c'/root/saved.vset', true, nil); addition_boot_rows(c'/root/saved.vset', false, nil)
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		check(status(c'/dev/mapper/vinix12').generation == first && status(c'/dev/mapper/vinix9').generation == second, c'boot desired additions retain generations')
		C.printf(c'PLAN ADDITION BATCH SAVED: seven explicit desired mappings restored in original row/pool order before replay\n')
	}
}

fn addition_boot_check() {
	fd := C.open(c'/etc/vinix/volumes.vset', C.O_RDONLY); mut original := [8768]u8{}
	size := C.read(fd, &original[0], 8768)
	check(fd >= 0 && size == 536 && C.close(fd) == 0, c'persistent addition bundle')
	mut output := [4096]char{}
	addition_boot_rows(c'/etc/vinix/volumes.vset', true, &output[0])
	check(contains(&output[0], c'requests=7 operation=preview-addition')
		&& contains(&output[0], c'request=0 disk=1 slot=9 action=keep')
		&& contains(&output[0], c'request=6 disk=0 slot=18 action=keep') && !contains(&output[0], c'action=add'), c'exact identity retries survive boot')
	addition_boot_rows(c'/etc/vinix/volumes.vset', false, unsafe { nil })
	bundle_unchanged(c'/etc/vinix/volumes.vset', &original[0], size)
	C.printf(c'PLAN ADDITION BATCH BOOT PRESERVED\n')
}
