// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

@[direct_array_access]
fn volume_scrub_tool(parent &char, report &char, recovery bool, readonly bool, offline bool, changed bool, expected i32) {
	unsafe {
		input := if recovery { if readonly { &char(c'/root/volume-ro.vrecover') } else { &char(c'/root/volume.vrecover') } }
			else { if readonly { &char(c'/root/volume-ro.sealed') } else { &char(c'/root/volume.sealed') } }
		mut args := [&char(c'/usr/sbin/vinix-volume'), if recovery { &char(c'scrub-recovery-volume') } else { &char(c'scrub-volume') }, parent, input,
			if recovery { &char(c'/root/recovery.key') } else { &char(c'/root/crypt.pass') }, if readonly { &char(c'/root/volume-ro.vchash') } else { &char(c'/root/volume.vchash') }, report, &char(nil)]!
		if offline { args[1] = &char(c'show-volume-scrub'); args[2] = report; args[3] = &char(nil) }
		capture := C.open(c'/root/scrub.out', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600)); check(capture >= 0, c'open scrub capture')
		child := C.fork(); check(child >= 0, c'fork scrub tool')
		if child == 0 { if C.dup2(capture, 1) != 1 || C.close(capture) != 0 { C._exit(126) }; C.execv(args[0], &args[0]); C._exit(127) }
		check(C.close(capture) == 0, c'close scrub capture'); mut code := i32(0)
		check(C.waitpid(child, &code, 0) == child && code == expected << 8, c'scrub command exact exit')
		fd := C.open(c'/root/scrub.out', C.O_RDONLY); mut text := [2048]char{}
		check(fd >= 0, c'open scrub output'); count := C.read(fd, &text[0], 2047)
		check(count >= 0 && count < 2047 && C.close(fd) == 0, c'bounded scrub output')
		if expected == 1 { check(C.strstr(&text[0], c'operation=') == nil, c'incomplete scrub reports no finding'); return }
		mut wanted := [2048]char{}
		C.snprintf(&wanted[0], 2048, c'format=VINIXCS1 operation=scrubbed-ciphertext mappings=1 matched=%lu changed=%lu algorithm=sha256 reference_sha256=%s\ndisk_bytes=16777216 sector=512 identity=mbr:12345678 slot=60 offset=15728640 bytes=4096 readonly=%lu result=%s expected_sha256=115d50809715a805656e2c32b2d84ce5b4df581c65e1ec9b4523df3f9e4a6748 actual_sha256=%s\n',
			u64(!changed), u64(changed), if readonly { &char(c'b3163f5b9fe199889368f06145927d5c7632102ef305580ff54a0fe37ad426b0') } else { &char(c'ceb82ed81ecbf7ac0ced5930717d27aea59e88d7cf485e3a2bf885974c1d2329') }, u64(readonly),
			if changed { &char(c'changed') } else { &char(c'match') }, if changed { &char(c'a45c3043d314e557b22fa0a7dc53957b2dd84154fedd0865703a1796c63bbc25') } else { &char(c'115d50809715a805656e2c32b2d84ce5b4df581c65e1ec9b4523df3f9e4a6748') })
		check(C.strcmp(&text[0], &wanted[0]) == 0, c'exact scrub findings and reference fingerprint')
	}
}

fn volume_scrub_name(output &char, recovery bool, readonly bool, changed bool) {
	C.snprintf(output, 64, c'/root/%s-%s%s.vcscrub', if changed { &char(c'changed') } else { &char(c'clean') }, if recovery { &char(c'recovery') } else { &char(c'volume') }, if readonly { &char(c'-ro') } else { &char(c'') })
}

fn volume_scrub_cycles(parent &char, count int) {
	for _ in 0 .. count {
		volume_scrub_tool(parent, c'/root/cycle.vcscrub', false, true, false, false, 0)
		volume_scrub_tool(parent, c'/root/cycle-rescue.vcscrub', true, true, false, false, 0)
		volume_scrub_tool(parent, c'/root/cycle-rescue.vcscrub', true, true, true, false, 0)
		check(C.unlink(c'/root/cycle.vcscrub') == 0 && C.unlink(c'/root/cycle-rescue.vcscrub') == 0, c'reclaim scrub cycle reports'); missing(c'/dev/mapper/vinix60')
	}
	C.sleep(13); C.printf(c'PLAN CIPHERTEXT SCRUB CYCLES count=%d\n', count)
}

@[direct_array_access]
fn volume_scrub_retention(parent &char) {
	volume_scrub_cycles(parent, 4); mut before := Heap{}; mut after := Heap{}
	heap_snapshot(mut before); heap_snapshot(mut after); heap_snapshot(mut before)
	volume_scrub_cycles(parent, 4); heap_snapshot(mut after)
	C.printf(c'PLAN CIPHERTEXT SCRUB LARGE before=%ld after=%ld\n', before.large, after.large)
	check(before.count == after.count && before.large == after.large, c'scrub large-page retention')
	for i in 0 .. before.count {
		C.printf(c'PLAN CIPHERTEXT SCRUB RETAIN size=%ld delta=%ld\n', before.sizes[i], after.live[i] - before.live[i])
		check(before.sizes[i] == after.sizes[i] && before.live[i] == after.live[i], c'scrub slab retention')
	}
}

@[direct_array_access]
fn volume_scrub_first(parent &char, wrong &char) {
	unsafe {
		volume_recovery_fixture(parent)
		volume_recovery_tool(c'/root/volume.sealed', c'/root/crypt.pass', c'/root/recovery.key', c'/root/volume.vrecover', true, 0)
		volume_recovery_tool(c'/root/volume-ro.sealed', c'/root/crypt.pass', c'/root/recovery.key', c'/root/volume-ro.vrecover', true, 0)
		ciphertext_tool(parent, c'/root/volume.vchash', false, false, false, 0); ciphertext_tool(parent, c'/root/volume-ro.vchash', false, false, true, 0)
		mut original := [6][320]u8{}; mut again := [320]u8{}
		paths := [&char(c'/root/volume.sealed'), &char(c'/root/volume-ro.sealed'), &char(c'/root/volume.vrecover'), &char(c'/root/volume-ro.vrecover'), &char(c'/root/volume.vchash'), &char(c'/root/volume-ro.vchash')]!
		for i in 0 .. 6 {
			fd := C.open(paths[i], C.O_RDONLY); check(fd >= 0 && C.read(fd, &original[i][0], if i < 4 { usize(320) } else { usize(128) }) == if i < 4 { 320 } else { 128 }, c'snapshot scrub inputs'); check(C.close(fd) == 0, c'close input snapshot')
		}
		mut name := [64]char{}
		for readonly in [false, true]! { for recovery in [false, true]! {
			volume_scrub_name(&name[0], recovery, readonly, false); volume_scrub_tool(parent, &name[0], recovery, readonly, false, false, 0)
			volume_scrub_tool(parent, &name[0], recovery, readonly, true, false, 0)
			volume_scrub_tool(parent, &name[0], recovery, readonly, false, false, 1)
			volume_scrub_tool(wrong, c'/root/absent.vcscrub', recovery, readonly, false, false, 1); missing(c'/dev/mapper/vinix60')
		} }
		bad_password := [&char(c'/usr/sbin/vinix-volume'), &char(c'scrub-volume'), parent, &char(c'/root/volume.sealed'), &char(c'/root/next.pass'), &char(c'/root/volume.vchash'), &char(c'/root/absent.vcscrub'), &char(nil)]!
		bad_recovery := [&char(c'/usr/sbin/vinix-volume'), &char(c'scrub-recovery-volume'), parent, &char(c'/root/volume.vrecover'), &char(c'/root/volume.vrecover'), &char(c'/root/volume.vchash'), &char(c'/root/absent.vcscrub'), &char(nil)]!
		run_utility(&bad_password[0], 1); run_utility(&bad_recovery[0], 1)
		raw := C.open(parent, C.O_RDWR); mut bytes := [512]u8{}; mut changed := [512]u8{}
		check(raw >= 0 && C.pread(raw, &bytes[0], 512, 15728640) == 512, c'pin controlled scrub corruption'); changed = bytes; changed[0] ^= 1
		check(C.pwrite(raw, &changed[0], 512, 15728640) == 512 && C.fsync(raw) == 0, c'persist scrub corruption')
		for readonly in [false, true]! { for recovery in [false, true]! {
			volume_scrub_name(&name[0], recovery, readonly, true); volume_scrub_tool(parent, &name[0], recovery, readonly, false, true, 2)
			volume_scrub_tool(parent, &name[0], recovery, readonly, true, true, 0)
		} }
		check(C.pwrite(raw, &bytes[0], 512, 15728640) == 512 && C.fsync(raw) == 0 && C.close(raw) == 0, c'restore scrub ciphertext')
		recovery_unlock_tool(c'/root/volume-ro.vrecover', c'/root/recovery.key', false, 0)
		before := status(c'/dev/mapper/vinix60'); held := C.open(c'/dev/mapper/vinix60', C.O_RDONLY); check(held >= 0, c'hold scrub mapping')
		for recovery in [false, true]! { volume_scrub_tool(parent, c'/root/live.vcscrub', recovery, false, false, false, 0); check(C.unlink(c'/root/live.vcscrub') == 0, c'reclaim live report') }
		check(before == status(c'/dev/mapper/vinix60'), c'scrub preserves complete live status/generation/counters'); crypt_data(held, 0, 0x73)
		check(C.close(held) == 0, c'close scrub held mapping'); simple(c'remove', c'/dev/mapper/vinix60', nil, 0)
		volume_scrub_retention(parent)
		for i in 0 .. 6 {
			fd := C.open(paths[i], C.O_RDONLY); length := if i < 4 { usize(320) } else { usize(128) }
			check(fd >= 0 && C.read(fd, &again[0], length) == i64(length) && C.close(fd) == 0 && C.memcmp(&original[i][0], &again[0], length) == 0, c'scrub preserves all credential/reference inputs')
		}
		check(C.open(c'/root/crypt.key', C.O_RDONLY) < 0 && C.errno == C.ENOENT, c'scrub creates no raw key')
		check(C.unlink(c'/root/scrub.out') == 0 && C.unlink(c'/root/ciphertext.out') == 0 && C.unlink(c'/etc/vinix/volumes.vmap') == 0, c'clear scrub captures/invalid plan')
		marker := C.open(c'/second-boot', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600)); check(marker >= 0 && C.fsync(marker) == 0 && C.close(marker) == 0, c'persist scrub phase')
		for path in [&char(c'/root'), &char(c'/etc/vinix'), &char(c'/')]! { fd := C.open(path, C.O_RDONLY | C.O_DIRECTORY); check(fd >= 0 && C.fsync(fd) == 0 && C.close(fd) == 0, c'persist scrub reports') }
		C.printf(c'PLAN CIPHERTEXT SCRUB PASSED: complete clean/changed reports, offline view, refusal/cleanup, stable live views and real-KDF lifetimes\n')
	}
}

@[direct_array_access]
fn ciphertext_scrub_entry() i32 {
	C.printf(c'PLAN START\n'); warm_image(); phase := C.open(c'/second-boot', C.O_RDONLY)
	if phase < 0 { volume_scrub_first($if amd64 { &char(c'/dev/sd0') } $else { &char(c'/dev/vda') }, $if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') }) }
	else {
		check(C.close(phase) == 0, c'close scrub phase'); parent := $if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') }; mut name := [64]char{}
		for changed in [false, true]! { for readonly in [false, true]! { for recovery in [false, true]! {
			volume_scrub_name(&name[0], recovery, readonly, changed); volume_scrub_tool(parent, &name[0], recovery, readonly, true, changed, 0)
		} } }
		volume_scrub_tool(parent, c'/root/reboot.vcscrub', true, true, false, false, 0); missing(c'/dev/mapper/vinix60')
		recovery_unlock_view(parent, c'/root/volume-ro.vrecover', false, true)
		C.printf(c'PLAN CIPHERTEXT SCRUB REORDERED BOOT PRESERVED\n')
	}
	C.printf(c'PLAN DONE\n'); for { C.pause() }; return 0
}
