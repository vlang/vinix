// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn reference_name(output &char, readonly bool, changed bool) {
	C.snprintf(output, 64, c'/root/%svolume%s.vchash', if changed { &char(c'changed-') } else { &char(c'') }, if readonly { &char(c'-ro') } else { &char(c'') })
}

@[direct_array_access]
fn reference_tool(before &char, after &char, readonly bool, old_changed bool, new_changed bool, expected i32) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'), if after == nil { &char(c'show-volume-reference') } else { &char(c'compare-volume-references') }, before, after, &char(nil)]!
		capture := C.open(c'/root/reference.out', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600)); check(capture >= 0, c'open reference capture')
		child := C.fork(); check(child >= 0, c'fork reference tool')
		if child == 0 { if C.dup2(capture, 1) != 1 || C.close(capture) != 0 { C._exit(126) }; C.execv(args[0], &args[0]); C._exit(127) }
		check(C.close(capture) == 0, c'close reference capture'); mut code := i32(0)
		check(C.waitpid(child, &code, 0) == child && code == expected << 8, c'reference exact exit')
		fd := C.open(c'/root/reference.out', C.O_RDONLY); mut text := [2048]char{}
		check(fd >= 0, c'open reference output'); count := C.read(fd, &text[0], 2047)
		check(count >= 0 && count < 2047 && C.close(fd) == 0, c'bounded reference output')
		if expected == 1 { check(C.strstr(&text[0], c'operation=') == nil, c'invalid reference emits no finding'); return }
		mut wanted := [2048]char{}
		if after == nil {
			C.snprintf(&wanted[0], 2048, c'format=VINIXCH1 operation=show-ciphertext-reference mappings=1 algorithm=sha256 reference_sha256=%s\ndisk_bytes=16777216 sector=512 identity=mbr:12345678 slot=60 offset=15728640 bytes=4096 readonly=%lu sha256=%s\n', reference_hash(readonly, old_changed), u64(readonly), reference_digest(old_changed))
		} else {
			changed := old_changed != new_changed
			C.snprintf(&wanted[0], 2048, c'format=VINIXCH1 operation=compared-ciphertext-references mappings=1 stable=%lu changed=%lu algorithm=sha256 before_reference_sha256=%s after_reference_sha256=%s\ndisk_bytes=16777216 sector=512 identity=mbr:12345678 slot=60 offset=15728640 bytes=4096 readonly=%lu result=%s before_sha256=%s after_sha256=%s\n', u64(!changed), u64(changed), reference_hash(readonly, old_changed), reference_hash(readonly, new_changed), u64(readonly), if changed { &char(c'changed') } else { &char(c'stable') }, reference_digest(old_changed), reference_digest(new_changed))
		}
		check(C.strcmp(&text[0], &wanted[0]) == 0, c'exact independent reference output')
	}
}

@[direct_array_access]
fn reference_matrix() {
	mut before := [64]char{}; mut after := [64]char{}; mut automatic := [64]char{}
	for readonly in [false, true]! {
		for old_changed in [false, true]! {
			reference_name(&before[0], readonly, old_changed); reference_tool(&before[0], unsafe { nil }, readonly, old_changed, false, 0)
			for new_changed in [false, true]! {
				reference_name(&after[0], readonly, new_changed); reference_tool(&before[0], &after[0], readonly, old_changed, new_changed, if old_changed == new_changed { 0 } else { 2 })
			}
		}
		reference_name(&before[0], readonly, false)
		for recovery in [false, true]! {
			ciphertext_auto_name(&automatic[0], recovery, readonly); reference_tool(&automatic[0], unsafe { nil }, readonly, false, false, 0)
			reference_tool(&before[0], &automatic[0], readonly, false, false, 0); ciphertext_references_equal(&before[0], &automatic[0])
		}
		reference_tool(&before[0], &before[0], readonly, false, false, 0)
	}

	reference_tool(c'/root/volume.vchash', c'/root/volume-ro.vchash', false, false, false, 1)
	mut bytes := [128]u8{}; fd := C.open(c'/root/volume.vchash', C.O_RDONLY)
	check(fd >= 0 && C.read(fd, &bytes[0], 128) == 128 && C.close(fd) == 0, c'read invalid reference fixture'); bytes[0] ^= 1
	bad := C.open(c'/root/bad.vchash', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
	check(bad >= 0 && C.write(bad, &bytes[0], 128) == 128 && C.close(bad) == 0, c'create invalid private reference')
	reference_tool(c'/root/bad.vchash', unsafe { nil }, false, false, false, 1)
	reference_tool(c'/root/volume.vchash', c'/root/bad.vchash', false, false, false, 1)
	check(C.unlink(c'/root/bad.vchash') == 0, c'reclaim invalid reference')
	check(C.chmod(c'/root/volume.vchash', 0o644) == 0, c'change reference privacy')
	reference_tool(c'/root/volume.vchash', unsafe { nil }, false, false, false, 1)
	reference_tool(c'/root/auto-volume.vchash', c'/root/volume.vchash', false, false, false, 1)
	check(C.chmod(c'/root/volume.vchash', 0o600) == 0, c'restore reference privacy'); missing(c'/dev/mapper/vinix60')
}

fn reference_cycles(count int) {
	for _ in 0 .. count {
		reference_tool(c'/root/volume-ro.vchash', unsafe { nil }, true, false, false, 0)
		reference_tool(c'/root/volume-ro.vchash', c'/root/changed-volume-ro.vchash', true, false, true, 2)
		reference_tool(c'/root/auto-recovery-ro.vchash', c'/root/volume-ro.vchash', true, false, false, 0)
	}
	C.sleep(13); C.printf(c'PLAN REFERENCE CYCLES count=%d\n', count)
}

@[direct_array_access]
fn reference_retention() {
	reference_cycles(100); mut before := Heap{}; mut after := Heap{}
	heap_snapshot(mut before); heap_snapshot(mut after); heap_snapshot(mut before)
	reference_cycles(100); heap_snapshot(mut after)
	C.printf(c'PLAN REFERENCE LARGE before=%ld after=%ld\n', before.large, after.large)
	check(before.count == after.count && before.large == after.large, c'reference large-page retention')
	for i in 0 .. before.count {
		C.printf(c'PLAN REFERENCE RETAIN size=%ld delta=%ld\n', before.sizes[i], after.live[i] - before.live[i])
		check(before.sizes[i] == after.sizes[i] && before.live[i] == after.live[i], c'reference slab retention')
	}
}

@[direct_array_access]
fn reference_entry() i32 {
	C.printf(c'PLAN START\n'); warm_image(); phase := C.open(c'/second-boot', C.O_RDONLY)
	if phase < 0 {
		parent := $if amd64 { &char(c'/dev/sd0') } $else { &char(c'/dev/vda') }
		ciphertext_first(parent, $if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') }); ciphertext_auto_matrix(true)
		raw := C.open(parent, C.O_RDWR); mut original := [512]u8{}; mut changed := [512]u8{}
		check(raw >= 0 && C.pread(raw, &original[0], 512, 15728640) == 512, c'pin reference corruption'); changed = original; changed[0] ^= 1
		check(C.pwrite(raw, &changed[0], 512, 15728640) == 512 && C.fsync(raw) == 0, c'persist reference corruption')
		unsafe { for readonly in [false, true]! {
			args := [&char(c'/usr/sbin/vinix-volume'), &char(c'hash-volume'), parent, if readonly { &char(c'/root/volume-ro.sealed') } else { &char(c'/root/volume.sealed') }, &char(c'/root/crypt.pass'), if readonly { &char(c'/root/changed-volume-ro.vchash') } else { &char(c'/root/changed-volume.vchash') }, &char(nil)]!
			run_utility(&args[0], 0)
		} }
		check(C.pwrite(raw, &original[0], 512, 15728640) == 512 && C.fsync(raw) == 0 && C.close(raw) == 0, c'restore reference ciphertext')
		reference_matrix(); recovery_unlock_tool(c'/root/volume-ro.vrecover', c'/root/recovery.key', false, 0)
		before := status(c'/dev/mapper/vinix60'); held := C.open(c'/dev/mapper/vinix60', C.O_RDONLY); check(held >= 0, c'hold reference mapping')
		reference_tool(c'/root/volume.vchash', unsafe { nil }, false, false, false, 0)
		reference_tool(c'/root/volume.vchash', c'/root/changed-volume.vchash', false, false, true, 2)
		check(before == status(c'/dev/mapper/vinix60'), c'reference queries preserve complete live status'); crypt_data(held, 0, 0x73)
		check(C.close(held) == 0, c'close reference mapping'); simple(c'remove', c'/dev/mapper/vinix60', unsafe { nil }, 0)
		reference_retention(); check(C.unlink(c'/root/ciphertext.out') == 0, c'reclaim reference source capture')
		root := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY); check(root >= 0 && C.fsync(root) == 0 && C.close(root) == 0, c'persist offline references')
		C.printf(c'PLAN REFERENCE PASSED: complete private references, exact metadata/digests/fingerprints, offline results and bounded lifetimes\n')
	} else {
		check(C.close(phase) == 0, c'close reference phase'); reference_matrix(); ciphertext_auto_matrix(false)
		recovery_unlock_view($if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') }, c'/root/volume-ro.vrecover', false, true)
		check(C.unlink(c'/root/ciphertext.out') == 0, c'reclaim reordered source capture'); C.printf(c'PLAN REFERENCE REORDERED BOOT PRESERVED\n')
	}
	check(C.unlink(c'/root/reference.out') == 0, c'reclaim reference capture')
	C.printf(c'PLAN DONE\n'); for { C.pause() }; return 0
}

fn reference_digest(changed bool) &char { return if changed { &char(c'a45c3043d314e557b22fa0a7dc53957b2dd84154fedd0865703a1796c63bbc25') } else { &char(c'115d50809715a805656e2c32b2d84ce5b4df581c65e1ec9b4523df3f9e4a6748') } }

fn reference_hash(readonly bool, changed bool) &char {
	if readonly { return if changed { &char(c'0f254751f9272ca548997c20cc262cead9bef7ced2cac311d48498c34c3860a4') } else { &char(c'b3163f5b9fe199889368f06145927d5c7632102ef305580ff54a0fe37ad426b0') } }
	return if changed { &char(c'8b3e17b83615ee5ecfbf1b081ab992f150b30456a0d514c4684405f98e298aa5') } else { &char(c'ceb82ed81ecbf7ac0ced5930717d27aea59e88d7cf485e3a2bf885974c1d2329') }
}
