// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

// Fixed argv remains live until the synchronous child has exited. Capture only
// functional previews; repeated cycles use the ordinary direct runner.
fn pool_batch(path &char, pool &char, first &char, first_length &char, first_mode &char,
	second &char, second_length &char, second_mode &char, preview bool, expected i32, output &char) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'),
			if preview { &char(c'pool-preview-batch') } else { &char(c'pool-allocate-batch') },
			path, pool, first, first_length, first_mode, second, second_length, second_mode, &char(nil)]!
		if output == nil { run_utility(&args[0], expected); return }
		fd := C.open(c'/root/batch-output', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600))
		check(fd >= 0, c'open batch output')
		child := C.fork()
		check(child >= 0, c'fork batch preview')
		if child == 0 {
			if C.dup2(fd, 1) != 1 || C.dup2(fd, 2) != 2 || C.close(fd) != 0 { C._exit(126) }
			C.execv(args[0], &args[0])
			C._exit(127)
		}
		mut code := i32(0)
		check(C.close(fd) == 0 && C.waitpid(child, &code, 0) == child && code == expected << 8, c'batch preview exit')
		input := C.open(c'/root/batch-output', C.O_RDONLY)
		count := C.read(input, output, 4095)
		check(input >= 0 && count > 0 && count < 4095 && C.close(input) == 0, c'read batch output')
		output[count] = 0
	}
}

@[direct_array_access]
fn planned_pool_batch(parent &char, other &char) {
	unsafe {
		fd := C.open(c'/root/saved.vset', C.O_RDONLY)
		mut baseline := [8768]u8{}
		size := C.read(fd, &baseline[0], 8768)
		check(fd >= 0 && size == 432 && C.close(fd) == 0, c'pool batch baseline')
		mut output := [4096]char{}
		for preview in [false, true]! {
			pool_batch(c'/root/saved.vset', c'3', c'14', c'4096', c'ro', c'15', c'16384', c'rw', preview, 1, &output[0])
			check(!contains(&output[0], c'action='), c'failed later batch request reports no placements')
			bundle_unchanged(c'/root/saved.vset', &baseline[0], size)
			pool_batch(c'/root/saved.vset', c'3', c'14', c'4096', c'ro', c'14', c'4096', c'rw', preview, 1, &output[0])
			bundle_unchanged(c'/root/saved.vset', &baseline[0], size)
		}
		pool_batch(c'/root/saved.vset', c'3', c'14', c'4096', c'ro', c'15', c'8192', c'rw', true, 0, &output[0])
		check(contains(&output[0], c'operation=preview')
			&& contains(&output[0], c'request=0 disk=0 slot=14 action=allocate offset=6291456 bytes=4096 readonly=1')
			&& contains(&output[0], c'request=1 disk=1 slot=15 action=allocate offset=6291456 bytes=8192 readonly=0'), c'complete cross-disk batch preview')
		bundle_unchanged(c'/root/saved.vset', &baseline[0], size)
		missing(c'/dev/mapper/vinix14'); missing(c'/dev/mapper/vinix15')
		pool_batch(c'/root/saved.vset', c'3', c'14', c'4096', c'ro', c'15', c'8192', c'rw', false, 0, nil)
		missing(c'/dev/mapper/vinix14'); missing(c'/dev/mapper/vinix15')
		planned := C.open(c'/root/saved.vset', C.O_RDONLY)
		mut complete := [8768]u8{}
		complete_size := C.read(planned, &complete[0], 8768)
		check(planned >= 0 && complete_size == 496 && C.close(planned) == 0, c'capture complete batch publication')
		tool(c'create', other, c'16', c'6291456', c'4096', 0)
		preview(c'check-bundle', false, 1, &output[0])
		check(!contains(&output[0], c'action='), c'later member live conflict rejects complete batch preflight')
		simple(c'restore-bundle', c'/root/saved.vset', nil, 1)
		missing(c'/dev/mapper/vinix14'); missing(c'/dev/mapper/vinix15')
		simple(c'remove', c'/dev/mapper/vinix16', nil, 0)
		simple(c'restore-bundle', c'/root/saved.vset', nil, 0)
		first := status(c'/dev/mapper/vinix14')
		second := status(c'/dev/mapper/vinix15')
		check(first.disk_id == status(parent).disk_id && first.bytes == 4096 && first.flags & 1 == 1
			&& second.disk_id == status(other).disk_id && second.bytes == 8192 && second.flags & 1 == 0, c'batch restores both disk identities and modes')
		held := C.open(c'/dev/mapper/vinix14', C.O_RDONLY)
		check(held >= 0, c'hold batch mapping across retry')
		pool_batch(c'/root/saved.vset', c'3', c'14', c'4096', c'ro', c'15', c'8192', c'rw', false, 0, &output[0])
		check(contains(&output[0], c'slot=14 action=keep') && contains(&output[0], c'slot=15 action=keep'), c'batch retry keeps both saved placements')
		bundle_unchanged(c'/root/saved.vset', &complete[0], complete_size)
		pool_batch(c'/root/saved.vset', c'3', c'14', c'4096', c'rw', c'15', c'8192', c'rw', false, 1, &output[0])
		bundle_unchanged(c'/root/saved.vset', &complete[0], complete_size)
		simple(c'restore-bundle', c'/root/saved.vset', nil, 0)
		mut data := [4096]u8{}
		check(status(c'/dev/mapper/vinix14').generation == first.generation
			&& status(c'/dev/mapper/vinix15').generation == second.generation
			&& C.pread(held, &data[0], 4096, 0) == 4096 && C.close(held) == 0, c'batch retry retains generations and descriptor')
		for byte in data { check(byte == 0xba, c'batch mapping retains first disk data') }
		for slot in [&char(c'14'), &char(c'15')]! { simple(c'plan-remove', c'/root/saved.vset', slot, 0) }
		simple(c'remove', c'/dev/mapper/vinix14', nil, 0)
		simple(c'remove', c'/dev/mapper/vinix15', nil, 0)
		bundle_unchanged(c'/root/saved.vset', &baseline[0], size)
		copy_plan(c'/root/saved.vset', c'/etc/vinix/volumes.vset')
		C.printf(c'PLAN POOL BATCH PASSED: complete cross-disk preview/publication, rollback, conflict preflight and stable retries\n')
	}
}

fn pool_batch_boot_check(parent &char) {
	unsafe {
		info := status(c'/dev/mapper/vinix18')
		check(info.disk_id == status(parent).disk_id && info.start == 16785408 && info.bytes == 8192
			&& info.flags & 1 == 1, c'additional batch mapping survives boot with readonly mode')
		fd := C.open(c'/dev/mapper/vinix18', C.O_RDONLY)
		mut data := [4096]u8{}
		check(fd >= 0 && C.pread(fd, &data[0], 4096, 0) == 4096, c'read persisted batch tail data')
		for byte in data { check(byte == 0xcc, c'batch tail data survives reboot') }
		check(C.pread(fd, &data[0], 4096, 4096) == 4096 && C.close(fd) == 0, c'read persisted growth batch extension')
		for byte in data { check(byte == 0xcd, c'growth batch tail data survives reboot') }
		C.printf(c'PLAN POOL BATCH BOOT PRESERVED\n')
		C.printf(c'PLAN POOL GROWTH BATCH BOOT PRESERVED\n')
	}
}
