// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

@[direct_array_access]
fn data_scrub_view_tool(path &char, expected i32) {
	mut output := [4096]char{}; data_auto_tool(c'show-data-scrub', path, unsafe { nil }, expected, &output[0])
	if expected != 0 { check(C.strstr(&output[0], c'format=VINIXSR1') == unsafe { nil } && C.strstr(&output[0], c'disk=') == unsafe { nil }, c'invalid scrub inspection emits no partial report'); return }
	fd := C.open(path, C.O_RDONLY); mut saved := [4096]char{}; count := C.read(fd, &saved[0], 4095)
	check(fd >= 0 && count > 0 && count < 4095 && C.close(fd) == 0, c'read saved scrub inspection fixture'); saved[count] = 0
	check(C.strcmp(&output[0], &saved[0]) == 0, c'inspection preserves complete canonical report bytes')
}

fn data_scrub_view_matrix() {
	data_scrub_view_tool(c'/root/auto-data-clean.txt', 0); copy_scrub_report(c'/root/auto-data-output', c'/root/view-clean.txt')
	data_scrub_view_tool(c'/root/auto-data-changed.txt', 0); copy_scrub_report(c'/root/auto-data-output', c'/root/view-changed.txt')
	data_scrub_view_tool(c'/root/manual-data.txt', 0); copy_scrub_report(c'/root/auto-data-output', c'/root/view-manual.txt')
}

fn data_scrub_view_cycles(count int) {
	for _ in 0 .. count { data_scrub_view_tool(c'/root/auto-data-clean.txt', 0); data_scrub_view_tool(c'/root/auto-data-changed.txt', 0); data_scrub_view_tool(c'/root/manual-data.txt', 0) }
	C.sleep(13); C.printf(c'PLAN DATA SCRUB VIEW CYCLES count=%d\n', count)
}

@[direct_array_access]
fn data_scrub_view_retention() {
	data_scrub_view_cycles(100); mut before := Heap{}; mut after := Heap{}
	heap_snapshot(mut before); heap_snapshot(mut after); heap_snapshot(mut before)
	data_scrub_view_cycles(100); heap_snapshot(mut after)
	C.printf(c'PLAN DATA SCRUB VIEW LARGE before=%ld after=%ld\n', before.large, after.large)
	check(before.count == after.count && before.large == after.large, c'scrub inspection retained large pages')
	for i in 0 .. before.count {
		C.printf(c'PLAN DATA SCRUB VIEW RETAIN size=%ld delta=%ld\n', before.sizes[i], after.live[i] - before.live[i])
		check(before.sizes[i] == after.sizes[i] && before.live[i] == after.live[i], c'scrub inspection retained slab objects')
	}
}

@[direct_array_access]
fn data_scrub_view_entry() i32 {
	C.printf(c'PLAN START\n'); warm_image(); phase := C.open(c'/second-boot', C.O_RDONLY)
	parent := $if amd64 { &char(c'/dev/sd0') } $else { &char(c'/dev/vda') }; other := $if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') }
	if phase < 0 {
		data_auto_setup(parent, other); data_auto_matrix(parent, other, false)
		left := C.open(parent, C.O_RDWR); right := C.open(other, C.O_RDWR); mut a := [4096]u8{}; mut b := [4096]u8{}; mut change := [4096]u8{}
		check(left >= 0 && right >= 0 && C.pread(left, &a[0], 4096, 1048576) == 4096 && C.pread(right, &b[0], 4096, 1048576) == 4096, c'pin scrub inspection corruption fixture')
		change = a; change[17] ^= 1; check(C.pwrite(left, &change[0], 4096, 1048576) == 4096 && C.fsync(left) == 0, c'persist first scrub inspection corruption')
		change = b; change[93] ^= 3; check(C.pwrite(right, &change[0], 4096, 1048576) == 4096 && C.fsync(right) == 0, c'persist later scrub inspection corruption')
		data_auto_matrix(parent, other, true)
		check(C.pwrite(left, &a[0], 4096, 1048576) == 4096 && C.fsync(left) == 0 && C.close(left) == 0 && C.pwrite(right, &b[0], 4096, 1048576) == 4096 && C.fsync(right) == 0 && C.close(right) == 0, c'restore both scrub inspection fixture pages')
		data_auto_matrix(parent, other, false); data_scrub_view_matrix()
		copy_scrub_report(c'/root/auto-data-changed.txt', c'/root/invalid-scrub.txt'); bad := C.open(c'/root/invalid-scrub.txt', C.O_RDWR); mut info := C.stat{}; mut nul := u8(0)
		check(bad >= 0 && C.fstat(bad, &info) == 0 && C.pwrite(bad, &nul, 1, info.st_size - 2) == 1 && C.fsync(bad) == 0 && C.close(bad) == 0, c'persist invalid last scrub digest')
		data_scrub_view_tool(c'/root/invalid-scrub.txt', 1); check(C.unlink(c'/root/invalid-scrub.txt') == 0, c'reclaim malformed scrub report')
		first := status(c'/dev/mapper/vinix2'); second := status(c'/dev/mapper/vinix9'); readonly := status(c'/dev/mapper/vinix5')
		held := C.open(c'/dev/mapper/vinix9', C.O_RDONLY); check(held >= 0, c'hold scrub inspection mapping')
		root := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY); check(root >= 0 && C.flock(root, C.LOCK_EX | C.LOCK_NB) == 0, c'hold scrub inspection writer lock')
		data_scrub_view_matrix(); check(C.close(root) == 0 && first == status(c'/dev/mapper/vinix2') && second == status(c'/dev/mapper/vinix9') && readonly == status(c'/dev/mapper/vinix5'), c'offline inspection preserves all live status under writer contention')
		check(C.pread(held, &change[0], 4096, 0) == 4096 && C.close(held) == 0, c'read held scrub inspection mapping'); for value in change { check(value == 0x9c, c'preserved scrub inspection mapping contents') }
		data_scrub_view_retention(); copy_plan(c'/root/auto-data.vset', c'/etc/vinix/volumes.vset')
		check(C.unlink(c'/etc/vinix/volumes.vmap') == 0, c'remove invalid scrub inspection boot plan')
		marker := C.open(c'/second-boot', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600)); check(marker >= 0 && C.fsync(marker) == 0 && C.close(marker) == 0, c'persist scrub inspection phase')
		C.printf(c'PLAN DATA SCRUB VIEW PASSED: complete clean/changed historical reports, no partial output, live status and bounded lifetimes\n')
	} else {
		check(C.close(phase) == 0, c'close scrub inspection phase'); data_auto_matrix(other, parent, false); data_scrub_view_matrix()
		C.printf(c'PLAN DATA SCRUB VIEW REORDERED BOOT PRESERVED\n')
	}
	for file in [&char(c'/root/data-output'), &char(c'/root/scrub-output'), &char(c'/root/auto-data-output')]! { if C.unlink(file) != 0 { check(C.errno == C.ENOENT, c'reclaim scrub inspection captures') } }
	for path in [&char(c'/root'), &char(c'/etc/vinix'), &char(c'/')]! { fd := C.open(path, C.O_RDONLY | C.O_DIRECTORY); check(fd >= 0 && C.fsync(fd) == 0 && C.close(fd) == 0, c'persist scrub inspection artifacts and boot phase') }
	C.printf(c'PLAN DONE\n'); for { C.pause() }; return 0
}
