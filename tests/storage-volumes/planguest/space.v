// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn planning_allocate(path &char, disk &char, slot &char, length &char, start &char, end &char,
	alignment &char, readonly bool, expected i32) {
	unsafe {
		arguments := [&char(c'/usr/sbin/vinix-volume'), &char(c'plan-allocate'), path, disk, slot,
			length, start, end, alignment, if readonly { &char(c'ro') } else { &char(nil) },
			&char(nil)]!
		run_utility(&arguments[0], expected)
	}
}

fn space_preview(disk &char, start &char, end &char, alignment &char, expected i32, output &char) {
	fd := C.open(c'/root/space-output', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600))
	check(fd >= 0, c'open space preview')
	unsafe {
		arguments := [&char(c'/usr/sbin/vinix-volume'), &char(c'plan-space'),
			&char(c'/root/saved.vset'), disk, start, end, alignment, &char(nil)]!
		child := C.fork()
		check(child >= 0, c'fork space preview')
		if child == 0 {
			if C.dup2(fd, 1) != 1 || C.dup2(fd, 2) != 2 || C.close(fd) != 0 { C._exit(126) }
			C.execv(arguments[0], &arguments[0])
			C._exit(127)
		}
		mut code := i32(0)
		check(C.close(fd) == 0 && C.waitpid(child, &code, 0) == child && code == expected << 8,
			c'space preview exit')
	}
	input := C.open(c'/root/space-output', C.O_RDONLY)
	count := C.read(input, output, 4095)
	check(input >= 0 && count > 0 && count < 4095 && C.close(input) == 0, c'read space preview')
	unsafe { output[count] = 0 }
}

@[direct_array_access]
fn planned_space(parent &char) {
	unsafe {
		first := status(c'/dev/mapper/vinix2').generation
		fd := C.open(c'/root/saved.vset', C.O_RDONLY)
		mut original := [6208]u8{}
		size := C.read(fd, &original[0], 6208)
		check(fd >= 0 && size == 352 && C.close(fd) == 0, c'read space baseline')
		mut output := [4096]char{}
		space_preview(c'0', c'1048576', c'1081344', c'4096', 0, &output[0])
		check(contains(&output[0], c'space disk=0 offset=1056768 bytes=24576')
			&& contains(&output[0], c'gaps=1 bytes=24576 largest=24576'), c'aligned free gap report')
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		mut bytes := [4096]u8{init: 0xf2}
		raw := C.open(parent, C.O_RDWR)
		check(raw >= 0 && C.pwrite(raw, &bytes[0], 4096, 1056768) == 4096 && C.fsync(raw) == 0
			&& C.close(raw) == 0, c'prepare allocated raw data')
		planning_allocate(c'/root/saved.vset', c'0', c'14', c'4096', c'1048576', c'1064960',
			c'8192', true, 0)
		missing(c'/dev/mapper/vinix14')
		preview(c'show-bundle', false, 0, &output[0])
		check(contains(&output[0], c'slot=14 offset=1056768 bytes=4096 readonly=1'), c'first-fit saved geometry')
		added_fd := C.open(c'/root/saved.vset', C.O_RDONLY)
		mut added := [6208]u8{}
		added_size := C.read(added_fd, &added[0], 6208)
		check(added_fd >= 0 && added_size == 384 && C.close(added_fd) == 0, c'read allocated bundle')
		space_preview(c'0', c'1048576', c'1064960', c'8192', 0, &output[0])
		check(contains(&output[0], c'gaps=0 bytes=0 largest=0'), c'alignment excludes a short tail')
		planning_allocate(c'/root/saved.vset', c'0', c'15', c'4096', c'1048576', c'1064960',
			c'8192', false, 1)
		planning_allocate(c'/root/saved.vset', c'0', c'9', c'4096', c'6291456', c'6307840',
			c'4096', false, 1)
		bundle_unchanged(c'/root/saved.vset', &added[0], added_size)
		space_preview(c'2', c'0', c'4096', c'4096', 1, &output[0])
		check(!contains(&output[0], c'space disk='), c'invalid space request has no gap rows')
		// Offline placement cannot infer unlisted live ownership. Complete live
		// preflight must reject it before creating the planned mapping.
		tool(c'create', parent, c'15', c'1056768', c'4096', 0)
		preview(c'check-bundle', false, 1, &output[0])
		check(!contains(&output[0], c'action='), c'unlisted extent blocks allocated actions')
		simple(c'restore-bundle', c'/root/saved.vset', &char(nil), 1)
		missing(c'/dev/mapper/vinix14')
		check(status(c'/dev/mapper/vinix2').generation == first, c'failed application keeps old generation')
		simple(c'remove', c'/dev/mapper/vinix15', &char(nil), 0)
		simple(c'restore-bundle', c'/root/saved.vset', &char(nil), 0)
		allocated := status(c'/dev/mapper/vinix14')
		check(allocated.start == 1056768 && allocated.bytes == 4096 && allocated.flags & 1 == 1,
			c'allocated mapping geometry and mode')
		held := C.open(c'/dev/mapper/vinix14', C.O_RDONLY)
		check(held >= 0, c'hold allocated mapping')
		simple(c'plan-remove', c'/root/saved.vset', c'14', 0)
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		simple(c'restore-bundle', c'/root/saved.vset', &char(nil), 0)
		check(C.pread(held, &bytes[0], 4096, 0) == 4096 && C.close(held) == 0,
			c'allocated data survives omission')
		for byte in bytes { check(byte == 0xf2, c'allocation preserves raw data') }
		check(status(c'/dev/mapper/vinix14').generation == allocated.generation,
			c'omission preserves allocated generation')
		simple(c'remove', c'/dev/mapper/vinix14', &char(nil), 0)
		missing(c'/dev/mapper/vinix14')
		copy_plan(c'/root/saved.vset', c'/etc/vinix/volumes.vset')
		C.printf(c'PLAN SPACE PASSED: bounded aligned gaps, first-fit allocation, complete preflight, preserved data and descriptors\n')
	}
}
