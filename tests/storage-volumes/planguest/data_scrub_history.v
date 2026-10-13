// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn data_scrub_history_path(state int) &char {
	return if state == 0 { c'/root/auto-data-clean.txt' } else if state == 1 { c'/root/history-first-changed.txt' } else { c'/root/history-second-changed.txt' }
}
fn data_scrub_history_hash(state int) &char {
	return if state == 0 { c'0da36733d67b9e64dddad6f1b8616d206a34aebbc955d033f8b8dc7b07862017' } else if state == 1 { c'3da5f47799ff79b6e409d2a0d20563b1baaf86b122e6fb068cbc09f15bcdc990' } else { c'4a75ee35dfb64875994b0fe04a01db4f0579937b450e7935e20676d02081e3db' }
}
fn data_scrub_history_digest(row int, state int) &char {
	if state != 2 || row == 1 { return data_reference_digest(row, state != 0) }
	return if row == 0 { c'c703584dd0b765aa6323f9e3a9097e692a020b08a50f1383e5aa8c2b3987375b' } else { c'76cfd05d7fa0507be717512dfc127f8fbba372f78d129e90cf75a0470d43e8f9' }
}

@[direct_array_access]
fn data_scrub_history_tool(first &char, second &char, before int, after int, expected i32) {
	mut actual := [4096]char{}; data_auto_tool(c'compare-data-scrubs', first, second, expected, &actual[0])
	if expected == 1 { check(C.strstr(&actual[0], c'format=VINIXSR1') == unsafe { nil } && C.strstr(&actual[0], c'disk=') == unsafe { nil }, c'invalid history emits no partial comparison'); return }
	mut text := [4096]char{}; different := before != after
	mut length := int(C.snprintf(&text[0], 4096, c'format=VINIXSR1 operation=compared-data-scrubs disks=2 mappings=3 stable=%d changed=%d new_changes=%d restored=%d changed_again=%d algorithm=sha256 reference_sha256=a54001cd53e073d1214f5c2ed19a0d4f14c18f6408ac69a4c65a6cf75f4d3d0a before_report_sha256=%s after_report_sha256=%s\n', if different { 1 } else { 3 }, if different { 2 } else { 0 }, if different && before == 0 { 2 } else { 0 }, if different && after == 0 { 2 } else { 0 }, if different && before != 0 && after != 0 { 2 } else { 0 }, data_scrub_history_hash(before), data_scrub_history_hash(after)))
	for row in 0 .. 3 {
		result := if row == 1 || !different { &char(c'stable') } else if after == 0 { &char(c'restored') } else if before == 0 { &char(c'new-change') } else { &char(c'changed-again') }
		length += int(C.snprintf(unsafe { &text[length] }, usize(4096 - length), c'disk=%u slot=%u offset=%lu bytes=%lu readonly=%lu before=%s after=%s result=%s expected_sha256=%s before_sha256=%s after_sha256=%s\n', if row == 2 { u32(1) } else { u32(0) }, if row == 0 { u32(2) } else if row == 1 { u32(5) } else { u32(9) }, if row == 1 { u64(2097152) } else { u64(1048576) }, if row == 1 { u64(12288) } else { u64(8192) }, if row == 1 { u64(1) } else { u64(0) }, if row == 1 || before == 0 { &char(c'match') } else { &char(c'changed') }, if row == 1 || after == 0 { &char(c'match') } else { &char(c'changed') }, result, data_reference_digest(row, false), data_scrub_history_digest(row, before), data_scrub_history_digest(row, after)))
	}
	check(length > 0 && length < 4096 && C.strcmp(&actual[0], &text[0]) == 0, c'exact complete historical transitions and both report fingerprints')
}

@[direct_array_access]
fn data_scrub_history_matrix() {
	for before in 0 .. 3 { for after in 0 .. 3 {
		data_scrub_history_tool(data_scrub_history_path(before), data_scrub_history_path(after), before, after, if before == after { 0 } else { 2 })
		mut path := [64]char{}; check(C.snprintf(&path[0], 64, c'/root/history-%d-%d.txt', before, after) > 0, c'bounded history artifact path'); copy_scrub_report(c'/root/auto-data-output', &path[0])
	} }
}
fn data_scrub_history_cycles(count int) {
	for _ in 0 .. count {
		data_scrub_history_tool(data_scrub_history_path(0), data_scrub_history_path(1), 0, 1, 2)
		data_scrub_history_tool(data_scrub_history_path(1), data_scrub_history_path(0), 1, 0, 2)
		data_scrub_history_tool(data_scrub_history_path(1), data_scrub_history_path(2), 1, 2, 2)
	}
	C.sleep(13); C.printf(c'PLAN DATA SCRUB HISTORY CYCLES count=%d\n', count)
}
@[direct_array_access]
fn data_scrub_history_retention() {
	data_scrub_history_cycles(100); mut before := Heap{}; mut after := Heap{}
	heap_snapshot(mut before); heap_snapshot(mut after); heap_snapshot(mut before); data_scrub_history_cycles(100); heap_snapshot(mut after)
	C.printf(c'PLAN DATA SCRUB HISTORY LARGE before=%ld after=%ld\n', before.large, after.large)
	check(before.count == after.count && before.large == after.large, c'scrub history retained large pages')
	for i in 0 .. before.count { C.printf(c'PLAN DATA SCRUB HISTORY RETAIN size=%ld delta=%ld\n', before.sizes[i], after.live[i] - before.live[i]); check(before.sizes[i] == after.sizes[i] && before.live[i] == after.live[i], c'scrub history retained slab objects') }
}

@[direct_array_access]
fn data_scrub_history_entry() i32 {
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
		copy_scrub_report(data_scrub_history_path(1), c'/root/auto-data-changed.txt'); data_auto_matrix(parent, other, false); data_scrub_view_matrix(); data_scrub_history_matrix()
		copy_scrub_report(data_scrub_history_path(2), c'/root/invalid-history.txt'); mut bad := C.open(c'/root/invalid-history.txt', C.O_RDWR); mut info := C.stat{}; mut nul := u8(0)
		check(bad >= 0 && C.fstat(bad, &info) == 0 && C.pwrite(bad, &nul, 1, info.st_size - 2) == 1 && C.fsync(bad) == 0 && C.close(bad) == 0, c'persist malformed last history digest')
		data_scrub_history_tool(data_scrub_history_path(1), c'/root/invalid-history.txt', 1, 2, 1)
		copy_scrub_report(data_scrub_history_path(2), c'/root/invalid-history.txt'); bad = C.open(c'/root/invalid-history.txt', C.O_RDWR); mut digit := u8(`b`)
		at := C.strlen(c'format=VINIXSR1 operation=scrubbed-data disks=2 mappings=3 matched=1 changed=2 algorithm=sha256 reference_sha256=')
		check(bad >= 0 && C.pwrite(bad, &digit, 1, i64(at)) == 1 && C.fsync(bad) == 0 && C.close(bad) == 0, c'persist valid incompatible history reference')
		data_scrub_history_tool(data_scrub_history_path(1), c'/root/invalid-history.txt', 1, 2, 1); check(C.unlink(c'/root/invalid-history.txt') == 0, c'reclaim invalid history fixture')
		first := status(c'/dev/mapper/vinix2'); second := status(c'/dev/mapper/vinix9'); readonly := status(c'/dev/mapper/vinix5'); held := C.open(c'/dev/mapper/vinix9', C.O_RDONLY)
		check(held >= 0, c'hold history live mapping'); root := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY); check(root >= 0 && C.flock(root, C.LOCK_EX | C.LOCK_NB) == 0, c'hold history writer lock')
		data_scrub_history_matrix(); check(C.close(root) == 0 && first == status(c'/dev/mapper/vinix2') && second == status(c'/dev/mapper/vinix9') && readonly == status(c'/dev/mapper/vinix5'), c'offline history preserves all live status under writer contention')
		check(C.pread(held, &change[0], 4096, 0) == 4096 && C.close(held) == 0, c'read held history mapping'); for value in change { check(value == 0x9c, c'preserved history mapping content') }
		data_scrub_history_retention(); copy_plan(c'/root/auto-data.vset', c'/etc/vinix/volumes.vset'); check(C.unlink(c'/etc/vinix/volumes.vmap') == 0, c'remove invalid history boot plan')
		marker := C.open(c'/second-boot', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600)); check(marker >= 0 && C.fsync(marker) == 0 && C.close(marker) == 0, c'persist history phase')
		C.printf(c'PLAN DATA SCRUB HISTORY PASSED: complete stable/new-change/restored/changed-again findings, full fingerprints, failure precedence and bounded lifetimes\n')
	} else { check(C.close(phase) == 0, c'close history phase'); data_auto_matrix(other, parent, false); data_scrub_view_matrix(); data_scrub_history_matrix(); C.printf(c'PLAN DATA SCRUB HISTORY REORDERED BOOT PRESERVED\n') }
	for file in [&char(c'/root/data-output'), &char(c'/root/scrub-output'), &char(c'/root/auto-data-output')]! { if C.unlink(file) != 0 { check(C.errno == C.ENOENT, c'reclaim history captures') } }
	for path in [&char(c'/root'), &char(c'/etc/vinix'), &char(c'/')]! { fd := C.open(path, C.O_RDONLY | C.O_DIRECTORY); check(fd >= 0 && C.fsync(fd) == 0 && C.close(fd) == 0, c'persist history artifacts and boot phase') }
	C.printf(c'PLAN DONE\n'); for { C.pause() }; return 0
}
