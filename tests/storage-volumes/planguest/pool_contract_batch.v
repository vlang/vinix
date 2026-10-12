// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn pool_contractions(path &char, pool &char, first &char, end &char, second &char, next_end &char,
	preview bool, expected i32, output &char) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'), if preview { &char(c'pool-preview-contract-batch') } else { &char(c'pool-contract-batch') },
			path, pool, first, end, second, next_end, &char(nil)]!
		if output == nil { run_utility(&args[0], expected); return }
		fd := C.open(c'/root/contraction-output', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600)); check(fd >= 0, c'open contraction output')
		child := C.fork(); check(child >= 0, c'fork contraction command')
		if child == 0 {
			if C.dup2(fd, 1) != 1 || C.dup2(fd, 2) != 2 || C.close(fd) != 0 { C._exit(126) }
			C.execv(args[0], &args[0]); C._exit(127)
		}
		mut code := i32(0); check(C.close(fd) == 0 && C.waitpid(child, &code, 0) == child && code == expected << 8, c'contraction command exit')
		input := C.open(c'/root/contraction-output', C.O_RDONLY); count := C.read(input, output, 4095)
		check(input >= 0 && count > 0 && count < 4095 && C.close(input) == 0, c'read contraction output'); output[count] = 0
	}
}

@[direct_array_access]
fn planned_pool_contractions(parent &char) {
	unsafe {
		fd := C.open(c'/root/saved.vset', C.O_RDONLY); mut baseline := [8768]u8{}; size := C.read(fd, &baseline[0], 8768)
		check(fd >= 0 && size == 432 && C.close(fd) == 0, c'contraction baseline')
		original_generation := status(c'/dev/mapper/vinix12').generation; original := C.open(c'/dev/mapper/vinix12', C.O_RDONLY)
		check(original >= 0, c'hold original across contraction')
		pool_growth(c'/root/saved.vset', c'pool-expand', c'3', c'0', c'6303744', 0)
		raw := C.open(parent, C.O_RDWR); mut data := [4096]u8{init: 0xf1}
		check(raw >= 0 && C.pwrite(raw, &data[0], 4096, 6299648) == 4096 && C.fsync(raw) == 0 && C.close(raw) == 0, c'prepare occupied pool tail')
		mapping_additions(c'/root/saved.vset', c'mbr:12345678', c'19', c'6299648', c'4096', c'ro',
			c'mbr:12345679', c'13', c'3145728', c'4096', c'rw', false, 0, nil)
		simple(c'restore-bundle', c'/root/saved.vset', nil, 0)
		generation := status(c'/dev/mapper/vinix19').generation; held := C.open(c'/dev/mapper/vinix19', C.O_RDONLY); check(held >= 0, c'hold pool tail across contraction')
		input := C.open(c'/root/saved.vset', C.O_RDONLY); mut configured := [8768]u8{}
		check(input >= 0 && C.read(input, &configured[0], 8768) == size + 32 && C.close(input) == 0, c'capture protected contraction source')
		mut output := [4096]char{}
		for preview in [false, true]! {
			pool_contractions(c'/root/saved.vset', c'3', c'mbr:12345679', c'6299648', c'mbr:12345678', c'6299648', preview, 1, &output[0])
			check(!contains(&output[0], c'action='), c'later occupied tail rejects prefix actions')
			bundle_unchanged(c'/root/saved.vset', &configured[0], size + 32)
			pool_contractions(c'/root/saved.vset', c'3', c'mbr:12345679', c'6299648', c'mbr:1234567b', c'6299648', preview, 1, &output[0])
			pool_contractions(c'/root/saved.vset', c'3', c'mbr:12345679', c'6299648', c'mbr:12345679', c'6303744', preview, 1, &output[0])
			bundle_unchanged(c'/root/saved.vset', &configured[0], size + 32)
		}
		directory := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
		check(directory >= 0 && C.flock(directory, C.LOCK_EX | C.LOCK_NB) == 0, c'hold contraction writer lock')
		pool_contractions(c'/root/saved.vset', c'3', c'mbr:12345679', c'6299648', c'mbr:12345678', c'6303744', false, 1, &output[0])
		pool_contractions(c'/root/saved.vset', c'3', c'mbr:12345679', c'6299648', c'mbr:12345678', c'6303744', true, 0, &output[0])
		check(contains(&output[0], c'pool=3 request=0 disk=1 action=contract start=6291456 previous_end=6303744 end=6299648 alignment=4096 identity=mbr:12345679')
			&& contains(&output[0], c'pool=3 request=1 disk=0 action=keep start=6291456 previous_end=6303744 end=6303744 alignment=4096 identity=mbr:12345678'), c'complete mixed contraction preview under lock')
		bundle_unchanged(c'/root/saved.vset', &configured[0], size + 32); check(C.close(directory) == 0, c'release contraction writer lock')
		pool_contractions(c'/root/saved.vset', c'3', c'mbr:12345679', c'6299648', c'mbr:12345678', c'6303744', false, 0, nil)
		mapping_removals(c'/root/saved.vset', c'19', c'20', nil, false, 0, nil)
		pool_contractions(c'/root/saved.vset', c'3', c'mbr:12345678', c'6299648', c'mbr:12345679', c'6299648', false, 0, nil)
		pool_preview_for(c'/root/saved.vset', c'3', 0, &output[0])
		check(contains(&output[0], c'pool=3 regions=2 gaps=2 bytes=16384 largest=8192'), c'contraction free capacity excludes released tails')
		pool_contractions(c'/root/saved.vset', c'3', c'mbr:12345679', c'6299648', c'mbr:12345678', c'6299648', false, 0, &output[0])
		check(contains(&output[0], c'request=0 disk=1 action=keep') && contains(&output[0], c'request=1 disk=0 action=keep'), c'durable equal-end contraction retry')
		pool_batch(c'/root/saved.vset', c'3', c'20', c'8192', c'ro', c'21', c'8192', c'rw', false, 0, nil)
		preview(c'check-bundle', false, 0, &output[0]); missing(c'/dev/mapper/vinix20'); missing(c'/dev/mapper/vinix21')
		check(contains(&output[0], c'disk=0 slot=20 action=create offset=6291456 current_bytes=0 planned_bytes=8192 readonly=1')
			&& contains(&output[0], c'disk=1 slot=21 action=create offset=6291456 current_bytes=0 planned_bytes=8192 readonly=0'), c'future allocations fit only retained windows')
		mapping_removals(c'/root/saved.vset', c'20', c'21', nil, false, 0, nil)
		check(status(c'/dev/mapper/vinix19').generation == generation && C.pread(held, &data[0], 4096, 0) == 4096 && C.close(held) == 0, c'excluded unlisted live tail remains readable')
		for byte in data { check(byte == 0xf1, c'contraction preserves tail data') }
		simple(c'remove', c'/dev/mapper/vinix19', nil, 0)
		pool_contractions(c'/root/saved.vset', c'3', c'mbr:12345678', c'6295552', c'mbr:12345679', c'6299648', false, 0, nil)
		pool_growth(c'/root/saved.vset', c'pool-expand', c'3', c'1', c'6303744', 0); bundle_unchanged(c'/root/saved.vset', &baseline[0], size)
		check(status(c'/dev/mapper/vinix12').generation == original_generation && C.pread(original, &data[0], 4096, 0) == 4096 && C.close(original) == 0, c'contraction retains original descriptor and generation')
		for byte in data { check(byte == 0xe7, c'original data survives contraction') }
		C.printf(c'PLAN POOL CONTRACTION BATCH PASSED: occupied intersections, mixed previews, rollback, bounded allocation and retained views\n')
	}
}

fn contraction_boot_prepare() {
	unsafe {
		first := status(c'/dev/mapper/vinix12').generation; second := status(c'/dev/mapper/vinix9').generation
		pool_members_batch(c'/root/saved.vset', c'5', c'1', c'12582912', c'12595200', c'0', c'12582912', c'12595200', false, false, 0, nil)
		pool_contractions(c'/root/saved.vset', c'5', c'mbr:12345678', c'12591104', c'mbr:12345679', c'12591104', true, 0, nil)
		pool_contractions(c'/root/saved.vset', c'5', c'mbr:12345678', c'12591104', c'mbr:12345679', c'12591104', false, 0, nil)
		copy_plan(c'/root/saved.vset', c'/root/contract-planned.vset')
		check(status(c'/dev/mapper/vinix12').generation == first && status(c'/dev/mapper/vinix9').generation == second, c'boot contraction retains live views')
		C.printf(c'PLAN POOL CONTRACTION BATCH SAVED: contracted two unused windows with reversed member priority before replay\n')
	}
}

fn contraction_boot_check() {
	unsafe {
		fd := C.open(c'/etc/vinix/volumes.vset', C.O_RDONLY); mut original := [8768]u8{}; size := C.read(fd, &original[0], 8768)
		check(fd >= 0 && size == 616 && C.close(fd) == 0, c'persistent contracted bundle')
		copy_plan(c'/etc/vinix/volumes.vset', c'/root/contract-boot.vset')
		mut output := [4096]char{}; pool_preview_for(c'/etc/vinix/volumes.vset', c'5', 0, &output[0])
		check(contains(&output[0], c'pool=5 disk=1 start=12582912 end=12591104 alignment=4096')
			&& contains(&output[0], c'pool=5 disk=0 start=12582912 end=12591104 alignment=4096')
			&& contains(&output[0], c'pool=5 regions=2 gaps=2 bytes=16384 largest=8192'), c'contracted bounds and priority survive boot')
		pool_contractions(c'/etc/vinix/volumes.vset', c'5', c'mbr:12345678', c'12591104', c'mbr:12345679', c'12591104', true, 0, &output[0])
		check(contains(&output[0], c'pool=5 request=0 disk=0 action=keep start=12582912 previous_end=12591104 end=12591104 alignment=4096 identity=mbr:12345678')
			&& contains(&output[0], c'pool=5 request=1 disk=1 action=keep start=12582912 previous_end=12591104 end=12591104 alignment=4096 identity=mbr:12345679'), c'equal-end identity retries survive boot')
		pool_contractions(c'/etc/vinix/volumes.vset', c'5', c'mbr:12345678', c'12591104', c'mbr:12345679', c'12591104', false, 0, nil)
		bundle_unchanged(c'/etc/vinix/volumes.vset', &original[0], size)
		// Retain the actual boot state separately before removing only the unused
		// fixture memberships, so earlier independent boot checks see their baseline.
		pool_members_batch(c'/etc/vinix/volumes.vset', c'5', c'0', nil, nil, c'1', nil, nil, true, false, 0, nil)
		copy_plan(c'/etc/vinix/volumes.vset', c'/root/saved.vset')
		C.printf(c'PLAN POOL CONTRACTION BATCH BOOT PRESERVED\n')
	}
}
