// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

@[direct_array_access]
fn grown_view_data() {
	check(status(c'/dev/mapper/vinix2').bytes == 8192
		&& status(c'/dev/mapper/vinix5').bytes == 12288
		&& status(c'/dev/mapper/vinix9').bytes == 8192, c'grown capacity preserved')
	view_data()
	second_view_data()
	fd := C.open(c'/dev/mapper/vinix2', C.O_RDONLY)
	mut bytes := [4096]u8{}
	check(fd >= 0 && C.pread(fd, &bytes[0], 4096, 4096) == 4096 && C.close(fd) == 0,
		c'read grown extent')
	for byte in bytes {
		check(byte == 0xd5, c'grown extent data preserved')
	}
}

@[direct_array_access]
fn planned_growth(parent &char, other &char) {
	unsafe {
		// Desired capacity changes independently from live block mappings.
		tool(c'plan-grow', c'/root/saved.vset', c'2', c'8192', &char(nil), 0)
		check(status(c'/dev/mapper/vinix2').bytes == 4096,
			c'capacity planning does not resize live volume')
		fd := C.open(c'/root/saved.vset', C.O_RDONLY)
		mut planned := [6208]u8{}
		size := C.read(fd, &planned[0], 6208)
		check(fd >= 0 && size == 288 && C.close(fd) == 0, c'read capacity plan')
		for length in [&char(c'4096'), &char(c'8193'), &char(c'1049088'),
			&char(c'18446744073709551615')]! {
			tool(c'plan-grow', c'/root/saved.vset', c'2', length, &char(nil), 1)
			bundle_unchanged(c'/root/saved.vset', &planned[0], size)
		}
		tool(c'plan-grow', c'/root/saved.vset', c'12', c'8192', &char(nil), 1)
		bundle_unchanged(c'/root/saved.vset', &planned[0], size)
		check_planned_bundle()
		bundle_unchanged(c'/root/saved.vset', &planned[0], size)
		simple(c'restore-bundle', c'/root/saved.vset', &char(nil), 1)
		check(status(c'/dev/mapper/vinix2').bytes == 4096, c'default restore cannot grow')
		// A conflict on the later disk must not grow the first disk's view.
		simple(c'remove', c'/dev/mapper/vinix9', &char(nil), 0)
		check_missing_bundle()
		tool(c'create', other, c'9', c'3145728', c'4096', 0)
		check_conflicting_bundle()
		tool(c'restore-bundle', c'/root/saved.vset', c'grow', &char(nil), &char(nil), 1)
		check(status(c'/dev/mapper/vinix2').bytes == 4096,
			c'later disk preflight leaves capacity unchanged')
		simple(c'remove', c'/dev/mapper/vinix9', &char(nil), 0)
		tool(c'create', other, c'9', c'1048576', c'4096', 0)
		// An unlisted extent in the extension also blocks growth before mutation.
		tool(c'create', parent, c'12', c'1052672', c'4096', 0)
		check_conflicting_bundle()
		tool(c'restore-bundle', c'/root/saved.vset', c'grow', &char(nil), &char(nil), 1)
		check(status(c'/dev/mapper/vinix2').bytes == 4096,
			c'extension overlap leaves capacity unchanged')
		simple(c'remove', c'/dev/mapper/vinix12', &char(nil), 0)
		tool(c'plan-grow', c'/root/saved.vset', c'5', c'12288', &char(nil), 0)
		tool(c'plan-grow', c'/root/saved.vset', c'9', c'8192', &char(nil), 0)
		first := status(c'/dev/mapper/vinix2').generation
		readonly := status(c'/dev/mapper/vinix5').generation
		second := status(c'/dev/mapper/vinix9').generation
		// This raw descriptor stays open across growth and reaches the new bytes.
		view := C.open(c'/dev/mapper/vinix2', C.O_RDWR)
		check(view >= 0, c'hold mapping descriptor across growth')
		tool(c'restore-bundle', c'/root/saved.vset', c'grow', &char(nil), &char(nil), 0)
		mut info := Status{}
		check(C.ioctl(view, u64(0x56560004), &info) == 0 && info.bytes == 8192
			&& info.generation == first, c'open descriptor retains generation and sees growth')
		mut extension := [4096]u8{init: 0xd5}
		check(C.pwrite(view, &extension[0], 4096, 4096) == 4096 && C.fsync(view) == 0
			&& C.close(view) == 0, c'write and flush grown extent through existing descriptor')
		check(status(c'/dev/mapper/vinix5').generation == readonly
			&& status(c'/dev/mapper/vinix9').generation == second,
			c'growth keeps other generations')
		grown_view_data()
		tool(c'restore-bundle', c'/root/saved.vset', c'grow', &char(nil), &char(nil), 0)
		check(status(c'/dev/mapper/vinix2').generation == first, c'growth replay is idempotent')
		// Publish the resulting geometry for ordinary boot replay after reboot.
		tool(c'save-set', c'/etc/vinix/volumes.vset', parent, other, &char(nil), 0)
		C.printf(c'PLAN GROWTH PASSED: offline planning, complete preflight, in-place capacity and stable descriptors\n')
		C.printf(c'PLAN CHECK PASSED: offline identities, read-only action preview, complete preflight and unchanged mappings\n')
	}
}
