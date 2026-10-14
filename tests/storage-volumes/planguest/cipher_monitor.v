// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

@[direct_array_access]
fn cipher_monitor_wanted(output &char, start int, count int, recovery bool, readonly bool, kind int) int {
	mut size := 0
	for sample in start .. start + count {
		changed := kind == 2 || (kind == 1 && sample == 2); latched := kind == 2 || (kind == 1 && sample >= 2)
		size += int(C.snprintf(unsafe { output + size }, usize(8192 - size), c'format=VINIXCM1 operation=monitored-ciphertext source=%s sample=%d changed_samples=%d session_changed=%d\nformat=VINIXCS1 operation=scrubbed-ciphertext mappings=1 matched=%d changed=%d algorithm=sha256 reference_sha256=%s\ndisk_bytes=16777216 sector=512 identity=mbr:12345678 slot=60 offset=15728640 bytes=4096 readonly=%lu result=%s expected_sha256=%s actual_sha256=%s\n', if recovery { &char(c'recovery') } else { &char(c'volume') }, sample, int(latched), int(latched), int(!changed), int(changed), reference_hash(readonly, false), u64(readonly), if changed { &char(c'changed') } else { &char(c'match') }, reference_digest(false), reference_digest(changed)))
	}
	check(size > 0 && size < 8192, c'bounded independent complete ciphertext monitor expectation'); return size
}
@[direct_array_access]
fn cipher_monitor_start(input &char, credential &char, reference &char, interval &char, count &char, recovery bool) i32 {
	unsafe { args := [&char(c'/usr/sbin/vinix-volume'), if recovery { &char(c'monitor-recovery-volume-auto') } else { &char(c'monitor-volume-auto') }, input, credential, reference, interval, count, &char(nil)]!
		fd := C.open(c'/root/cipher-monitor.out', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600)); check(fd >= 0, c'open ciphertext monitor capture'); child := C.fork(); check(child >= 0, c'fork ciphertext monitor')
		if child == 0 { if C.dup2(fd, 1) != 1 || C.close(fd) != 0 { C._exit(126) }; C.execv(args[0], &args[0]); C._exit(127) }; check(C.close(fd) == 0, c'close ciphertext monitor capture'); return child }
}
@[direct_array_access]
fn cipher_monitor_command(recovery bool, readonly bool, interval &char, count &char) i32 {
	input := if recovery { if readonly { &char(c'/root/volume-ro.vrecover') } else { &char(c'/root/volume.vrecover') } } else { if readonly { &char(c'/root/volume-ro.sealed') } else { &char(c'/root/volume.sealed') } }
	return cipher_monitor_start(input, if recovery { &char(c'/root/recovery.key') } else { &char(c'/root/crypt.pass') }, if readonly { &char(c'/root/volume-ro.vchash') } else { &char(c'/root/volume.vchash') }, interval, count, recovery)
}
@[direct_array_access]
fn cipher_monitor_wait(count int, recovery bool, readonly bool, kind int) {
	mut expected := [8192]char{}; size := cipher_monitor_wanted(&expected[0], 1, count, recovery, readonly, kind); mut actual := [8192]char{}; fd := C.open(c'/root/cipher-monitor.out', C.O_RDONLY); check(fd >= 0, c'open ciphertext checkpoint')
	for _ in 0 .. 6000 { n := C.pread(fd, &actual[0], 8191, 0); check(n >= 0 && n < 8192, c'read ciphertext checkpoint'); if n >= size && C.memcmp(&actual[0], &expected[0], usize(size)) == 0 { check(C.close(fd) == 0, c'close ciphertext checkpoint'); return }; C.usleep(10000) }; check(false, c'ciphertext monitor checkpoint timeout')
}
@[direct_array_access]
fn cipher_monitor_finish(child i32, count int, recovery bool, readonly bool, kind int, result i32) {
	mut code := i32(-1); check(C.waitpid(child, &code, 0) == child && code == result << 8, c'ciphertext monitor exact exit'); mut expected := [8192]char{}; mut size := cipher_monitor_wanted(&expected[0], 1, count, recovery, readonly, kind)
	if kind == 2 { size += int(C.snprintf(unsafe { &expected[size] }, usize(8192 - size), c'vinix-volume: volume disk identity or geometry changed before publication or import\n')) }
	mut actual := [8192]char{}; fd := C.open(c'/root/cipher-monitor.out', C.O_RDONLY); check(fd >= 0 && C.read(fd, &actual[0], 8191) == size && C.close(fd) == 0 && C.memcmp(&actual[0], &expected[0], usize(size)) == 0, c'complete ciphertext monitor transcript and persistent status')
}
@[direct_array_access]
fn cipher_monitor_tool(recovery bool, readonly bool, count int) {
	mut number := [32]char{}; check(C.snprintf(&number[0], 32, c'%d', count) > 0, c'bounded ciphertext count'); child := cipher_monitor_command(recovery, readonly, c'0', &number[0]); cipher_monitor_finish(child, count, recovery, readonly, 0, 0)
}
@[direct_array_access]
fn cipher_monitor_matrix() {
	mut name := [96]char{}
	for readonly in [false, true]! { for recovery in [false, true]! { for count in 1 .. 4 { cipher_monitor_tool(recovery, readonly, count); check(C.snprintf(&name[0], 96, c'/root/monitor-%s%s-%d.txt', if recovery { &char(c'recovery') } else { &char(c'volume') }, if readonly { &char(c'-ro') } else { &char(c'') }, count) > 0, c'bounded monitor transcript name'); copy_scrub_report(c'/root/cipher-monitor.out', &name[0]) } } }
}
@[direct_array_access]
fn cipher_monitor_long() {
	child := cipher_monitor_command(false, true, c'0', c'512'); mut code := i32(-1); check(C.waitpid(child, &code, 0) == child && code == 0, c'long encrypted monitor exit'); fd := C.open(c'/root/cipher-monitor.out', C.O_RDONLY); check(fd >= 0, c'open long encrypted monitor'); mut expected := [8192]char{}; mut actual := [8192]char{}
	for sample in 1 .. 513 { size := cipher_monitor_wanted(&expected[0], sample, 1, false, true, 0); check(C.read(fd, &actual[0], usize(size)) == size && C.memcmp(&actual[0], &expected[0], usize(size)) == 0, c'every complete long encrypted monitor frame') }
	check(C.read(fd, &actual[0], 1) == 0 && C.close(fd) == 0 && C.rename(c'/root/cipher-monitor.out', c'/root/monitor-long.txt') == 0, c'persist long encrypted monitor'); C.printf(c'PLAN CIPHER MONITOR LONG samples=512\n')
}
fn cipher_monitor_cycles(count int) {
	for _ in 0 .. count { cipher_monitor_tool(false, true, 3); cipher_monitor_tool(true, false, 3); for _ in 0 .. 25 { cipher_monitor_tool(true, true, 1); cipher_monitor_tool(true, false, 2); cipher_monitor_tool(true, true, 3) } }
	C.sleep(13); C.printf(c'PLAN CIPHER MONITOR CYCLES count=%d\n', count)
}
@[direct_array_access]
fn cipher_monitor_retention() {
	cipher_monitor_cycles(4); mut before := Heap{}; mut after := Heap{}; heap_snapshot(mut before); heap_snapshot(mut after); heap_snapshot(mut before); cipher_monitor_cycles(4); heap_snapshot(mut after)
	C.printf(c'PLAN CIPHER MONITOR LARGE before=%ld after=%ld\n', before.large, after.large); check(before.count == after.count && before.large == after.large, c'cipher monitor large-page retention')
	for i in 0 .. before.count { C.printf(c'PLAN CIPHER MONITOR RETAIN size=%ld delta=%ld\n', before.sizes[i], after.live[i] - before.live[i]); check(before.sizes[i] == after.sizes[i] && before.live[i] == after.live[i], c'cipher monitor slab retention') }
}
@[direct_array_access]
fn cipher_monitor_entry() i32 {
	C.printf(c'PLAN START\n'); warm_image(); phase := C.open(c'/second-boot', C.O_RDONLY); parent := $if amd64 { &char(c'/dev/sd0') } $else { &char(c'/dev/vda') }
	if phase < 0 {
		volume_scrub_first(parent, $if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') }); cipher_binding_matrix(); recovery_unlock_tool(c'/root/volume-ro.vrecover', c'/root/recovery.key', false, 0)
		before := status(c'/dev/mapper/vinix60'); held := C.open(c'/dev/mapper/vinix60', C.O_RDONLY); root := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY); check(held >= 0 && root >= 0 && C.flock(root, C.LOCK_EX | C.LOCK_NB) == 0, c'hold live encrypted view and writer contention')
		raw := C.open(parent, C.O_RDWR); mut original := [512]u8{}; mut changed := [512]u8{}; check(raw >= 0 && C.pread(raw, &original[0], 512, 15728640) == 512, c'pin ciphertext monitor corruption'); changed = original; changed[0] ^= 1
		copy_plan(c'/root/volume-ro.sealed', c'/root/monitor.sealed'); copy_scrub_report(c'/root/crypt.pass', c'/root/monitor.pass'); copy_plan(c'/root/volume-ro.vchash', c'/root/monitor-input.vchash')
		child := cipher_monitor_start(c'/root/monitor.sealed', c'/root/monitor.pass', c'/root/monitor-input.vchash', c'2', c'3', false); cipher_monitor_wait(1, false, true, 1)
		check(C.pwrite(raw, &changed[0], 512, 15728640) == 512 && C.fsync(raw) == 0, c'change physical ciphertext between monitor samples'); cipher_monitor_wait(2, false, true, 1)
		check(C.pwrite(raw, &original[0], 512, 15728640) == 512 && C.fsync(raw) == 0, c'restore physical ciphertext between monitor samples')
		for path in [&char(c'/root/monitor.sealed'), &char(c'/root/monitor.pass'), &char(c'/root/monitor-input.vchash')]! { bad := C.open(c'/root/cipher-monitor-replacement', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600)); byte := u8(0); check(bad >= 0 && C.write(bad, &byte, 1) == 1 && C.fsync(bad) == 0 && C.close(bad) == 0 && C.rename(c'/root/cipher-monitor-replacement', path) == 0, c'replace authenticated/reference path after secrets erased') }
		cipher_monitor_finish(child, 3, false, true, 1, 2); copy_scrub_report(c'/root/cipher-monitor.out', c'/root/monitor-sequence.txt'); copy_plan(c'/root/volume-ro.vchash', c'/root/monitor-input.vchash'); check(C.unlink(c'/root/monitor.sealed') == 0 && C.unlink(c'/root/monitor.pass') == 0, c'reclaim replaced credential copies')
		check(C.pwrite(raw, &changed[0], 512, 15728640) == 512 && C.fsync(raw) == 0, c'persist changed ciphertext error sample'); failed := cipher_monitor_command(true, false, c'2', c'3'); cipher_monitor_wait(1, true, false, 2); signature(parent, 0x1234567a)
		cipher_monitor_finish(failed, 1, true, false, 2, 1); copy_scrub_report(c'/root/cipher-monitor.out', c'/root/monitor-late-error.txt'); signature(parent, 0x12345678); check(C.pwrite(raw, &original[0], 512, 15728640) == 512 && C.fsync(raw) == 0 && C.close(raw) == 0, c'restore ciphertext and physical identity')
		cipher_monitor_matrix(); check(before == status(c'/dev/mapper/vinix60') && C.close(root) == 0, c'encrypted monitor preserves complete live status under writer contention'); crypt_data(held, 0, 0x73); check(C.close(held) == 0, c'close retained encrypted view'); simple(c'remove', c'/dev/mapper/vinix60', unsafe { nil }, 0)
		cipher_monitor_long(); cipher_monitor_retention(); check(C.open(c'/root/crypt.key', C.O_RDONLY) < 0 && C.errno == C.ENOENT, c'monitor creates no raw keyfile')
		C.printf(c'PLAN CIPHER MONITOR PASSED: one authentication per pinned session, complete repeated ciphertext scans, erased secrets, restored-data latch, late-error precedence and bounded real-KDF lifetimes\n')
	} else { check(C.close(phase) == 0, c'close cipher monitor phase'); cipher_binding_matrix(); cipher_monitor_matrix(); recovery_unlock_view($if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') }, c'/root/volume-ro.vrecover', false, true); C.printf(c'PLAN CIPHER MONITOR REORDERED BOOT PRESERVED\n') }
	for path in [&char(c'/root/cipher-monitor.out'), &char(c'/root/cipher-bind.out')]! { check(C.unlink(path) == 0, c'reclaim cipher monitor captures') }; fd := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY); check(fd >= 0 && C.fsync(fd) == 0 && C.close(fd) == 0, c'persist complete cipher monitor evidence'); C.printf(c'PLAN DONE\n'); for { C.pause() }; return 0
}
