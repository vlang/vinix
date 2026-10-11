// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn pool_expand_batch(path &char, pool &char, first &char, first_end &char,
	second &char, second_end &char, preview bool, expected i32, output &char) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'),
			if preview { &char(c'pool-preview-expand-batch') } else { &char(c'pool-expand-batch') },
			path, pool, first, first_end, second, second_end, &char(nil)]!
		if output == nil { run_utility(&args[0], expected); return }
		fd := C.open(c'/root/expand-batch-output', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600))
		check(fd >= 0, c'open expansion batch output')
		child := C.fork()
		check(child >= 0, c'fork expansion batch preview')
		if child == 0 {
			if C.dup2(fd, 1) != 1 || C.dup2(fd, 2) != 2 || C.close(fd) != 0 { C._exit(126) }
			C.execv(args[0], &args[0]); C._exit(127)
		}
		mut code := i32(0)
		check(C.close(fd) == 0 && C.waitpid(child, &code, 0) == child && code == expected << 8, c'expansion batch preview exit')
		input := C.open(c'/root/expand-batch-output', C.O_RDONLY)
		count := C.read(input, output, 4095)
		check(input >= 0 && count > 0 && count < 4095 && C.close(input) == 0, c'read expansion batch output')
		output[count] = 0
	}
}

@[direct_array_access]
fn planned_pool_expand_batch(parent &char, other &char) {
	unsafe {
		fd := C.open(c'/root/saved.vset', C.O_RDONLY)
		mut original := [8768]u8{}
		size := C.read(fd, &original[0], 8768)
		check(fd >= 0 && size == 432 && C.close(fd) == 0, c'expansion batch baseline')
		first := status(c'/dev/mapper/vinix2'); second := status(c'/dev/mapper/vinix9')
		held := C.open(c'/dev/mapper/vinix2', C.O_RDONLY)
		check(held >= 0, c'hold old view across expansion batch')
		mut output := [4096]char{}
		for preview in [false, true]! {
			pool_expand_batch(c'/root/saved.vset', c'3', c'1', c'6307840', c'0', c'16777728', preview, 1, &output[0])
			check(!contains(&output[0], c'action='), c'later expansion failure reports no partial actions')
			bundle_unchanged(c'/root/saved.vset', &original[0], size)
			pool_expand_batch(c'/root/saved.vset', c'3', c'1', c'6307840', c'1', c'6307840', preview, 1, &output[0])
			bundle_unchanged(c'/root/saved.vset', &original[0], size)
		}
		directory := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
		check(directory >= 0 && C.flock(directory, C.LOCK_EX | C.LOCK_NB) == 0, c'hold expansion writer lock')
		pool_expand_batch(c'/root/saved.vset', c'3', c'1', c'6307840', c'0', c'6299648', false, 1, &output[0])
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		pool_expand_batch(c'/root/saved.vset', c'3', c'1', c'6307840', c'0', c'6299648', true, 0, &output[0])
		check(contains(&output[0], c'operation=preview-expansion')
			&& contains(&output[0], c'request=0 disk=1 action=expand start=6291456 previous_end=6303744 end=6307840 alignment=4096')
			&& contains(&output[0], c'request=1 disk=0 action=expand start=6291456 previous_end=6295552 end=6299648 alignment=4096'), c'complete expansion preview in request order under writer lock')
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		check(C.close(directory) == 0, c'release expansion writer lock')
		pool_expand_batch(c'/root/saved.vset', c'3', c'1', c'6307840', c'0', c'6299648', false, 0, nil)
		configured := C.open(c'/root/saved.vset', C.O_RDONLY)
		mut expanded := [8768]u8{}
		check(configured >= 0 && C.read(configured, &expanded[0], 8768) == size && C.close(configured) == 0,
			c'capture complete expanded pool bundle')
		for i in 0 .. 24 { check(original[i] == expanded[i], c'expansion preserves bundle counts') }
		for i in 64 .. 352 { check(original[i] == expanded[i], c'expansion preserves every disk identity and desired mapping') }
		pool_preview(c'/root/saved.vset', 0, &output[0])
		check(contains(&output[0], c'pool=3 disk=0 start=6291456 end=6299648 alignment=4096')
			&& contains(&output[0], c'pool=3 disk=1 start=6291456 end=6307840 alignment=4096')
			&& contains(&output[0], c'pool=3 regions=2 gaps=2 bytes=24576 largest=16384'), c'both expanded members add exact eligibility')
		pool_expand_batch(c'/root/saved.vset', c'3', c'1', c'6307840', c'0', c'6299648', false, 0, &output[0])
		check(contains(&output[0], c'request=0 disk=1 action=keep') && contains(&output[0], c'request=1 disk=0 action=keep'), c'equal-end retry keeps both members')
		bundle_unchanged(c'/root/saved.vset', &expanded[0], size)
		pool_allocate(c'/root/saved.vset', c'3', c'14', c'8192', true, 0)
		missing(c'/dev/mapper/vinix14')
		simple(c'restore-bundle', c'/root/saved.vset', nil, 0)
		view := status(c'/dev/mapper/vinix14')
		check(view.disk_id == status(parent).disk_id && view.start == 6291456 && view.bytes == 8192 && view.flags & 1 == 1,
			c'reverse expansion request order retains original first-fit member priority')
		check(status(c'/dev/mapper/vinix2').generation == first.generation && status(c'/dev/mapper/vinix2').bytes == first.bytes
			&& status(c'/dev/mapper/vinix9').generation == second.generation && status(c'/dev/mapper/vinix9').bytes == second.bytes
			&& first.disk_id == status(parent).disk_id && second.disk_id == status(other).disk_id, c'expansion preserves live geometry and generations')
		mut data := [4096]u8{}
		check(C.pread(held, &data[0], 4096, 0) == 4096 && C.close(held) == 0, c'held old view survives expansion and replay')
		for byte in data { check(byte == 0x6d, c'old data preserved across pool expansion') }
		simple(c'plan-remove', c'/root/saved.vset', c'14', 0)
		simple(c'remove', c'/dev/mapper/vinix14', nil, 0)
		tool(c'pool-remove', c'/root/saved.vset', c'3', c'0', nil, 0)
		tool(c'pool-remove', c'/root/saved.vset', c'3', c'1', nil, 0)
		pool_members(c'/root/saved.vset')
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		copy_plan(c'/root/saved.vset', c'/etc/vinix/volumes.vset')
		C.printf(c'PLAN POOL EXPANSION BATCH PASSED: complete rollback/previews, writer exclusion, exact eligibility and retained member priority/views\n')
	}
}
