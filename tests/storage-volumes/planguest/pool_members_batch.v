// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn pool_members_batch(path &char, pool &char, first &char, first_start &char, first_end &char,
	second &char, second_start &char, second_end &char, remove bool, preview bool, expected i32, output &char) {
	unsafe {
		command := if remove {
			if preview { &char(c'pool-preview-remove-batch') } else { &char(c'pool-remove-batch') }
		} else { if preview { &char(c'pool-preview-add-batch') } else { &char(c'pool-add-batch') } }
		mut args := [&char(c'/usr/sbin/vinix-volume'), command, path, pool, first, first_start,
			first_end, &char(c'4096'), second, second_start, second_end, &char(c'4096'), &char(nil)]!
		if remove { args[5] = second; args[6] = &char(nil) }
		if output == nil { run_utility(&args[0], expected); return }
		fd := C.open(c'/root/members-batch-output', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600))
		check(fd >= 0, c'open membership batch output')
		child := C.fork(); check(child >= 0, c'fork membership batch command')
		if child == 0 {
			if C.dup2(fd, 1) != 1 || C.dup2(fd, 2) != 2 || C.close(fd) != 0 { C._exit(126) }
			C.execv(args[0], &args[0]); C._exit(127)
		}
		mut code := i32(0)
		check(C.close(fd) == 0 && C.waitpid(child, &code, 0) == child && code == expected << 8, c'membership batch exit')
		input := C.open(c'/root/members-batch-output', C.O_RDONLY)
		count := C.read(input, output, 4095)
		check(input >= 0 && count > 0 && count < 4095 && C.close(input) == 0, c'read membership batch output')
		output[count] = 0
	}
}

@[direct_array_access]
fn planned_pool_members_batch(parent &char, other &char) {
	unsafe {
		fd := C.open(c'/root/saved.vset', C.O_RDONLY)
		mut original := [8768]u8{}
		size := C.read(fd, &original[0], 8768)
		check(fd >= 0 && size == 432 && C.close(fd) == 0, c'membership batch baseline')
		first := status(c'/dev/mapper/vinix2'); second := status(c'/dev/mapper/vinix9')
		held := C.open(c'/dev/mapper/vinix2', C.O_RDONLY)
		check(held >= 0, c'hold view across membership batch')
		mut output := [4096]char{}
		for preview in [false, true]! {
			pool_members_batch(c'/root/saved.vset', c'4', c'1', c'8388608', c'8404992', c'0', c'8388608', c'16781312', false, preview, 1, &output[0])
			check(!contains(&output[0], c'action='), c'later member failure has no partial actions')
			bundle_unchanged(c'/root/saved.vset', &original[0], size)
			pool_members_batch(c'/root/saved.vset', c'4', c'1', c'8388608', c'8404992', c'1', c'8388608', c'8404992', false, preview, 1, &output[0])
			bundle_unchanged(c'/root/saved.vset', &original[0], size)
			pool_members_batch(c'/root/saved.vset', c'3', c'0', nil, nil, c'2', nil, nil, true, preview, 1, &output[0])
			bundle_unchanged(c'/root/saved.vset', &original[0], size)
		}
		directory := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
		check(directory >= 0 && C.flock(directory, C.LOCK_EX | C.LOCK_NB) == 0, c'hold membership writer lock')
		pool_members_batch(c'/root/saved.vset', c'4', c'1', c'8388608', c'8404992', c'0', c'8388608', c'8404992', false, false, 1, &output[0])
		pool_members_batch(c'/root/saved.vset', c'4', c'1', c'8388608', c'8404992', c'0', c'8388608', c'8404992', false, true, 0, &output[0])
		check(contains(&output[0], c'operation=preview-membership-add')
			&& contains(&output[0], c'request=0 disk=1 action=add') && contains(&output[0], c'request=1 disk=0 action=add'), c'complete ordered membership preview under writer lock')
		pool_members_batch(c'/root/saved.vset', c'3', c'0', nil, nil, c'1', nil, nil, true, false, 1, &output[0])
		pool_members_batch(c'/root/saved.vset', c'3', c'0', nil, nil, c'1', nil, nil, true, true, 0, &output[0])
		check(contains(&output[0], c'request=0 disk=0 action=remove') && contains(&output[0], c'request=1 disk=1 action=remove'), c'complete membership removal preview under writer lock')
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		check(C.close(directory) == 0, c'release membership writer lock')
		pool_members_batch(c'/root/saved.vset', c'4', c'1', c'8388608', c'8404992', c'0', c'8388608', c'8404992', false, false, 0, nil)
		configured := C.open(c'/root/saved.vset', C.O_RDONLY)
		mut added := [8768]u8{}
		check(configured >= 0 && C.read(configured, &added[0], 8768) == size + 80 && C.close(configured) == 0, c'capture both admitted pool members')
		pool_members_batch(c'/root/saved.vset', c'4', c'0', c'8388608', c'8404992', c'1', c'8388608', c'8404992', false, false, 0, &output[0])
		check(contains(&output[0], c'request=0 disk=0 action=keep') && contains(&output[0], c'request=1 disk=1 action=keep'), c'matching membership retry keeps saved priority')
		bundle_unchanged(c'/root/saved.vset', &added[0], size + 80)
		pool_members_batch(c'/root/saved.vset', c'4', c'0', nil, nil, nil, nil, nil, true, false, 0, nil)
		pool_members_batch(c'/root/saved.vset', c'4', c'1', c'8388608', c'8404992', c'0', c'8388608', c'8404992', false, true, 0, &output[0])
		check(contains(&output[0], c'request=0 disk=1 action=keep') && contains(&output[0], c'request=1 disk=0 action=add'), c'mixed keep/new admission preview')
		pool_members_batch(c'/root/saved.vset', c'4', c'1', c'8388608', c'8404992', c'0', c'8388608', c'8404992', false, false, 0, nil)
		bundle_unchanged(c'/root/saved.vset', &added[0], size + 80)
		pool_allocate(c'/root/saved.vset', c'4', c'14', c'4096', true, 0)
		preview(c'show-bundle', false, 0, &output[0])
		check(contains(&output[0], c'disk=1 slot=14 offset=8388608 bytes=4096 readonly=1'), c'admission order controls first fit even after reverse retry')
		pool_members_batch(c'/root/saved.vset', c'4', c'0', nil, nil, c'1', nil, nil, true, false, 0, &output[0])
		check(contains(&output[0], c'request=0 disk=0 action=remove') && contains(&output[0], c'request=1 disk=1 action=remove'), c'complete removal publication')
		preview(c'show-bundle', false, 0, &output[0])
		check(contains(&output[0], c'disk=1 slot=14 offset=8388608 bytes=4096 readonly=1'), c'membership removal preserves desired mapping')
		pool_members_batch(c'/root/saved.vset', c'4', c'0', nil, nil, c'1', nil, nil, true, false, 0, &output[0])
		check(contains(&output[0], c'request=0 disk=0 action=keep') && contains(&output[0], c'request=1 disk=1 action=keep'), c'absent members are durable removal retries')
		pool_members_batch(c'/root/saved.vset', c'4', c'1', c'8388608', c'8404992', nil, nil, nil, false, false, 0, nil)
		pool_members_batch(c'/root/saved.vset', c'4', c'0', nil, nil, c'1', nil, nil, true, false, 0, &output[0])
		check(contains(&output[0], c'request=0 disk=0 action=keep') && contains(&output[0], c'request=1 disk=1 action=remove'), c'mixed absent/present removal')
		simple(c'plan-remove', c'/root/saved.vset', c'14', 0)
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		check(status(c'/dev/mapper/vinix2').generation == first.generation && status(c'/dev/mapper/vinix9').generation == second.generation
			&& first.disk_id == status(parent).disk_id && second.disk_id == status(other).disk_id, c'membership batches preserve live identity and generations')
		mut data := [4096]u8{}
		check(C.pread(held, &data[0], 4096, 0) == 4096 && C.close(held) == 0, c'held view survives membership batch')
		for byte in data { check(byte == 0x6d, c'membership batches preserve held bytes') }
		C.printf(c'PLAN POOL MEMBERSHIP BATCH PASSED: complete additions/removals/previews, retry priority, rollback and retained mappings/views\n')
	}
}

fn pool_members_batch_boot_check() {
	fd := C.open(c'/etc/vinix/volumes.vset', C.O_RDONLY)
	mut original := [8768]u8{}
	size := C.read(fd, &original[0], 8768)
	check(fd >= 0 && size == 536 && C.close(fd) == 0, c'membership batch persisted bundle')
	mut output := [4096]char{}
	pool_members_batch(c'/etc/vinix/volumes.vset', c'3', c'1', c'6291456', c'6303744', c'0', c'6291456', c'6295552', false, true, 0, &output[0])
	check(contains(&output[0], c'request=0 disk=1 action=keep') && contains(&output[0], c'request=1 disk=0 action=keep'), c'persistent membership bounds match exact reverse retry')
	pool_members_batch(c'/etc/vinix/volumes.vset', c'3', c'1', c'6291456', c'6303744', c'0', c'6291456', c'6295552', false, false, 0, unsafe { nil })
	bundle_unchanged(c'/etc/vinix/volumes.vset', &original[0], size)
	C.printf(c'PLAN POOL MEMBERSHIP BATCH BOOT PRESERVED\n')
}
