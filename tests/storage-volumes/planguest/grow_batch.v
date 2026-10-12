// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn run_explicit_growth(arguments &&char, expected i32, output &char) {
	unsafe {
		if output == nil { run_utility(arguments, expected); return }
		fd := C.open(c'/root/explicit-growth-output', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600))
		check(fd >= 0, c'open explicit growth output')
		child := C.fork(); check(child >= 0, c'fork explicit growth command')
		if child == 0 {
			if C.dup2(fd, 1) != 1 || C.dup2(fd, 2) != 2 || C.close(fd) != 0 { C._exit(126) }
			C.execv(arguments[0], arguments); C._exit(127)
		}
		mut code := i32(0)
		check(C.close(fd) == 0 && C.waitpid(child, &code, 0) == child && code == expected << 8, c'explicit growth command exit')
		input := C.open(c'/root/explicit-growth-output', C.O_RDONLY); count := C.read(input, output, 4095)
		check(input >= 0 && count > 0 && count < 4095 && C.close(input) == 0, c'read explicit growth output'); output[count] = 0
	}
}

fn mapping_growths(path &char, first &char, slot &char, length &char,
	second &char, next_slot &char, next_length &char, preview bool, expected i32, output &char) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'), if preview { &char(c'plan-preview-grow-batch') } else { &char(c'plan-grow-batch') },
			path, first, slot, length, second, next_slot, next_length, &char(nil)]!
		run_explicit_growth(&args[0], expected, output)
	}
}

@[direct_array_access]
fn planned_explicit_growth_batch(parent &char, other &char) {
	unsafe {
		fd := C.open(c'/root/saved.vset', C.O_RDONLY); mut baseline := [8768]u8{}
		size := C.read(fd, &baseline[0], 8768)
		check(fd >= 0 && size == 432 && C.close(fd) == 0, c'explicit growth baseline')
		first_original := status(c'/dev/mapper/vinix12').generation; second_original := status(c'/dev/mapper/vinix9').generation
		held_original := C.open(c'/dev/mapper/vinix12', C.O_RDONLY); check(held_original >= 0, c'hold original across explicit growth')
		for target in [parent, other]! {
			raw := C.open(target, C.O_RDWR); mut data := [8192]u8{}
			for i in 0 .. 8192 { data[i] = if target == parent { if i < 4096 { u8(0xdb) } else { u8(0xdd) } } else { if i < 4096 { u8(0xdc) } else { u8(0xde) } } }
			check(raw >= 0 && C.pwrite(raw, &data[0], 8192, 10485760) == 8192 && C.fsync(raw) == 0 && C.close(raw) == 0, c'prepare explicit growth extent data')
		}
		mapping_additions(c'/root/saved.vset', c'mbr:12345678', c'19', c'10485760', c'4096', c'ro',
			c'mbr:12345679', c'20', c'10485760', c'4096', c'rw', false, 0, nil)
		simple(c'restore-bundle', c'/root/saved.vset', nil, 0)
		first := status(c'/dev/mapper/vinix19'); second := status(c'/dev/mapper/vinix20')
		held_first := C.open(c'/dev/mapper/vinix19', C.O_RDONLY); held_second := C.open(c'/dev/mapper/vinix20', C.O_RDWR)
		check(held_first >= 0 && held_second >= 0, c'hold both explicit growth mappings')
		input := C.open(c'/root/saved.vset', C.O_RDONLY); mut original := [8768]u8{}
		check(input >= 0 && C.read(input, &original[0], 8768) == size + 64 && C.close(input) == 0, c'capture before explicit growth')
		mut output := [4096]char{}
		for preview in [false, true]! {
			mapping_growths(c'/root/saved.vset', c'mbr:12345678', c'19', c'8192', c'mbr:12345678', c'20', c'8192', preview, 1, &output[0])
			check(!contains(&output[0], c'action='), c'wrong later growth identity reports no prefix')
			bundle_unchanged(c'/root/saved.vset', &original[0], size + 64)
			mapping_growths(c'/root/saved.vset', c'mbr:12345678', c'19', c'8192', c'mbr:12345679', c'20', c'4097', preview, 1, &output[0])
			mapping_growths(c'/root/saved.vset', c'mbr:12345678', c'19', c'8192', c'mbr:12345678', c'19', c'8192', preview, 1, &output[0])
			bundle_unchanged(c'/root/saved.vset', &original[0], size + 64)
		}
		directory := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
		check(directory >= 0 && C.flock(directory, C.LOCK_EX | C.LOCK_NB) == 0, c'hold explicit growth writer lock')
		mapping_growths(c'/root/saved.vset', c'mbr:12345678', c'19', c'8192', c'mbr:12345679', c'20', c'4096', false, 1, &output[0])
		mapping_growths(c'/root/saved.vset', c'mbr:12345678', c'19', c'8192', c'mbr:12345679', c'20', c'4096', true, 0, &output[0])
		check(contains(&output[0], c'request=0 disk=0 slot=19 action=grow offset=10485760 previous_bytes=4096 bytes=8192 readonly=1 identity=mbr:12345678')
			&& contains(&output[0], c'request=1 disk=1 slot=20 action=keep offset=10485760 previous_bytes=4096 bytes=4096 readonly=0 identity=mbr:12345679'), c'complete mixed explicit growth preview under lock')
		bundle_unchanged(c'/root/saved.vset', &original[0], size + 64); check(C.close(directory) == 0, c'release explicit growth writer lock')
		mapping_growths(c'/root/saved.vset', c'mbr:12345678', c'19', c'8192', c'mbr:12345679', c'20', c'4096', false, 0, nil)
		mapping_growths(c'/root/saved.vset', c'mbr:12345678', c'19', c'8192', c'mbr:12345679', c'20', c'8192', false, 0, nil)
		check(status(c'/dev/mapper/vinix19').bytes == 4096 && status(c'/dev/mapper/vinix20').bytes == 4096, c'explicit growth publication remains offline')
		simple(c'restore-bundle', c'/root/saved.vset', nil, 1)
		tool(c'create', other, c'21', c'10489856', c'4096', 0)
		preview(c'check-bundle', true, 1, &output[0]); check(!contains(&output[0], c'action='), c'later live extension conflict rejects complete growth check')
		tool(c'restore-bundle', c'/root/saved.vset', c'grow', nil, nil, 1)
		check(status(c'/dev/mapper/vinix19').bytes == 4096 && status(c'/dev/mapper/vinix20').bytes == 4096, c'later conflict prevents first live growth')
		simple(c'remove', c'/dev/mapper/vinix21', nil, 0); tool(c'restore-bundle', c'/root/saved.vset', c'grow', nil, nil, 0)
		check(status(c'/dev/mapper/vinix19').generation == first.generation && status(c'/dev/mapper/vinix19').bytes == 8192
			&& status(c'/dev/mapper/vinix20').generation == second.generation && status(c'/dev/mapper/vinix20').bytes == 8192, c'explicit growth keeps both generations')
		mut bytes := [4096]u8{}
		check(C.pread(held_first, &bytes[0], 4096, 4096) == 4096 && C.close(held_first) == 0, c'held readonly view reads grown extent')
		for byte in bytes { check(byte == 0xdd, c'primary explicit extension preserved') }
		check(C.pread(held_second, &bytes[0], 4096, 4096) == 4096 && C.close(held_second) == 0, c'held writable view reads grown extent')
		for byte in bytes { check(byte == 0xde, c'secondary explicit extension preserved') }
		check(C.open(c'/dev/mapper/vinix19', C.O_RDWR) < 0 && C.errno == C.EROFS, c'explicit growth preserves readonly mode')
		planned := C.open(c'/root/saved.vset', C.O_RDONLY); mut complete := [8768]u8{}
		check(planned >= 0 && C.read(planned, &complete[0], 8768) == size + 64 && C.close(planned) == 0, c'capture complete explicit growth')
		mapping_growths(c'/root/saved.vset', c'mbr:12345679', c'20', c'8192', c'mbr:12345678', c'19', c'8192', false, 0, &output[0])
		check(contains(&output[0], c'slot=20 action=keep') && contains(&output[0], c'slot=19 action=keep'), c'equal-size explicit growth retry')
		bundle_unchanged(c'/root/saved.vset', &complete[0], size + 64)
		mapping_removals(c'/root/saved.vset', c'20', c'19', nil, false, 0, nil); bundle_unchanged(c'/root/saved.vset', &baseline[0], size)
		simple(c'restore-bundle', c'/root/saved.vset', nil, 0)
		check(status(c'/dev/mapper/vinix19').generation == first.generation && status(c'/dev/mapper/vinix20').generation == second.generation, c'desired omission retains grown live views')
		simple(c'remove', c'/dev/mapper/vinix19', nil, 0); simple(c'remove', c'/dev/mapper/vinix20', nil, 0)
		check(status(c'/dev/mapper/vinix12').generation == first_original && status(c'/dev/mapper/vinix9').generation == second_original
			&& C.pread(held_original, &bytes[0], 4096, 0) == 4096 && C.close(held_original) == 0, c'explicit growth retains original views')
		for byte in bytes { check(byte == 0xe7, c'original data survives explicit growth') }
		C.printf(c'PLAN EXPLICIT GROWTH BATCH PASSED: identity growth, mixed previews, rollback, live preflight and held descriptors\n')
	}
}

fn explicit_growth_boot_prepare() {
	unsafe {
		fd := C.open(c'/root/saved.vset', C.O_RDONLY); mut original := [8768]u8{}
		size := C.read(fd, &original[0], 8768); check(fd >= 0 && size == 536 && C.close(fd) == 0, c'boot explicit growth baseline')
		first := status(c'/dev/mapper/vinix2').generation; second := status(c'/dev/mapper/vinix9').generation
		removals := [&char(c'/usr/sbin/vinix-volume'), &char(c'plan-remove-batch'), &char(c'/root/saved.vset'),
			&char(c'2'), &char(c'5'), &char(c'12'), &char(c'14'), &char(c'18'), &char(c'9'), &char(c'13'), &char(nil)]!
		run_utility(&removals[0], 0)
		rows := [&char(c'/usr/sbin/vinix-volume'), &char(c'plan-add-batch'), &char(c'/root/saved.vset'),
			&char(c'mbr:12345679'), &char(c'9'), &char(c'1048576'), &char(c'4096'), &char(c'rw'),
			&char(c'mbr:12345678'), &char(c'2'), &char(c'1048576'), &char(c'4096'), &char(c'rw'),
			&char(c'mbr:12345678'), &char(c'5'), &char(c'2097152'), &char(c'12288'), &char(c'ro'),
			&char(c'mbr:12345679'), &char(c'13'), &char(c'3145728'), &char(c'4096'), &char(c'rw'),
			&char(c'mbr:12345678'), &char(c'12'), &char(c'4194304'), &char(c'4096'), &char(c'ro'),
			&char(c'mbr:12345678'), &char(c'14'), &char(c'16777216'), &char(c'8192'), &char(c'rw'),
			&char(c'mbr:12345678'), &char(c'18'), &char(c'16785408'), &char(c'8192'), &char(c'ro'), &char(nil)]!
		run_utility(&rows[0], 0)
		mapping_growths(c'/root/saved.vset', c'mbr:12345679', c'9', c'8192', c'mbr:12345678', c'2', c'8192', true, 0, nil)
		mapping_growths(c'/root/saved.vset', c'mbr:12345679', c'9', c'8192', c'mbr:12345678', c'2', c'8192', false, 0, nil)
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		check(status(c'/dev/mapper/vinix2').generation == first && status(c'/dev/mapper/vinix9').generation == second, c'boot explicit desired growth retains live generations')
		C.printf(c'PLAN EXPLICIT GROWTH BATCH SAVED: two cross-disk desired lengths restored with exact row/pool order before replay\n')
	}
}

fn explicit_growth_boot_check() {
	fd := C.open(c'/etc/vinix/volumes.vset', C.O_RDONLY); mut original := [8768]u8{}
	size := C.read(fd, &original[0], 8768); check(fd >= 0 && size == 536 && C.close(fd) == 0, c'persistent explicit growth bundle')
	mut output := [4096]char{}
	mapping_growths(c'/etc/vinix/volumes.vset', c'mbr:12345679', c'9', c'8192', c'mbr:12345678', c'2', c'8192', true, 0, &output[0])
	check(contains(&output[0], c'requests=2 operation=preview-explicit-growth')
		&& contains(&output[0], c'request=0 disk=1 slot=9 action=keep offset=1048576 previous_bytes=8192 bytes=8192 readonly=0 identity=mbr:12345679')
		&& contains(&output[0], c'request=1 disk=0 slot=2 action=keep offset=1048576 previous_bytes=8192 bytes=8192 readonly=0 identity=mbr:12345678'), c'exact explicit growth retries survive boot')
	mapping_growths(c'/etc/vinix/volumes.vset', c'mbr:12345679', c'9', c'8192', c'mbr:12345678', c'2', c'8192', false, 0, unsafe { nil })
	bundle_unchanged(c'/etc/vinix/volumes.vset', &original[0], size); C.printf(c'PLAN EXPLICIT GROWTH BATCH BOOT PRESERVED\n')
}
