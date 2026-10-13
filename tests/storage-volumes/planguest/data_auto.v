// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

@[direct_array_access]
fn data_auto_tool(verb &char, input &char, destination &char, expected i32, output &char) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'), verb, input, destination, &char(nil)]!
		fd := C.open(c'/root/auto-data-output', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600)); check(fd >= 0, c'open automatic data capture')
		child := C.fork(); check(child >= 0, c'fork automatic data utility')
		if child == 0 { if C.dup2(fd, 1) != 1 || C.close(fd) != 0 { C._exit(126) }; C.execv(args[0], &args[0]); C._exit(127) }
		mut code := i32(0); check(C.close(fd) == 0 && C.waitpid(child, &code, 0) == child && code == expected << 8, c'automatic data exact exit')
		capture := C.open(c'/root/auto-data-output', C.O_RDONLY); count := C.read(capture, output, 4095)
		check(capture >= 0 && count >= 0 && count < 4095 && C.close(capture) == 0, c'bounded automatic data output'); output[count] = 0
		if expected == 1 { check(C.strstr(output, c'operation=') == nil, c'automatic data failure emits no success') }
	}
}

@[direct_array_access]
fn data_auto_equal(first &char, second &char) {
	left := C.open(first, C.O_RDONLY); right := C.open(second, C.O_RDONLY); mut a := [4096]u8{}; mut b := [4096]u8{}
	check(left >= 0 && right >= 0, c'open equal data artifacts'); na := C.read(left, &a[0], 4096); nb := C.read(right, &b[0], 4096)
	check(na > 0 && na < 4096 && na == nb && C.close(left) == 0 && C.close(right) == 0, c'bounded equal data artifacts')
	for i := i64(0); i < na; i++ { check(a[i] == b[i], c'exact manual automatic artifact equality') }
}

@[direct_array_access]
fn data_auto_setup(parent &char, other &char) {
	unsafe {
		tool(c'create', parent, c'2', c'1048576', c'8192', 0); tool(c'create', other, c'9', c'1048576', c'8192', 0)
		readonly := [&char(c'/usr/sbin/vinix-volume'), &char(c'create'), parent, &char(c'5'), &char(c'2097152'), &char(c'12288'), &char(c'ro'), &char(nil)]!
		run_utility(&readonly[0], 0)
		for disk in 0 .. 2 {
			fd := C.open(if disk == 0 { &char(c'/dev/mapper/vinix2') } else { &char(c'/dev/mapper/vinix9') }, C.O_RDWR); mut bytes := [4096]u8{}
			for i in 0 .. 4096 { bytes[i] = if disk == 0 { u8(0x6d) } else { u8(0x9c) } }
			check(fd >= 0 && C.pwrite(fd, &bytes[0], 4096, 0) == 4096 && C.pwrite(fd, &bytes[0], 4096, 4096) == 4096 && C.fsync(fd) == 0 && C.close(fd) == 0, c'persist two-disk automatic data fixture')
		}
		tool(c'save-set', c'/root/auto-data.vset', parent, other, nil, 0)
		mut manual := [4096]char{}; mut automatic := [4096]char{}
		data_tool(c'/root/auto-data.vset', c'/root/manual-data.vhash', parent, other, true, 0, &manual[0])
		data_auto_tool(c'hash-bundle-auto', c'/root/auto-data.vset', c'/root/auto-data.vhash', 0, &automatic[0])
		check(C.strcmp(&manual[0], &automatic[0]) == 0, c'exact automatic hash output'); data_auto_equal(c'/root/manual-data.vhash', c'/root/auto-data.vhash')
	}
}

@[direct_array_access]
fn data_auto_matrix(parent &char, other &char, corrupt bool) {
	mut manual := [4096]char{}; mut automatic := [4096]char{}
	data_tool(unsafe { nil }, c'/root/manual-data.vhash', parent, other, false, if corrupt { 1 } else { 0 }, &manual[0])
	data_auto_tool(c'verify-data-auto', c'/root/auto-data.vhash', unsafe { nil }, if corrupt { 1 } else { 0 }, &automatic[0])
	if !corrupt { check(C.strcmp(&manual[0], &automatic[0]) == 0, c'exact automatic verification output') }
	scrub_tool(c'/root/manual-data.vhash', c'/root/manual-data.txt', parent, other, if corrupt { 2 } else { 0 }, &manual[0])
	data_auto_tool(c'scrub-data-auto', c'/root/auto-data.vhash', c'/root/auto-data.txt', if corrupt { 2 } else { 0 }, &automatic[0])
	check(C.strcmp(&manual[0], &automatic[0]) == 0, c'exact automatic complete scrub output'); data_auto_equal(c'/root/manual-data.txt', c'/root/auto-data.txt')
	copy_scrub_report(c'/root/auto-data.txt', if corrupt { &char(c'/root/auto-data-changed.txt') } else { &char(c'/root/auto-data-clean.txt') })
}

fn data_auto_cycles(count int) {
	mut output := [4096]char{}
	for _ in 0 .. count {
		data_auto_tool(c'hash-bundle-auto', c'/root/auto-data.vset', c'/root/auto-data.vhash', 0, &output[0])
		data_auto_tool(c'verify-data-auto', c'/root/auto-data.vhash', unsafe { nil }, 0, &output[0])
		data_auto_tool(c'scrub-data-auto', c'/root/auto-data.vhash', c'/root/auto-data.txt', 0, &output[0])
	}
	C.sleep(13); C.printf(c'PLAN DATA AUTO CYCLES count=%d\n', count)
}

@[direct_array_access]
fn data_auto_retention() {
	data_auto_cycles(100); mut before := Heap{}; mut after := Heap{}
	heap_snapshot(mut before); heap_snapshot(mut after); heap_snapshot(mut before)
	data_auto_cycles(100); heap_snapshot(mut after)
	C.printf(c'PLAN DATA AUTO LARGE before=%ld after=%ld\n', before.large, after.large)
	check(before.count == after.count && before.large == after.large, c'automatic data large-page retention')
	for i in 0 .. before.count {
		C.printf(c'PLAN DATA AUTO RETAIN size=%ld delta=%ld\n', before.sizes[i], after.live[i] - before.live[i])
		check(before.sizes[i] == after.sizes[i] && before.live[i] == after.live[i], c'automatic data slab retention')
	}
}

@[direct_array_access]
fn data_auto_entry() i32 {
	C.printf(c'PLAN START\n'); warm_image(); phase := C.open(c'/second-boot', C.O_RDONLY)
	parent := $if amd64 { &char(c'/dev/sd0') } $else { &char(c'/dev/vda') }; other := $if amd64 { &char(c'/dev/sd1') } $else { &char(c'/dev/vdb') }
	if phase < 0 {
		data_auto_setup(parent, other); data_auto_matrix(parent, other, false)
		first := status(c'/dev/mapper/vinix2'); second := status(c'/dev/mapper/vinix9'); held := C.open(c'/dev/mapper/vinix9', C.O_RDONLY); check(held >= 0, c'hold automatic data view')
		mut output := [4096]char{}; data_auto_tool(c'verify-data-auto', c'/root/auto-data.vhash', unsafe { nil }, 0, &output[0])
		check(first == status(c'/dev/mapper/vinix2') && second == status(c'/dev/mapper/vinix9'), c'automatic verification preserves complete live status')
		left := C.open(parent, C.O_RDWR); right := C.open(other, C.O_RDWR); mut a := [4096]u8{}; mut b := [4096]u8{}
		check(left >= 0 && right >= 0 && C.pread(left, &a[0], 4096, 1048576) == 4096 && C.pread(right, &b[0], 4096, 1048576) == 4096, c'pin two-disk automatic corruption')
		mut change := a; change[17] ^= 1; check(C.pwrite(left, &change[0], 4096, 1048576) == 4096 && C.fsync(left) == 0, c'persist first automatic corruption')
		change = b; change[93] ^= 3; check(C.pwrite(right, &change[0], 4096, 1048576) == 4096 && C.fsync(right) == 0, c'persist later automatic corruption')
		data_auto_matrix(parent, other, true)
		check(C.pwrite(left, &a[0], 4096, 1048576) == 4096 && C.fsync(left) == 0 && C.close(left) == 0 && C.pwrite(right, &b[0], 4096, 1048576) == 4096 && C.fsync(right) == 0 && C.close(right) == 0, c'restore both automatic corruption pages')
		signature(other, 0x1234567a)
		data_auto_tool(c'verify-data-auto', c'/root/auto-data.vhash', unsafe { nil }, 1, &output[0]); data_auto_tool(c'scrub-data-auto', c'/root/auto-data.vhash', c'/root/auto-data.txt', 1, &output[0])
		data_auto_equal(c'/root/auto-data.txt', c'/root/auto-data-changed.txt'); signature(other, 0x12345679)
		data_auto_matrix(parent, other, false)
		check(C.pread(held, &change[0], 4096, 0) == 4096 && C.close(held) == 0, c'read held automatic data view'); for value in change { check(value == 0x9c, c'preserved held automatic data') }
		check(status(c'/dev/mapper/vinix2').generation == first.generation && status(c'/dev/mapper/vinix9').generation == second.generation, c'automatic data preserves mapping generations')
		root := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY); check(root >= 0 && C.flock(root, C.LOCK_EX | C.LOCK_NB) == 0, c'hold automatic data writer lock')
		data_auto_tool(c'hash-bundle-auto', c'/root/auto-data.vset', c'/root/auto-data.vhash', 1, &output[0]); data_auto_tool(c'scrub-data-auto', c'/root/auto-data.vhash', c'/root/auto-data.txt', 1, &output[0])
		data_auto_tool(c'verify-data-auto', c'/root/auto-data.vhash', unsafe { nil }, 0, &output[0]); check(C.close(root) == 0, c'release automatic data writer lock')
		data_auto_retention()
		copy_plan(c'/root/auto-data.vset', c'/etc/vinix/volumes.vset')
		check(C.unlink(c'/etc/vinix/volumes.vmap') == 0, c'remove invalid automatic data boot plan')
		marker := C.open(c'/second-boot', C.O_WRONLY | C.O_CREAT | C.O_EXCL, u32(0o600))
		check(marker >= 0 && C.fsync(marker) == 0 && C.close(marker) == 0, c'persist automatic data phase')
		for path in [&char(c'/'), &char(c'/etc/vinix')]! {
			fd := C.open(path, C.O_RDONLY | C.O_DIRECTORY); check(fd >= 0 && C.fsync(fd) == 0 && C.close(fd) == 0, c'persist automatic data boot state')
		}
		C.printf(c'PLAN DATA AUTO PASSED: all-disk discovery, complete manual/automatic artifacts, corruption/failure precedence and bounded lifetimes\n')
	} else {
		check(C.close(phase) == 0, c'close automatic data phase'); data_auto_matrix(other, parent, false)
		mut output := [4096]char{}; data_auto_tool(c'hash-bundle-auto', c'/root/auto-data.vset', c'/root/auto-data.vhash', 0, &output[0]); data_auto_equal(c'/root/manual-data.vhash', c'/root/auto-data.vhash')
		C.printf(c'PLAN DATA AUTO REORDERED BOOT PRESERVED\n')
	}
	for file in [&char(c'/root/data-output'), &char(c'/root/scrub-output'), &char(c'/root/auto-data-output')]! { check(C.unlink(file) == 0, c'reclaim automatic data captures') }
	dir := C.open(c'/root', C.O_RDONLY | C.O_DIRECTORY); check(dir >= 0 && C.fsync(dir) == 0 && C.close(dir) == 0, c'persist automatic data artifacts')
	C.printf(c'PLAN DONE\n'); for { C.pause() }; return 0
}
