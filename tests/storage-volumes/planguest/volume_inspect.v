// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

// Capture the real CLI stdout while leaving diagnostics on the serial console.
// Exact reports are small and remain in fixed caller-owned stack buffers.
@[direct_array_access]
fn volume_inspect_tool(config &char, key &char, online bool, readonly bool, parent &char, expected i32) {
	unsafe {
		output := C.open(c'/root/inspection.out', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600))
		check(output >= 0, c'open volume inspection output')
		args := [&char(c'/usr/sbin/vinix-volume'), if online { &char(c'discover-volume') } else { &char(c'show-volume') }, config, key, &char(nil)]!
		child := C.fork(); check(child >= 0, c'fork volume inspection utility')
		if child == 0 {
			if C.dup2(output, 1) != 1 || C.close(output) != 0 { C._exit(126) }
			C.execv(args[0], &args[0]); C._exit(127)
		}
		check(C.close(output) == 0, c'close parent inspection output')
		mut code := i32(0); check(C.waitpid(child, &code, 0) == child && code == expected << 8, c'volume inspection utility exit')
		fd := C.open(c'/root/inspection.out', C.O_RDONLY); mut text := [512]char{}
		check(fd >= 0, c'open captured volume report'); count := C.read(fd, &text[0], 511)
		check(count >= 0 && count < 511 && C.close(fd) == 0, c'bounded captured volume report')
		if expected != 0 {
			check(C.strstr(&text[0], c'operation=') == nil && C.strstr(&text[0], c'disk_bytes=') == nil
				&& C.strstr(&text[0], c'slot=') == nil, c'failed inspection emits no successful metadata'); return
		}
		mut wanted := [512]char{}
		if online {
			C.snprintf(&wanted[0], 512, c'operation=discovered-volume device=%s\n', parent)
		} else { C.snprintf(&wanted[0], 512, c'operation=authenticated-volume\n') }
		at := int(C.strlen(&wanted[0]))
		C.snprintf(&wanted[at], usize(512 - at), c'disk_bytes=16777216 sector=512 identity=mbr:12345678\nslot=60 offset=15728640 bytes=4096 readonly=%lu\n', u64(readonly))
		check(C.strcmp(&text[0], &wanted[0]) == 0, c'exact authenticated volume metadata, mode and current device')
	}
}

fn volume_inspect_cycles(parent &char, count int) {
	for _ in 0 .. count {
		volume_inspect_tool(c'/root/volume-ro.sealed', c'/root/crypt.pass', false, true, parent, 0)
		volume_inspect_tool(c'/root/volume-ro.sealed', c'/root/crypt.pass', true, true, parent, 0)
		missing(c'/dev/mapper/vinix60')
	}
	C.sleep(13); C.printf(c'PLAN VOLUME INSPECTION CYCLES count=%d\n', count)
}

@[direct_array_access]
fn volume_inspect_retention(parent &char) {
	volume_inspect_cycles(parent, 4)
	mut before := Heap{}; mut after := Heap{}
	heap_snapshot(mut before); heap_snapshot(mut after); heap_snapshot(mut before)
	volume_inspect_cycles(parent, 4); heap_snapshot(mut after)
	C.printf(c'PLAN VOLUME INSPECTION LARGE before=%ld after=%ld\n', before.large, after.large)
	check(before.count == after.count && before.large == after.large, c'volume inspection large-page retention')
	for i in 0 .. before.count {
		C.printf(c'PLAN VOLUME INSPECTION RETAIN size=%ld delta=%ld\n', before.sizes[i], after.live[i] - before.live[i])
		check(before.sizes[i] == after.sizes[i] && before.live[i] == after.live[i], c'volume inspection slab retention')
	}
}

@[direct_array_access]
fn volume_inspect_first(parent &char) {
	unsafe {
		volume_recovery_fixture(parent)
		check(C.open(c'/root/crypt.key', C.O_RDONLY) < 0 && C.errno == C.ENOENT, c'configuration queries require no raw keyfile')

		mut original := [320]u8{}; mut again := [320]u8{}
		volume_rewrap_read(c'/root/volume.sealed', &original[0]); again = original; again[288] ^= 1
		bad := C.open(c'/root/bad.sealed', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
		check(bad >= 0 && C.write(bad, &again[0], 320) == 320 && C.close(bad) == 0, c'tampered inspection fixture')
		for online in [false, true]! {
			volume_inspect_tool(c'/root/bad.sealed', c'/root/crypt.pass', online, false, parent, 1)
			volume_inspect_tool(c'/root/volume.sealed', c'/root/next.pass', online, false, parent, 1)
			for readonly in [false, true]! {
				volume_inspect_tool(if readonly { &char(c'/root/volume-ro.sealed') } else { &char(c'/root/volume.sealed') }, c'/root/crypt.pass', online, readonly, parent, 0)
				missing(c'/dev/mapper/vinix60')
			}
		}
		volume_seal_open_tool(parent, c'/root/volume-ro.sealed', c'/root/crypt.pass', false, 0)
		before := status(c'/dev/mapper/vinix60'); held := C.open(c'/dev/mapper/vinix60', C.O_RDONLY)
		mut ciphertext := [512]u8{}; mut after_ciphertext := [512]u8{}
		raw := C.open(parent, C.O_RDONLY)
		check(held >= 0 && raw >= 0 && C.pread(raw, &ciphertext[0], 512, 15728640) == 512, c'pin live encrypted descriptor and ciphertext')
		volume_inspect_tool(c'/root/volume.sealed', c'/root/crypt.pass', true, false, parent, 0)
		after := status(c'/dev/mapper/vinix60')
		check(before == after, c'discovery preserves occupied mapping, mode, generation and counters'); crypt_data(held, 0, 0x73)
		check(C.pread(raw, &after_ciphertext[0], 512, 15728640) == 512 && C.memcmp(&ciphertext[0], &after_ciphertext[0], 512) == 0, c'discovery never changes physical ciphertext')
		check(C.close(raw) == 0 && C.close(held) == 0, c'close held inspection descriptors'); simple(c'remove', c'/dev/mapper/vinix60', nil, 0)
		volume_inspect_retention(parent)
		volume_rewrap_read(c'/root/volume.sealed', &again[0]); check(C.memcmp(&original[0], &again[0], 320) == 0, c'inspection preserves config bytes')
		check(C.unlink(c'/root/inspection.out') == 0 && C.unlink(c'/etc/vinix/volumes.vmap') == 0, c'clear capture and initial invalid boot plan')
		marker := C.open(c'/second-boot', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
		check(marker >= 0 && C.fsync(marker) == 0 && C.close(marker) == 0, c'persist volume inspection phase')
		for path in [&char(c'/root'), &char(c'/etc/vinix'), &char(c'/')]! {
			fd := C.open(path, C.O_RDONLY | C.O_DIRECTORY); check(fd >= 0 && C.fsync(fd) == 0 && C.close(fd) == 0, c'persist volume inspection configs')
		}
		C.printf(c'PLAN VOLUME INSPECTION PASSED: authenticated reports, read-only discovery, unchanged occupied mappings/ciphertext and measured lifetimes\n')
	}
}

@[direct_array_access]
fn volume_inspect_entry() i32 {
	C.printf(c'PLAN START\n'); warm_image()
	phase := C.open(c'/second-boot', C.O_RDONLY)
	if phase < 0 {
		parent := $if amd64 { &char(c'/dev/sd0') } $else { &char(c'/dev/vda') }
		volume_inspect_first(parent)
	} else {
		check(C.close(phase) == 0, c'close volume inspection phase'); check(C.open(c'/root/crypt.key', C.O_RDONLY) < 0 && unsafe { C.errno == C.ENOENT }, c'volume inspection creates no raw keyfile')
		parent := $if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') }
		for readonly in [false, true]! {
			config := if readonly { &char(c'/root/volume-ro.sealed') } else { &char(c'/root/volume.sealed') }
			volume_inspect_tool(config, c'/root/crypt.pass', false, readonly, parent, 0)
			volume_inspect_tool(config, c'/root/crypt.pass', true, readonly, parent, 0)
			missing(c'/dev/mapper/vinix60')
		}
		volume_seal_view(parent, c'/root/volume.sealed', false, false)
		volume_seal_view(parent, c'/root/volume-ro.sealed', false, true)
		check(C.unlink(c'/root/inspection.out') == 0, c'clear reordered inspection capture')
		check(C.open(c'/root/crypt.key', C.O_RDONLY) < 0 && unsafe { C.errno == C.ENOENT }, c'volume inspection creates no raw keyfile'); C.printf(c'PLAN VOLUME INSPECTION REORDERED BOOT PRESERVED\n')
	}
	C.printf(c'PLAN DONE\n'); for { C.pause() }
	return 0
}
