// SPDX-License-Identifier: GPL-2.0-or-later
module planguest

fn C.strstr(&char, &char) &char

fn preview(command &char, grow bool, expected i32, output &char) {
	fd := C.open(c'/root/check-output', C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600))
	check(fd >= 0, c'open preview output')
	unsafe {
		arguments := [&char(c'/usr/sbin/vinix-volume'), command, &char(c'/root/saved.vset'), if grow {
			&char(c'grow')
		} else {
			&char(nil)
		}, &char(nil)]!
		child := C.fork()
		check(child >= 0, c'fork bundle preview')
		if child == 0 {
			if C.dup2(fd, 1) != 1 || C.dup2(fd, 2) != 2 || C.close(fd) != 0 { C._exit(126) }
			C.execv(arguments[0], &arguments[0])
			C._exit(127)
		}
		mut code := i32(0)
		check(C.close(fd) == 0 && C.waitpid(child, &code, 0) == child && code == expected << 8,
			c'bundle preview exit')
	}
	read := C.open(c'/root/check-output', C.O_RDONLY)
	count := C.read(read, output, 4095)
	check(read >= 0 && count > 0 && count < 4095 && C.close(read) == 0,
		c'read bounded preview output')
	unsafe {
		output[count] = 0
	}
}

fn contains(output &char, text &char) bool {
	return C.strstr(output, text) != unsafe { nil }
}

fn check_planned_bundle() {
	mut output := [4096]char{}
	first := status(c'/dev/mapper/vinix2').generation
	preview(c'show-bundle', false, 0, &output[0])
	check(contains(&output[0], c'identity=mbr:12345678')
		&& contains(&output[0], c'identity=mbr:12345679')
		&& contains(&output[0], c'slot=2 offset=1048576 bytes=8192 readonly=0')
		&& contains(&output[0], c'disks=2 mappings=3'), c'offline bundle report')
	preview(c'check-bundle', false, 1, &output[0])
	check(!contains(&output[0], c'action='), c'failed check has no action rows')
	preview(c'check-bundle', true, 0, &output[0])
	check(contains(&output[0], c'slot=2 action=grow') && contains(&output[0], c'slot=5 action=keep')
		&& contains(&output[0], c'slot=9 action=keep')
		&& contains(&output[0], c'current_bytes=4096 planned_bytes=8192')
		&& contains(&output[0], c'checked disks=2 create=0 keep=2 grow=1'),
		c'checked growth report')
	check(status(c'/dev/mapper/vinix2').bytes == 4096
		&& status(c'/dev/mapper/vinix2').generation == first,
		c'preview preserves live generation and capacity')
}

fn check_missing_bundle() {
	mut output := [4096]char{}
	preview(c'check-bundle', true, 0, &output[0])
	check(contains(&output[0], c'slot=9 action=create')
		&& contains(&output[0], c'checked disks=2 create=1 keep=1 grow=1'),
		c'checked missing view report')
	missing(c'/dev/mapper/vinix9')
	check(status(c'/dev/mapper/vinix2').bytes == 4096, c'preview creates and grows nothing')
}

fn check_conflicting_bundle() {
	mut output := [4096]char{}
	preview(c'check-bundle', true, 1, &output[0])
	check(!contains(&output[0], c'action='), c'later conflict prevents all preview actions')
	check(status(c'/dev/mapper/vinix2').bytes == 4096, c'failed preview leaves capacity unchanged')
}
