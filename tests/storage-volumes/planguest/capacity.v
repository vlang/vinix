// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn planning_capacity(path &char, disk &char, device &char, expected_bytes &char, expected i32) {
	tool(c'plan-capacity', path, disk, device, expected_bytes, expected)
}

@[direct_array_access]
fn capacity_view_data() {
	info := status(c'/dev/mapper/vinix14')
	check(info.start == 16777216 && info.bytes == 8192 && info.flags & 1 == 0,
		c'new physical tail mapping geometry')
	fd := C.open(c'/dev/mapper/vinix14', C.O_RDONLY)
	mut bytes := [4096]u8{}
	for offset in [i64(0), 4096]! {
		check(fd >= 0 && C.pread(fd, &bytes[0], 4096, offset) == 4096,
			c'read newly adopted physical extent')
		for byte in bytes {
			check(byte == if offset == 0 { u8(0xc1) } else { u8(0xc2) },
				c'new physical tail data preserved')
		}
	}
	check(C.close(fd) == 0, c'close physical tail view')
}

// The host enlarges only its disposable raw disk after the ordinary two-boot
// qualification. Production init must reject the old geometry before this
// explicit adoption, and must restore the enlarged bundle on the next boot.
@[direct_array_access]
fn physical_capacity_phase(parent &char, other &char) {
	unsafe {
		check(C.getppid() == 1 && status(parent).bytes == 25165824, c'physical capacity phase')
		phase := C.open(c'/capacity-boot', C.O_RDONLY)
		if phase >= 0 {
			check(C.close(phase) == 0, c'close capacity reboot phase')
			resize_boot_check()
			contraction_boot_check()
			grown_view_data()
			edited_view_data()
			capacity_view_data()
			pool_batch_boot_check(parent)
			pool_boot_check()
			pool_growth_boot_check()
			pool_members_batch_boot_check()
			pool_order_boot_check()
			removal_boot_check()
			enrollment_boot_check()
			forget_boot_check()
			addition_boot_check()
			explicit_growth_boot_check()
			check(status(c'/dev/mapper/vinix14').disk_id == status(parent).disk_id
				&& status(c'/dev/mapper/vinix9').disk_id == status(other).disk_id,
				c'capacity boot maps the correct physical disks')
			first := status(c'/dev/mapper/vinix2').generation
			tail := status(c'/dev/mapper/vinix14').generation
			capacity_batch(c'/etc/vinix/volumes.vset', c'1', other, c'16777216', c'0', parent, c'25165824', false, 0, unsafe { nil })
			simple(c'boot-restore', &char(nil), &char(nil), 0)
			check(status(c'/dev/mapper/vinix2').generation == first
				&& status(c'/dev/mapper/vinix14').generation == tail, c'capacity boot replay is idempotent')
			C.printf(c'PLAN CAPACITY BOOT RESTORED: exact enlarged identity, old data and new physical tail\n')
			C.printf(c'PLAN CAPACITY BATCH BOOT PRESERVED\n')
			capacity_contract_boot_prepare()
			return
		}
		missing(c'/dev/mapper/vinix2'); missing(c'/dev/mapper/vinix5'); missing(c'/dev/mapper/vinix9')
		missing(c'/dev/mapper/vinix12'); missing(c'/dev/mapper/vinix13'); missing(c'/dev/mapper/vinix14')
		copy_plan(c'/etc/vinix/volumes.vset', c'/root/saved.vset')
		fd := C.open(c'/root/saved.vset', C.O_RDONLY)
		mut original := [6208]u8{}
		size := C.read(fd, &original[0], 6208)
		check(fd >= 0 && size == 432 && C.close(fd) == 0, c'read pre-adoption pool bundle')
		planning_allocate(c'/root/saved.vset', c'0', c'14', c'4096', c'16777216', c'25165824', c'4096', false, 1)
		pool_growth(c'/root/saved.vset', c'pool-expand', c'3', c'0', c'25165824', 1)
		pool_expand_batch(c'/root/saved.vset', c'3', c'1', c'6307840', c'0', c'25165824', true, 1, nil)
		pool_expand_batch(c'/root/saved.vset', c'3', c'1', c'6307840', c'0', c'25165824', false, 1, nil)
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		planning_capacity(c'/root/saved.vset', c'0', other, c'25165824', 1)
		planning_capacity(c'/root/saved.vset', c'0', parent, c'16777216', 1)
		planning_capacity(c'/root/saved.vset', c'0', parent, c'8388608', 1)
		planning_capacity(c'/root/saved.vset', c'0', parent, c'25165825', 1)
		planning_capacity(c'/root/saved.vset', c'2', parent, c'25165824', 1)
		planning_capacity(c'/root/saved.vset', c'0', c'/root/saved.vset', c'25165824', 1)
		physical_alias(parent)
		planning_capacity(c'/root/saved.vset', c'0', c'/dev/volume-plan-link', c'25165824', 1)
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		mut output := [4096]char{}
		// The first requested disk really grew. A later wrong observed size must
		// still roll back that earlier adoption for publication and preview.
		for preview in [false, true]! {
			capacity_batch(c'/root/saved.vset', c'0', parent, c'25165824', c'1', other, c'33554432', preview, 1, &output[0])
			check(!contains(&output[0], c'action='), c'later capacity failure discards earlier real growth')
			bundle_unchanged(c'/root/saved.vset', &original[0], size)
		}
		capacity_batch(c'/root/saved.vset', c'1', other, c'16777216', c'0', c'/dev/volume-plan-alias', c'25165824', true, 0, &output[0])
		check(contains(&output[0], c'request=0 disk=1 action=keep previous_bytes=16777216 bytes=16777216 sector=512')
			&& contains(&output[0], c'request=1 disk=0 action=adopt previous_bytes=16777216 bytes=25165824 sector=512'), c'mixed keep/adopt preview')
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		capacity_batch(c'/root/saved.vset', c'1', other, c'16777216', c'0', c'/dev/volume-plan-alias', c'25165824', false, 0, nil)
		capacity_batch(c'/root/saved.vset', c'1', other, c'16777216', c'0', parent, c'25165824', false, 0, &output[0])
		check(contains(&output[0], c'request=0 disk=1 action=keep') && contains(&output[0], c'request=1 disk=0 action=keep'), c'durable complete capacity retry')
		missing(c'/dev/mapper/vinix2')
		missing(c'/dev/mapper/vinix14')
		preview(c'show-bundle', false, 0, &output[0])
		check(contains(&output[0], c'disk=0 bytes=25165824 sector=512 identity=mbr:12345678')
			&& contains(&output[0], c'disk=1 bytes=16777216 sector=512 identity=mbr:12345679')
			&& contains(&output[0], c'disks=2 mappings=5'), c'only chosen physical capacity changes')
		simple(c'restore-bundle', c'/root/saved.vset', &char(nil), 0)
		grown_view_data()
		edited_view_data()
		first := status(c'/dev/mapper/vinix2').generation
		old := C.open(c'/dev/mapper/vinix2', C.O_RDONLY)
		check(old >= 0, c'hold old descriptor across capacity planning')
		pool_members_batch(c'/root/saved.vset', c'4', c'0', c'16777216', c'16781312', nil, nil, nil, false, true, 0, &output[0])
		check(contains(&output[0], c'request=0 disk=0 action=add start=16777216 end=16781312 alignment=4096'), c'preview admission on newly adopted physical tail')
		pool_members_batch(c'/root/saved.vset', c'4', c'0', c'16777216', c'16781312', nil, nil, nil, false, false, 0, nil)
		pool_expand_batch(c'/root/saved.vset', c'4', c'0', c'25165824', nil, nil, true, 0, &output[0])
		check(contains(&output[0], c'action=expand start=16777216 previous_end=16781312 end=25165824 alignment=4096'), c'preview adopted tail eligibility')
		pool_expand_batch(c'/root/saved.vset', c'4', c'0', c'25165824', nil, nil, false, 0, nil)
		pool_expand_batch(c'/root/saved.vset', c'4', c'0', c'25165824', nil, nil, false, 0, &output[0])
		check(contains(&output[0], c'action=keep start=16777216 previous_end=25165824 end=25165824 alignment=4096'), c'durable tail eligibility retry')
		pool_allocate(c'/root/saved.vset', c'4', c'14', c'4096', false, 0)
		missing(c'/dev/mapper/vinix14')
		planning_capacity(c'/root/saved.vset', c'0', parent, c'25165824', 0)
		simple(c'restore-bundle', c'/root/saved.vset', &char(nil), 0)
		tail := status(c'/dev/mapper/vinix14').generation
		held := C.open(c'/dev/mapper/vinix14', C.O_RDWR)
		mut bytes := [4096]u8{init: 0xc1}
		check(held >= 0 && C.pwrite(held, &bytes[0], 4096, 0) == 4096, c'write new physical tail')
		pool_growth(c'/root/saved.vset', c'pool-grow', c'4', c'14', c'8192', 0)
		simple(c'restore-bundle', c'/root/saved.vset', &char(nil), 1)
		tool(c'restore-bundle', c'/root/saved.vset', c'grow', &char(nil), &char(nil), 0)
		for i in 0 .. 4096 { bytes[i] = 0xc2 }
		check(C.pwrite(held, &bytes[0], 4096, 4096) == 4096 && C.fsync(held) == 0
			&& C.close(held) == 0, c'held descriptor writes grown physical tail')
		check(C.pread(old, &bytes[0], 4096, 0) == 4096 && C.close(old) == 0, c'old descriptor remains readable')
		for byte in bytes { check(byte == 0x6d, c'old descriptor data unchanged') }
		check(status(c'/dev/mapper/vinix2').generation == first
			&& status(c'/dev/mapper/vinix14').generation == tail, c'adoption and growth preserve live generations')
		grown_view_data()
		edited_view_data()
		capacity_view_data()
		// Retry an existing tail row and add its readonly neighbor in one batch.
		raw := C.open(parent, C.O_RDWR)
		for i in 0 .. 4096 { bytes[i] = 0xcc }
		check(raw >= 0 && C.pwrite(raw, &bytes[0], 4096, 16785408) == 4096
			&& C.fsync(raw) == 0 && C.close(raw) == 0, c'prepare persisted batch tail data')
		pool_batch(c'/root/saved.vset', c'4', c'14', c'8192', c'rw', c'18', c'4096', c'ro', true, 0, &output[0])
		check(contains(&output[0], c'slot=14 action=keep') && contains(&output[0], c'slot=18 action=allocate'), c'mixed existing/new batch preview')
		pool_batch(c'/root/saved.vset', c'4', c'14', c'8192', c'rw', c'18', c'4096', c'ro', false, 0, nil)
		missing(c'/dev/mapper/vinix18')
		simple(c'restore-bundle', c'/root/saved.vset', nil, 0)
		check(status(c'/dev/mapper/vinix14').generation == tail, c'mixed batch retains existing tail generation')
		capacity_growth_batch(parent)
		pool_batch_boot_check(parent)
		pool_order(c'/root/saved.vset', c'3', c'1', c'0', false, 0, nil)
		removal_boot_prepare()
		enrollment_boot_prepare(parent, other)
		forget_boot_prepare()
		addition_boot_prepare()
		explicit_growth_boot_prepare()
		contraction_boot_prepare()
		resize_boot_prepare()
		copy_plan(c'/root/saved.vset', c'/etc/vinix/volumes.vset')
		check(C.unlink(c'/dev/volume-plan-alias') == 0 && C.unlink(c'/dev/volume-plan-link') == 0,
			c'capacity aliases cleanup')
		marker := C.open(c'/capacity-boot', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
		check(marker >= 0 && C.write(marker, c'1', 1) == 1 && C.fsync(marker) == 0 && C.close(marker) == 0,
			c'persist capacity reboot phase')
		directory := C.open(c'/', C.O_RDONLY | C.O_DIRECTORY)
		check(directory >= 0 && C.fsync(directory) == 0 && C.close(directory) == 0,
			c'persist capacity phase directory')
		C.printf(c'PLAN CAPACITY PASSED: physical growth, explicit identity adoption, bounded tail allocation and stable descriptors\n')
	}
}
