// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

@[direct_array_access]
fn scrub_compare_tool(before &char, after &char, readonly bool, old_changed bool, new_changed bool, expected i32) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'), &char(c'compare-volume-scrubs'), before, after, &char(nil)]!
		capture := C.open(c'/root/compare.out', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600)); check(capture >= 0, c'open compare capture')
		child := C.fork(); check(child >= 0, c'fork compare tool')
		if child == 0 { if C.dup2(capture, 1) != 1 || C.close(capture) != 0 { C._exit(126) }; C.execv(args[0], &args[0]); C._exit(127) }
		check(C.close(capture) == 0, c'close compare capture'); mut code := i32(0)
		check(C.waitpid(child, &code, 0) == child && code == expected << 8, c'compare exact exit')
		fd := C.open(c'/root/compare.out', C.O_RDONLY); mut text := [2048]char{}
		check(fd >= 0, c'open compare output'); count := C.read(fd, &text[0], 2047)
		check(count >= 0 && count < 2047 && C.close(fd) == 0, c'bounded compare output')
		if expected == 1 { check(C.strstr(&text[0], c'operation=') == nil, c'invalid later report emits no comparison'); return }
		changed := old_changed != new_changed; mut wanted := [2048]char{}
		C.snprintf(&wanted[0], 2048, c'format=VINIXCS1 operation=compared-ciphertext mappings=1 stable=%lu changed=%lu algorithm=sha256 reference_sha256=%s\ndisk_bytes=16777216 sector=512 identity=mbr:12345678 slot=60 offset=15728640 bytes=4096 readonly=%lu before=%s after=%s result=%s expected_sha256=115d50809715a805656e2c32b2d84ce5b4df581c65e1ec9b4523df3f9e4a6748 before_sha256=%s after_sha256=%s\n',
			u64(!changed), u64(changed), if readonly { &char(c'b3163f5b9fe199889368f06145927d5c7632102ef305580ff54a0fe37ad426b0') } else { &char(c'ceb82ed81ecbf7ac0ced5930717d27aea59e88d7cf485e3a2bf885974c1d2329') }, u64(readonly),
			if old_changed { &char(c'changed') } else { &char(c'match') }, if new_changed { &char(c'changed') } else { &char(c'match') },
			if !changed { &char(c'stable') } else if new_changed { &char(c'new-change') } else { &char(c'restored') },
			if old_changed { &char(c'a45c3043d314e557b22fa0a7dc53957b2dd84154fedd0865703a1796c63bbc25') } else { &char(c'115d50809715a805656e2c32b2d84ce5b4df581c65e1ec9b4523df3f9e4a6748') },
			if new_changed { &char(c'a45c3043d314e557b22fa0a7dc53957b2dd84154fedd0865703a1796c63bbc25') } else { &char(c'115d50809715a805656e2c32b2d84ce5b4df581c65e1ec9b4523df3f9e4a6748') })
		check(C.strcmp(&text[0], &wanted[0]) == 0, c'exact independent historical comparison')
	}
}

@[direct_array_access]
fn scrub_compare_matrix() {
	mut before := [64]char{}; mut after := [64]char{}; mut original := [224]u8{}; mut again := [224]u8{}
	for readonly in [false, true]! { for old_changed in [false, true]! { for new_changed in [false, true]! {
		volume_scrub_name(&before[0], false, readonly, old_changed); volume_scrub_name(&after[0], true, readonly, new_changed)
		fd := C.open(&before[0], C.O_RDONLY); check(fd >= 0 && C.read(fd, &original[0], 224) == 224 && C.close(fd) == 0, c'snapshot comparison input')
		scrub_compare_tool(&before[0], &after[0], readonly, old_changed, new_changed, if old_changed == new_changed { 0 } else { 2 })
		fd2 := C.open(&before[0], C.O_RDONLY); check(fd2 >= 0 && C.read(fd2, &again[0], 224) == 224 && C.close(fd2) == 0 && original == again, c'comparison preserves input bytes')
		scrub_compare_tool(&before[0], &before[0], readonly, old_changed, old_changed, 0)
	} } }
	// Canonical reports with different saved modes cannot be compared.
	scrub_compare_tool(c'/root/clean-volume.vcscrub', c'/root/clean-volume-ro.vcscrub', false, false, false, 1)
	fd := C.open(c'/root/clean-volume.vcscrub', C.O_RDONLY); check(fd >= 0 && C.read(fd, &original[0], 224) == 224 && C.close(fd) == 0, c'read later invalid report fixture')
	original[0] ^= 1; bad := C.open(c'/root/bad.vcscrub', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
	check(bad >= 0 && C.write(bad, &original[0], 224) == 224 && C.close(bad) == 0, c'create private invalid report')
	scrub_compare_tool(c'/root/clean-volume.vcscrub', c'/root/bad.vcscrub', false, false, false, 1)
	check(C.unlink(c'/root/bad.vcscrub') == 0, c'reclaim invalid report'); missing(c'/dev/mapper/vinix60')
}

fn scrub_compare_cycles(count int) {
	for _ in 0 .. count {
		scrub_compare_tool(c'/root/clean-volume-ro.vcscrub', c'/root/changed-recovery-ro.vcscrub', true, false, true, 2)
		scrub_compare_tool(c'/root/changed-volume-ro.vcscrub', c'/root/clean-recovery-ro.vcscrub', true, true, false, 2)
		scrub_compare_tool(c'/root/changed-volume-ro.vcscrub', c'/root/changed-recovery-ro.vcscrub', true, true, true, 0)
	}
	C.sleep(13); C.printf(c'PLAN SCRUB COMPARE CYCLES count=%d\n', count)
}

@[direct_array_access]
fn scrub_compare_retention() {
	scrub_compare_cycles(100); mut before := Heap{}; mut after := Heap{}
	heap_snapshot(mut before); heap_snapshot(mut after); heap_snapshot(mut before)
	scrub_compare_cycles(100); heap_snapshot(mut after)
	C.printf(c'PLAN SCRUB COMPARE LARGE before=%ld after=%ld\n', before.large, after.large)
	check(before.count == after.count && before.large == after.large, c'comparison large-page retention')
	for i in 0 .. before.count {
		C.printf(c'PLAN SCRUB COMPARE RETAIN size=%ld delta=%ld\n', before.sizes[i], after.live[i] - before.live[i])
		check(before.sizes[i] == after.sizes[i] && before.live[i] == after.live[i], c'comparison slab retention')
	}
}

@[direct_array_access]
fn scrub_compare_entry() i32 {
	C.printf(c'PLAN START\n'); warm_image(); phase := C.open(c'/second-boot', C.O_RDONLY)
	if phase < 0 {
		volume_scrub_first($if amd64 { &char(c'/dev/sd0') } $else { &char(c'/dev/vda') }, $if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') })
		scrub_compare_matrix()
		recovery_unlock_tool(c'/root/volume-ro.vrecover', c'/root/recovery.key', false, 0)
		status_before := status(c'/dev/mapper/vinix60'); held := C.open(c'/dev/mapper/vinix60', C.O_RDONLY); check(held >= 0, c'hold comparison mapping')
		scrub_compare_tool(c'/root/clean-volume-ro.vcscrub', c'/root/changed-recovery-ro.vcscrub', true, false, true, 2)
		check(status_before == status(c'/dev/mapper/vinix60'), c'comparison preserves live status'); crypt_data(held, 0, 0x73)
		check(C.close(held) == 0, c'close comparison mapping'); simple(c'remove', c'/dev/mapper/vinix60', unsafe { nil }, 0)
		scrub_compare_retention(); C.printf(c'PLAN SCRUB COMPARE PASSED: stable/new-change/restored, exact references, private inputs and bounded lifetimes\n')
	} else {
		check(C.close(phase) == 0, c'close comparison phase'); scrub_compare_matrix()
		parent := $if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') }
		recovery_unlock_view(parent, c'/root/volume-ro.vrecover', false, true)
		C.printf(c'PLAN SCRUB COMPARE REORDERED BOOT PRESERVED\n')
	}
	check(C.unlink(c'/root/compare.out') == 0, c'reclaim comparison capture')
	C.printf(c'PLAN DONE\n'); for { C.pause() }; return 0
}
