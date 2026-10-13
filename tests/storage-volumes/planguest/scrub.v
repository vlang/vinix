// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

@[direct_array_access]
fn scrub_tool(reference &char, report &char, parent &char, other &char, expected i32, output &char) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'), &char(c'scrub-data'), reference, report, &char(c'1'), other, &char(c'0'), parent, &char(nil)]!
		if output == nil { run_utility(&args[0], expected); return }
		fd := C.open(c'/root/scrub-output', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600)); check(fd >= 0, c'open scrub capture')
		child := C.fork(); check(child >= 0, c'fork scrub')
		if child == 0 {
			if C.dup2(fd, 1) != 1 || C.dup2(fd, 2) != 2 || C.close(fd) != 0 { C._exit(126) }
			C.execv(args[0], &args[0]); C._exit(127)
		}
		mut code := i32(0); check(C.close(fd) == 0 && C.waitpid(child, &code, 0) == child && code == expected << 8, c'scrub exit')
		input := C.open(c'/root/scrub-output', C.O_RDONLY); size := C.read(input, output, 4095)
		check(input >= 0 && size >= 0 && size < 4095 && (size > 0 || expected == 1) && C.close(input) == 0, c'read scrub capture'); output[size] = 0
	}
}

fn copy_scrub_report(from &char, to &char) {
	input := C.open(from, C.O_RDONLY); mut bytes := [32768]u8{}; size := C.read(input, &bytes[0], 32768)
	check(input >= 0 && size > 0 && size < 32768 && C.close(input) == 0, c'read scrub report copy')
	output := C.open(to, C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600))
	check(output >= 0 && C.write(output, &bytes[0], usize(size)) == size && C.fsync(output) == 0 && C.close(output) == 0, c'persist scrub report copy')
}

@[direct_array_access]
fn planned_scrub(parent &char, other &char) {
	unsafe {
		ref := C.open(c'/root/data.vhash', C.O_RDONLY); mut reference := [11392]u8{}; size := C.read(ref, &reference[0], 11392)
		check(ref >= 0 && size == 696 && C.close(ref) == 0, c'scrub trusted reference')
		first := status(c'/dev/mapper/vinix2').generation; second := status(c'/dev/mapper/vinix9').generation
		held_first := C.open(c'/dev/mapper/vinix2', C.O_RDONLY); held_second := C.open(c'/dev/mapper/vinix9', C.O_RDONLY)
		check(held_first >= 0 && held_second >= 0, c'hold scrub views')
		mut clean := [4096]char{}; mut output := [4096]char{}
		scrub_tool(c'/root/data.vhash', c'/root/scrub-report.txt', parent, other, 0, &clean[0])
		check(contains(&clean[0], c'format=VINIXSR1 operation=scrubbed-data disks=2 mappings=5 matched=5 changed=0 algorithm=sha256') && contains(&clean[0], c'disk=1 slot=13'), c'complete clean scrub')
		copy_scrub_report(c'/root/scrub-report.txt', c'/root/scrub-clean.txt')
		directory := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
		check(directory >= 0 && C.flock(directory, C.LOCK_EX | C.LOCK_NB) == 0, c'hold scrub writer lock')
		scrub_tool(c'/root/data.vhash', c'/root/scrub-report.txt', parent, other, 1, &output[0]); check(!contains(&output[0], c'operation=scrubbed-data'), c'busy scrub emits no findings')
		data_tool(nil, c'/root/data.vhash', parent, other, false, 0, nil); check(C.close(directory) == 0, c'release scrub writer lock')
		raw_first := C.open(parent, C.O_RDWR); raw_second := C.open(other, C.O_RDWR)
		mut original_first := [4096]u8{}; mut original_second := [4096]u8{}
		check(raw_first >= 0 && raw_second >= 0 && C.pread(raw_first, &original_first[0], 4096, 1048576) == 4096 && C.pread(raw_second, &original_second[0], 4096, 1048576) == 4096, c'read two-disk scrub corruption fixtures')
		mut changed := original_first; changed[17] ^= 1; check(C.pwrite(raw_first, &changed[0], 4096, 1048576) == 4096 && C.fsync(raw_first) == 0, c'persist first scrub corruption')
		changed = original_second; changed[93] ^= 3; check(C.pwrite(raw_second, &changed[0], 4096, 1048576) == 4096 && C.fsync(raw_second) == 0, c'persist later scrub corruption')
		scrub_tool(c'/root/data.vhash', c'/root/scrub-report.txt', parent, other, 2, &output[0])
		check(contains(&output[0], c'mappings=5 matched=3 changed=2') && contains(&output[0], c'disk=0 slot=2 offset=1048576 bytes=8192 readonly=0 result=changed')
			&& contains(&output[0], c'disk=1 slot=9 offset=1048576 bytes=8192 readonly=0 result=changed') && contains(&output[0], c'disk=0 slot=5 offset=2097152 bytes=12288 readonly=1 result=match')
			&& contains(&output[0], c'expected_sha256=') && contains(&output[0], c'actual_sha256='), c'complete multiple-corruption scrub findings')
		copy_scrub_report(c'/root/scrub-report.txt', c'/root/scrub-changed.txt')
		fd := C.open(c'/root/scrub-report.txt', C.O_RDONLY); mut findings := [4096]u8{}; found := C.read(fd, &findings[0], 4096)
		check(fd >= 0 && found > 0 && found < 4096 && C.close(fd) == 0, c'capture scrub findings')
		scrub_tool(c'/root/data.vhash', c'/root/scrub-report.txt', parent, c'/dev/missing-scrub-disk', 1, &output[0]); check(!contains(&output[0], c'operation=scrubbed-data'), c'incomplete scan emits no findings')
		bundle_unchanged(c'/root/scrub-report.txt', &findings[0], found); bundle_unchanged(c'/root/data.vhash', &reference[0], size)
		check(C.pwrite(raw_first, &original_first[0], 4096, 1048576) == 4096 && C.fsync(raw_first) == 0 && C.close(raw_first) == 0
			&& C.pwrite(raw_second, &original_second[0], 4096, 1048576) == 4096 && C.fsync(raw_second) == 0 && C.close(raw_second) == 0, c'restore both scrub fixture pages')
		scrub_tool(c'/root/data.vhash', c'/root/scrub-report.txt', parent, other, 0, &output[0]); check(C.strcmp(&clean[0], &output[0]) == 0, c'clean retry reproduces exact complete report')
		scrub_tool(c'/root/data.vhash', c'/root/data.vhash', parent, other, 1, &output[0]); bundle_unchanged(c'/root/data.vhash', &reference[0], size)
		scrub_tool(c'/root/data.vhash', other, parent, other, 1, &output[0]); check(status(other).bytes == 16777216, c'scrub preserves physical destination node')
		check(C.pread(held_first, &changed[0], 4096, 0) == 4096 && C.close(held_first) == 0, c'read held first scrub view')
		for i in 0 .. 4096 { check(changed[i] == original_first[i], c'held first scrub data') }
		check(C.pread(held_second, &changed[0], 4096, 0) == 4096 && C.close(held_second) == 0, c'read held second scrub view')
		for i in 0 .. 4096 { check(changed[i] == original_second[i], c'held second scrub data') }
		check(status(c'/dev/mapper/vinix2').generation == first && status(c'/dev/mapper/vinix9').generation == second, c'scrub retains mapping generations')
		C.printf(c'PLAN SCRUB PASSED: all rows, multiple corruptions, complete durable findings, failed-scan rollback, writer exclusion and preserved held data\n')
	}
}

fn scrub_reordered_boot(parent &char, other &char) {
	unsafe {
		scrub_tool(c'/root/data.vhash', c'/root/reordered-scrub.txt', parent, other, 0, nil)
		C.printf(c'PLAN SCRUB REORDERED BOOT PRESERVED\n')
	}
}

fn prepare_scrub_boot(parent &char, other &char) {
	unsafe {
		scrub_tool(c'/root/boot-data.vhash', c'/root/boot-scrub.txt', parent, other, 0, nil)
		copy_scrub_report(c'/root/boot-scrub.txt', c'/root/scrub-before-boot.txt'); C.printf(c'PLAN SCRUB SAVED: complete nine-mapping clean report\n')
	}
}

@[direct_array_access]
fn scrub_boot_phase(parent &char, other &char) {
	unsafe {
		fd := C.open(c'/root/boot-scrub.txt', C.O_RDONLY); mut prior := [4096]u8{}; size := C.read(fd, &prior[0], 4096)
		check(fd >= 0 && size > 0 && size < 4096 && C.close(fd) == 0, c'persisted nine-row scrub report')
		first := status(c'/dev/mapper/vinix20').generation; second := status(c'/dev/mapper/vinix19').generation
		mut output := [4096]char{}; scrub_tool(c'/root/boot-data.vhash', c'/root/boot-scrub.txt', parent, other, 0, &output[0])
		check(contains(&output[0], c'mappings=9 matched=9 changed=0') && contains(&output[0], c'disk=1 slot=19'), c'complete nine-row boot scrub')
		bundle_unchanged(c'/root/boot-scrub.txt', &prior[0], size)
		check(status(c'/dev/mapper/vinix20').generation == first && status(c'/dev/mapper/vinix19').generation == second, c'boot scrub preserves generations')
		C.printf(c'PLAN SCRUB BOOT PRESERVED\n')
	}
}
