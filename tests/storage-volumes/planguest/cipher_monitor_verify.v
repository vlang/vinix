// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn cipher_verify_hash(recovery bool, readonly bool, kind int) &char {
	index := if kind == 4 { 12 } else if kind == 5 { 13 } else { int(readonly) * 6 + int(recovery) * 3 + kind - 1 }
	return match index {
		0 { &char(c'53edb913226d3a1f818af0387699ed7f4aa30f47994da434ebb1b45ccaf05f70') }
		1 { &char(c'12d3bcf67680b4155f5051e30af42688eb1c81bbdcf5a35ee35b7b70ba7bb109') }
		2 { &char(c'9b950951202057e3448bcd1f116b8e8bf54fb45aee2a44e6e5627b17df565fe3') }
		3 { &char(c'3dd62846eb8abee5ac93123d8d8f52e60e3e4a9d3d456b9e0c3092a80a3ebd04') }
		4 { &char(c'cee6f004bcedd4fa7dedce7d1187724ca2f308ed0874e5bad2e9e80e3ec2400a') }
		5 { &char(c'35b7995160f8210eaee7e01825d734a24eef4e53c700807e237d81ff0e3bdae6') }
		6 { &char(c'26751d63be0540b15b443714c49045ca3d7c40972855b1a0497472e72dd5c013') }
		7 { &char(c'7754ae7b207487d55e6cffdba4a49dc5c79cfb31f363f3dda9592b3287f0b65e') }
		8 { &char(c'78568b8fc78b8264cc62e787d3f307f669be31d5ed5c48637df5c16bad6a13f9') }
		9 { &char(c'2128dbfd7421a890153c55db405f31ad70ce8f69dcdcd8e6e56309069e9b63c4') }
		10 { &char(c'94d494ae6b44b7971590a8a020d3910e634ef0b789c31044875881a390e7b623') }
		11 { &char(c'ba6754f7cc1a4713af57e9f23e814b0651497689ba719904f6ecf6a17b05458b') }
		12 { &char(c'19b71ee07918af50c9912e74b5d300079e79739f18eb94d53f8c81fd82ba0d18') }
		13 { &char(c'cfcbe23ef19b9583424cd4b1897532be6c5b406bd99418358d409c963f6166b7') }
		else { &char(c'') }
	}
}

@[direct_array_access]
fn cipher_verify_expected(output &char, recovery bool, readonly bool, kind int) int {
	count := if kind == 5 { 512 } else if kind == 4 { 3 } else { kind }; changed := int(kind == 4)
	return int(C.snprintf(output, 2048, c'format=VINIXCM1 operation=verified-ciphertext-monitor source=%s mappings=1 samples=%d changed_samples=%d session_changed=%d final_changed=0 stable=%d new_changes=%d restored=%d changed_again=0 algorithm=sha256 reference_sha256=%s transcript_sha256=%s\ndisk_bytes=16777216 sector=512 identity=mbr:12345678 slot=60 offset=15728640 bytes=4096 readonly=%lu result=match expected_sha256=%s final_sha256=%s\n', if recovery { &char(c'recovery') } else { &char(c'volume') }, count, changed, changed, if changed != 0 { 0 } else { count - 1 }, changed, changed, reference_hash(readonly, false), cipher_verify_hash(recovery, readonly, kind), u64(readonly), reference_digest(false), reference_digest(false)))
}
@[direct_array_access]
fn cipher_verify_tool(recovery bool, readonly bool, kind int) {
	mut path := [96]char{}; check(C.snprintf(&path[0], 96, c'/root/monitor-%s%s-%d.txt', if recovery { &char(c'recovery') } else { &char(c'volume') }, if readonly { &char(c'-ro') } else { &char(c'') }, kind) > 0, c'bounded ciphertext verifier input')
	input := if kind in [4, 7]! { &char(c'/root/monitor-sequence.txt') } else if kind == 5 { &char(c'/root/monitor-long.txt') } else if kind == 6 { &char(c'/root/monitor-late-error.txt') } else { unsafe { &path[0] } }
	unsafe { args := [&char(c'/usr/sbin/vinix-volume'), &char(c'verify-volume-monitor'), if readonly { &char(c'/root/volume-ro.vchash') } else { &char(c'/root/volume.vchash') }, input, &char(nil)]!
		fd := C.open(c'/root/cipher-verify.out', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600)); check(fd >= 0, c'open ciphertext verifier capture'); child := C.fork(); check(child >= 0, c'fork ciphertext verifier')
		if child == 0 { if C.dup2(fd, 1) != 1 || C.close(fd) != 0 { C._exit(126) }; C.execv(args[0], &args[0]); C._exit(127) }; check(C.close(fd) == 0, c'close ciphertext verifier capture'); mut code := i32(-1)
		check(C.waitpid(child, &code, 0) == child && code == (if kind >= 6 { 1 } else if kind == 4 { 2 } else { 0 }) << 8, c'exact ciphertext verifier exit')
	}
	mut actual := [2048]char{}; fd := C.open(c'/root/cipher-verify.out', C.O_RDONLY); n := C.read(fd, &actual[0], 2047); check(fd >= 0 && n > 0 && n < 2048 && C.close(fd) == 0, c'read full ciphertext verifier output')
	if kind >= 6 { check(C.memcmp(&actual[0], c'vinix-volume:', 13) == 0, c'late error or wrong reference produces only refusal'); return }
	mut expected := [2048]char{}; size := cipher_verify_expected(&expected[0], recovery, readonly, kind); check(size > 0 && size < 2048 && n == size && C.memcmp(&actual[0], &expected[0], usize(size)) == 0, c'exact complete ciphertext history and original input hashes')
}
@[direct_array_access]
fn cipher_verify_matrix() {
	mut path := [96]char{}
	for readonly in [false, true]! { for recovery in [false, true]! { for count in 1 .. 4 { cipher_verify_tool(recovery, readonly, count); check(C.snprintf(&path[0], 96, c'/root/verified-%s%s-%d.txt', if recovery { &char(c'recovery') } else { &char(c'volume') }, if readonly { &char(c'-ro') } else { &char(c'') }, count) > 0, c'bounded ciphertext history artifact'); copy_scrub_report(c'/root/cipher-verify.out', &path[0]) } } }
	cipher_verify_tool(false, true, 4); copy_scrub_report(c'/root/cipher-verify.out', c'/root/verified-sequence.txt'); cipher_verify_tool(true, false, 6); cipher_verify_tool(false, false, 7)
}
fn cipher_verify_long() { cipher_verify_tool(false, true, 5); copy_scrub_report(c'/root/cipher-verify.out', c'/root/verified-long.txt'); C.printf(c'PLAN CIPHER MONITOR VERIFY LONG samples=512\n') }
fn cipher_verify_cycles(count int) { for _ in 0 .. count { cipher_verify_tool(false, false, 1); cipher_verify_tool(true, true, 2); cipher_verify_tool(false, true, 4) }; C.sleep(13); C.printf(c'PLAN CIPHER MONITOR VERIFY CYCLES count=%d\n', count) }
@[direct_array_access]
fn cipher_verify_retention() {
	cipher_verify_cycles(100); mut before := Heap{}; mut after := Heap{}; heap_snapshot(mut before); heap_snapshot(mut after); heap_snapshot(mut before); cipher_verify_cycles(100); heap_snapshot(mut after)
	C.printf(c'PLAN CIPHER MONITOR VERIFY LARGE before=%ld after=%ld\n', before.large, after.large); check(before.count == after.count && before.large == after.large, c'ciphertext verifier large page retention')
	for i in 0 .. before.count { C.printf(c'PLAN CIPHER MONITOR VERIFY RETAIN size=%ld delta=%ld\n', before.sizes[i], after.live[i] - before.live[i]); check(before.sizes[i] == after.sizes[i] && before.live[i] == after.live[i], c'ciphertext verifier slab retention') }
}

@[direct_array_access]
fn cipher_monitor_verify_entry() i32 {
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
		cipher_monitor_matrix(); cipher_verify_matrix(); check(before == status(c'/dev/mapper/vinix60') && C.close(root) == 0, c'encrypted monitor preserves complete live status under writer contention'); crypt_data(held, 0, 0x73); check(C.close(held) == 0, c'close retained encrypted view'); simple(c'remove', c'/dev/mapper/vinix60', unsafe { nil }, 0)
		cipher_monitor_long(); cipher_monitor_retention(); cipher_verify_long(); cipher_verify_retention(); check(C.open(c'/root/crypt.key', C.O_RDONLY) < 0 && C.errno == C.ENOENT, c'monitor creates no raw keyfile')
		C.printf(c'PLAN CIPHER MONITOR VERIFY PASSED: one authentication per pinned session, complete repeated ciphertext scans, erased secrets, restored-data latch, late-error precedence and bounded real-KDF lifetimes\n')
	} else { check(C.close(phase) == 0, c'close cipher monitor phase'); cipher_binding_matrix(); cipher_monitor_matrix(); cipher_verify_matrix(); recovery_unlock_view($if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') }, c'/root/volume-ro.vrecover', false, true); C.printf(c'PLAN CIPHER MONITOR VERIFY REORDERED BOOT PRESERVED\n') }
	for path in [&char(c'/root/cipher-monitor.out'), &char(c'/root/cipher-bind.out'), &char(c'/root/cipher-verify.out')]! { check(C.unlink(path) == 0, c'reclaim cipher monitor captures') }; fd := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY); check(fd >= 0 && C.fsync(fd) == 0 && C.close(fd) == 0, c'persist complete cipher monitor evidence'); C.printf(c'PLAN DONE\n'); for { C.pause() }; return 0
}
