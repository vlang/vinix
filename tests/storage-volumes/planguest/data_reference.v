// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn data_reference_digest(row int, changed bool) &char {
	if row == 1 { return &char(c'f3cc103136423a57975750907ebc1d367e2985ac6338976d4d5a439f50323f4a') }
	if row == 0 { return if changed { &char(c'a0e9b2388628ce1ede06be9a96dc1f4d56696875758ced513eaf48a37fcd98d3') } else { &char(c'dbaee3acb7eaf137548de787f699f10538ac4e7baa408e00c185423f522fc0b7') } }
	return if changed { &char(c'b403b9d011e220cdfc6aa3b17c22dfac97c2c599b74bf8057c3861cfa977592f') } else { &char(c'8fed39bbc0483c6e4218dcb90b668c6fef2160217153098c528656e5758caec6') }
}
fn data_reference_hash(changed bool) &char {
	return if changed { &char(c'c464c0c5d2f2fc71c03efb0e88385d4c39b2f85b8743286bacd07d7d8db057a1') } else { &char(c'a54001cd53e073d1214f5c2ed19a0d4f14c18f6408ac69a4c65a6cf75f4d3d0a') }
}
fn data_reference_path(changed bool) &char {
	return if changed { &char(c'/root/changed-data.vhash') } else { &char(c'/root/manual-data.vhash') }
}

@[direct_array_access]
fn data_reference_tool(first &char, second &char, before bool, after bool, expected i32) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'), &char(c'compare-data-references'), first, second, &char(nil)]!
		fd := C.open(c'/root/reference-data-output', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600)); check(fd >= 0, c'open data reference capture')
		child := C.fork(); check(child >= 0, c'fork data reference utility')
		if child == 0 { if C.dup2(fd, 1) != 1 || C.close(fd) != 0 { C._exit(126) }; C.execv(args[0], &args[0]); C._exit(127) }
		mut code := i32(0); check(C.close(fd) == 0 && C.waitpid(child, &code, 0) == child && code == expected << 8, c'data reference exact exit')
		capture := C.open(c'/root/reference-data-output', C.O_RDONLY); mut actual := [4096]char{}; count := C.read(capture, &actual[0], 4095)
		check(capture >= 0 && count >= 0 && count < 4095 && C.close(capture) == 0, c'bounded data reference output'); actual[count] = 0
		if expected == 1 { check(C.strstr(&actual[0], c'operation=') == nil, c'data reference failure emits no finding'); return }
		mut text := [4096]char{}
		mut length := int(C.snprintf(&text[0], 4096, c'format=VINIXDH1 operation=compared-data-references disks=2 mappings=3 stable=%d changed=%d algorithm=sha256 before_reference_sha256=%s after_reference_sha256=%s\n', if before == after { 3 } else { 1 }, if before == after { 0 } else { 2 }, data_reference_hash(before), data_reference_hash(after)))
		for row in 0 .. 3 {
			disk := if row == 2 { u32(1) } else { u32(0) }; slot := if row == 0 { u32(2) } else if row == 1 { u32(5) } else { u32(9) }
			if row != 1 { length += int(C.snprintf(&text[length], usize(4096 - length), c'disk=%u disk_bytes=16777216 sector=512 identity=mbr:%08x\n', disk, u32(0x12345678) + disk)) }
			length += int(C.snprintf(&text[length], usize(4096 - length), c'disk=%u slot=%u offset=%lu bytes=%lu readonly=%lu result=%s before_sha256=%s after_sha256=%s\n', disk, slot, if row == 1 { u64(2097152) } else { u64(1048576) }, if row == 1 { u64(12288) } else { u64(8192) }, if row == 1 { u64(1) } else { u64(0) }, if row == 1 || before == after { &char(c'stable') } else { &char(c'changed') }, data_reference_digest(row, before), data_reference_digest(row, after)))
		}
		check(length > 0 && length < 4096 && C.strcmp(&actual[0], &text[0]) == 0, c'exact complete data reference report')
	}
}

@[direct_array_access]
fn data_reference_matrix() {
	for before in [false, true]! { for after in [false, true]! {
		data_reference_tool(data_reference_path(before), data_reference_path(after), before, after, if before == after { 0 } else { 2 })
		copy_scrub_report(c'/root/reference-data-output', if before { if after { &char(c'/root/cmp-changed-stable.txt') } else { &char(c'/root/cmp-reverse.txt') } } else { if after { &char(c'/root/cmp-changed.txt') } else { &char(c'/root/cmp-stable.txt') } })
	} }
	data_reference_tool(c'/root/manual-data.vhash', c'/root/auto-data.vhash', false, false, 0)
}

fn data_reference_cycles(count int) {
	for _ in 0 .. count {
		data_reference_tool(c'/root/manual-data.vhash', c'/root/manual-data.vhash', false, false, 0)
		data_reference_tool(c'/root/manual-data.vhash', c'/root/changed-data.vhash', false, true, 2)
		data_reference_tool(c'/root/changed-data.vhash', c'/root/manual-data.vhash', true, false, 2)
	}
	C.sleep(13); C.printf(c'PLAN DATA REFERENCE CYCLES count=%d\n', count)
}

@[direct_array_access]
fn data_reference_retention() {
	data_reference_cycles(100); mut before := Heap{}; mut after := Heap{}
	heap_snapshot(mut before); heap_snapshot(mut after); heap_snapshot(mut before)
	data_reference_cycles(100); heap_snapshot(mut after)
	C.printf(c'PLAN DATA REFERENCE LARGE before=%ld after=%ld\n', before.large, after.large)
	check(before.count == after.count && before.large == after.large, c'data reference retained large pages')
	for i in 0 .. before.count {
		C.printf(c'PLAN DATA REFERENCE RETAIN size=%ld delta=%ld\n', before.sizes[i], after.live[i] - before.live[i])
		check(before.sizes[i] == after.sizes[i] && before.live[i] == after.live[i], c'data reference retained slab objects')
	}
}

@[direct_array_access]
fn data_reference_entry() i32 {
	C.printf(c'PLAN START\n'); warm_image(); phase := C.open(c'/second-boot', C.O_RDONLY)
	parent := $if amd64 { &char(c'/dev/sd0') } $else { &char(c'/dev/vda') }; other := $if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') }
	if phase < 0 {
		data_auto_setup(parent, other); data_auto_matrix(parent, other, false)
		left := C.open(parent, C.O_RDWR); right := C.open(other, C.O_RDWR); mut a := [4096]u8{}; mut b := [4096]u8{}; mut changed := [4096]u8{}
		check(left >= 0 && right >= 0 && C.pread(left, &a[0], 4096, 1048576) == 4096 && C.pread(right, &b[0], 4096, 1048576) == 4096, c'pin changed data reference fixture')
		changed = a; changed[17] ^= 1; check(C.pwrite(left, &changed[0], 4096, 1048576) == 4096 && C.fsync(left) == 0, c'persist first changed reference extent')
		changed = b; changed[93] ^= 3; check(C.pwrite(right, &changed[0], 4096, 1048576) == 4096 && C.fsync(right) == 0, c'persist later changed reference extent')
		mut output := [4096]char{}; data_auto_tool(c'hash-bundle-auto', c'/root/auto-data.vset', c'/root/changed-data.vhash', 0, &output[0])
		check(C.pwrite(left, &a[0], 4096, 1048576) == 4096 && C.fsync(left) == 0 && C.close(left) == 0 && C.pwrite(right, &b[0], 4096, 1048576) == 4096 && C.fsync(right) == 0 && C.close(right) == 0, c'restore changed reference fixture')
		data_auto_matrix(parent, other, false); data_reference_matrix()
		copy_plan(c'/root/manual-data.vhash', c'/root/malformed-data.vhash'); bad := C.open(c'/root/malformed-data.vhash', C.O_RDWR); mut broken := u8(1)
		check(bad >= 0 && C.pwrite(bad, &broken, 1, 471) == 1 && C.fsync(bad) == 0 && C.close(bad) == 0, c'persist invalid later reference')
		data_reference_tool(c'/root/changed-data.vhash', c'/root/malformed-data.vhash', true, false, 1); check(C.unlink(c'/root/malformed-data.vhash') == 0, c'reclaim malformed data reference')
		first := status(c'/dev/mapper/vinix2'); second := status(c'/dev/mapper/vinix9'); held := C.open(c'/dev/mapper/vinix9', C.O_RDONLY); check(held >= 0, c'hold reference live mapping')
		root := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY); check(root >= 0 && C.flock(root, C.LOCK_EX | C.LOCK_NB) == 0, c'hold data reference writer lock')
		data_reference_matrix(); check(C.close(root) == 0 && first == status(c'/dev/mapper/vinix2') && second == status(c'/dev/mapper/vinix9'), c'offline comparisons preserve all live status under writer contention')
		check(C.pread(held, &changed[0], 4096, 0) == 4096 && C.close(held) == 0, c'read held data reference mapping'); for value in changed { check(value == 0x9c, c'preserved reference mapping content') }
		data_reference_retention(); copy_plan(c'/root/auto-data.vset', c'/etc/vinix/volumes.vset')
		check(C.unlink(c'/etc/vinix/volumes.vmap') == 0, c'remove invalid reference boot plan')
		marker := C.open(c'/second-boot', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600)); check(marker >= 0 && C.fsync(marker) == 0 && C.close(marker) == 0, c'persist data reference phase')
		C.printf(c'PLAN DATA REFERENCE PASSED: complete saved metadata, all-row digests/fingerprints, offline failure precedence and bounded lifetimes\n')
	} else {
		check(C.close(phase) == 0, c'close data reference phase'); data_auto_matrix(other, parent, false); data_reference_matrix()
		C.printf(c'PLAN DATA REFERENCE REORDERED BOOT PRESERVED\n')
	}
	for file in [&char(c'/root/data-output'), &char(c'/root/scrub-output'), &char(c'/root/auto-data-output'), &char(c'/root/reference-data-output')]! {
		// The reordered branch does not execute hash capture; its other captures exist.
		if C.unlink(file) != 0 { check(C.errno == C.ENOENT, c'reclaim reference captures') }
	}
	for path in [&char(c'/root'), &char(c'/etc/vinix'), &char(c'/')]! { fd := C.open(path, C.O_RDONLY | C.O_DIRECTORY); check(fd >= 0 && C.fsync(fd) == 0 && C.close(fd) == 0, c'persist data reference artifacts and boot phase') }
	C.printf(c'PLAN DONE\n'); for { C.pause() }; return 0
}
