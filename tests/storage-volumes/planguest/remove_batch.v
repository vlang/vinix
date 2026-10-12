// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn mapping_removals(path &char, first &char, second &char, third &char, preview bool, expected i32, output &char) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'),
			if preview { &char(c'plan-preview-remove-batch') } else { &char(c'plan-remove-batch') },
			path, first, second, third, &char(nil)]!
		if output == nil { run_utility(&args[0], expected); return }
		fd := C.open(c'/root/removal-output', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600))
		check(fd >= 0, c'open removal output')
		child := C.fork(); check(child >= 0, c'fork removal command')
		if child == 0 {
			if C.dup2(fd, 1) != 1 || C.dup2(fd, 2) != 2 || C.close(fd) != 0 { C._exit(126) }
			C.execv(args[0], &args[0]); C._exit(127)
		}
		mut code := i32(0)
		check(C.close(fd) == 0 && C.waitpid(child, &code, 0) == child && code == expected << 8, c'removal command exit')
		input := C.open(c'/root/removal-output', C.O_RDONLY)
		count := C.read(input, output, 4095)
		check(input >= 0 && count > 0 && count < 4095 && C.close(input) == 0, c'read removal output')
		output[count] = 0
	}
}

@[direct_array_access]
fn planned_mapping_removals(parent &char, other &char) {
	unsafe {
		fd := C.open(c'/root/saved.vset', C.O_RDONLY)
		mut original := [8768]u8{}
		size := C.read(fd, &original[0], 8768)
		check(fd >= 0 && size == 432 && C.close(fd) == 0, c'removal baseline')
		copy_plan(c'/root/saved.vset', c'/root/removal-baseline.vset')
		first := status(c'/dev/mapper/vinix12'); second := status(c'/dev/mapper/vinix13')
		check(first.disk_id == status(parent).disk_id && second.disk_id == status(other).disk_id, c'removal selects both physical disks')
		held := C.open(c'/dev/mapper/vinix12', C.O_RDONLY)
		check(held >= 0, c'hold view across batch removal')
		mut output := [4096]char{}
		for preview in [false, true]! {
			mapping_removals(c'/root/saved.vset', c'12', c'13', c'12', preview, 1, &output[0])
			check(!contains(&output[0], c'action='), c'later duplicate has no partial actions')
			mapping_removals(c'/root/saved.vset', c'12', c'13', c'64', preview, 2, nil)
			bundle_unchanged(c'/root/saved.vset', &original[0], size)
		}
		directory := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
		check(directory >= 0 && C.flock(directory, C.LOCK_EX | C.LOCK_NB) == 0, c'hold removal writer lock')
		mapping_removals(c'/root/saved.vset', c'13', c'63', c'12', false, 1, &output[0])
		mapping_removals(c'/root/saved.vset', c'13', c'63', c'12', true, 0, &output[0])
		check(contains(&output[0], c'request=0 disk=1 slot=13 action=remove offset=3145728 bytes=4096 readonly=0')
			&& contains(&output[0], c'request=1 slot=63 action=keep')
			&& contains(&output[0], c'request=2 disk=0 slot=12 action=remove offset=4194304 bytes=4096 readonly=1'), c'complete cross-disk removal preview under writer lock')
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		check(C.close(directory) == 0, c'release removal writer lock')
		mapping_removals(c'/root/saved.vset', c'13', c'63', c'12', false, 0, nil)
		changed := C.open(c'/root/saved.vset', C.O_RDONLY)
		mut removed := [8768]u8{}
		check(changed >= 0 && C.read(changed, &removed[0], 8768) == size - 64 && C.close(changed) == 0, c'capture complete removal')
		mapping_removals(c'/root/saved.vset', c'13', c'63', c'12', false, 0, &output[0])
		check(contains(&output[0], c'request=0 slot=13 action=keep') && contains(&output[0], c'request=1 slot=63 action=keep')
			&& contains(&output[0], c'request=2 slot=12 action=keep'), c'durable absent removal retry')
		bundle_unchanged(c'/root/saved.vset', &removed[0], size - 64)
		preview(c'check-bundle', false, 0, &output[0])
		check(contains(&output[0], c'checked disks=2 create=0 keep=3 grow=0') && !contains(&output[0], c'slot=12 action=')
			&& !contains(&output[0], c'slot=13 action='), c'removed desired rows are omitted from replay')
		simple(c'restore-bundle', c'/root/saved.vset', nil, 0)
		check(status(c'/dev/mapper/vinix12').generation == first.generation && status(c'/dev/mapper/vinix13').generation == second.generation,
			c'cross-disk desired removals preserve live generations')
		mut bytes := [4096]u8{}
		check(C.pread(held, &bytes[0], 4096, 0) == 4096 && C.close(held) == 0, c'held removed desired view readable')
		for byte in bytes { check(byte == 0xe7, c'batch removal preserves disk data') }
		// Reusing a freed desired slot cannot bypass a conflicting live view.
		planning_add(c'/root/saved.vset', c'0', c'14', c'8388608', c'4096', false, 0)
		planning_add(c'/root/saved.vset', c'1', c'12', c'5242880', c'4096', true, 0)
		preview(c'check-bundle', false, 1, &output[0])
		check(!contains(&output[0], c'action='), c'live slot reuse conflict has no prefix actions')
		simple(c'restore-bundle', c'/root/saved.vset', nil, 1)
		missing(c'/dev/mapper/vinix14')
		check(status(c'/dev/mapper/vinix12').generation == first.generation && status(c'/dev/mapper/vinix13').generation == second.generation,
			c'failed reused-slot application preserves live generations')
		copy_plan(c'/root/removal-baseline.vset', c'/root/saved.vset')
		check(C.unlink(c'/root/removal-baseline.vset') == 0, c'removal baseline cleanup')
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		simple(c'restore-bundle', c'/root/saved.vset', nil, 0)
		edited_view_data()
		C.printf(c'PLAN REMOVAL BATCH PASSED: complete cross-disk previews, rollback, durable absent retries, live preflight and retained views\n')
	}
}

fn removal_boot_prepare() {
	fd := C.open(c'/root/saved.vset', C.O_RDONLY)
	mut original := [8768]u8{}
	size := C.read(fd, &original[0], 8768)
	check(fd >= 0 && size == 536 && C.close(fd) == 0, c'boot removal baseline')
	planning_add(c'/root/saved.vset', c'0', c'19', c'8388608', c'4096', false, 0)
	planning_add(c'/root/saved.vset', c'1', c'20', c'8388608', c'4096', true, 0)
	mapping_removals(c'/root/saved.vset', c'20', c'19', unsafe { nil }, true, 0, unsafe { nil })
	mapping_removals(c'/root/saved.vset', c'20', c'19', unsafe { nil }, false, 0, unsafe { nil })
	bundle_unchanged(c'/root/saved.vset', &original[0], size)
	missing(c'/dev/mapper/vinix19'); missing(c'/dev/mapper/vinix20')
	C.printf(c'PLAN REMOVAL BATCH SAVED: both desired rows removed before persistent boot replay\n')
}

fn removal_boot_check() {
	fd := C.open(c'/etc/vinix/volumes.vset', C.O_RDONLY)
	mut original := [8768]u8{}
	size := C.read(fd, &original[0], 8768)
	check(fd >= 0 && size == 536 && C.close(fd) == 0, c'persistent removal bundle')
	missing(c'/dev/mapper/vinix19'); missing(c'/dev/mapper/vinix20')
	mut output := [4096]char{}
	mapping_removals(c'/etc/vinix/volumes.vset', c'20', c'19', unsafe { nil }, true, 0, &output[0])
	check(contains(&output[0], c'request=0 slot=20 action=keep') && contains(&output[0], c'request=1 slot=19 action=keep'), c'removal absence survives boot')
	mapping_removals(c'/etc/vinix/volumes.vset', c'20', c'19', unsafe { nil }, false, 0, unsafe { nil })
	bundle_unchanged(c'/etc/vinix/volumes.vset', &original[0], size)
	C.printf(c'PLAN REMOVAL BATCH BOOT PRESERVED\n')
}
