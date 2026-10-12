// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn pool_order(path &char, pool &char, first &char, second &char, preview bool, expected i32, output &char) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'),
			if preview { &char(c'pool-preview-order') } else { &char(c'pool-order') },
			path, pool, first, second, &char(nil)]!
		if output == nil { run_utility(&args[0], expected); return }
		fd := C.open(c'/root/priority-output', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600))
		check(fd >= 0, c'open priority output')
		child := C.fork(); check(child >= 0, c'fork priority command')
		if child == 0 {
			if C.dup2(fd, 1) != 1 || C.dup2(fd, 2) != 2 || C.close(fd) != 0 { C._exit(126) }
			C.execv(args[0], &args[0]); C._exit(127)
		}
		mut code := i32(0)
		check(C.close(fd) == 0 && C.waitpid(child, &code, 0) == child && code == expected << 8, c'priority exit')
		input := C.open(c'/root/priority-output', C.O_RDONLY)
		count := C.read(input, output, 4095)
		check(input >= 0 && count > 0 && count < 4095 && C.close(input) == 0, c'read priority output')
		output[count] = 0
	}
}

@[direct_array_access]
fn planned_pool_order(parent &char, other &char) {
	unsafe {
		fd := C.open(c'/root/saved.vset', C.O_RDONLY)
		mut original := [8768]u8{}
		size := C.read(fd, &original[0], 8768)
		check(fd >= 0 && size == 432 && C.close(fd) == 0, c'priority baseline')
		first := status(c'/dev/mapper/vinix2'); second := status(c'/dev/mapper/vinix9')
		mut output := [4096]char{}
		for preview in [false, true]! {
			pool_order(c'/root/saved.vset', c'3', c'0', nil, preview, 1, &output[0])
			check(!contains(&output[0], c'action='), c'incomplete priority has no partial actions')
			pool_order(c'/root/saved.vset', c'3', c'0', c'0', preview, 1, &output[0])
			pool_order(c'/root/saved.vset', c'3', c'0', c'2', preview, 1, &output[0])
			bundle_unchanged(c'/root/saved.vset', &original[0], size)
		}
		directory := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
		check(directory >= 0 && C.flock(directory, C.LOCK_EX | C.LOCK_NB) == 0, c'hold priority writer lock')
		pool_order(c'/root/saved.vset', c'3', c'1', c'0', false, 1, &output[0])
		pool_order(c'/root/saved.vset', c'3', c'1', c'0', true, 0, &output[0])
		check(contains(&output[0], c'priority=0 disk=1 previous_priority=1 action=move')
			&& contains(&output[0], c'priority=1 disk=0 previous_priority=0 action=move'), c'complete priority preview under writer lock')
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		check(C.close(directory) == 0, c'release priority writer lock')
		pool_order(c'/root/saved.vset', c'3', c'1', c'0', false, 0, nil)
		changed := C.open(c'/root/saved.vset', C.O_RDONLY)
		mut reordered := [8768]u8{}
		check(changed >= 0 && C.read(changed, &reordered[0], 8768) == size && C.close(changed) == 0, c'capture changed priority')
		pool_order(c'/root/saved.vset', c'3', c'1', c'0', false, 0, &output[0])
		check(contains(&output[0], c'priority=0 disk=1 previous_priority=0 action=keep')
			&& contains(&output[0], c'priority=1 disk=0 previous_priority=1 action=keep'), c'durable priority retry')
		bundle_unchanged(c'/root/saved.vset', &reordered[0], size)
		pool_allocate(c'/root/saved.vset', c'3', c'14', c'4096', true, 0)
		simple(c'restore-bundle', c'/root/saved.vset', nil, 0)
		view := status(c'/dev/mapper/vinix14')
		check(view.disk_id == status(other).disk_id && view.start == 6291456 && view.flags & 1 == 1, c'priority selects the requested first physical member')
		held := C.open(c'/dev/mapper/vinix14', C.O_RDONLY)
		check(held >= 0, c'hold view across priority changes')
		pool_order(c'/root/saved.vset', c'3', c'0', c'1', false, 0, nil)
		pool_allocate(c'/root/saved.vset', c'3', c'15', c'4096', false, 0)
		preview(c'show-bundle', false, 0, &output[0])
		check(contains(&output[0], c'disk=0 slot=15 offset=6291456 bytes=4096 readonly=0')
			&& contains(&output[0], c'disk=1 slot=14 offset=6291456 bytes=4096 readonly=1'), c'repriority changes new first fit and retains existing desired placement')
		check(status(c'/dev/mapper/vinix14').generation == view.generation
			&& status(c'/dev/mapper/vinix2').generation == first.generation && status(c'/dev/mapper/vinix9').generation == second.generation
			&& first.disk_id == status(parent).disk_id, c'priority changes preserve live generations')
		mut bytes := [4096]u8{}
		check(C.pread(held, &bytes[0], 4096, 0) == 4096 && C.close(held) == 0, c'held priority view readable')
		for byte in bytes { check(byte == 0xb8, c'priority changes preserve existing disk data') }
		simple(c'plan-remove', c'/root/saved.vset', c'14', 0)
		simple(c'plan-remove', c'/root/saved.vset', c'15', 0)
		simple(c'remove', c'/dev/mapper/vinix14', nil, 0)
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		C.printf(c'PLAN POOL PRIORITY PASSED: complete previews, rollback, durable retries, first fit and retained views\n')
	}
}

fn pool_order_boot_check() {
	fd := C.open(c'/etc/vinix/volumes.vset', C.O_RDONLY)
	mut original := [8768]u8{}
	size := C.read(fd, &original[0], 8768)
	check(fd >= 0 && size == 536 && C.close(fd) == 0, c'persistent priority bundle')
	mut output := [4096]char{}
	pool_order(c'/etc/vinix/volumes.vset', c'3', c'1', c'0', true, 0, &output[0])
	check(contains(&output[0], c'priority=0 disk=1 previous_priority=0 action=keep')
		&& contains(&output[0], c'priority=1 disk=0 previous_priority=1 action=keep'), c'reordered pool priority survives boot')
	pool_order(c'/etc/vinix/volumes.vset', c'3', c'1', c'0', false, 0, unsafe { nil })
	bundle_unchanged(c'/etc/vinix/volumes.vset', &original[0], size)
	C.printf(c'PLAN POOL PRIORITY BOOT PRESERVED\n')
}
