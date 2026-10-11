// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn capacity_batch(path &char, first &char, first_device &char, first_bytes &char,
	second &char, second_device &char, second_bytes &char, preview bool, expected i32, output &char) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'),
			if preview { &char(c'plan-preview-capacity-batch') } else { &char(c'plan-capacity-batch') },
			path, first, first_device, first_bytes, second, second_device, second_bytes, &char(nil)]!
		if output == nil { run_utility(&args[0], expected); return }
		fd := C.open(c'/root/capacity-batch-output', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600))
		check(fd >= 0, c'open capacity batch output')
		child := C.fork(); check(child >= 0, c'fork capacity batch command')
		if child == 0 {
			if C.dup2(fd, 1) != 1 || C.dup2(fd, 2) != 2 || C.close(fd) != 0 { C._exit(126) }
			C.execv(args[0], &args[0]); C._exit(127)
		}
		mut code := i32(0)
		check(C.close(fd) == 0 && C.waitpid(child, &code, 0) == child && code == expected << 8, c'capacity batch exit')
		input := C.open(c'/root/capacity-batch-output', C.O_RDONLY)
		count := C.read(input, output, 4095)
		check(input >= 0 && count > 0 && count < 4095 && C.close(input) == 0, c'read capacity batch output')
		output[count] = 0
	}
}

@[direct_array_access]
fn planned_capacity_batch(parent &char, other &char) {
	unsafe {
		fd := C.open(c'/root/saved.vset', C.O_RDONLY)
		mut original := [8768]u8{}
		size := C.read(fd, &original[0], 8768)
		check(fd >= 0 && size == 432 && C.close(fd) == 0, c'capacity batch baseline')
		first := status(c'/dev/mapper/vinix2'); second := status(c'/dev/mapper/vinix9')
		held := C.open(c'/dev/mapper/vinix2', C.O_RDONLY)
		check(held >= 0, c'hold view across capacity batch')
		mut output := [4096]char{}
		for preview in [false, true]! {
			capacity_batch(c'/root/saved.vset', c'0', parent, c'16777216', c'1', other, c'33554432', preview, 1, &output[0])
			check(!contains(&output[0], c'action='), c'later capacity mismatch reports no partial actions')
			bundle_unchanged(c'/root/saved.vset', &original[0], size)
			capacity_batch(c'/root/saved.vset', c'0', parent, c'16777216', c'1', parent, c'16777216', preview, 1, &output[0])
			check(!contains(&output[0], c'action='), c'duplicate physical disk reports no actions')
			bundle_unchanged(c'/root/saved.vset', &original[0], size)
			capacity_batch(c'/root/saved.vset', c'0', parent, c'16777216', c'0', parent, c'16777216', preview, 1, &output[0])
			bundle_unchanged(c'/root/saved.vset', &original[0], size)
		}
		physical_alias(parent)
		capacity_batch(c'/root/saved.vset', c'1', other, c'16777216', c'0', c'/dev/volume-plan-link', c'16777216', false, 1, &output[0])
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		directory := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
		check(directory >= 0 && C.flock(directory, C.LOCK_EX | C.LOCK_NB) == 0, c'hold capacity batch writer lock')
		capacity_batch(c'/root/saved.vset', c'1', other, c'16777216', c'0', c'/dev/volume-plan-alias', c'16777216', false, 1, &output[0])
		capacity_batch(c'/root/saved.vset', c'1', other, c'16777216', c'0', c'/dev/volume-plan-alias', c'16777216', true, 0, &output[0])
		check(contains(&output[0], c'requests=2 operation=preview-capacity')
			&& contains(&output[0], c'request=0 disk=1 action=keep previous_bytes=16777216 bytes=16777216 sector=512')
			&& contains(&output[0], c'request=1 disk=0 action=keep previous_bytes=16777216 bytes=16777216 sector=512'), c'complete reverse-order capacity preview under writer lock')
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		check(C.close(directory) == 0, c'release capacity batch writer lock')
		capacity_batch(c'/root/saved.vset', c'1', other, c'16777216', c'0', c'/dev/volume-plan-alias', c'16777216', false, 0, &output[0])
		check(contains(&output[0], c'requests=2 operation=planned-capacity'), c'published capacity batch report')
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		capacity_batch(c'/root/saved.vset', c'1', other, c'16777216', c'0', parent, c'16777216', false, 0, nil)
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		check(status(c'/dev/mapper/vinix2').generation == first.generation && status(c'/dev/mapper/vinix2').bytes == first.bytes
			&& status(c'/dev/mapper/vinix9').generation == second.generation && status(c'/dev/mapper/vinix9').bytes == second.bytes,
			c'capacity batches retain live views and generations')
		mut data := [4096]u8{}
		check(C.pread(held, &data[0], 4096, 0) == 4096 && C.close(held) == 0, c'held capacity view readable')
		for byte in data { check(byte == 0x6d, c'capacity batch preserves held data') }
		check(C.unlink(c'/dev/volume-plan-alias') == 0 && C.unlink(c'/dev/volume-plan-link') == 0, c'capacity batch alias cleanup')
		C.printf(c'PLAN CAPACITY BATCH PASSED: whole-set rollback, complete previews, pinned physical aliases and preserved live views\n')
	}
}
