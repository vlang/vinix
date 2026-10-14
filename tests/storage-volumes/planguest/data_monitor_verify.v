// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn monitor_verify_hash(kind int) &char {
	return match kind {
		0 { &char(c'd3c83a49404f0aac2fd8ada0d93879d29235727879333ab6c639237958ebb1fa') }
		1 { &char(c'fa7157ddd6f203981f36a4509b65a47fa2b4a2db2be5b326e8eeb3ece2db9ff0') }
		2 { &char(c'8897730dd51816b0fae91c51e70be7ab18b903121d86c73e3e1293e58567dc04') }
		3 { &char(c'37477cbb1c3abaaeb390916b3c02af1a80a5a83923c13079adc8141b36fc185f') }
		4 { &char(c'283245ba4af65e06814ccad901bbe8af43aa21488f9b53d687903ba4822ac894') }
		else { &char(c'') }
	}
}

@[direct_array_access]
fn monitor_verify_expected(output &char, kind int) int {
	count := if kind == 4 { 512 } else if kind == 3 { 3 } else { kind + 1 }; changed := int(kind == 3)
	mut length := int(C.snprintf(output, 8192, c'format=VINIXDM1 operation=verified-data-monitor disks=2 mappings=3 samples=%d changed_samples=%d session_changed=%d final_changed=0 algorithm=sha256 reference_sha256=a54001cd53e073d1214f5c2ed19a0d4f14c18f6408ac69a4c65a6cf75f4d3d0a transcript_sha256=%s\n', count, changed, changed, monitor_verify_hash(kind)))
	for row in 0 .. 3 {
		if row != 1 { length += int(C.snprintf(unsafe { output + length }, usize(8192 - length), c'disk=%d disk_bytes=16777216 sector=512 identity=mbr:%s\n', if row == 2 { 1 } else { 0 }, if row == 2 { &char(c'12345679') } else { &char(c'12345678') })) }
		changed_row := kind == 3 && row != 1
		length += int(C.snprintf(unsafe { output + length }, usize(8192 - length), c'disk=%u slot=%u offset=%lu bytes=%lu readonly=%lu changed_samples=%d stable=%d new_changes=%d restored=%d changed_again=0 final=match expected_sha256=%s final_sha256=%s\n', if row == 2 { u32(1) } else { u32(0) }, if row == 0 { u32(2) } else if row == 1 { u32(5) } else { u32(9) }, if row == 1 { u64(2097152) } else { u64(1048576) }, if row == 1 { u64(12288) } else { u64(8192) }, if row == 1 { u64(1) } else { u64(0) }, int(changed_row), if changed_row { 0 } else { count - 1 }, int(changed_row), int(changed_row), data_reference_digest(row, false), data_reference_digest(row, false)))
	}; check(length > 0 && length < 8192, c'bounded independent transcript summary'); return length
}
@[direct_array_access]
fn monitor_verify_tool(kind int) {
	mut path := [64]char{}; check(C.snprintf(&path[0], 64, c'/root/monitor-clean-%d.txt', kind + 1) > 0, c'bounded verify input')
	input := if kind == 3 { &char(c'/root/monitor-sequence.txt') } else if kind == 4 { &char(c'/root/monitor-long.txt') } else if kind == 5 { &char(c'/root/monitor-late-error.txt') } else if kind == 6 { &char(c'/root/manual-data.vhash') } else { unsafe { &path[0] } }
	unsafe { args := [&char(c'/usr/sbin/vinix-volume'), &char(c'verify-data-monitor'), &char(c'/root/manual-data.vhash'), input, &char(nil)]!
		fd := C.open(c'/root/verify-output', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600)); child := C.fork(); check(fd >= 0 && child >= 0, c'open and fork transcript verifier')
		if child == 0 { if C.dup2(fd, 1) != 1 || C.close(fd) != 0 { C._exit(126) }; C.execv(args[0], &args[0]); C._exit(127) }; check(C.close(fd) == 0, c'close verifier capture'); mut code := i32(-1)
		check(C.waitpid(child, &code, 0) == child && code == (if kind >= 5 { 1 } else if kind == 3 { 2 } else { 0 }) << 8, c'exact whole transcript verification exit')
	}
	mut actual := [8192]char{}; fd := C.open(c'/root/verify-output', C.O_RDONLY); n := C.read(fd, &actual[0], 8191); check(fd >= 0 && n > 0 && n < 8192 && C.close(fd) == 0, c'read complete verifier capture')
	if kind >= 5 { check(C.memcmp(&actual[0], c'vinix-volume:', 13) == 0, c'late diagnostics or non transcript produce only refusal'); return }
	mut expected := [8192]char{}; size := monitor_verify_expected(&expected[0], kind); check(n == size && C.memcmp(&actual[0], &expected[0], usize(size)) == 0, c'exact reference bound verified history and full transcript SHA')
}
fn monitor_verify_matrix() {
	for kind in 0 .. 4 { monitor_verify_tool(kind); mut path := [64]char{}; check(C.snprintf(&path[0], 64, c'/root/verified-monitor-%d.txt', kind + 1) > 0, c'bounded verified history artifact'); copy_scrub_report(c'/root/verify-output', &path[0]) }
	monitor_verify_tool(5); monitor_verify_tool(6)
}
fn monitor_verify_long() { monitor_verify_tool(4); copy_scrub_report(c'/root/verify-output', c'/root/verified-monitor-long.txt'); C.printf(c'PLAN DATA MONITOR VERIFY LONG samples=512\n') }
fn monitor_verify_cycles(count int) { for _ in 0 .. count { monitor_verify_tool(0); monitor_verify_tool(1); monitor_verify_tool(3) }; C.sleep(13); C.printf(c'PLAN DATA MONITOR VERIFY CYCLES count=%d\n', count) }
@[direct_array_access]
fn monitor_verify_retention() {
	monitor_verify_cycles(100); mut before := Heap{}; mut after := Heap{}; heap_snapshot(mut before); heap_snapshot(mut after); heap_snapshot(mut before); monitor_verify_cycles(100); heap_snapshot(mut after)
	C.printf(c'PLAN DATA MONITOR VERIFY LARGE before=%ld after=%ld\n', before.large, after.large); check(before.count == after.count && before.large == after.large, c'verifier large page retention')
	for i in 0 .. before.count { C.printf(c'PLAN DATA MONITOR VERIFY RETAIN size=%ld delta=%ld\n', before.sizes[i], after.live[i] - before.live[i]); check(before.sizes[i] == after.sizes[i] && before.live[i] == after.live[i], c'verifier slab retention') }
}

@[direct_array_access]
fn data_monitor_verify_entry() i32 {
	C.printf(c'PLAN START\n'); warm_image(); phase := C.open(c'/second-boot', C.O_RDONLY); parent := $if amd64 { &char(c'/dev/sd0') } $else { &char(c'/dev/vda') }; other := $if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') }
	if phase < 0 {
		data_auto_setup(parent, other); data_auto_matrix(parent, other, false)
		left := C.open(parent, C.O_RDWR); right := C.open(other, C.O_RDWR); mut a := [4096]u8{}; mut b := [4096]u8{}; mut ca := [4096]u8{}; mut cb := [4096]u8{}
		check(left >= 0 && right >= 0 && C.pread(left, &a[0], 4096, 1048576) == 4096 && C.pread(right, &b[0], 4096, 1048576) == 4096, c'pin monitor corruption fixtures'); ca = a; cb = b; ca[17] ^= 1; cb[93] ^= 3
		check(C.pwrite(left, &ca[0], 4096, 1048576) == 4096 && C.fsync(left) == 0 && C.pwrite(right, &cb[0], 4096, 1048576) == 4096 && C.fsync(right) == 0, c'persist monitor baseline corruption'); data_auto_matrix(parent, other, true)
		check(C.pwrite(left, &a[0], 4096, 1048576) == 4096 && C.fsync(left) == 0 && C.pwrite(right, &b[0], 4096, 1048576) == 4096 && C.fsync(right) == 0, c'restore monitor baseline'); data_auto_matrix(parent, other, false)
		first := status(c'/dev/mapper/vinix2'); second := status(c'/dev/mapper/vinix9'); readonly := status(c'/dev/mapper/vinix5'); held := C.open(c'/dev/mapper/vinix9', C.O_RDONLY)
		root := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY); check(held >= 0 && root >= 0 && C.flock(root, C.LOCK_EX | C.LOCK_NB) == 0, c'hold live view and monitor writer contention')
		copy_plan(c'/root/manual-data.vhash', c'/root/monitor-input.vhash'); child := data_monitor_start(c'/root/monitor-input.vhash', c'2', c'3'); data_monitor_wait_samples(1, 1)
		check(C.pwrite(left, &ca[0], 4096, 1048576) == 4096 && C.fsync(left) == 0 && C.pwrite(right, &cb[0], 4096, 1048576) == 4096 && C.fsync(right) == 0, c'change data during monitor interval'); data_monitor_wait_samples(2, 1)
		check(C.pwrite(left, &a[0], 4096, 1048576) == 4096 && C.fsync(left) == 0 && C.pwrite(right, &b[0], 4096, 1048576) == 4096 && C.fsync(right) == 0, c'restore data during monitor interval')
		bad := C.open(c'/root/monitor-replacement', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600)); byte := u8(0); check(bad >= 0 && C.write(bad, &byte, 1) == 1 && C.fsync(bad) == 0 && C.close(bad) == 0 && C.rename(c'/root/monitor-replacement', c'/root/monitor-input.vhash') == 0, c'replace reference pathname during held session')
		data_monitor_finish(child, 3, 1, 2); copy_scrub_report(c'/root/monitor-output', c'/root/monitor-sequence.txt'); copy_plan(c'/root/manual-data.vhash', c'/root/monitor-input.vhash')
		check(C.pwrite(left, &ca[0], 4096, 1048576) == 4096 && C.fsync(left) == 0 && C.pwrite(right, &cb[0], 4096, 1048576) == 4096 && C.fsync(right) == 0, c'persist first changed error-session sample'); failed := data_monitor_start(c'/root/manual-data.vhash', c'2', c'3'); data_monitor_wait_samples(1, 2); signature(other, 0x1234567a)
		data_monitor_finish(failed, 1, 2, 1); copy_scrub_report(c'/root/monitor-output', c'/root/monitor-late-error.txt'); signature(other, 0x12345679)
		check(C.pwrite(left, &a[0], 4096, 1048576) == 4096 && C.fsync(left) == 0 && C.close(left) == 0 && C.pwrite(right, &b[0], 4096, 1048576) == 4096 && C.fsync(right) == 0 && C.close(right) == 0, c'restore and flush monitor data and identity')
		data_monitor_matrix(); monitor_verify_matrix(); check(first == status(c'/dev/mapper/vinix2') && second == status(c'/dev/mapper/vinix9') && readonly == status(c'/dev/mapper/vinix5') && C.close(root) == 0, c'monitor preserves complete live status under writer contention')
		check(C.pread(held, &ca[0], 4096, 0) == 4096 && C.close(held) == 0, c'read held monitor view'); for value in ca { check(value == 0x9c, c'preserved restored monitor view') }
		data_monitor_long(); data_monitor_retention(); monitor_verify_long(); monitor_verify_retention(); copy_plan(c'/root/auto-data.vset', c'/etc/vinix/volumes.vset'); check(C.unlink(c'/etc/vinix/volumes.vmap') == 0, c'remove invalid monitor boot plan'); marker := C.open(c'/second-boot', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600)); check(marker >= 0 && C.fsync(marker) == 0 && C.close(marker) == 0, c'persist monitor boot phase')
		C.printf(c'PLAN DATA MONITOR VERIFY PASSED: complete repeated scans, held discovery/reference, restored-data latch, late failure precedence and bounded lifetimes\n')
	} else { check(C.close(phase) == 0, c'close monitor phase'); data_auto_matrix(other, parent, false); data_monitor_matrix(); monitor_verify_matrix(); C.printf(c'PLAN DATA MONITOR VERIFY REORDERED BOOT PRESERVED\n') }
	for file in [&char(c'/root/data-output'), &char(c'/root/scrub-output'), &char(c'/root/auto-data-output'), &char(c'/root/monitor-output'), &char(c'/root/verify-output')]! { if C.unlink(file) != 0 { check(C.errno == C.ENOENT, c'reclaim monitor captures') } }
	for path in [&char(c'/root'), &char(c'/etc/vinix'), &char(c'/')]! { fd := C.open(path, C.O_RDONLY | C.O_DIRECTORY); check(fd >= 0 && C.fsync(fd) == 0 && C.close(fd) == 0, c'persist monitor artifacts and boot phase') }; C.printf(c'PLAN DONE\n'); for { C.pause() }; return 0
}
