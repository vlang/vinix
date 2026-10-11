// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn pool_growth(path &char, command &char, pool &char, index &char, size &char, expected i32) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'), command, path, pool, index, size, &char(nil)]!
		run_utility(&args[0], expected)
	}
}

fn pool_growth_boot_check() {
	mut output := [4096]char{}
	pool_preview_for(c'/etc/vinix/volumes.vset', c'4', 0, &output[0])
	check(contains(&output[0], c'pool=4 disk=0 start=16777216 end=25165824 alignment=4096')
		&& contains(&output[0], c'pool=4 regions=1 gaps=1 bytes=8376320 largest=8376320'),
		c'expanded tail pool and grown mapping survive boot')
	C.printf(c'PLAN POOL GROWTH BOOT PRESERVED\n')
}

@[direct_array_access]
fn planned_pool_growth(parent &char) {
	unsafe {
		fd := C.open(c'/root/saved.vset', C.O_RDONLY)
		mut baseline := [8768]u8{}
		size := C.read(fd, &baseline[0], 8768)
		check(fd >= 0 && size == 432 && C.close(fd) == 0, c'pool growth baseline')
		pool_growth(c'/root/saved.vset', c'pool-expand', c'3', c'0', c'6295040', 1)
		pool_growth(c'/root/saved.vset', c'pool-expand', c'3', c'0', c'6295553', 1)
		pool_growth(c'/root/saved.vset', c'pool-expand', c'3', c'0', c'16777728', 1)
		pool_growth(c'/root/saved.vset', c'pool-expand', c'3', c'2', c'6299648', 1)
		pool_growth(c'/root/saved.vset', c'pool-grow', c'3', c'2', c'8192', 1)
		pool_growth(c'/root/saved.vset', c'pool-grow', c'3', c'14', c'8192', 1)
		bundle_unchanged(c'/root/saved.vset', &baseline[0], size)
		pool_growth(c'/root/saved.vset', c'pool-expand', c'3', c'0', c'6299648', 0)
		mut output := [4096]char{}
		pool_preview(c'/root/saved.vset', 0, &output[0])
		check(contains(&output[0], c'pool=3 regions=2 gaps=2 bytes=20480 largest=12288'), c'expansion adds eligible capacity')
		raw := C.open(parent, C.O_RDWR)
		mut data := [4096]u8{init: 0xba}
		check(raw >= 0 && C.pwrite(raw, &data[0], 4096, 6291456) == 4096
			&& C.pwrite(raw, &data[0], 4096, 6295552) == 4096 && C.fsync(raw) == 0
			&& C.close(raw) == 0, c'prepare pool growth data')
		pool_allocate(c'/root/saved.vset', c'3', c'14', c'4096', true, 0)
		missing(c'/dev/mapper/vinix14')
		simple(c'restore-bundle', c'/root/saved.vset', &char(nil), 0)
		info := status(c'/dev/mapper/vinix14')
		check(info.disk_id == status(parent).disk_id && info.start == 6291456 && info.bytes == 4096 && info.flags & 1 == 1,
			c'expansion retains first-member allocation priority')
		held := C.open(c'/dev/mapper/vinix14', C.O_RDONLY)
		check(held >= 0, c'hold readonly pool mapping')
		pool_growth(c'/root/saved.vset', c'pool-grow', c'3', c'14', c'8192', 0)
		check(status(c'/dev/mapper/vinix14').bytes == 4096, c'pool growth remains offline')
		planned := C.open(c'/root/saved.vset', C.O_RDONLY)
		mut grown := [8768]u8{}
		grown_size := C.read(planned, &grown[0], 8768)
		check(planned >= 0 && grown_size == 464 && C.close(planned) == 0, c'capture planned pool growth')
		for length in [&char(c'4096'), &char(c'8193'), &char(c'12288'), &char(c'18446744073709551615')]! {
			pool_growth(c'/root/saved.vset', c'pool-grow', c'3', c'14', length, 1)
			bundle_unchanged(c'/root/saved.vset', &grown[0], grown_size)
		}
		pool_growth(c'/root/saved.vset', c'pool-grow', c'4', c'14', c'8192', 1)
		bundle_unchanged(c'/root/saved.vset', &grown[0], grown_size)
		simple(c'restore-bundle', c'/root/saved.vset', &char(nil), 1)
		tool(c'create', parent, c'16', c'6295552', c'4096', 0)
		preview(c'check-bundle', true, 1, &output[0])
		check(!contains(&output[0], c'action='), c'pool extension conflict has no preview actions')
		tool(c'restore-bundle', c'/root/saved.vset', c'grow', &char(nil), &char(nil), 1)
		check(status(c'/dev/mapper/vinix14').bytes == 4096 && status(c'/dev/mapper/vinix14').generation == info.generation,
			c'pool conflict leaves existing capacity unchanged')
		simple(c'remove', c'/dev/mapper/vinix16', &char(nil), 0)
		preview(c'check-bundle', true, 0, &output[0])
		check(contains(&output[0], c'slot=14 action=grow'), c'pool growth action preview')
		tool(c'restore-bundle', c'/root/saved.vset', c'grow', &char(nil), &char(nil), 0)
		check(status(c'/dev/mapper/vinix14').bytes == 8192 && status(c'/dev/mapper/vinix14').generation == info.generation
			&& status(c'/dev/mapper/vinix14').flags & 1 == 1 && C.pread(held, &data[0], 4096, 4096) == 4096
			&& C.close(held) == 0, c'pool growth keeps mode generation and held descriptor')
		for byte in data { check(byte == 0xba, c'grown pool data remains intact') }
		pool_growth(c'/root/saved.vset', c'pool-expand', c'3', c'0', c'6299648', 0)
		pool_growth(c'/root/saved.vset', c'pool-grow', c'3', c'14', c'8192', 0)
		bundle_unchanged(c'/root/saved.vset', &grown[0], grown_size)
		simple(c'restore-bundle', c'/root/saved.vset', &char(nil), 0)
		check(status(c'/dev/mapper/vinix14').generation == info.generation, c'pool growth replay is idempotent')
		simple(c'plan-remove', c'/root/saved.vset', c'14', 0)
		simple(c'remove', c'/dev/mapper/vinix14', &char(nil), 0)
		// Restore this fixture's original eligibility and member order for reboot.
		tool(c'pool-remove', c'/root/saved.vset', c'3', c'0', &char(nil), 0)
		tool(c'pool-remove', c'/root/saved.vset', c'3', c'1', &char(nil), 0)
		pool_members(c'/root/saved.vset')
		bundle_unchanged(c'/root/saved.vset', &baseline[0], size)
		copy_plan(c'/root/saved.vset', c'/etc/vinix/volumes.vset')
		C.printf(c'PLAN POOL GROWTH PASSED: stable member order, bounded offline growth, complete preflight and retained readonly descriptors\n')
	}
}
