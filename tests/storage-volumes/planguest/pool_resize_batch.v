// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn pool_resizes(path &char, first &char, pool &char, start &char, end &char,
	second &char, next_pool &char, next_start &char, next_end &char,
	preview bool, expected i32, output &char) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'), if preview { &char(c'pool-preview-resize-batch') } else { &char(c'pool-resize-batch') },
			path, first, pool, start, end, second, next_pool, next_start, next_end, &char(nil)]!
		if output == nil { run_utility(&args[0], expected); return }
		fd := C.open(c'/root/resize-output', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600)); check(fd >= 0, c'open resize output')
		child := C.fork(); check(child >= 0, c'fork resize command')
		if child == 0 {
			if C.dup2(fd, 1) != 1 || C.dup2(fd, 2) != 2 || C.close(fd) != 0 { C._exit(126) }
			C.execv(args[0], &args[0]); C._exit(127)
		}
		mut code := i32(0); check(C.close(fd) == 0 && C.waitpid(child, &code, 0) == child && code == expected << 8, c'resize command exit')
		input := C.open(c'/root/resize-output', C.O_RDONLY); count := C.read(input, output, 4095)
		check(input >= 0 && count > 0 && count < 4095 && C.close(input) == 0, c'read resize output'); output[count] = 0
	}
}

@[direct_array_access]
fn planned_pool_resizes(parent &char) {
	unsafe {
		fd := C.open(c'/root/saved.vset', C.O_RDONLY); mut baseline := [8768]u8{}; size := C.read(fd, &baseline[0], 8768)
		check(fd >= 0 && size == 432 && C.close(fd) == 0, c'resize baseline')
		original_generation := status(c'/dev/mapper/vinix12').generation; original := C.open(c'/dev/mapper/vinix12', C.O_RDONLY); check(original >= 0, c'hold original across resize')
		pool_members_batch(c'/root/saved.vset', c'5', c'0', c'14680064', c'14692352', c'1', c'14680064', c'14692352', false, false, 0, nil)
		pool_members_batch(c'/root/saved.vset', c'6', c'0', c'14692352', c'14700544', c'1', c'14692352', c'14700544', false, false, 0, nil)
		raw := C.open(parent, C.O_RDWR); mut data := [4096]u8{init: 0xf2}
		check(raw >= 0 && C.pwrite(raw, &data[0], 4096, 14680064) == 4096, c'prepare occupied resize head')
		for i in 0 .. 4096 { data[i] = 0xf3 }
		check(C.pwrite(raw, &data[0], 4096, 14696448) == 4096 && C.fsync(raw) == 0 && C.close(raw) == 0, c'prepare occupied resize tail')
		mapping_additions(c'/root/saved.vset', c'mbr:12345678', c'19', c'14680064', c'4096', c'ro', c'mbr:12345678', c'20', c'14696448', c'4096', c'rw', false, 0, nil)
		simple(c'restore-bundle', c'/root/saved.vset', nil, 0)
		head_generation := status(c'/dev/mapper/vinix19').generation; tail_generation := status(c'/dev/mapper/vinix20').generation
		head := C.open(c'/dev/mapper/vinix19', C.O_RDONLY); tail := C.open(c'/dev/mapper/vinix20', C.O_RDONLY); check(head >= 0 && tail >= 0, c'hold resize views')
		input := C.open(c'/root/saved.vset', C.O_RDONLY); mut configured := [8768]u8{}
		check(input >= 0 && C.read(input, &configured[0], 8768) == size + 224 && C.close(input) == 0, c'capture resize source')
		mut output := [4096]char{}
		for preview in [false, true]! {
			pool_resizes(c'/root/saved.vset', c'mbr:12345678', c'6', c'14688256', c'14700544', c'mbr:12345678', c'5', c'14684160', c'14688256', preview, 1, &output[0])
			check(!contains(&output[0], c'action='), c'later occupied head rejects prefix actions'); bundle_unchanged(c'/root/saved.vset', &configured[0], size + 224)
			pool_resizes(c'/root/saved.vset', c'mbr:12345678', c'6', c'14688256', c'14700544', c'mbr:12345678', c'5', c'14680064', c'14680576', preview, 1, &output[0])
			pool_resizes(c'/root/saved.vset', c'mbr:12345678', c'6', c'14688256', c'14700544', c'mbr:12345678', c'5', c'14680064', c'14692352', preview, 1, &output[0])
			pool_resizes(c'/root/saved.vset', c'mbr:12345678', c'6', c'14688256', c'14700544', c'mbr:1234567b', c'5', c'14680064', c'14688256', preview, 1, &output[0])
			pool_resizes(c'/root/saved.vset', c'mbr:12345678', c'6', c'14688256', c'14700544', c'mbr:12345678', c'6', c'14692352', c'14700544', preview, 1, &output[0])
			bundle_unchanged(c'/root/saved.vset', &configured[0], size + 224)
		}
		directory := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC); check(directory >= 0 && C.flock(directory, C.LOCK_EX | C.LOCK_NB) == 0, c'hold resize writer lock')
		pool_resizes(c'/root/saved.vset', c'mbr:12345678', c'6', c'14688256', c'14700544', c'mbr:12345678', c'5', c'14680064', c'14688256', false, 1, &output[0])
		pool_resizes(c'/root/saved.vset', c'mbr:12345678', c'6', c'14688256', c'14700544', c'mbr:12345678', c'5', c'14680064', c'14688256', true, 0, &output[0])
		check(contains(&output[0], c'request=0 pool=6 disk=0 action=resize previous_start=14692352 previous_end=14700544 start=14688256 end=14700544 alignment=4096 identity=mbr:12345678')
			&& contains(&output[0], c'request=1 pool=5 disk=0 action=resize previous_start=14680064 previous_end=14692352 start=14680064 end=14688256 alignment=4096 identity=mbr:12345678'), c'complete cross-pool preview under lock')
		bundle_unchanged(c'/root/saved.vset', &configured[0], size + 224); check(C.close(directory) == 0, c'release resize writer lock')
		pool_resizes(c'/root/saved.vset', c'mbr:12345678', c'6', c'14688256', c'14700544', c'mbr:12345678', c'5', c'14680064', c'14688256', false, 0, nil)
		pool_preview_for(c'/root/saved.vset', c'5', 0, &output[0]); check(contains(&output[0], c'pool=5 regions=2 gaps=2 bytes=16384 largest=12288'), c'donor pool free capacity')
		pool_preview_for(c'/root/saved.vset', c'6', 0, &output[0]); check(contains(&output[0], c'pool=6 regions=2 gaps=2 bytes=16384 largest=8192'), c'receiver pool free capacity')
		pool_resizes(c'/root/saved.vset', c'mbr:12345678', c'5', c'14680064', c'14688256', c'mbr:12345678', c'6', c'14688256', c'14700544', false, 0, &output[0]); check(contains(&output[0], c'action=keep') && !contains(&output[0], c'action=resize'), c'equal-bound retry in reverse order')
		pool_batch(c'/root/saved.vset', c'6', c'21', c'4096', c'ro', c'22', c'4096', c'rw', false, 0, nil)
		preview(c'check-bundle', false, 0, &output[0]); missing(c'/dev/mapper/vinix21'); missing(c'/dev/mapper/vinix22')
		check(contains(&output[0], c'disk=0 slot=21 action=create offset=14688256') && contains(&output[0], c'disk=0 slot=22 action=create offset=14692352'), c'future allocations consume transferred capacity')
		mapping_removals(c'/root/saved.vset', c'21', c'22', nil, false, 0, nil); mapping_removals(c'/root/saved.vset', c'19', c'21', nil, false, 0, nil)
		pool_resizes(c'/root/saved.vset', c'mbr:12345678', c'5', c'14684160', c'14688256', c'mbr:12345678', c'6', c'14688256', c'14700544', false, 0, nil)
		check(status(c'/dev/mapper/vinix19').generation == head_generation && C.pread(head, &data[0], 4096, 0) == 4096 && C.close(head) == 0, c'released unlisted head retains descriptor and generation'); for byte in data { check(byte == 0xf2, c'preserved resize head data') }
		check(status(c'/dev/mapper/vinix20').generation == tail_generation && C.pread(tail, &data[0], 4096, 0) == 4096 && C.close(tail) == 0, c'resize tail retains descriptor and generation'); for byte in data { check(byte == 0xf3, c'preserved resize tail data') }
		mapping_removals(c'/root/saved.vset', c'19', c'20', nil, false, 0, nil)
		pool_members_batch(c'/root/saved.vset', c'5', c'0', nil, nil, c'1', nil, nil, true, false, 0, nil)
		pool_members_batch(c'/root/saved.vset', c'6', c'0', nil, nil, c'1', nil, nil, true, false, 0, nil)
		bundle_unchanged(c'/root/saved.vset', &baseline[0], size); simple(c'remove', c'/dev/mapper/vinix19', nil, 0); simple(c'remove', c'/dev/mapper/vinix20', nil, 0)
		check(status(c'/dev/mapper/vinix12').generation == original_generation && C.pread(original, &data[0], 4096, 0) == 4096 && C.close(original) == 0, c'resize preserves original generation and descriptor'); for byte in data { check(byte == 0xe7, c'resize preserves original data') }
		C.printf(c'PLAN POOL RESIZE BATCH PASSED: atomic boundary transfer, two-sided occupation, rollback, retained views and new capacity\n')
	}
}

fn resize_boot_prepare() {
	unsafe {
		first := status(c'/dev/mapper/vinix12').generation; second := status(c'/dev/mapper/vinix9').generation
		pool_members_batch(c'/root/saved.vset', c'6', c'0', c'12591104', c'12599296', c'1', c'12591104', c'12599296', false, false, 0, nil)
		pool_resizes(c'/root/saved.vset', c'mbr:12345679', c'6', c'12587008', c'12599296', c'mbr:12345679', c'5', c'12582912', c'12587008', true, 0, nil)
		pool_resizes(c'/root/saved.vset', c'mbr:12345679', c'6', c'12587008', c'12599296', c'mbr:12345679', c'5', c'12582912', c'12587008', false, 0, nil)
		copy_plan(c'/root/saved.vset', c'/root/resize-planned.vset')
		check(status(c'/dev/mapper/vinix12').generation == first && status(c'/dev/mapper/vinix9').generation == second, c'boot resize preserves live views')
		C.printf(c'PLAN POOL RESIZE BATCH SAVED: transferred unused capacity between adjacent pools with unchanged priority\n')
	}
}

fn resize_boot_check() {
	unsafe {
		fd := C.open(c'/etc/vinix/volumes.vset', C.O_RDONLY); mut original := [8768]u8{}; size := C.read(fd, &original[0], 8768)
		check(fd >= 0 && size == 696 && C.close(fd) == 0, c'persistent resized bundle'); copy_plan(c'/etc/vinix/volumes.vset', c'/root/resize-boot.vset')
		mut output := [4096]char{}; pool_preview_for(c'/etc/vinix/volumes.vset', c'5', 0, &output[0])
		check(contains(&output[0], c'pool=5 disk=1 start=12582912 end=12587008 alignment=4096') && contains(&output[0], c'pool=5 regions=2 gaps=2 bytes=12288 largest=8192'), c'donor bounds and priority survive boot')
		pool_preview_for(c'/etc/vinix/volumes.vset', c'6', 0, &output[0])
		check(contains(&output[0], c'pool=6 disk=1 start=12587008 end=12599296 alignment=4096') && contains(&output[0], c'pool=6 regions=2 gaps=2 bytes=20480 largest=12288'), c'receiver bounds and priority survive boot')
		pool_resizes(c'/etc/vinix/volumes.vset', c'mbr:12345679', c'6', c'12587008', c'12599296', c'mbr:12345679', c'5', c'12582912', c'12587008', true, 0, &output[0]); check(contains(&output[0], c'action=keep') && !contains(&output[0], c'action=resize'), c'boot equal-bound retries')
		pool_resizes(c'/etc/vinix/volumes.vset', c'mbr:12345679', c'6', c'12587008', c'12599296', c'mbr:12345679', c'5', c'12582912', c'12587008', false, 0, nil); bundle_unchanged(c'/etc/vinix/volumes.vset', &original[0], size)
		// Preserve actual boot state before reversing only the unused fixture
		// transfer and memberships. The earlier independent checks retain 616/536.
		pool_resizes(c'/etc/vinix/volumes.vset', c'mbr:12345679', c'6', c'12591104', c'12599296', c'mbr:12345679', c'5', c'12582912', c'12591104', false, 0, nil)
		pool_members_batch(c'/etc/vinix/volumes.vset', c'6', c'0', nil, nil, c'1', nil, nil, true, false, 0, nil)
		C.printf(c'PLAN POOL RESIZE BATCH BOOT PRESERVED\n')
	}
}
