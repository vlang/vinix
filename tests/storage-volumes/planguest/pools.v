// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn pool_add(path &char, pool &char, disk &char, start &char, end &char, alignment &char, expected i32) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'), &char(c'pool-add'), path, pool, disk, start,
			end, alignment, &char(nil)]!
		run_utility(&args[0], expected)
	}
}

fn pool_allocate(path &char, pool &char, slot &char, length &char, readonly bool, expected i32) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'), &char(c'pool-allocate'), path, pool, slot, length,
			if readonly { &char(c'ro') } else { &char(nil) }, &char(nil)]!
		run_utility(&args[0], expected)
	}
}

fn pool_members(path &char) {
	pool_add(path, c'3', c'0', c'6291456', c'6295552', c'4096', 0)
	pool_add(path, c'3', c'1', c'6291456', c'6303744', c'4096', 0)
}

fn pool_preview(path &char, expected i32, output &char) {
	fd := C.open(c'/root/pool-output', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600))
	check(fd >= 0, c'open pool output')
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'), &char(c'pool-space'), path, &char(c'3'), &char(nil)]!
		child := C.fork()
		check(child >= 0, c'fork pool preview')
		if child == 0 {
			if C.dup2(fd, 1) != 1 || C.dup2(fd, 2) != 2 || C.close(fd) != 0 { C._exit(126) }
			C.execv(args[0], &args[0])
			C._exit(127)
		}
		mut code := i32(0)
		check(C.close(fd) == 0 && C.waitpid(child, &code, 0) == child && code == expected << 8, c'pool preview exit')
	}
	input := C.open(c'/root/pool-output', C.O_RDONLY)
	count := C.read(input, output, 4095)
	check(input >= 0 && count > 0 && count < 4095 && C.close(input) == 0, c'read pool output')
	unsafe { output[count] = 0 }
}

fn pool_boot_check() {
	mut output := [4096]char{}
	pool_preview(c'/etc/vinix/volumes.vset', 0, &output[0])
	check(contains(&output[0], c'pool=3 disk=0 start=6291456 end=6295552 alignment=4096')
		&& contains(&output[0], c'pool=3 disk=1 start=6291456 end=6303744 alignment=4096')
		&& contains(&output[0], c'pool=3 regions=2 gaps=2 bytes=16384 largest=12288'),
		c'pool definitions survive boot and physical device reorder')
	C.printf(c'PLAN POOL BOOT PRESERVED\n')
}

@[direct_array_access]
fn planned_pools(parent &char, other &char) {
	unsafe {
		fd := C.open(c'/root/saved.vset', C.O_RDONLY)
		mut baseline := [8768]u8{}
		size := C.read(fd, &baseline[0], 8768)
		check(fd >= 0 && size == 352 && C.close(fd) == 0, c'pool V1 baseline')
		pool_members(c'/root/saved.vset')
		v2 := C.open(c'/root/saved.vset', C.O_RDONLY)
		mut configured := [8768]u8{}
		configured_size := C.read(v2, &configured[0], 8768)
		check(v2 >= 0 && configured_size == 432 && C.close(v2) == 0
			&& configured[7] == `2`, c'pool V2 atomic configuration')
		mut output := [4096]char{}
		pool_preview(c'/root/saved.vset', 0, &output[0])
		check(contains(&output[0], c'pool=3 regions=2 gaps=2 bytes=16384 largest=12288'), c'pool aggregate free capacity')
		pool_add(c'/root/saved.vset', c'3', c'0', c'6291456', c'6295552', c'4096', 1)
		pool_add(c'/root/saved.vset', c'4', c'0', c'6291456', c'6303744', c'4096', 1)
		pool_add(c'/root/saved.vset', c'4', c'2', c'6291456', c'6303744', c'4096', 1)
		pool_allocate(c'/root/saved.vset', c'4', c'14', c'4096', true, 1)
		pool_allocate(c'/root/saved.vset', c'3', c'9', c'4096', true, 1)
		pool_allocate(c'/root/saved.vset', c'3', c'14', c'16384', true, 1)
		bundle_unchanged(c'/root/saved.vset', &configured[0], configured_size)
		raw := C.open(other, C.O_RDWR)
		mut bytes := [4096]u8{init: 0xb8}
		check(raw >= 0 && C.pwrite(raw, &bytes[0], 4096, 6291456) == 4096
			&& C.pwrite(raw, &bytes[0], 4096, 6295552) == 4096 && C.fsync(raw) == 0
			&& C.close(raw) == 0, c'prepare second pool member data')
		generation := status(c'/dev/mapper/vinix2').generation
		pool_allocate(c'/root/saved.vset', c'3', c'14', c'8192', true, 0)
		missing(c'/dev/mapper/vinix14')
		preview(c'show-bundle', false, 0, &output[0])
		check(contains(&output[0], c'disk=1 slot=14 offset=6291456 bytes=8192 readonly=1'), c'pool allocation skips small first member')
		// Offline capacity is not a live reservation. A conflict on the selected
		// later disk must prevent every mapping action in complete-set preflight.
		tool(c'create', other, c'16', c'6291456', c'4096', 0)
		preview(c'check-bundle', false, 1, &output[0])
		check(!contains(&output[0], c'action='), c'pool live conflict has no preview actions')
		simple(c'restore-bundle', c'/root/saved.vset', &char(nil), 1)
		missing(c'/dev/mapper/vinix14')
		check(status(c'/dev/mapper/vinix2').generation == generation, c'failed pool preflight preserves generation')
		simple(c'remove', c'/dev/mapper/vinix16', &char(nil), 0)
		simple(c'restore-bundle', c'/root/saved.vset', &char(nil), 0)
		allocated := status(c'/dev/mapper/vinix14')
		check(allocated.disk_id == status(other).disk_id && allocated.bytes == 8192 && allocated.flags & 1 == 1,
			c'pool mapping uses selected physical disk and mode')
		held := C.open(c'/dev/mapper/vinix14', C.O_RDONLY)
		check(held >= 0 && C.pread(held, &bytes[0], 4096, 0) == 4096, c'hold pool allocation')
		for byte in bytes { check(byte == 0xb8, c'pool allocation preserves physical data') }
		tool(c'pool-remove', c'/root/saved.vset', c'3', c'1', &char(nil), 0)
		simple(c'restore-bundle', c'/root/saved.vset', &char(nil), 0)
		check(status(c'/dev/mapper/vinix14').generation == allocated.generation
			&& C.pread(held, &bytes[0], 4096, 4096) == 4096 && C.close(held) == 0,
			c'pool membership removal retains desired mapping and open descriptor')
		for byte in bytes { check(byte == 0xb8, c'held pool descriptor keeps second page') }
		pool_add(c'/root/saved.vset', c'3', c'1', c'6291456', c'6303744', c'4096', 0)
		pool_allocate(c'/root/saved.vset', c'3', c'15', c'4096', false, 0)
		preview(c'show-bundle', false, 0, &output[0])
		check(contains(&output[0], c'disk=0 slot=15 offset=6291456 bytes=4096 readonly=0'), c'pool allocation follows saved member order')
		simple(c'plan-remove', c'/root/saved.vset', c'15', 0)
		simple(c'plan-remove', c'/root/saved.vset', c'14', 0)
		simple(c'remove', c'/dev/mapper/vinix14', &char(nil), 0)
		missing(c'/dev/mapper/vinix14')
		missing(c'/dev/mapper/vinix15')
		bundle_unchanged(c'/root/saved.vset', &configured[0], configured_size)
		tool(c'pool-remove', c'/root/saved.vset', c'3', c'0', &char(nil), 0)
		tool(c'pool-remove', c'/root/saved.vset', c'3', c'1', &char(nil), 0)
		bundle_unchanged(c'/root/saved.vset', &baseline[0], size)
		pool_members(c'/root/saved.vset')
		bundle_unchanged(c'/root/saved.vset', &configured[0], configured_size)
		check(status(c'/dev/mapper/vinix2').generation == generation
			&& status(c'/dev/mapper/vinix2').disk_id == status(parent).disk_id, c'pool edits preserve old mappings')
		copy_plan(c'/root/saved.vset', c'/etc/vinix/volumes.vset')
		C.printf(c'PLAN POOLS PASSED: atomic persistent regions, aggregate capacity, cross-disk first fit and retained mappings\n')
	}
}
