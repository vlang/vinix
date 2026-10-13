// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

@[direct_array_access]
fn growth_preview_tool(parent &char, input &char, credential &char, recovery bool, readonly bool, capacity u64, length u64, expected i32) {
	unsafe {
		mut capacity_text := [24]char{}; mut length_text := [24]char{}
		C.snprintf(&capacity_text[0], 24, c'%lu', capacity); C.snprintf(&length_text[0], 24, c'%lu', length)
		args := [&char(c'/usr/sbin/vinix-volume'), if recovery { &char(c'plan-preview-grow-recovery-volume') } else { &char(c'plan-preview-grow-volume') }, parent, input, credential, &capacity_text[0], &length_text[0], &char(nil)]!
		output := C.open(c'/root/preview.out', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600)); check(output >= 0, c'open preview capture')
		child := C.fork(); check(child >= 0, c'fork growth preview')
		if child == 0 {
			if C.dup2(output, 1) != 1 || C.close(output) != 0 { C._exit(126) }
			C.execv(args[0], &args[0]); C._exit(127)
		}
		check(C.close(output) == 0, c'close parent preview capture')
		mut code := i32(0); check(C.waitpid(child, &code, 0) == child && code == expected << 8, c'growth preview exit')
		fd := C.open(c'/root/preview.out', C.O_RDONLY); mut text := [512]char{}
		check(fd >= 0, c'open preview report'); count := C.read(fd, &text[0], 511)
		check(count >= 0 && count < 511 && C.close(fd) == 0, c'bounded preview report')
		if expected != 0 {
			check(C.strstr(&text[0], c'operation=') == nil && C.strstr(&text[0], c'planned_disk_bytes=') == nil && C.strstr(&text[0], c'slot=') == nil, c'failed preview emits no successful candidate'); return
		}
		mut wanted := [512]char{}
		C.snprintf(&wanted[0], 512, c'operation=checked-growth format=%s\ncurrent_disk_bytes=16777216 planned_disk_bytes=%lu sector=512 identity=mbr:12345678 capacity_action=%s\nslot=60 offset=15728640 current_bytes=4096 planned_bytes=%lu readonly=%lu extent_action=%s\n',
			if recovery { &char(c'recovery') } else { &char(c'volume') }, capacity, if capacity == 16777216 { &char(c'keep') } else { &char(c'grow') }, length, u64(readonly), if length == 4096 { &char(c'keep') } else { &char(c'grow') })
		check(C.strcmp(&text[0], &wanted[0]) == 0, c'exact original/candidate capacity, extent, mode and keep/grow actions')
	}
}

fn growth_preview_query(parent &char, recovery bool, readonly bool, capacity u64, length u64, expected i32) {
	unsafe {
		input := if recovery { if readonly { &char(c'/root/volume-ro.vrecover') } else { &char(c'/root/volume.vrecover') } }
			else { if readonly { &char(c'/root/volume-ro.sealed') } else { &char(c'/root/volume.sealed') } }
		growth_preview_tool(parent, input, if recovery { &char(c'/root/recovery.key') } else { &char(c'/root/crypt.pass') }, recovery, readonly, capacity, length, expected)
	}
}

fn growth_preview_cycles(parent &char, count int) {
	for _ in 0 .. count {
		growth_preview_query(parent, false, true, 16777216, 8192, 0)
		growth_preview_query(parent, true, true, 16777216, 8192, 0)
		missing(c'/dev/mapper/vinix60')
	}
	C.sleep(13); C.printf(c'PLAN GROWTH PREVIEW CYCLES count=%d\n', count)
}

@[direct_array_access]
fn growth_preview_retention(parent &char) {
	growth_preview_cycles(parent, 4)
	mut before := Heap{}; mut after := Heap{}
	heap_snapshot(mut before); heap_snapshot(mut after); heap_snapshot(mut before)
	growth_preview_cycles(parent, 4); heap_snapshot(mut after)
	C.printf(c'PLAN GROWTH PREVIEW LARGE before=%ld after=%ld\n', before.large, after.large)
	check(before.count == after.count && before.large == after.large, c'growth preview large-page retention')
	for i in 0 .. before.count {
		C.printf(c'PLAN GROWTH PREVIEW RETAIN size=%ld delta=%ld\n', before.sizes[i], after.live[i] - before.live[i])
		check(before.sizes[i] == after.sizes[i] && before.live[i] == after.live[i], c'growth preview slab retention')
	}
}

@[direct_array_access]
fn growth_preview_first(parent &char, wrong &char) {
	unsafe {
		volume_recovery_fixture(parent)
		volume_recovery_tool(c'/root/volume.sealed', c'/root/crypt.pass', c'/root/recovery.key', c'/root/volume.vrecover', true, 0)
		volume_recovery_tool(c'/root/volume-ro.sealed', c'/root/crypt.pass', c'/root/recovery.key', c'/root/volume-ro.vrecover', true, 0)
		mut originals := [4][320]u8{}; mut again := [320]u8{}
		paths := [&char(c'/root/volume.sealed'), &char(c'/root/volume-ro.sealed'), &char(c'/root/volume.vrecover'), &char(c'/root/volume-ro.vrecover')]!
		for i in 0 .. 4 { volume_rewrap_read(paths[i], &originals[i][0]) }
		for recovery in [false, true]! {
			for readonly in [false, true]! {
				growth_preview_query(parent, recovery, readonly, 16777216, 4096, 0)
				growth_preview_query(parent, recovery, readonly, 16777216, 8192, 0)
				growth_preview_query(wrong, recovery, readonly, 16777216, 8192, 1)
				growth_preview_query(parent, recovery, readonly, 33554432, 8192, 1)
				growth_preview_query(parent, recovery, readonly, 16777216, 512, 1)
				growth_preview_query(parent, recovery, readonly, 16777216, 8193, 1)
				missing(c'/dev/mapper/vinix60')
			}
		}
		growth_preview_tool(parent, c'/root/volume.sealed', c'/root/next.pass', false, false, 16777216, 8192, 1)
		growth_preview_tool(parent, c'/root/volume.vrecover', c'/root/volume.vrecover', true, false, 16777216, 8192, 1)
		recovery_unlock_tool(c'/root/volume-ro.vrecover', c'/root/recovery.key', false, 0)
		before := status(c'/dev/mapper/vinix60'); held := C.open(c'/dev/mapper/vinix60', C.O_RDONLY)
		mut ciphertext := [512]u8{}; mut after_ciphertext := [512]u8{}; raw := C.open(parent, C.O_RDONLY)
		check(held >= 0 && raw >= 0 && C.pread(raw, &ciphertext[0], 512, 15728640) == 512, c'pin existing view and physical ciphertext')
		for recovery in [false, true]! { growth_preview_query(parent, recovery, false, 16777216, 8192, 0) }
		after := status(c'/dev/mapper/vinix60'); check(before == after, c'previews preserve entire live status/generation/counters'); crypt_data(held, 0, 0x73)
		check(C.pread(raw, &after_ciphertext[0], 512, 15728640) == 512 && C.memcmp(&ciphertext[0], &after_ciphertext[0], 512) == 0, c'previews never write ciphertext')
		check(C.close(held) == 0 && C.close(raw) == 0, c'close held preview descriptors'); simple(c'remove', c'/dev/mapper/vinix60', nil, 0)
		growth_preview_retention(parent)
		for i in 0 .. 4 { volume_rewrap_read(paths[i], &again[0]); check(C.memcmp(&originals[i][0], &again[0], 320) == 0, c'previews preserve all configuration and backup bytes') }
		check(C.open(c'/root/crypt.key', C.O_RDONLY) < 0 && C.errno == C.ENOENT, c'previews create no raw keyfile')
		check(C.unlink(c'/root/preview.out') == 0 && C.unlink(c'/etc/vinix/volumes.vmap') == 0, c'clear capture and invalid boot plan')
		marker := C.open(c'/second-boot', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
		check(marker >= 0 && C.fsync(marker) == 0 && C.close(marker) == 0, c'persist preview phase')
		for path in [&char(c'/root'), &char(c'/etc/vinix'), &char(c'/')]! {
			fd := C.open(path, C.O_RDONLY | C.O_DIRECTORY); check(fd >= 0 && C.fsync(fd) == 0 && C.close(fd) == 0, c'persist preview inputs')
		}
		C.printf(c'PLAN GROWTH PREVIEW PASSED: exact authenticated keep/grow reports, refusal/cleanup, stable live views and real-KDF lifetimes\n')
	}
}

@[direct_array_access]
fn growth_preview_entry() i32 {
	C.printf(c'PLAN START\n'); warm_image()
	phase := C.open(c'/second-boot', C.O_RDONLY)
	if phase < 0 {
		parent := $if amd64 { &char(c'/dev/sd0') } $else { &char(c'/dev/vda') }
		wrong := $if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') }
		growth_preview_first(parent, wrong)
	} else {
		check(C.close(phase) == 0, c'close preview phase')
		parent := $if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') }
		check(status(parent).bytes == 33554432, c'physical disk expanded and reordered')
		for recovery in [false, true]! {
			for readonly in [false, true]! {
				growth_preview_query(parent, recovery, readonly, 16777216, 8192, 1)
				growth_preview_query(parent, recovery, readonly, 33554432, 4096, 0)
				growth_preview_query(parent, recovery, readonly, 33554432, 12288, 0)
				missing(c'/dev/mapper/vinix60')
			}
		}
		// Actual adoption/application is a separate explicit action after preview.
		recovery_growth_tool(parent, c'/root/volume-ro.vrecover', c'33554432', c'4096', c'/root/adopted.vrecover', 0)
		recovery_unlock_view(parent, c'/root/adopted.vrecover', false, true)
		check(C.unlink(c'/root/preview.out') == 0, c'clear expanded preview capture')
		check(C.open(c'/root/crypt.key', C.O_RDONLY) < 0 && unsafe { C.errno == C.ENOENT }, c'expanded previews create no raw key')
		C.printf(c'PLAN GROWTH PREVIEW CAPACITY BOOT PRESERVED\n')
	}
	C.printf(c'PLAN DONE\n'); for { C.pause() }
	return 0
}
