// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn pool_grow_batch(path &char, pool &char, first &char, first_length &char,
	second &char, second_length &char, preview bool, expected i32, output &char) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'),
			if preview { &char(c'pool-preview-grow-batch') } else { &char(c'pool-grow-batch') },
			path, pool, first, first_length, second, second_length, &char(nil)]!
		if output == nil { run_utility(&args[0], expected); return }
		fd := C.open(c'/root/grow-batch-output', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600))
		check(fd >= 0, c'open growth batch output')
		child := C.fork()
		check(child >= 0, c'fork growth batch preview')
		if child == 0 {
			if C.dup2(fd, 1) != 1 || C.dup2(fd, 2) != 2 || C.close(fd) != 0 { C._exit(126) }
			C.execv(args[0], &args[0]); C._exit(127)
		}
		mut code := i32(0)
		check(C.close(fd) == 0 && C.waitpid(child, &code, 0) == child && code == expected << 8, c'growth batch preview exit')
		input := C.open(c'/root/grow-batch-output', C.O_RDONLY)
		count := C.read(input, output, 4095)
		check(input >= 0 && count > 0 && count < 4095 && C.close(input) == 0, c'read growth batch output')
		output[count] = 0
	}
}

@[direct_array_access]
fn planned_pool_grow_batch(parent &char, other &char) {
	unsafe {
		fd := C.open(c'/root/saved.vset', C.O_RDONLY)
		mut baseline := [8768]u8{}
		size := C.read(fd, &baseline[0], 8768)
		check(fd >= 0 && size == 432 && C.close(fd) == 0, c'growth batch baseline')
		pool_growth(c'/root/saved.vset', c'pool-expand', c'3', c'0', c'6299648', 0)
		pool_batch(c'/root/saved.vset', c'3', c'14', c'4096', c'ro', c'15', c'8192', c'rw', false, 0, nil)
		simple(c'restore-bundle', c'/root/saved.vset', nil, 0)
		first := status(c'/dev/mapper/vinix14'); second := status(c'/dev/mapper/vinix15')
		held_first := C.open(c'/dev/mapper/vinix14', C.O_RDONLY)
		held_second := C.open(c'/dev/mapper/vinix15', C.O_RDWR)
		check(held_first >= 0 && held_second >= 0, c'hold cross-disk growth views')
		raw := C.open(other, C.O_RDWR)
		mut data := [4096]u8{init: 0xb9}
		check(raw >= 0 && C.pwrite(raw, &data[0], 4096, 6299648) == 4096 && C.fsync(raw) == 0 && C.close(raw) == 0, c'prepare second growth extension data')
		input := C.open(c'/root/saved.vset', C.O_RDONLY)
		mut original := [8768]u8{}
		original_size := C.read(input, &original[0], 8768)
		check(input >= 0 && original_size == 496 && C.close(input) == 0, c'capture before growth batch')
		mut output := [4096]char{}
		for preview in [false, true]! {
			pool_grow_batch(c'/root/saved.vset', c'3', c'14', c'8192', c'15', c'16384', preview, 1, &output[0])
			check(!contains(&output[0], c'action='), c'later growth failure reports no partial actions')
			bundle_unchanged(c'/root/saved.vset', &original[0], original_size)
			pool_grow_batch(c'/root/saved.vset', c'3', c'14', c'8192', c'14', c'8192', preview, 1, &output[0])
			bundle_unchanged(c'/root/saved.vset', &original[0], original_size)
		}
		pool_grow_batch(c'/root/saved.vset', c'3', c'14', c'8192', c'15', c'12288', true, 0, &output[0])
		check(contains(&output[0], c'operation=preview-growth')
			&& contains(&output[0], c'disk=0 slot=14 action=grow offset=6291456 previous_bytes=4096 bytes=8192 readonly=1')
			&& contains(&output[0], c'disk=1 slot=15 action=grow offset=6291456 previous_bytes=8192 bytes=12288 readonly=0'), c'complete cross-disk growth preview')
		bundle_unchanged(c'/root/saved.vset', &original[0], original_size)
		pool_grow_batch(c'/root/saved.vset', c'3', c'14', c'8192', c'15', c'12288', false, 0, nil)
		check(status(c'/dev/mapper/vinix14').bytes == first.bytes && status(c'/dev/mapper/vinix15').bytes == second.bytes, c'growth batch remains offline')
		planned := C.open(c'/root/saved.vset', C.O_RDONLY)
		mut complete := [8768]u8{}
		complete_size := C.read(planned, &complete[0], 8768)
		check(planned >= 0 && complete_size == original_size && C.close(planned) == 0, c'capture grown desired bundle')
		simple(c'restore-bundle', c'/root/saved.vset', nil, 1)
		tool(c'create', other, c'16', c'6299648', c'4096', 0)
		preview(c'check-bundle', true, 1, &output[0])
		check(!contains(&output[0], c'action='), c'later-disk extension conflict rejects complete growth preview')
		tool(c'restore-bundle', c'/root/saved.vset', c'grow', nil, nil, 1)
		check(status(c'/dev/mapper/vinix14').bytes == first.bytes && status(c'/dev/mapper/vinix15').bytes == second.bytes, c'preflight rejection prevents first growth')
		simple(c'remove', c'/dev/mapper/vinix16', nil, 0)
		tool(c'restore-bundle', c'/root/saved.vset', c'grow', nil, nil, 0)
		check(status(c'/dev/mapper/vinix14').generation == first.generation && status(c'/dev/mapper/vinix14').bytes == 8192
			&& status(c'/dev/mapper/vinix15').generation == second.generation && status(c'/dev/mapper/vinix15').bytes == 12288, c'growth batch replay retains both generations')
		check(C.pread(held_first, &data[0], 4096, 4096) == 4096 && C.close(held_first) == 0, c'held readonly descriptor reads first extension')
		for byte in data { check(byte == 0xba, c'first extension data preserved') }
		check(C.pread(held_second, &data[0], 4096, 8192) == 4096 && C.close(held_second) == 0, c'held writable descriptor reads second extension')
		for byte in data { check(byte == 0xb9, c'second extension data preserved') }
		pool_grow_batch(c'/root/saved.vset', c'3', c'14', c'8192', c'15', c'12288', false, 0, &output[0])
		check(contains(&output[0], c'slot=14 action=keep') && contains(&output[0], c'slot=15 action=keep'), c'growth batch retries report both kept rows')
		bundle_unchanged(c'/root/saved.vset', &complete[0], complete_size)
		for slot in [&char(c'14'), &char(c'15')]! { simple(c'plan-remove', c'/root/saved.vset', slot, 0) }
		simple(c'remove', c'/dev/mapper/vinix14', nil, 0); simple(c'remove', c'/dev/mapper/vinix15', nil, 0)
		tool(c'pool-remove', c'/root/saved.vset', c'3', c'0', nil, 0)
		tool(c'pool-remove', c'/root/saved.vset', c'3', c'1', nil, 0)
		pool_members(c'/root/saved.vset')
		bundle_unchanged(c'/root/saved.vset', &baseline[0], size)
		check(first.disk_id == status(parent).disk_id && second.disk_id == status(other).disk_id, c'growth retained physical disk identities')
		copy_plan(c'/root/saved.vset', c'/etc/vinix/volumes.vset')
		C.printf(c'PLAN POOL GROWTH BATCH PASSED: atomic cross-disk growth, complete previews, rollback, live preflight and held descriptors\n')
	}
}

fn capacity_growth_batch(parent &char) {
	unsafe {
		before := status(c'/dev/mapper/vinix18')
		held := C.open(c'/dev/mapper/vinix18', C.O_RDONLY)
		raw := C.open(parent, C.O_RDWR)
		mut data := [4096]u8{init: 0xcd}
		check(held >= 0 && raw >= 0 && C.pwrite(raw, &data[0], 4096, 16789504) == 4096
			&& C.fsync(raw) == 0 && C.close(raw) == 0, c'prepare readonly batch growth tail')
		mut output := [4096]char{}
		pool_grow_batch(c'/root/saved.vset', c'4', c'14', c'8192', c'18', c'8192', true, 0, &output[0])
		check(contains(&output[0], c'slot=14 action=keep') && contains(&output[0], c'slot=18 action=grow'), c'mixed keep/grow preview')
		pool_grow_batch(c'/root/saved.vset', c'4', c'14', c'8192', c'18', c'8192', false, 0, nil)
		check(status(c'/dev/mapper/vinix18').bytes == 4096, c'tail growth planning is offline')
		tool(c'restore-bundle', c'/root/saved.vset', c'grow', nil, nil, 0)
		check(status(c'/dev/mapper/vinix18').bytes == 8192 && status(c'/dev/mapper/vinix18').generation == before.generation
			&& C.pread(held, &data[0], 4096, 4096) == 4096 && C.close(held) == 0, c'held tail descriptor reads grown readonly extent')
		for byte in data { check(byte == 0xcd, c'grown readonly tail bytes preserved') }
		pool_grow_batch(c'/root/saved.vset', c'4', c'14', c'8192', c'18', c'8192', false, 0, &output[0])
		check(contains(&output[0], c'slot=14 action=keep') && contains(&output[0], c'slot=18 action=keep'), c'tail retry retains both grown rows')
	}
}
