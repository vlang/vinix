// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

#include <unistd.h>
fn C.usleep(u32) i32

@[direct_array_access]
fn data_monitor_expected(output &char, start int, count int, kind int) int {
	mut length := 0
	for sample in start .. start + count {
		changed := kind == 2 || (kind == 1 && sample == 2); latched := kind == 2 || (kind == 1 && sample >= 2)
		length += int(C.snprintf(unsafe { output + length }, usize(8192 - length), c'format=VINIXDM1 operation=monitored-data sample=%d changed_samples=%d session_changed=%d\nformat=VINIXSR1 operation=scrubbed-data disks=2 mappings=3 matched=%d changed=%d algorithm=sha256 reference_sha256=a54001cd53e073d1214f5c2ed19a0d4f14c18f6408ac69a4c65a6cf75f4d3d0a\n', sample, int(latched), int(latched), if changed { 1 } else { 3 }, if changed { 2 } else { 0 }))
		for row in 0 .. 3 { length += int(C.snprintf(unsafe { output + length }, usize(8192 - length), c'disk=%u slot=%u offset=%lu bytes=%lu readonly=%lu result=%s expected_sha256=%s actual_sha256=%s\n', if row == 2 { u32(1) } else { u32(0) }, if row == 0 { u32(2) } else if row == 1 { u32(5) } else { u32(9) }, if row == 1 { u64(2097152) } else { u64(1048576) }, if row == 1 { u64(12288) } else { u64(8192) }, if row == 1 { u64(1) } else { u64(0) }, if row == 1 || !changed { &char(c'match') } else { &char(c'changed') }, data_reference_digest(row, false), data_reference_digest(row, changed))) }
	}
	check(length > 0 && length < 8192, c'bounded independent monitor expectation'); return length
}
@[direct_array_access]
fn data_monitor_start(path &char, interval &char, count &char) i32 {
	unsafe { args := [&char(c'/usr/sbin/vinix-volume'), &char(c'monitor-data-auto'), path, interval, count, &char(nil)]!; fd := C.open(c'/root/monitor-output', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600)); check(fd >= 0, c'open monitor capture'); child := C.fork(); check(child >= 0, c'fork monitor')
		if child == 0 { if C.dup2(fd, 1) != 1 || C.close(fd) != 0 { C._exit(126) }; C.execv(args[0], &args[0]); C._exit(127) }; check(C.close(fd) == 0, c'close monitor capture'); return child }
}
@[direct_array_access]
fn data_monitor_wait_samples(count int, kind int) {
	mut expected := [8192]char{}; size := data_monitor_expected(&expected[0], 1, count, kind); mut actual := [8192]char{}
	fd := C.open(c'/root/monitor-output', C.O_RDONLY); check(fd >= 0, c'open monitor checkpoint')
	for _ in 0 .. 3000 { n := C.pread(fd, &actual[0], 8191, 0); check(n >= 0 && n < 8192, c'read monitor checkpoint'); if n >= size && C.memcmp(&actual[0], &expected[0], usize(size)) == 0 { check(C.close(fd) == 0, c'close monitor checkpoint'); return }; C.usleep(10000) }
	check(false, c'monitor checkpoint timed out')
}
@[direct_array_access]
fn data_monitor_finish(child i32, count int, kind int, expected_code i32) {
	mut code := i32(-1); check(C.waitpid(child, &code, 0) == child && code == expected_code << 8, c'monitor exact exit')
	mut expected := [8192]char{}; mut size := data_monitor_expected(&expected[0], 1, count, kind)
	if kind == 2 { size += int(C.snprintf(unsafe { &expected[size] }, usize(8192 - size), c'vinix-volume: checksum disk identity or geometry changed\n')) }
	mut actual := [8192]char{}; fd := C.open(c'/root/monitor-output', C.O_RDONLY); n := C.read(fd, &actual[0], 8191); check(fd >= 0 && n == size && C.close(fd) == 0 && C.memcmp(&actual[0], &expected[0], usize(size)) == 0, c'exact complete monitor transcript and latched status')
}
@[direct_array_access]
fn data_monitor_tool(count int) {
	mut number := [32]char{}; check(C.snprintf(&number[0], 32, c'%d', count) > 0, c'bounded monitor count'); child := data_monitor_start(c'/root/manual-data.vhash', c'0', &number[0]); data_monitor_finish(child, count, 0, 0)
}
@[direct_array_access]
fn data_monitor_matrix() {
	for count in 1 .. 4 { data_monitor_tool(count); mut path := [64]char{}; check(C.snprintf(&path[0], 64, c'/root/monitor-clean-%d.txt', count) > 0, c'bounded monitor artifact'); copy_scrub_report(c'/root/monitor-output', &path[0]) }
}
@[direct_array_access]
fn data_monitor_long() {
	child := data_monitor_start(c'/root/manual-data.vhash', c'0', c'512'); mut code := i32(-1); check(C.waitpid(child, &code, 0) == child && code == 0, c'long monitor exact exit')
	fd := C.open(c'/root/monitor-output', C.O_RDONLY); check(fd >= 0, c'open long monitor'); mut expected := [8192]char{}; mut actual := [8192]char{}
	for sample in 1 .. 513 { size := data_monitor_expected(&expected[0], sample, 1, 0); check(C.read(fd, &actual[0], usize(size)) == size && C.memcmp(&actual[0], &expected[0], usize(size)) == 0, c'long monitor every complete sample') }
	check(C.read(fd, &actual[0], 1) == 0 && C.close(fd) == 0 && C.rename(c'/root/monitor-output', c'/root/monitor-long.txt') == 0, c'persist exact long monitor'); C.printf(c'PLAN DATA MONITOR LONG samples=512\n')
}
fn data_monitor_cycles(count int) { for _ in 0 .. count { data_monitor_tool(1); data_monitor_tool(2); data_monitor_tool(3) }; C.sleep(13); C.printf(c'PLAN DATA MONITOR CYCLES count=%d\n', count) }
@[direct_array_access]
fn data_monitor_retention() {
	data_monitor_cycles(100); mut before := Heap{}; mut after := Heap{}; heap_snapshot(mut before); heap_snapshot(mut after); heap_snapshot(mut before); data_monitor_cycles(100); heap_snapshot(mut after)
	C.printf(c'PLAN DATA MONITOR LARGE before=%ld after=%ld\n', before.large, after.large); check(before.count == after.count && before.large == after.large, c'monitor large-page retention')
	for i in 0 .. before.count { C.printf(c'PLAN DATA MONITOR RETAIN size=%ld delta=%ld\n', before.sizes[i], after.live[i] - before.live[i]); check(before.sizes[i] == after.sizes[i] && before.live[i] == after.live[i], c'monitor slab retention') }
}
@[direct_array_access]
fn data_monitor_entry() i32 {
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
		data_monitor_matrix(); check(first == status(c'/dev/mapper/vinix2') && second == status(c'/dev/mapper/vinix9') && readonly == status(c'/dev/mapper/vinix5') && C.close(root) == 0, c'monitor preserves complete live status under writer contention')
		check(C.pread(held, &ca[0], 4096, 0) == 4096 && C.close(held) == 0, c'read held monitor view'); for value in ca { check(value == 0x9c, c'preserved restored monitor view') }
		data_monitor_long(); data_monitor_retention(); copy_plan(c'/root/auto-data.vset', c'/etc/vinix/volumes.vset'); check(C.unlink(c'/etc/vinix/volumes.vmap') == 0, c'remove invalid monitor boot plan'); marker := C.open(c'/second-boot', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600)); check(marker >= 0 && C.fsync(marker) == 0 && C.close(marker) == 0, c'persist monitor boot phase')
		C.printf(c'PLAN DATA MONITOR PASSED: complete repeated scans, held discovery/reference, restored-data latch, late failure precedence and bounded lifetimes\n')
	} else { check(C.close(phase) == 0, c'close monitor phase'); data_auto_matrix(other, parent, false); data_monitor_matrix(); C.printf(c'PLAN DATA MONITOR REORDERED BOOT PRESERVED\n') }
	for file in [&char(c'/root/data-output'), &char(c'/root/scrub-output'), &char(c'/root/auto-data-output'), &char(c'/root/monitor-output')]! { if C.unlink(file) != 0 { check(C.errno == C.ENOENT, c'reclaim monitor captures') } }
	for path in [&char(c'/root'), &char(c'/etc/vinix'), &char(c'/')]! { fd := C.open(path, C.O_RDONLY | C.O_DIRECTORY); check(fd >= 0 && C.fsync(fd) == 0 && C.close(fd) == 0, c'persist monitor artifacts and boot phase') }; C.printf(c'PLAN DONE\n'); for { C.pause() }; return 0
}
