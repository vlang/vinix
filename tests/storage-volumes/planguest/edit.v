// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn planning_add(path &char, disk &char, slot &char, offset &char, length &char, readonly bool, expected i32) {
	unsafe {
		arguments := [&char(c'/usr/sbin/vinix-volume'), &char(c'plan-add'), path, disk, slot, offset,
			length, if readonly { &char(c'ro') } else { &char(nil) }, &char(nil)]!
		run_utility(&arguments[0], expected)
	}
}

@[direct_array_access]
fn edited_view_data() {
	check(status(c'/dev/mapper/vinix12').bytes == 4096
		&& status(c'/dev/mapper/vinix12').flags & 1 == 1
		&& status(c'/dev/mapper/vinix13').bytes == 4096, c'planned mappings restored')
	mut bytes := [4096]u8{}
	readonly := C.open(c'/dev/mapper/vinix12', C.O_RDONLY)
	check(readonly >= 0 && C.pread(readonly, &bytes[0], 4096, 0) == 4096 && C.close(readonly) == 0,
		c'read planned read-only mapping')
	for byte in bytes {
		check(byte == 0xe7, c'planned read-only extent preserves raw data')
	}
	check(C.open(c'/dev/mapper/vinix12', C.O_RDWR) < 0 && unsafe { C.errno == C.EROFS },
		c'planned read-only mapping refuses write access')
	writable := C.open(c'/dev/mapper/vinix13', C.O_RDONLY)
	check(writable >= 0 && C.pread(writable, &bytes[0], 4096, 0) == 4096 && C.close(writable) == 0,
		c'read planned writable mapping')
	for byte in bytes {
		check(byte == 0xa6, c'planned writable extent preserves durable data')
	}
}

@[direct_array_access]
fn planned_mappings(parent &char, other &char) {
	unsafe {
		// Offline configuration must not format or rewrite the selected extents.
		raw := C.open(parent, C.O_RDWR)
		mut bytes := [4096]u8{init: 0xe7}
		check(raw >= 0 && C.pwrite(raw, &bytes[0], 4096, 4194304) == 4096 && C.fsync(raw) == 0
			&& C.close(raw) == 0, c'prepare planned raw data')
		first := status(c'/dev/mapper/vinix2').generation
		planning_add(c'/root/saved.vset', c'1', c'13', c'3145728', c'4096', false, 0)
		planning_add(c'/root/saved.vset', c'0', c'12', c'4194304', c'4096', true, 0)
		missing(c'/dev/mapper/vinix12')
		missing(c'/dev/mapper/vinix13')
		fd := C.open(c'/root/saved.vset', C.O_RDONLY)
		mut planned := [6208]u8{}
		size := C.read(fd, &planned[0], 6208)
		check(fd >= 0 && size == 352 && C.close(fd) == 0, c'read five-mapping plan')
		planning_add(c'/root/saved.vset', c'0', c'13', c'5242880', c'4096', false, 1)
		planning_add(c'/root/saved.vset', c'0', c'14', c'4194304', c'4096', false, 1)
		planning_add(c'/root/saved.vset', c'2', c'14', c'6291456', c'4096', false, 1)
		planning_add(c'/root/saved.vset', c'0', c'14', c'6291457', c'4096', false, 1)
		bundle_unchanged(c'/root/saved.vset', &planned[0], size)
		mut output := [4096]char{}
		preview(c'show-bundle', false, 0, &output[0])
		check(contains(&output[0], c'slot=12 offset=4194304 bytes=4096 readonly=1')
			&& contains(&output[0], c'disks=2 mappings=5'), c'inspect offline additions')
		preview(c'check-bundle', false, 0, &output[0])
		check(contains(&output[0], c'slot=12 action=create')
			&& contains(&output[0], c'slot=13 action=create')
			&& contains(&output[0], c'checked disks=2 create=2 keep=3 grow=0'),
			c'preview planned additions')
		missing(c'/dev/mapper/vinix12')
		missing(c'/dev/mapper/vinix13')
		// A conflicting later disk and an unlisted extent both block any prefix.
		tool(c'create', other, c'13', c'5242880', c'4096', 0)
		preview(c'check-bundle', false, 1, &output[0])
		check(!contains(&output[0], c'action='), c'planned later conflict has no actions')
		simple(c'restore-bundle', c'/root/saved.vset', &char(nil), 1)
		missing(c'/dev/mapper/vinix12')
		simple(c'remove', c'/dev/mapper/vinix13', &char(nil), 0)
		tool(c'create', parent, c'14', c'4194304', c'4096', 0)
		simple(c'restore-bundle', c'/root/saved.vset', &char(nil), 1)
		missing(c'/dev/mapper/vinix12')
		missing(c'/dev/mapper/vinix13')
		simple(c'remove', c'/dev/mapper/vinix14', &char(nil), 0)
		bundle_unchanged(c'/root/saved.vset', &planned[0], size)
		check(status(c'/dev/mapper/vinix2').generation == first,
			c'planning preserves old generation')
		simple(c'restore-bundle', c'/root/saved.vset', &char(nil), 0)
		view := C.open(c'/dev/mapper/vinix13', C.O_RDWR)
		for i in 0 .. 4096 {
			bytes[i] = 0xa6
		}
		check(view >= 0 && C.pwrite(view, &bytes[0], 4096, 0) == 4096 && C.fsync(view) == 0
			&& C.close(view) == 0, c'write planned writable data')
		edited_view_data()
		readonly_generation := status(c'/dev/mapper/vinix12').generation
		writable_generation := status(c'/dev/mapper/vinix13').generation
		held := C.open(c'/dev/mapper/vinix12', C.O_RDONLY)
		check(held >= 0, c'hold mapping across planned removal')
		simple(c'plan-remove', c'/root/saved.vset', c'12', 0)
		preview(c'check-bundle', false, 0, &output[0])
		check(!contains(&output[0], c'slot=12 action=')
			&& contains(&output[0], c'checked disks=2 create=0 keep=4 grow=0'),
			c'omitted entry is absent from replay actions')
		simple(c'restore-bundle', c'/root/saved.vset', &char(nil), 0)
		check(status(c'/dev/mapper/vinix12').generation == readonly_generation
			&& C.pread(held, &bytes[0], 4096, 0) == 4096 && C.close(held) == 0,
			c'planned removal preserves live mapping and descriptor')
		for byte in bytes {
			check(byte == 0xe7, c'held descriptor data after planned removal')
		}
		planning_add(c'/root/saved.vset', c'0', c'12', c'4194304', c'4096', true, 0)
		bundle_unchanged(c'/root/saved.vset', &planned[0], size)
		simple(c'restore-bundle', c'/root/saved.vset', &char(nil), 0)
		check(status(c'/dev/mapper/vinix12').generation == readonly_generation
			&& status(c'/dev/mapper/vinix13').generation == writable_generation,
			c'reenrollment keeps existing generations')
		tool(c'save-set', c'/etc/vinix/volumes.vset', parent, other, &char(nil), 0)
		C.printf(c'PLAN EDIT PASSED: offline additions, removal, complete preflight, preserved data and live generations\n')
	}
}
