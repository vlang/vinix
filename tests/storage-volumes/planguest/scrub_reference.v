// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

@[direct_array_access]
fn scrub_reference_tool(manifest &char, report &char, state int, expected i32) {
	mut actual := [4096]char{}; data_auto_tool(c'verify-data-scrub-reference', manifest, report, expected, &actual[0])
	if expected == 1 { check(C.strstr(&actual[0], c'format=VINIXSR1') == unsafe { nil } && C.strstr(&actual[0], c'disk=') == unsafe { nil }, c'invalid reference binding emits no findings'); return }
	mut text := [4096]char{}
	mut length := int(C.snprintf(&text[0], 4096, c'format=VINIXSR1 operation=verified-data-scrub-reference disks=2 mappings=3 matched=%d changed=%d algorithm=sha256 reference_sha256=a54001cd53e073d1214f5c2ed19a0d4f14c18f6408ac69a4c65a6cf75f4d3d0a report_sha256=%s\n', if state == 0 { 3 } else { 1 }, if state == 0 { 0 } else { 2 }, data_scrub_history_hash(state)))
	for row in 0 .. 3 {
		if row == 0 || row == 2 { length += int(C.snprintf(unsafe { &text[length] }, usize(4096 - length), c'disk=%u disk_bytes=16777216 sector=512 identity=mbr:123456%02x\n', if row == 0 { u32(0) } else { u32(1) }, if row == 0 { u32(0x78) } else { u32(0x79) })) }
		length += int(C.snprintf(unsafe { &text[length] }, usize(4096 - length), c'disk=%u slot=%u offset=%lu bytes=%lu readonly=%lu result=%s expected_sha256=%s actual_sha256=%s\n', if row == 2 { u32(1) } else { u32(0) }, if row == 0 { u32(2) } else if row == 1 { u32(5) } else { u32(9) }, if row == 1 { u64(2097152) } else { u64(1048576) }, if row == 1 { u64(12288) } else { u64(8192) }, if row == 1 { u64(1) } else { u64(0) }, if row == 1 || state == 0 { &char(c'match') } else { &char(c'changed') }, data_reference_digest(row, false), data_scrub_history_digest(row, state)))
	}
	check(length > 0 && length < 4096 && C.strcmp(&actual[0], &text[0]) == 0, c'exact full reference binding, native geometry and historical findings')
}
@[direct_array_access]
fn scrub_reference_matrix() {
	for state in 0 .. 3 {
		for manifest in [&char(c'/root/manual-data.vhash'), &char(c'/root/auto-data.vhash')]! { scrub_reference_tool(manifest, data_scrub_history_path(state), state, if state == 0 { 0 } else { 2 }) }
		mut path := [64]char{}; check(C.snprintf(&path[0], 64, c'/root/bound-%d.txt', state) > 0, c'bounded binding artifact path'); copy_scrub_report(c'/root/auto-data-output', &path[0])
	}
}
fn scrub_reference_cycles(count int) {
	for _ in 0 .. count { for state in 0 .. 3 { scrub_reference_tool(c'/root/manual-data.vhash', data_scrub_history_path(state), state, if state == 0 { 0 } else { 2 }) } }
	C.sleep(13); C.printf(c'PLAN SCRUB REFERENCE CYCLES count=%d\n', count)
}
@[direct_array_access]
fn scrub_reference_retention() {
	scrub_reference_cycles(100); mut before := Heap{}; mut after := Heap{}
	heap_snapshot(mut before); heap_snapshot(mut after); heap_snapshot(mut before); scrub_reference_cycles(100); heap_snapshot(mut after)
	C.printf(c'PLAN SCRUB REFERENCE LARGE before=%ld after=%ld\n', before.large, after.large)
	check(before.count == after.count && before.large == after.large, c'reference binding retained large pages')
	for i in 0 .. before.count { C.printf(c'PLAN SCRUB REFERENCE RETAIN size=%ld delta=%ld\n', before.sizes[i], after.live[i] - before.live[i]); check(before.sizes[i] == after.sizes[i] && before.live[i] == after.live[i], c'reference binding retained slab objects') }
}

@[direct_array_access]
fn scrub_reference_entry() i32 {
	C.printf(c'PLAN START\n'); warm_image(); phase := C.open(c'/second-boot', C.O_RDONLY)
	parent := $if amd64 { &char(c'/dev/sd0') } $else { &char(c'/dev/vda') }; other := $if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') }
	if phase < 0 {
		data_auto_setup(parent, other); data_auto_matrix(parent, other, false)
		left := C.open(parent, C.O_RDWR); right := C.open(other, C.O_RDWR); mut a := [4096]u8{}; mut b := [4096]u8{}; mut change := [4096]u8{}
		check(left >= 0 && right >= 0 && C.pread(left, &a[0], 4096, 1048576) == 4096 && C.pread(right, &b[0], 4096, 1048576) == 4096, c'pin history corruption fixtures')
		for state in 1 .. 3 {
			change = a; change[17] ^= if state == 1 { u8(1) } else { u8(2) }; check(C.pwrite(left, &change[0], 4096, 1048576) == 4096 && C.fsync(left) == 0, c'persist first history corruption')
			change = b; change[93] ^= if state == 1 { u8(3) } else { u8(5) }; check(C.pwrite(right, &change[0], 4096, 1048576) == 4096 && C.fsync(right) == 0, c'persist later history corruption')
			data_auto_matrix(parent, other, true); copy_scrub_report(c'/root/auto-data-changed.txt', data_scrub_history_path(state))
		}
		check(C.pwrite(left, &a[0], 4096, 1048576) == 4096 && C.fsync(left) == 0 && C.close(left) == 0 && C.pwrite(right, &b[0], 4096, 1048576) == 4096 && C.fsync(right) == 0 && C.close(right) == 0, c'restore and flush both history pages')
		copy_scrub_report(data_scrub_history_path(1), c'/root/auto-data-changed.txt'); data_auto_matrix(parent, other, false); data_scrub_view_matrix(); data_scrub_history_matrix(); scrub_reference_matrix()
		copy_scrub_report(data_scrub_history_path(2), c'/root/invalid-history.txt'); mut bad := C.open(c'/root/invalid-history.txt', C.O_RDWR); mut info := C.stat{}; mut nul := u8(0)
		check(bad >= 0 && C.fstat(bad, &info) == 0 && C.pwrite(bad, &nul, 1, info.st_size - 2) == 1 && C.fsync(bad) == 0 && C.close(bad) == 0, c'persist malformed last history digest')
		data_scrub_history_tool(data_scrub_history_path(1), c'/root/invalid-history.txt', 1, 2, 1); scrub_reference_tool(c'/root/manual-data.vhash', c'/root/invalid-history.txt', 2, 1)
		copy_scrub_report(data_scrub_history_path(2), c'/root/invalid-history.txt'); bad = C.open(c'/root/invalid-history.txt', C.O_RDWR); mut digit := u8(`b`)
		at := C.strlen(c'format=VINIXSR1 operation=scrubbed-data disks=2 mappings=3 matched=1 changed=2 algorithm=sha256 reference_sha256=')
		check(bad >= 0 && C.pwrite(bad, &digit, 1, i64(at)) == 1 && C.fsync(bad) == 0 && C.close(bad) == 0, c'persist valid incompatible history reference')
		data_scrub_history_tool(data_scrub_history_path(1), c'/root/invalid-history.txt', 1, 2, 1); scrub_reference_tool(c'/root/manual-data.vhash', c'/root/invalid-history.txt', 2, 1); check(C.unlink(c'/root/invalid-history.txt') == 0, c'reclaim invalid history fixture')
		first := status(c'/dev/mapper/vinix2'); second := status(c'/dev/mapper/vinix9'); readonly := status(c'/dev/mapper/vinix5'); held := C.open(c'/dev/mapper/vinix9', C.O_RDONLY)
		check(held >= 0, c'hold history live mapping'); root := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY); check(root >= 0 && C.flock(root, C.LOCK_EX | C.LOCK_NB) == 0, c'hold history writer lock')
		data_scrub_history_matrix(); scrub_reference_matrix(); check(C.close(root) == 0 && first == status(c'/dev/mapper/vinix2') && second == status(c'/dev/mapper/vinix9') && readonly == status(c'/dev/mapper/vinix5'), c'offline history preserves all live status under writer contention')
		check(C.pread(held, &change[0], 4096, 0) == 4096 && C.close(held) == 0, c'read held history mapping'); for value in change { check(value == 0x9c, c'preserved history mapping content') }
		scrub_reference_retention(); copy_plan(c'/root/auto-data.vset', c'/etc/vinix/volumes.vset'); check(C.unlink(c'/etc/vinix/volumes.vmap') == 0, c'remove invalid history boot plan')
		marker := C.open(c'/second-boot', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600)); check(marker >= 0 && C.fsync(marker) == 0 && C.close(marker) == 0, c'persist history phase')
		C.printf(c'PLAN SCRUB REFERENCE PASSED: full checksum reference binding, exact native geometry, clean/changed findings and bounded lifetimes\n')
	} else { check(C.close(phase) == 0, c'close history phase'); data_auto_matrix(other, parent, false); data_scrub_view_matrix(); data_scrub_history_matrix(); scrub_reference_matrix(); C.printf(c'PLAN SCRUB REFERENCE REORDERED BOOT PRESERVED\n') }
	for file in [&char(c'/root/data-output'), &char(c'/root/scrub-output'), &char(c'/root/auto-data-output')]! { if C.unlink(file) != 0 { check(C.errno == C.ENOENT, c'reclaim history captures') } }
	for path in [&char(c'/root'), &char(c'/etc/vinix'), &char(c'/')]! { fd := C.open(path, C.O_RDONLY | C.O_DIRECTORY); check(fd >= 0 && C.fsync(fd) == 0 && C.close(fd) == 0, c'persist history artifacts and boot phase') }
	C.printf(c'PLAN DONE\n'); for { C.pause() }; return 0
}
