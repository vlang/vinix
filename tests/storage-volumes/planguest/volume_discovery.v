// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn volume_discovery_tool(config &char, password &char, readonly bool, expected i32) {
	unsafe {
		args := [&char(c'/usr/sbin/vinix-volume'), &char(c'open-volume-auto'), config, password, if readonly { &char(c'ro') } else { &char(nil) }, &char(nil)]!
		run_utility(&args[0], expected)
	}
}

fn volume_discovery_view(parent &char, config &char, readonly bool, saved_readonly bool) {
	unsafe {
		volume_discovery_tool(config, c'/root/next.pass', readonly, 0)
		info := status(c'/dev/mapper/vinix60')
		check(info.flags & 64 != 0 && (info.flags & 1 != 0) == (readonly || saved_readonly)
			&& info.disk_id == status(parent).disk_id && info.start == 15728640 && info.bytes == 4096, c'discovered configured geometry and physical identity')
		fd := C.open(c'/dev/mapper/vinix60', C.O_RDONLY)
		check(fd >= 0, c'open discovered encrypted view'); crypt_data(fd, 0, 0x73); check(C.close(fd) == 0, c'close discovered view')
		if readonly || saved_readonly { check(C.open(c'/dev/mapper/vinix60', C.O_RDWR) < 0 && C.errno == C.EROFS, c'automatic unlock retains readonly') }
		simple(c'remove', c'/dev/mapper/vinix60', nil, 0)
	}
}

fn planned_volume_discovery(parent &char, wrong &char) {
	unsafe {
		check(C.unlink(c'/root/crypt.key') == 0, c'delete raw key before automatic unlock')
		volume_discovery_tool(c'/root/volume-next.sealed', c'/root/crypt.pass', false, 1); missing(c'/dev/mapper/vinix60')
		volume_discovery_tool(c'/root/volume-bad.sealed', c'/root/crypt.pass', false, 1); missing(c'/dev/mapper/vinix60')
		physical_alias(parent)
		volume_discovery_view(parent, c'/root/volume-next.sealed', false, false)
		volume_discovery_view(parent, c'/root/volume-next.sealed', true, false)
		volume_discovery_view(parent, c'/root/volume-ro-next.sealed', false, true)
		signature(wrong, 0x12345678)
		volume_discovery_tool(c'/root/volume-next.sealed', c'/root/next.pass', true, 1); missing(c'/dev/mapper/vinix60')
		signature(wrong, 0x12345679)
		check(C.unlink(c'/dev/volume-plan-alias') == 0 && C.unlink(c'/dev/volume-plan-link') == 0, c'automatic unlock alias cleanup')
		check(C.open(c'/root/crypt.key', C.O_RDONLY) < 0 && C.errno == C.ENOENT, c'automatic unlock creates no raw key')
		volume_seal_key_tool(c'/root/volume-next.sealed', c'/root/next.pass', c'/root/crypt.key', 0); recovery_check(c'/root/crypt.key')
		C.printf(c'PLAN VOLUME DISCOVERY PASSED: keyless RW/RO, physical aliases, clone refusal and authenticated identity\n')
	}
}

fn volume_discovery_cycles(parent &char, count int) {
	for _ in 0 .. count { volume_discovery_view(parent, c'/root/volume-next.sealed', true, false) }
	C.sleep(13); C.printf(c'PLAN VOLUME DISCOVERY CYCLES count=%d\n', count)
}

@[direct_array_access]
fn volume_discovery_retention(parent &char) {
	volume_discovery_cycles(parent, 4)
	mut before := Heap{}; mut after := Heap{}
	heap_snapshot(mut before); heap_snapshot(mut after); heap_snapshot(mut before)
	volume_discovery_cycles(parent, 4); heap_snapshot(mut after)
	C.printf(c'PLAN VOLUME DISCOVERY LARGE before=%ld after=%ld\n', before.large, after.large)
	check(before.count == after.count && before.large == after.large, c'automatic unlock large-page retention')
	for i in 0 .. before.count {
		C.printf(c'PLAN VOLUME DISCOVERY RETAIN size=%ld delta=%ld\n', before.sizes[i], after.live[i] - before.live[i])
		check(before.sizes[i] == after.sizes[i] && before.live[i] == after.live[i], c'automatic unlock slab retention')
	}
}

fn volume_discovery_reordered_boot(parent &char) {
	unsafe {
		check(C.unlink(c'/root/crypt.key') == 0, c'delete raw key before automatic reboot unlock')
		volume_discovery_view(parent, c'/root/volume-next.sealed', true, false)
		volume_discovery_view(parent, c'/root/volume-ro-next.sealed', false, true)
		check(C.open(c'/root/crypt.key', C.O_RDONLY) < 0 && C.errno == C.ENOENT, c'automatic reboot unlock creates no raw key')
		volume_seal_key_tool(c'/root/volume-next.sealed', c'/root/next.pass', c'/root/crypt.key', 0); recovery_check(c'/root/crypt.key')
		C.printf(c'PLAN VOLUME DISCOVERY REORDERED BOOT PRESERVED\n')
	}
}
