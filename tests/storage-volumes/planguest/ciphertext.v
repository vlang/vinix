// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

@[direct_array_access]
fn ciphertext_tool(parent &char, reference &char, recovery bool, verify bool, readonly bool, expected i32) {
	unsafe {
		input := if recovery { if readonly { &char(c'/root/volume-ro.vrecover') } else { &char(c'/root/volume.vrecover') } }
			else { if readonly { &char(c'/root/volume-ro.sealed') } else { &char(c'/root/volume.sealed') } }
		verb := if verify { if recovery { &char(c'verify-recovery-volume') } else { &char(c'verify-volume') } }
			else { if recovery { &char(c'hash-recovery-volume') } else { &char(c'hash-volume') } }
		args := [&char(c'/usr/sbin/vinix-volume'), verb, parent, input, if recovery { &char(c'/root/recovery.key') } else { &char(c'/root/crypt.pass') }, reference, &char(nil)]!
		capture := C.open(c'/root/ciphertext.out', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600)); check(capture >= 0, c'open ciphertext capture')
		child := C.fork(); check(child >= 0, c'fork ciphertext tool')
		if child == 0 {
			if C.dup2(capture, 1) != 1 || C.close(capture) != 0 { C._exit(126) }
			C.execv(args[0], &args[0]); C._exit(127)
		}
		check(C.close(capture) == 0, c'close ciphertext capture'); mut code := i32(0)
		check(C.waitpid(child, &code, 0) == child && code == expected << 8, c'ciphertext tool exit')
		fd := C.open(c'/root/ciphertext.out', C.O_RDONLY); mut text := [512]char{}
		check(fd >= 0, c'open ciphertext report'); count := C.read(fd, &text[0], 511)
		check(count >= 0 && count < 511 && C.close(fd) == 0, c'bounded ciphertext report')
		if expected != 0 { check(C.strstr(&text[0], c'operation=') == nil && C.strstr(&text[0], c'sha256=') == nil, c'failed scan emits no success'); return }
		mut wanted := [512]char{}
		C.snprintf(&wanted[0], 512, c'operation=%s-ciphertext format=%s algorithm=sha256\ndisk_bytes=16777216 sector=512 identity=mbr:12345678 slot=60 offset=15728640 bytes=4096 readonly=%lu sha256=115d50809715a805656e2c32b2d84ce5b4df581c65e1ec9b4523df3f9e4a6748\n',
			if verify { &char(c'verified') } else { &char(c'recorded') }, if recovery { &char(c'recovery') } else { &char(c'volume') }, u64(readonly))
		check(C.strcmp(&text[0], &wanted[0]) == 0, c'exact ciphertext report and independent expected digest')
	}
}

@[direct_array_access]
fn ciphertext_references_equal(first &char, second &char) {
	mut left := [128]u8{}; mut right := [128]u8{}
	for i in 0 .. 2 {
		fd := C.open(if i == 0 { first } else { second }, C.O_RDONLY)
		check(fd >= 0, c'open ciphertext reference')
		check(C.read(fd, unsafe { if i == 0 { &left[0] } else { &right[0] } }, 128) == 128 && C.close(fd) == 0, c'read exact reference')
	}
	check(C.memcmp(&left[0], &right[0], 128) == 0, c'credential domains produce identical public ciphertext references')
}

fn ciphertext_cycles(parent &char, count int) {
	for _ in 0 .. count {
		ciphertext_tool(parent, c'/root/cycle.vchash', false, false, true, 0)
		ciphertext_tool(parent, c'/root/cycle.vchash', true, true, true, 0)
		check(C.unlink(c'/root/cycle.vchash') == 0, c'remove measured reference'); missing(c'/dev/mapper/vinix60')
	}
	C.sleep(13); C.printf(c'PLAN CIPHERTEXT CYCLES count=%d\n', count)
}

@[direct_array_access]
fn ciphertext_retention(parent &char) {
	ciphertext_cycles(parent, 4); mut before := Heap{}; mut after := Heap{}
	heap_snapshot(mut before); heap_snapshot(mut after); heap_snapshot(mut before)
	ciphertext_cycles(parent, 4); heap_snapshot(mut after)
	C.printf(c'PLAN CIPHERTEXT LARGE before=%ld after=%ld\n', before.large, after.large)
	check(before.count == after.count && before.large == after.large, c'ciphertext large-page retention')
	for i in 0 .. before.count {
		C.printf(c'PLAN CIPHERTEXT RETAIN size=%ld delta=%ld\n', before.sizes[i], after.live[i] - before.live[i])
		check(before.sizes[i] == after.sizes[i] && before.live[i] == after.live[i], c'ciphertext slab retention')
	}
}

@[direct_array_access]
fn ciphertext_first(parent &char, wrong &char) {
	unsafe {
		volume_recovery_fixture(parent)
		volume_recovery_tool(c'/root/volume.sealed', c'/root/crypt.pass', c'/root/recovery.key', c'/root/volume.vrecover', true, 0)
		volume_recovery_tool(c'/root/volume-ro.sealed', c'/root/crypt.pass', c'/root/recovery.key', c'/root/volume-ro.vrecover', true, 0)
		mut originals := [4][320]u8{}; mut again := [320]u8{}
		paths := [&char(c'/root/volume.sealed'), &char(c'/root/volume-ro.sealed'), &char(c'/root/volume.vrecover'), &char(c'/root/volume-ro.vrecover')]!
		for i in 0 .. 4 { volume_rewrap_read(paths[i], &originals[i][0]) }
		for readonly in [false, true]! {
			ref := if readonly { &char(c'/root/volume-ro.vchash') } else { &char(c'/root/volume.vchash') }
			rescue := if readonly { &char(c'/root/recovery-ro.vchash') } else { &char(c'/root/recovery.vchash') }
			ciphertext_tool(parent, ref, false, false, readonly, 0); ciphertext_tool(parent, rescue, true, false, readonly, 0)
			ciphertext_references_equal(ref, rescue)
		}
		for readonly in [false, true]! {
			ref := if readonly { &char(c'/root/volume-ro.vchash') } else { &char(c'/root/volume.vchash') }
			for recovery in [false, true]! {
				ciphertext_tool(parent, ref, recovery, true, readonly, 0)
				ciphertext_tool(parent, ref, recovery, false, readonly, 1)
				ciphertext_tool(wrong, ref, recovery, true, readonly, 1)
				ciphertext_tool(parent, if readonly { &char(c'/root/volume.vchash') } else { &char(c'/root/volume-ro.vchash') }, recovery, true, readonly, 1)
			}
			missing(c'/dev/mapper/vinix60')
		}
		bad_password := [&char(c'/usr/sbin/vinix-volume'), &char(c'verify-volume'), parent, &char(c'/root/volume.sealed'), &char(c'/root/next.pass'), &char(c'/root/volume.vchash'), &char(nil)]!
		bad_recovery := [&char(c'/usr/sbin/vinix-volume'), &char(c'verify-recovery-volume'), parent, &char(c'/root/volume.vrecover'), &char(c'/root/volume.vrecover'), &char(c'/root/volume.vchash'), &char(nil)]!
		run_utility(&bad_password[0], 1); run_utility(&bad_recovery[0], 1)
		// Quiescent physical corruption is detected through either credential.
		raw := C.open(parent, C.O_RDWR); mut bytes := [512]u8{}; mut changed := [512]u8{}
		check(raw >= 0 && C.pread(raw, &bytes[0], 512, 15728640) == 512, c'pin ciphertext for controlled corruption')
		changed = bytes; changed[0] ^= 1
		check(C.pwrite(raw, &changed[0], 512, 15728640) == 512 && C.fsync(raw) == 0, c'persist controlled ciphertext corruption')
		for recovery in [false, true]! { ciphertext_tool(parent, c'/root/volume.vchash', recovery, true, false, 1) }
		check(C.pwrite(raw, &bytes[0], 512, 15728640) == 512 && C.fsync(raw) == 0 && C.close(raw) == 0, c'restore physical ciphertext')
		recovery_unlock_tool(c'/root/volume-ro.vrecover', c'/root/recovery.key', false, 0)
		before := status(c'/dev/mapper/vinix60'); held := C.open(c'/dev/mapper/vinix60', C.O_RDONLY)
		check(held >= 0, c'hold encrypted mapping')
		for recovery in [false, true]! { ciphertext_tool(parent, c'/root/volume.vchash', recovery, true, false, 0) }
		check(before == status(c'/dev/mapper/vinix60'), c'ciphertext scans preserve live status/generation/counters'); crypt_data(held, 0, 0x73)
		check(C.close(held) == 0, c'close held ciphertext view'); simple(c'remove', c'/dev/mapper/vinix60', nil, 0)
		ciphertext_retention(parent)
		for i in 0 .. 4 { volume_rewrap_read(paths[i], &again[0]); check(C.memcmp(&originals[i][0], &again[0], 320) == 0, c'ciphertext scans preserve credential envelopes') }
		check(C.open(c'/root/crypt.key', C.O_RDONLY) < 0 && C.errno == C.ENOENT, c'ciphertext scans create no raw key')
		check(C.unlink(c'/root/ciphertext.out') == 0 && C.unlink(c'/etc/vinix/volumes.vmap') == 0, c'clear capture and invalid boot plan')
		marker := C.open(c'/second-boot', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
		check(marker >= 0 && C.fsync(marker) == 0 && C.close(marker) == 0, c'persist ciphertext phase')
		for path in [&char(c'/root'), &char(c'/etc/vinix'), &char(c'/')]! {
			fd := C.open(path, C.O_RDONLY | C.O_DIRECTORY); check(fd >= 0 && C.fsync(fd) == 0 && C.close(fd) == 0, c'persist ciphertext inputs and references')
		}
		C.printf(c'PLAN CIPHERTEXT PASSED: exact authenticated reports, corruption detection, stable live views, no-overwrite references and real-KDF lifetimes\n')
	}
}

@[direct_array_access]
fn ciphertext_entry() i32 {
	C.printf(c'PLAN START\n'); warm_image(); phase := C.open(c'/second-boot', C.O_RDONLY)
	if phase < 0 {
		ciphertext_first($if amd64 { &char(c'/dev/sd0') } $else { &char(c'/dev/vda') }, $if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') })
	} else {
		check(C.close(phase) == 0, c'close ciphertext phase')
		parent := $if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') }
		for readonly in [false, true]! { for recovery in [false, true]! {
			ciphertext_tool(parent, if readonly { &char(c'/root/volume-ro.vchash') } else { &char(c'/root/volume.vchash') }, recovery, true, readonly, 0)
			missing(c'/dev/mapper/vinix60')
		} }
		recovery_unlock_view(parent, c'/root/volume-ro.vrecover', false, true)
		check(C.unlink(c'/root/ciphertext.out') == 0, c'clear reordered capture')
		C.printf(c'PLAN CIPHERTEXT REORDERED BOOT PRESERVED\n')
	}
	C.printf(c'PLAN DONE\n'); for { C.pause() }; return 0
}
