// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn C.strcmp(&char, &char) i32

fn multi_pool_allocations(path &char, first_pool &char, first_slot &char, first_length &char, first_mode &char,
	second_pool &char, second_slot &char, second_length &char, second_mode &char, preview bool, expected i32, output &char) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'), if preview { &char(c'pool-preview-set-batch') } else { &char(c'pool-allocate-set-batch') }, path,
			first_pool, first_slot, first_length, first_mode, second_pool, second_slot, second_length, second_mode, &char(nil)]!
		if output == nil { run_utility(&args[0], expected); return }
		fd := C.open(c'/root/multi-pool-output', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600)); check(fd >= 0, c'open multi-pool output')
		child := C.fork(); check(child >= 0, c'fork multi-pool allocation')
		if child == 0 {
			if C.dup2(fd, 1) != 1 || C.dup2(fd, 2) != 2 || C.close(fd) != 0 { C._exit(126) }
			C.execv(args[0], &args[0]); C._exit(127)
		}
		mut code := i32(0); check(C.close(fd) == 0 && C.waitpid(child, &code, 0) == child && code == expected << 8, c'multi-pool allocation exit')
		input := C.open(c'/root/multi-pool-output', C.O_RDONLY); size := C.read(input, output, 4095)
		check(input >= 0 && size > 0 && size < 4095 && C.close(input) == 0, c'read multi-pool output'); output[size] = 0
	}
}

fn multi_pool_members(path &char) {
	unsafe {
		pool_members_batch(path, c'7', c'0', c'11534336', c'11546624', nil, nil, nil, false, false, 0, nil)
		pool_members_batch(path, c'8', c'1', c'11534336', c'11546624', nil, nil, nil, false, false, 0, nil)
	}
}

@[direct_array_access]
fn multi_pool_data(parent &char, other &char) {
	for path in [&char(c'/dev/mapper/vinix19'), &char(c'/dev/mapper/vinix20')]! {
		info := status(path); readonly := unsafe { C.strcmp(path, c'/dev/mapper/vinix19') == 0 }
		check(info.start == 11534336 && info.bytes == 4096 && info.flags & 1 == if readonly { u64(1) } else { u64(0) }
			&& info.disk_id == status(if readonly { other } else { parent }).disk_id, c'multi-pool placement and mode')
		fd := C.open(path, C.O_RDONLY); mut data := [4096]u8{}
		check(fd >= 0 && C.pread(fd, &data[0], 4096, 0) == 4096 && C.close(fd) == 0, c'read multi-pool data')
		for byte in data { check(byte == if readonly { u8(0xa8) } else { u8(0xa7) }, c'multi-pool retained data') }
	}
}

@[direct_array_access]
fn planned_multi_pool_batch(parent &char, other &char) {
	unsafe {
		fd := C.open(c'/root/saved.vset', C.O_RDONLY); mut original := [8768]u8{}; size := C.read(fd, &original[0], 8768)
		check(fd >= 0 && size == 432 && C.close(fd) == 0, c'multi-pool baseline')
		first := status(c'/dev/mapper/vinix12').generation; held := C.open(c'/dev/mapper/vinix12', C.O_RDONLY); check(held >= 0, c'hold original multi-pool view')
		multi_pool_members(c'/root/saved.vset'); copy_plan(c'/root/saved.vset', c'/root/multi-pool-base.vset')
		base := C.open(c'/root/multi-pool-base.vset', C.O_RDONLY); mut configured := [8768]u8{}; configured_size := C.read(base, &configured[0], 8768)
		check(base >= 0 && configured_size == 512 && C.close(base) == 0, c'multi-pool membership baseline')
		mut output := [4096]char{}
		for preview in [false, true]! {
			multi_pool_allocations(c'/root/saved.vset', c'8', c'19', c'4096', c'ro', c'7', c'20', c'16384', c'rw', preview, 1, &output[0])
			check(!contains(&output[0], c'action='), c'later pool exhaustion emits no prefix'); bundle_unchanged(c'/root/saved.vset', &configured[0], configured_size)
			multi_pool_allocations(c'/root/saved.vset', c'8', c'19', c'4096', c'ro', c'9', c'20', c'4096', c'rw', preview, 1, &output[0])
			bundle_unchanged(c'/root/saved.vset', &configured[0], configured_size)
			multi_pool_allocations(c'/root/saved.vset', c'8', c'19', c'4096', c'ro', c'7', c'19', c'4096', c'rw', preview, 1, &output[0])
			bundle_unchanged(c'/root/saved.vset', &configured[0], configured_size)
		}
		directory := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
		check(directory >= 0 && C.flock(directory, C.LOCK_EX | C.LOCK_NB) == 0, c'hold multi-pool writer lock')
		multi_pool_allocations(c'/root/saved.vset', c'8', c'19', c'4096', c'ro', c'7', c'20', c'4096', c'rw', false, 1, &output[0])
		multi_pool_allocations(c'/root/saved.vset', c'8', c'19', c'4096', c'ro', c'7', c'20', c'4096', c'rw', true, 0, &output[0])
		check(contains(&output[0], c'request=0 pool=8 disk=1 slot=19 action=allocate offset=11534336 bytes=4096 readonly=1')
			&& contains(&output[0], c'request=1 pool=7 disk=0 slot=20 action=allocate offset=11534336 bytes=4096 readonly=0'), c'complete cross-pool preview under writer contention')
		bundle_unchanged(c'/root/saved.vset', &configured[0], configured_size); check(C.close(directory) == 0, c'release multi-pool writer lock')
		for disk in [parent, other]! {
			raw := C.open(disk, C.O_RDWR); mut data := [4096]u8{init: if disk == parent { u8(0xa7) } else { u8(0xa8) }}
			check(raw >= 0 && C.pwrite(raw, &data[0], 4096, 11534336) == 4096 && C.fsync(raw) == 0 && C.close(raw) == 0, c'prepare multi-pool physical data')
		}
		multi_pool_allocations(c'/root/saved.vset', c'8', c'19', c'4096', c'ro', c'7', c'20', c'4096', c'rw', false, 0, nil)
		missing(c'/dev/mapper/vinix19'); missing(c'/dev/mapper/vinix20')
		tool(c'create', parent, c'21', c'11534336', c'4096', 0)
		simple(c'restore-bundle', c'/root/saved.vset', nil, 1); missing(c'/dev/mapper/vinix19'); missing(c'/dev/mapper/vinix20')
		simple(c'remove', c'/dev/mapper/vinix21', nil, 0); simple(c'restore-bundle', c'/root/saved.vset', nil, 0); multi_pool_data(parent, other)
		secondary := status(c'/dev/mapper/vinix19').generation; primary := status(c'/dev/mapper/vinix20').generation
		multi_pool_allocations(c'/root/saved.vset', c'7', c'20', c'4096', c'rw', c'8', c'19', c'4096', c'ro', false, 0, &output[0])
		check(contains(&output[0], c'action=keep') && !contains(&output[0], c'action=allocate'), c'exact reverse-order multi-pool retries')
		check(status(c'/dev/mapper/vinix19').generation == secondary && status(c'/dev/mapper/vinix20').generation == primary, c'multi-pool metadata retains generations')
		planned_multi_pool_growth(parent, other)
		mapping_removals(c'/root/saved.vset', c'19', c'20', nil, false, 0, nil)
		simple(c'remove', c'/dev/mapper/vinix19', nil, 0); simple(c'remove', c'/dev/mapper/vinix20', nil, 0)
		tool(c'pool-remove', c'/root/saved.vset', c'7', c'0', nil, 0); tool(c'pool-remove', c'/root/saved.vset', c'8', c'1', nil, 0)
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		mut data := [4096]u8{}; check(C.pread(held, &data[0], 4096, 0) == 4096 && C.close(held) == 0 && status(c'/dev/mapper/vinix12').generation == first, c'held original descriptor and generation survive multi-pool transaction')
		for byte in data { check(byte == 0xe7, c'original data preserved across multi-pool transaction') }
		C.printf(c'PLAN MULTI POOL BATCH PASSED: complete multi-pool placement, later rollback, live preflight, writer contention and retained views\n')
	}
}

fn multi_pool_boot_prepare() {
	unsafe {
		copy_plan(c'/etc/vinix/volumes.vset', c'/root/disk-contract-final.vset')
		multi_pool_members(c'/etc/vinix/volumes.vset')
		multi_pool_allocations(c'/etc/vinix/volumes.vset', c'8', c'19', c'4096', c'ro', c'7', c'20', c'4096', c'rw', true, 0, nil)
		multi_pool_allocations(c'/etc/vinix/volumes.vset', c'8', c'19', c'4096', c'ro', c'7', c'20', c'4096', c'rw', false, 0, nil)
		copy_plan(c'/etc/vinix/volumes.vset', c'/root/multi-pool-planned.vset')
		marker := C.open(c'/multi-pool-boot', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
		check(marker >= 0 && C.write(marker, c'1', 1) == 1 && C.fsync(marker) == 0 && C.close(marker) == 0, c'persist multi-pool boot marker')
		directory := C.open(c'/', C.O_RDONLY | C.O_DIRECTORY); check(directory >= 0 && C.fsync(directory) == 0 && C.close(directory) == 0, c'persist multi-pool phase directory')
		C.printf(c'PLAN MULTI POOL BATCH SAVED: two independent pool placements, unchanged seven original rows and member priority\n')
	}
}

@[direct_array_access]
fn multi_pool_boot_phase(parent &char, other &char) {
	unsafe {
		check(C.getppid() == 1 && status(parent).bytes == 20971520 && status(other).bytes == 16777216, c'multi-pool production boot geometry')
		fd := C.open(c'/etc/vinix/volumes.vset', C.O_RDONLY); mut bytes := [8768]u8{}; size := C.read(fd, &bytes[0], 8768)
		check(fd >= 0 && size == 680 && C.close(fd) == 0, c'persistent nine-mapping multi-pool bundle')
		copy_plan(c'/etc/vinix/volumes.vset', c'/root/multi-pool-boot.vset'); copy_plan(c'/etc/vinix/volumes.vset', c'/root/saved.vset')
		grown_view_data(); edited_view_data(); capacity_view_data(); pool_batch_boot_check(parent); multi_pool_data(parent, other)
		first := status(c'/dev/mapper/vinix19').generation; second := status(c'/dev/mapper/vinix20').generation
		mut output := [4096]char{}
		multi_pool_allocations(c'/etc/vinix/volumes.vset', c'7', c'20', c'4096', c'rw', c'8', c'19', c'4096', c'ro', false, 0, nil)
		multi_pool_allocations(c'/etc/vinix/volumes.vset', c'7', c'20', c'4096', c'rw', c'8', c'19', c'4096', c'ro', true, 0, &output[0])
		check(contains(&output[0], c'request=0 pool=7 disk=0 slot=20 action=keep') && contains(&output[0], c'request=1 pool=8 disk=1 slot=19 action=keep'), c'boot multi-pool complete keep report')
		bundle_unchanged(c'/etc/vinix/volumes.vset', &bytes[0], size); simple(c'boot-restore', nil, nil, 0)
		check(status(c'/dev/mapper/vinix19').generation == first && status(c'/dev/mapper/vinix20').generation == second, c'boot multi-pool durable retries preserve live generations')
		C.printf(c'PLAN MULTI POOL BATCH BOOT PRESERVED\n')
		multi_pool_growth_boot_prepare()
	}
}
