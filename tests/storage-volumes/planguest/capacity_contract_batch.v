// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn capacity_contracts(path &char, first &char, first_device &char, first_bytes &char,
	second &char, second_device &char, second_bytes &char, preview bool, expected i32, output &char) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'),
			if preview { &char(c'plan-preview-contract-capacity-batch') } else { &char(c'plan-contract-capacity-batch') },
			path, first, first_device, first_bytes, second, second_device, second_bytes, &char(nil)]!
		if output == nil { run_utility(&args[0], expected); return }
		fd := C.open(c'/root/capacity-contract-output', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600)); check(fd >= 0, c'open capacity contraction output')
		child := C.fork(); check(child >= 0, c'fork capacity contraction')
		if child == 0 {
			if C.dup2(fd, 1) != 1 || C.dup2(fd, 2) != 2 || C.close(fd) != 0 { C._exit(126) }
			C.execv(args[0], &args[0]); C._exit(127)
		}
		mut code := i32(0); check(C.close(fd) == 0 && C.waitpid(child, &code, 0) == child && code == expected << 8, c'capacity contraction exit')
		input := C.open(c'/root/capacity-contract-output', C.O_RDONLY); count := C.read(input, output, 4095)
		check(input >= 0 && count > 0 && count < 4095 && C.close(input) == 0, c'read capacity contraction output'); output[count] = 0
	}
}

@[direct_array_access]
fn planned_capacity_contracts(parent &char, other &char) {
	unsafe {
		fd := C.open(c'/root/saved.vset', C.O_RDONLY); mut original := [8768]u8{}; size := C.read(fd, &original[0], 8768)
		check(fd >= 0 && size == 432 && C.close(fd) == 0, c'capacity contraction baseline')
		first := status(c'/dev/mapper/vinix2'); second := status(c'/dev/mapper/vinix9')
		held := C.open(c'/dev/mapper/vinix2', C.O_RDONLY); check(held >= 0, c'hold capacity contraction view')
		mut output := [4096]char{}
		for preview in [false, true]! {
			capacity_contracts(c'/root/saved.vset', c'mbr:12345678', parent, c'16777216', c'mbr:12345679', other, c'8388608', preview, 1, &output[0])
			check(!contains(&output[0], c'action='), c'later observed contraction mismatch has no partial report')
			bundle_unchanged(c'/root/saved.vset', &original[0], size)
			capacity_contracts(c'/root/saved.vset', c'mbr:12345678', parent, c'16777216', c'mbr:12345679', parent, c'16777216', preview, 1, &output[0])
			bundle_unchanged(c'/root/saved.vset', &original[0], size)
			capacity_contracts(c'/root/saved.vset', c'mbr:12345678', parent, c'16777216', c'mbr:12345678', other, c'16777216', preview, 1, &output[0])
			bundle_unchanged(c'/root/saved.vset', &original[0], size)
		}
		physical_alias(parent)
		capacity_contracts(c'/root/saved.vset', c'mbr:12345679', other, c'16777216', c'mbr:12345678', c'/dev/volume-plan-link', c'16777216', false, 1, &output[0])
		directory := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
		check(directory >= 0 && C.flock(directory, C.LOCK_EX | C.LOCK_NB) == 0, c'hold contraction writer lock')
		capacity_contracts(c'/root/saved.vset', c'mbr:12345679', other, c'16777216', c'mbr:12345678', c'/dev/volume-plan-alias', c'16777216', false, 1, &output[0])
		capacity_contracts(c'/root/saved.vset', c'mbr:12345679', other, c'16777216', c'mbr:12345678', c'/dev/volume-plan-alias', c'16777216', true, 0, &output[0])
		check(contains(&output[0], c'operation=preview-disk-contraction') && contains(&output[0], c'request=0 disk=1 identity=mbr:12345679 action=keep')
			&& contains(&output[0], c'request=1 disk=0 identity=mbr:12345678 action=keep'), c'complete identity contraction preview under writer lock')
		bundle_unchanged(c'/root/saved.vset', &original[0], size); check(C.close(directory) == 0, c'release contraction writer lock')
		capacity_contracts(c'/root/saved.vset', c'mbr:12345679', other, c'16777216', c'mbr:12345678', c'/dev/volume-plan-alias', c'16777216', false, 0, &output[0])
		bundle_unchanged(c'/root/saved.vset', &original[0], size)
		check(status(c'/dev/mapper/vinix2').generation == first.generation && status(c'/dev/mapper/vinix2').bytes == first.bytes
			&& status(c'/dev/mapper/vinix9').generation == second.generation && status(c'/dev/mapper/vinix9').bytes == second.bytes, c'contraction preserves live generations and geometry')
		mut data := [4096]u8{}; check(C.pread(held, &data[0], 4096, 0) == 4096 && C.close(held) == 0, c'read held contraction view')
		for byte in data { check(byte == 0x6d, c'held contraction data') }
		check(C.unlink(c'/dev/volume-plan-alias') == 0 && C.unlink(c'/dev/volume-plan-link') == 0, c'contraction alias cleanup')
		C.printf(c'PLAN CAPACITY CONTRACTION BATCH PASSED: identity selection, whole-set rollback, pinned aliases, writer exclusion and unchanged live views\n')
	}
}

// Preserve the completed fourth-boot state. Prepare pool eligibility in a
// separate guest-produced candidate before the host truncates its disposable disk.
fn capacity_contract_boot_prepare() {
	unsafe {
		copy_plan(c'/etc/vinix/volumes.vset', c'/root/expanded-final.vset')
		copy_plan(c'/etc/vinix/volumes.vset', c'/root/contract-capacity-source.vset')
		pool_resizes(c'/root/contract-capacity-source.vset', c'mbr:12345678', c'4', c'16777216', c'20971520',
			c'mbr:12345678', c'3', c'6291456', c'6295552', false, 0, nil)
		C.printf(c'PLAN CAPACITY CONTRACTION PREPARED: retained all mappings and bounded tail eligibility at 20 MiB\n')
	}
}

fn capacity_contract_data(parent &char, other &char) {
	grown_view_data(); edited_view_data(); capacity_view_data(); pool_batch_boot_check(parent); explicit_growth_boot_check()
	check(status(c'/dev/mapper/vinix14').disk_id == status(parent).disk_id && status(c'/dev/mapper/vinix9').disk_id == status(other).disk_id,
		c'contracted boot selects physical identities')
}

@[direct_array_access]
fn physical_capacity_contract_phase(parent &char, other &char) {
	unsafe {
		check(C.getppid() == 1 && status(parent).bytes == 20971520 && status(other).bytes == 16777216, c'physical contraction phase geometry')
		phase := C.open(c'/capacity-contract-boot', C.O_RDONLY)
		mut output := [4096]char{}; mut original := [8768]u8{}
		if phase < 0 {
			missing(c'/dev/mapper/vinix2'); missing(c'/dev/mapper/vinix5'); missing(c'/dev/mapper/vinix9')
			missing(c'/dev/mapper/vinix12'); missing(c'/dev/mapper/vinix13'); missing(c'/dev/mapper/vinix14'); missing(c'/dev/mapper/vinix18')
			fd := C.open(c'/etc/vinix/volumes.vset', C.O_RDONLY); size := C.read(fd, &original[0], 8768)
			check(fd >= 0 && size == 536 && C.close(fd) == 0, c'old enlarged bundle remains intact')
			for preview in [false, true]! {
				capacity_contracts(c'/etc/vinix/volumes.vset', c'mbr:12345678', parent, c'20971520', c'mbr:12345679', other, c'16777216', preview, 1, &output[0])
				check(!contains(&output[0], c'action='), c'old tail pool rejects physical contraction before any action')
				bundle_unchanged(c'/etc/vinix/volumes.vset', &original[0], size)
			}
			candidate := C.open(c'/root/contract-capacity-source.vset', C.O_RDONLY); candidate_size := C.read(candidate, &original[0], 8768)
			check(candidate >= 0 && candidate_size == 536 && C.close(candidate) == 0, c'bounded candidate still retains old disk geometry')
			for preview in [false, true]! {
				capacity_contracts(c'/root/contract-capacity-source.vset', c'mbr:12345678', parent, c'20971520', c'mbr:12345679', other, c'8388608', preview, 1, &output[0])
				check(!contains(&output[0], c'action='), c'later mismatch rolls back earlier real contraction')
				bundle_unchanged(c'/root/contract-capacity-source.vset', &original[0], candidate_size)
			}
			directory := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
			check(directory >= 0 && C.flock(directory, C.LOCK_EX | C.LOCK_NB) == 0, c'hold real contraction writer lock')
			capacity_contracts(c'/root/contract-capacity-source.vset', c'mbr:12345678', parent, c'20971520', c'mbr:12345679', other, c'16777216', false, 1, &output[0])
			capacity_contracts(c'/root/contract-capacity-source.vset', c'mbr:12345678', parent, c'20971520', c'mbr:12345679', other, c'16777216', true, 0, &output[0])
			check(contains(&output[0], c'request=0 disk=0 identity=mbr:12345678 action=contract previous_bytes=25165824 bytes=20971520 sector=512')
				&& contains(&output[0], c'request=1 disk=1 identity=mbr:12345679 action=keep previous_bytes=16777216 bytes=16777216 sector=512'), c'complete observed contract/keep preview')
			bundle_unchanged(c'/root/contract-capacity-source.vset', &original[0], candidate_size); check(C.close(directory) == 0, c'release real contraction writer lock')
			capacity_contracts(c'/root/contract-capacity-source.vset', c'mbr:12345678', parent, c'20971520', c'mbr:12345679', other, c'16777216', false, 0, nil)
			missing(c'/dev/mapper/vinix14')
			copy_plan(c'/root/contract-capacity-source.vset', c'/root/capacity-contracted.vset')
			copy_plan(c'/root/capacity-contracted.vset', c'/etc/vinix/volumes.vset'); copy_plan(c'/root/capacity-contracted.vset', c'/root/saved.vset')
			simple(c'restore-bundle', c'/etc/vinix/volumes.vset', nil, 0); capacity_contract_data(parent, other)
			marker := C.open(c'/capacity-contract-boot', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
			check(marker >= 0 && C.write(marker, c'1', 1) == 1 && C.fsync(marker) == 0 && C.close(marker) == 0, c'persist contraction boot marker')
			dir := C.open(c'/', C.O_RDONLY | C.O_DIRECTORY)
			check(dir >= 0 && C.fsync(dir) == 0 && C.close(dir) == 0, c'persist contraction phase directory')
			C.printf(c'PLAN CAPACITY CONTRACTION SAVED: explicit observed 24-to-20 MiB contraction, all seven desired mappings and original data\n')
		} else {
			check(C.close(phase) == 0, c'close contraction boot marker'); capacity_contract_data(parent, other)
			copy_plan(c'/etc/vinix/volumes.vset', c'/root/capacity-contracted-boot.vset')
			C.printf(c'PLAN CAPACITY CONTRACT BOOT RESTORED: exact smaller geometry and seven identity-selected mappings before application start\n')
		}
		fd := C.open(c'/etc/vinix/volumes.vset', C.O_RDONLY); size := C.read(fd, &original[0], 8768)
		check(fd >= 0 && size == 536 && C.close(fd) == 0, c'complete contracted bundle')
		first := status(c'/dev/mapper/vinix2').generation; tail := status(c'/dev/mapper/vinix14').generation
		held := C.open(c'/dev/mapper/vinix14', C.O_RDONLY); check(held >= 0, c'hold contracted live tail')
		capacity_contracts(c'/etc/vinix/volumes.vset', c'mbr:12345679', other, c'16777216', c'mbr:12345678', parent, c'20971520', false, 0, nil)
		capacity_contracts(c'/etc/vinix/volumes.vset', c'mbr:12345679', other, c'16777216', c'mbr:12345678', parent, c'20971520', true, 0, &output[0])
		check(contains(&output[0], c'operation=preview-disk-contraction') && contains(&output[0], c'request=0 disk=1 identity=mbr:12345679 action=keep')
			&& contains(&output[0], c'request=1 disk=0 identity=mbr:12345678 action=keep previous_bytes=20971520 bytes=20971520 sector=512'), c'boot complete durable contraction keeps')
		bundle_unchanged(c'/etc/vinix/volumes.vset', &original[0], size)
		pool_preview_for(c'/etc/vinix/volumes.vset', c'4', 0, &output[0])
		check(contains(&output[0], c'pool=4 disk=0 start=16777216 end=20971520 alignment=4096')
			&& contains(&output[0], c'pool=4 regions=1 gaps=1 bytes=4177920 largest=4177920'), c'contracted capacity bounds and full-width free bytes')
		// Restore the contraction report after the shared preview output helper.
		capacity_contracts(c'/etc/vinix/volumes.vset', c'mbr:12345679', other, c'16777216', c'mbr:12345678', parent, c'20971520', true, 0, &output[0])
		simple(c'boot-restore', nil, nil, 0)
		mut data := [4096]u8{}; check(C.pread(held, &data[0], 4096, 0) == 4096 && C.close(held) == 0, c'held contracted descriptor remains readable')
		for byte in data { check(byte == 0xc1, c'held contracted tail data unchanged') }
		check(status(c'/dev/mapper/vinix2').generation == first && status(c'/dev/mapper/vinix14').generation == tail, c'contraction metadata and replay preserve live generations')
		C.printf(c'PLAN CAPACITY CONTRACTION BOOT PRESERVED\n')
		if phase >= 0 { multi_pool_boot_prepare() }
	}
}
