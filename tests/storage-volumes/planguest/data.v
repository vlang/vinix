// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

@[direct_array_access]
fn data_tool(bundle &char, manifest &char, parent &char, other &char, create bool, expected i32, output &char) {
	unsafe {
		mut args := [9]&char{}
		args[0] = &char(c'/usr/sbin/vinix-volume'); args[1] = if create { &char(c'hash-bundle') } else { &char(c'verify-data') }
		args[2] = if create { bundle } else { manifest }; mut at := 3
		if create { args[at] = manifest; at++ }
		args[at] = &char(c'1'); args[at + 1] = other; args[at + 2] = &char(c'0'); args[at + 3] = parent
		if output == nil { run_utility(&args[0], expected); return }
		fd := C.open(c'/root/data-output', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600)); check(fd >= 0, c'open checksum report')
		child := C.fork(); check(child >= 0, c'fork checksum utility')
		if child == 0 {
			if C.dup2(fd, 1) != 1 || C.dup2(fd, 2) != 2 || C.close(fd) != 0 { C._exit(126) }
			C.execv(args[0], &args[0]); C._exit(127)
		}
		mut code := i32(0); check(C.close(fd) == 0 && C.waitpid(child, &code, 0) == child && code == expected << 8, c'checksum utility exit')
		input := C.open(c'/root/data-output', C.O_RDONLY); size := C.read(input, output, 4095)
		check(input >= 0 && size > 0 && size < 4095 && C.close(input) == 0, c'read checksum report'); output[size] = 0
	}
}

@[direct_array_access]
fn planned_data(parent &char, other &char) {
	unsafe {
		fd := C.open(c'/root/saved.vset', C.O_RDONLY); mut baseline := [8768]u8{}; size := C.read(fd, &baseline[0], 8768)
		check(fd >= 0 && size == 432 && C.close(fd) == 0, c'checksum baseline bundle'); copy_plan(c'/root/saved.vset', c'/root/data-base.vset')
		first := status(c'/dev/mapper/vinix2').generation; second := status(c'/dev/mapper/vinix9').generation
		held := C.open(c'/dev/mapper/vinix9', C.O_RDONLY); check(held >= 0, c'hold checksum view')
		mut output := [4096]char{}
		data_tool(c'/root/saved.vset', other, parent, other, true, 1, &output[0]); check(status(other).bytes == 16777216, c'checksum destination preserves physical node')
		data_tool(c'/root/saved.vset', c'/root/data.vhash', parent, other, true, 0, &output[0])
		check(contains(&output[0], c'operation=recorded-data disks=2 mappings=5 algorithm=sha256') && contains(&output[0], c'disk=1 slot=9'), c'complete canonical checksum report')
		bundle_unchanged(c'/root/saved.vset', &baseline[0], size)
		manifest_fd := C.open(c'/root/data.vhash', C.O_RDONLY); mut reference := [11392]u8{}; reference_size := C.read(manifest_fd, &reference[0], 11392)
		check(manifest_fd >= 0 && reference_size == 696 && C.close(manifest_fd) == 0, c'capture checksum reference')
		directory := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
		check(directory >= 0 && C.flock(directory, C.LOCK_EX | C.LOCK_NB) == 0, c'hold checksum writer lock')
		data_tool(c'/root/saved.vset', c'/root/data.vhash', parent, other, true, 1, &output[0])
		data_tool(nil, c'/root/data.vhash', parent, other, false, 0, &output[0]); simple(c'show-data', c'/root/data.vhash', nil, 0)
		check(C.close(directory) == 0, c'release checksum writer lock')
		data_tool(nil, c'/root/data.vhash', parent, parent, false, 1, &output[0]); check(!contains(&output[0], c'operation=verified-data'), c'wrong participant reports no verified rows')
		data_tool(nil, c'/root/data.vhash', parent, c'/dev/missing-checksum-disk', false, 1, &output[0])
		// Corrupt one later-disk page, verify against the retained reference, and
		// restore the exact original bytes before subsequent persistence tests.
		raw := C.open(other, C.O_RDWR); mut original := [4096]u8{}
		check(raw >= 0 && C.pread(raw, &original[0], 4096, 1048576) == 4096, c'read corruption fixture')
		mut changed := original; changed[17] ^= 1
		check(C.pwrite(raw, &changed[0], 4096, 1048576) == 4096 && C.fsync(raw) == 0, c'persist later data corruption')
		data_tool(nil, c'/root/data.vhash', parent, other, false, 1, &output[0])
		check(!contains(&output[0], c'operation=verified-data') && !contains(&output[0], c'sha256='), c'later mismatch reports no successful prefix')
		bundle_unchanged(c'/root/data.vhash', &reference[0], reference_size)
		check(C.pwrite(raw, &original[0], 4096, 1048576) == 4096 && C.fsync(raw) == 0 && C.close(raw) == 0, c'restore corruption fixture')
		data_tool(nil, c'/root/data.vhash', parent, other, false, 0, &output[0])
		data_tool(c'/root/saved.vset', c'/root/data.vhash', parent, other, true, 0, nil)
		bundle_unchanged(c'/root/data.vhash', &reference[0], reference_size); bundle_unchanged(c'/root/saved.vset', &baseline[0], size)
		check(C.pread(held, &changed[0], 4096, 0) == 4096 && C.close(held) == 0, c'held view after checksum verification')
		for i in 0 .. 4096 { check(changed[i] == original[i], c'held checksum view data') }
		check(status(c'/dev/mapper/vinix2').generation == first && status(c'/dev/mapper/vinix9').generation == second, c'checksum operations preserve mapping generations')
		C.printf(c'PLAN DATA PASSED: complete read-only hashing, trusted reference, later corruption rejection, writer contention and preserved held data\n')
	}
}

fn prepare_data_boot(parent &char, other &char) {
	unsafe {
		data_tool(c'/etc/vinix/volumes.vset', c'/root/boot-data.vhash', parent, other, true, 0, nil)
		data_tool(nil, c'/root/boot-data.vhash', parent, other, false, 0, nil)
		marker := C.open(c'/data-boot', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
		check(marker >= 0 && C.write(marker, c'1', 1) == 1 && C.fsync(marker) == 0 && C.close(marker) == 0, c'persist checksum boot marker')
		directory := C.open(c'/', C.O_RDONLY | C.O_DIRECTORY); check(directory >= 0 && C.fsync(directory) == 0 && C.close(directory) == 0, c'persist checksum phase directory')
		C.printf(c'PLAN DATA SAVED: nine grown mappings and two physical identities\n')
	}
}

@[direct_array_access]
fn data_boot_phase(parent &char, other &char) {
	unsafe {
		check(C.getppid() == 1, c'checksum test started after production init')
		fd := C.open(c'/etc/vinix/volumes.vset', C.O_RDONLY); mut bundle := [8768]u8{}; size := C.read(fd, &bundle[0], 8768)
		check(fd >= 0 && size == 680 && C.close(fd) == 0, c'checksum boot bundle')
		ref := C.open(c'/root/boot-data.vhash', C.O_RDONLY); mut bytes := [11392]u8{}; refsize := C.read(ref, &bytes[0], 11392)
		check(ref >= 0 && refsize == 1104 && C.close(ref) == 0, c'checksum boot reference')
		first := status(c'/dev/mapper/vinix20').generation; second := status(c'/dev/mapper/vinix19').generation
		data_tool(nil, c'/root/boot-data.vhash', parent, other, false, 0, nil); simple(c'show-data', c'/root/boot-data.vhash', nil, 0)
		grown_view_data(); edited_view_data(); capacity_view_data(); pool_batch_boot_check(parent); multi_pool_grown_data(parent, other)
		bundle_unchanged(c'/etc/vinix/volumes.vset', &bundle[0], size); bundle_unchanged(c'/root/boot-data.vhash', &bytes[0], refsize)
		check(status(c'/dev/mapper/vinix20').generation == first && status(c'/dev/mapper/vinix19').generation == second, c'checksum boot verification preserves generation')
		C.printf(c'PLAN DATA BOOT PRESERVED\n')
	}
}
