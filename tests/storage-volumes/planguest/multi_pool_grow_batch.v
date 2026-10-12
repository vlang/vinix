// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn multi_pool_growth(path &char, first_pool &char, first_slot &char, first_length &char,
	second_pool &char, second_slot &char, second_length &char, preview bool, expected i32, output &char) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'), if preview { &char(c'pool-preview-grow-set-batch') } else { &char(c'pool-grow-set-batch') },
			path, first_pool, first_slot, first_length, second_pool, second_slot, second_length, &char(nil)]!
		if output == nil { run_utility(&args[0], expected); return }
		fd := C.open(c'/root/multi-growth-output', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600)); check(fd >= 0, c'open multi-pool growth output')
		child := C.fork(); check(child >= 0, c'fork multi-pool growth')
		if child == 0 {
			if C.dup2(fd, 1) != 1 || C.dup2(fd, 2) != 2 || C.close(fd) != 0 { C._exit(126) }
			C.execv(args[0], &args[0]); C._exit(127)
		}
		mut code := i32(0); check(C.close(fd) == 0 && C.waitpid(child, &code, 0) == child && code == expected << 8, c'multi-pool growth exit')
		input := C.open(c'/root/multi-growth-output', C.O_RDONLY); size := C.read(input, output, 4095)
		check(input >= 0 && size > 0 && size < 4095 && C.close(input) == 0, c'read multi-pool growth output'); output[size] = 0
	}
}

@[direct_array_access]
fn multi_pool_grown_data(parent &char, other &char) {
	unsafe {
		for path in [&char(c'/dev/mapper/vinix20'), &char(c'/dev/mapper/vinix19')]! {
			primary := C.strcmp(path, c'/dev/mapper/vinix20') == 0; info := status(path)
			check(info.start == 11534336 && info.bytes == 8192 && info.flags & 1 == if primary { u64(0) } else { u64(1) }
				&& info.disk_id == status(if primary { parent } else { other }).disk_id, c'multi-pool grown geometry and mode')
			fd := C.open(path, C.O_RDONLY); mut data := [8192]u8{}
			check(fd >= 0 && C.pread(fd, &data[0], 8192, 0) == 8192 && C.close(fd) == 0, c'read complete multi-pool grown data')
			for i in 0 .. 8192 {
				byte := if i < 4096 { if primary { u8(0xa7) } else { u8(0xa8) } } else { if primary { u8(0xa9) } else { u8(0xaa) } }
				check(data[i] == byte, c'multi-pool old and extension data preserved')
			}
		}
	}
}

@[direct_array_access]
fn planned_multi_pool_growth(parent &char, other &char) {
	unsafe {
		fd := C.open(c'/root/saved.vset', C.O_RDONLY); mut baseline := [8768]u8{}; size := C.read(fd, &baseline[0], 8768)
		check(fd >= 0 && size == 576 && C.close(fd) == 0, c'multi-pool growth baseline')
		first := status(c'/dev/mapper/vinix20'); second := status(c'/dev/mapper/vinix19')
		held_first := C.open(c'/dev/mapper/vinix20', C.O_RDWR); held_second := C.open(c'/dev/mapper/vinix19', C.O_RDONLY)
		check(held_first >= 0 && held_second >= 0 && first.bytes == 4096 && second.bytes == 4096, c'hold multi-pool growth views')
		for disk in [parent, other]! {
			raw := C.open(disk, C.O_RDWR); mut data := [4096]u8{init: if disk == parent { u8(0xa9) } else { u8(0xaa) }}
			check(raw >= 0 && C.pwrite(raw, &data[0], 4096, 11538432) == 4096 && C.fsync(raw) == 0 && C.close(raw) == 0, c'prepare multi-pool extension data')
		}
		mut output := [4096]char{}
		for preview in [false, true]! {
			multi_pool_growth(c'/root/saved.vset', c'7', c'20', c'8192', c'8', c'19', c'16384', preview, 1, &output[0])
			check(!contains(&output[0], c'action='), c'later multi-pool growth failure emits no prefix'); bundle_unchanged(c'/root/saved.vset', &baseline[0], size)
			multi_pool_growth(c'/root/saved.vset', c'7', c'20', c'8192', c'9', c'19', c'8192', preview, 1, &output[0]); bundle_unchanged(c'/root/saved.vset', &baseline[0], size)
			multi_pool_growth(c'/root/saved.vset', c'7', c'20', c'8192', c'8', c'20', c'8192', preview, 1, &output[0]); bundle_unchanged(c'/root/saved.vset', &baseline[0], size)
		}
		directory := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
		check(directory >= 0 && C.flock(directory, C.LOCK_EX | C.LOCK_NB) == 0, c'hold multi-pool growth writer lock')
		multi_pool_growth(c'/root/saved.vset', c'7', c'20', c'8192', c'8', c'19', c'8192', false, 1, &output[0])
		multi_pool_growth(c'/root/saved.vset', c'7', c'20', c'8192', c'8', c'19', c'8192', true, 0, &output[0])
		check(contains(&output[0], c'request=0 pool=7 disk=0 slot=20 action=grow offset=11534336 previous_bytes=4096 bytes=8192 readonly=0')
			&& contains(&output[0], c'request=1 pool=8 disk=1 slot=19 action=grow offset=11534336 previous_bytes=4096 bytes=8192 readonly=1'), c'complete cross-pool growth preview under writer contention')
		bundle_unchanged(c'/root/saved.vset', &baseline[0], size); check(C.close(directory) == 0, c'release multi-pool growth writer lock')
		multi_pool_growth(c'/root/saved.vset', c'7', c'20', c'8192', c'8', c'19', c'8192', false, 0, nil)
		check(status(c'/dev/mapper/vinix20').bytes == 4096 && status(c'/dev/mapper/vinix19').bytes == 4096, c'multi-pool growth planning stays offline')
		planned := C.open(c'/root/saved.vset', C.O_RDONLY); mut complete := [8768]u8{}; complete_size := C.read(planned, &complete[0], 8768)
		check(planned >= 0 && complete_size == size && C.close(planned) == 0, c'capture complete multi-pool growth')
		simple(c'restore-bundle', c'/root/saved.vset', nil, 1)
		tool(c'create', other, c'21', c'11538432', c'4096', 0)
		preview(c'check-bundle', true, 1, &output[0]); check(!contains(&output[0], c'action='), c'later live conflict rejects complete multi-pool growth preview')
		tool(c'restore-bundle', c'/root/saved.vset', c'grow', nil, nil, 1)
		check(status(c'/dev/mapper/vinix20').bytes == 4096 && status(c'/dev/mapper/vinix19').bytes == 4096, c'preflight failure prevents either live growth')
		simple(c'remove', c'/dev/mapper/vinix21', nil, 0); tool(c'restore-bundle', c'/root/saved.vset', c'grow', nil, nil, 0)
		check(status(c'/dev/mapper/vinix20').generation == first.generation && status(c'/dev/mapper/vinix19').generation == second.generation, c'multi-pool replay preserves generations')
		mut data := [4096]u8{}
		check(C.pread(held_first, &data[0], 4096, 4096) == 4096 && C.close(held_first) == 0, c'held writable descriptor reads multi-pool extension')
		for byte in data { check(byte == 0xa9, c'held writable extension data') }
		check(C.pread(held_second, &data[0], 4096, 4096) == 4096 && C.close(held_second) == 0, c'held readonly descriptor reads multi-pool extension')
		for byte in data { check(byte == 0xaa, c'held readonly extension data') }
		multi_pool_grown_data(parent, other)
		multi_pool_growth(c'/root/saved.vset', c'8', c'19', c'8192', c'7', c'20', c'8192', false, 0, &output[0])
		check(contains(&output[0], c'request=0 pool=8 disk=1 slot=19 action=keep') && contains(&output[0], c'request=1 pool=7 disk=0 slot=20 action=keep'), c'complete reverse-order multi-pool growth retry')
		bundle_unchanged(c'/root/saved.vset', &complete[0], complete_size)
		C.printf(c'PLAN MULTI POOL GROWTH PASSED: whole-set rollback, writer contention, complete live preflight, retained generations and held extensions\n')
	}
}

fn multi_pool_growth_boot_prepare() {
	unsafe {
		copy_plan(c'/etc/vinix/volumes.vset', c'/root/multi-pool-final.vset')
		multi_pool_growth(c'/etc/vinix/volumes.vset', c'8', c'19', c'8192', c'7', c'20', c'8192', true, 0, nil)
		multi_pool_growth(c'/etc/vinix/volumes.vset', c'8', c'19', c'8192', c'7', c'20', c'8192', false, 0, nil)
		copy_plan(c'/etc/vinix/volumes.vset', c'/root/multi-growth-planned.vset')
		marker := C.open(c'/multi-pool-growth-boot', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
		check(marker >= 0 && C.write(marker, c'1', 1) == 1 && C.fsync(marker) == 0 && C.close(marker) == 0, c'persist multi-pool growth marker')
		directory := C.open(c'/', C.O_RDONLY | C.O_DIRECTORY); check(directory >= 0 && C.fsync(directory) == 0 && C.close(directory) == 0, c'persist multi-pool growth phase directory')
		C.printf(c'PLAN MULTI POOL GROWTH SAVED: two-pool in-place growth, unchanged nine mapping starts/modes and member priority\n')
	}
}

@[direct_array_access]
fn multi_pool_growth_boot_phase(parent &char, other &char) {
	unsafe {
		check(C.getppid() == 1 && status(parent).bytes == 20971520 && status(other).bytes == 16777216, c'multi-pool growth production boot geometry')
		fd := C.open(c'/etc/vinix/volumes.vset', C.O_RDONLY); mut bytes := [8768]u8{}; size := C.read(fd, &bytes[0], 8768)
		check(fd >= 0 && size == 680 && C.close(fd) == 0, c'persistent nine-row grown multi-pool bundle')
		copy_plan(c'/etc/vinix/volumes.vset', c'/root/multi-growth-boot.vset'); copy_plan(c'/etc/vinix/volumes.vset', c'/root/saved.vset')
		grown_view_data(); edited_view_data(); capacity_view_data(); pool_batch_boot_check(parent); multi_pool_grown_data(parent, other)
		first := status(c'/dev/mapper/vinix20').generation; second := status(c'/dev/mapper/vinix19').generation; mut output := [4096]char{}
		multi_pool_growth(c'/etc/vinix/volumes.vset', c'7', c'20', c'8192', c'8', c'19', c'8192', false, 0, nil)
		multi_pool_growth(c'/etc/vinix/volumes.vset', c'7', c'20', c'8192', c'8', c'19', c'8192', true, 0, &output[0])
		check(contains(&output[0], c'request=0 pool=7 disk=0 slot=20 action=keep offset=11534336 previous_bytes=8192 bytes=8192 readonly=0')
			&& contains(&output[0], c'request=1 pool=8 disk=1 slot=19 action=keep offset=11534336 previous_bytes=8192 bytes=8192 readonly=1'), c'boot complete two-pool growth keep report')
		bundle_unchanged(c'/etc/vinix/volumes.vset', &bytes[0], size); simple(c'boot-restore', nil, nil, 0)
		check(status(c'/dev/mapper/vinix20').generation == first && status(c'/dev/mapper/vinix19').generation == second, c'boot multi-pool growth retries preserve live generations')
		C.printf(c'PLAN MULTI POOL GROWTH BOOT PRESERVED\n')
	}
}
