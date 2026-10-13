// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn ciphertext_auto_name(output &char, recovery bool, readonly bool) {
	C.snprintf(output, 64, c'/root/auto-%s%s.vchash', if recovery { &char(c'recovery') } else { &char(c'volume') }, if readonly { &char(c'-ro') } else { &char(c'') })
}

@[direct_array_access]
fn ciphertext_auto_matrix(create bool) {
	mut name := [64]char{}
	for readonly in [false, true]! { for recovery in [false, true]! {
		ciphertext_auto_name(&name[0], recovery, readonly)
		if create {
			ciphertext_auto_tool(&name[0], recovery, false, readonly, 0)
			ciphertext_references_equal(&name[0], if readonly { &char(c'/root/volume-ro.vchash') } else { &char(c'/root/volume.vchash') })
		}
		ciphertext_auto_tool(&name[0], recovery, true, readonly, 0)
		ciphertext_auto_tool(&name[0], !recovery, true, readonly, 0)
		ciphertext_auto_tool(&name[0], recovery, false, readonly, 1)
		ciphertext_auto_tool(if readonly { &char(c'/root/volume.vchash') } else { &char(c'/root/volume-ro.vchash') }, recovery, true, readonly, 1)
		missing(c'/dev/mapper/vinix60')
	} }
}

fn ciphertext_auto_cycles(count int) {
	for _ in 0 .. count {
		ciphertext_auto_tool(c'/root/auto-cycle.vchash', false, false, true, 0)
		ciphertext_auto_tool(c'/root/auto-cycle.vchash', true, true, true, 0)
		check(C.unlink(c'/root/auto-cycle.vchash') == 0, c'reclaim automatic reference'); missing(c'/dev/mapper/vinix60')
	}
	C.sleep(13); C.printf(c'PLAN CIPHERTEXT AUTO CYCLES count=%d\n', count)
}

@[direct_array_access]
fn ciphertext_auto_retention() {
	ciphertext_auto_cycles(4); mut before := Heap{}; mut after := Heap{}
	heap_snapshot(mut before); heap_snapshot(mut after); heap_snapshot(mut before)
	ciphertext_auto_cycles(4); heap_snapshot(mut after)
	C.printf(c'PLAN CIPHERTEXT AUTO LARGE before=%ld after=%ld\n', before.large, after.large)
	check(before.count == after.count && before.large == after.large, c'automatic checksum large-page retention')
	for i in 0 .. before.count {
		C.printf(c'PLAN CIPHERTEXT AUTO RETAIN size=%ld delta=%ld\n', before.sizes[i], after.live[i] - before.live[i])
		check(before.sizes[i] == after.sizes[i] && before.live[i] == after.live[i], c'automatic checksum slab retention')
	}
}

@[direct_array_access]
fn ciphertext_auto_entry() i32 {
	C.printf(c'PLAN START\n'); warm_image(); phase := C.open(c'/second-boot', C.O_RDONLY)
	if phase < 0 {
		parent := $if amd64 { &char(c'/dev/sd0') } $else { &char(c'/dev/vda') }
		ciphertext_first(parent, $if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') })
		ciphertext_auto_matrix(true)
		unsafe {
			bad_password := [&char(c'/usr/sbin/vinix-volume'), &char(c'verify-volume-auto'), &char(c'/root/volume.sealed'), &char(c'/root/next.pass'), &char(c'/root/auto-volume.vchash'), &char(nil)]!
			bad_recovery := [&char(c'/usr/sbin/vinix-volume'), &char(c'verify-recovery-volume-auto'), &char(c'/root/volume.vrecover'), &char(c'/root/volume.vrecover'), &char(c'/root/auto-volume.vchash'), &char(nil)]!
			run_utility(&bad_password[0], 1); run_utility(&bad_recovery[0], 1)
		}
		raw := C.open(parent, C.O_RDWR); mut bytes := [512]u8{}; mut changed := [512]u8{}
		check(raw >= 0 && C.pread(raw, &bytes[0], 512, 15728640) == 512, c'pin automatic verification corruption'); changed = bytes; changed[0] ^= 1
		check(C.pwrite(raw, &changed[0], 512, 15728640) == 512 && C.fsync(raw) == 0, c'persist automatic verification corruption')
		for readonly in [false, true]! { for recovery in [false, true]! { ciphertext_auto_tool(if readonly { &char(c'/root/auto-volume-ro.vchash') } else { &char(c'/root/auto-volume.vchash') }, recovery, true, readonly, 1) } }
		check(C.pwrite(raw, &bytes[0], 512, 15728640) == 512 && C.fsync(raw) == 0 && C.close(raw) == 0, c'restore automatic verification ciphertext')
		recovery_unlock_tool(c'/root/volume-ro.vrecover', c'/root/recovery.key', false, 0)
		before := status(c'/dev/mapper/vinix60'); held := C.open(c'/dev/mapper/vinix60', C.O_RDONLY); check(held >= 0, c'hold automatic checksum mapping')
		for recovery in [false, true]! { ciphertext_auto_tool(c'/root/auto-volume.vchash', recovery, true, false, 0) }
		check(before == status(c'/dev/mapper/vinix60'), c'automatic checksums preserve complete live status'); crypt_data(held, 0, 0x73)
		check(C.close(held) == 0, c'close automatic checksum mapping'); simple(c'remove', c'/dev/mapper/vinix60', unsafe { nil }, 0)
		ciphertext_auto_retention(); check(C.unlink(c'/root/ciphertext.out') == 0, c'reclaim automatic checksum capture')
		root := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY); check(root >= 0 && C.fsync(root) == 0 && C.close(root) == 0, c'persist automatic checksum references')
		C.printf(c'PLAN CIPHERTEXT AUTO PASSED: authenticated discovery, exact references, complete verification, corruption/refusal and real-KDF lifetimes\n')
	} else {
		check(C.close(phase) == 0, c'close automatic checksum phase'); ciphertext_auto_matrix(false)
		recovery_unlock_view($if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') }, c'/root/volume-ro.vrecover', false, true)
		check(C.unlink(c'/root/ciphertext.out') == 0, c'reclaim reordered automatic capture')
		C.printf(c'PLAN CIPHERTEXT AUTO REORDERED BOOT PRESERVED\n')
	}
	C.printf(c'PLAN DONE\n'); for { C.pause() }; return 0
}

@[direct_array_access]
fn ciphertext_auto_tool(reference &char, recovery bool, verify bool, readonly bool, expected i32) {
	unsafe {
		input := if recovery { if readonly { &char(c'/root/volume-ro.vrecover') } else { &char(c'/root/volume.vrecover') } }
			else { if readonly { &char(c'/root/volume-ro.sealed') } else { &char(c'/root/volume.sealed') } }
		verb := if verify { if recovery { &char(c'verify-recovery-volume-auto') } else { &char(c'verify-volume-auto') } }
			else { if recovery { &char(c'hash-recovery-volume-auto') } else { &char(c'hash-volume-auto') } }
		args := [&char(c'/usr/sbin/vinix-volume'), verb, input, if recovery { &char(c'/root/recovery.key') } else { &char(c'/root/crypt.pass') }, reference, &char(nil)]!
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
