// SPDX-License-Identifier: GPL-2.0-or-later
// Host PTY contract: literal exec arguments, geometry, input and fd retirement.
module main

import desktop.ptycore
import os
import time

fn collect(fd int, until string) !string {
	mut output := ''
	mut buffer := []u8{len: 4096}
	for _ in 0 .. 500 {
		got := C.read(fd, buffer.data, usize(buffer.len))
		if got > 0 { output += unsafe { tos(buffer.data, int(got)) } }
		if output.contains(until) { return output }
		time.sleep(10 * time.millisecond)
	}
	return error('terminal output timeout: ${output}')
}

fn check() ! {
	executable := os.executable()
	literal := 'space ; \$literal `argument`'
	// A non-CLOEXEC descriptor must also be closed before the child executes.
	initial := C.open(c'/dev/null', C.O_RDONLY)
	extra := C.fcntl(initial, C.F_DUPFD, 200)
	C.close(initial)
	assert extra >= 3
	defer { C.close(extra) }
	child := ptycore.spawn([executable, 'probe', literal, extra.str()], ['TERM=linux'], os.temp_dir(), 24, 80, 640, 384)!
	defer { C.close(child.terminal) }
	mut status := i32(0)
	mut reaped := false
	defer { if !reaped { C.kill(child.pid, C.SIGTERM); C.waitpid(child.pid, &status, 0) } }
	first := collect(child.terminal, 'PTY READY') or {
		if C.waitpid(child.pid, &status, C.WNOHANG) == child.pid { reaped = true }
		return error('${err}; child reaped=${reaped}, status=${status}')
	}
	assert first.contains(literal) && first.contains('24x80') && first.contains('TTY=111 FD=CLOSED TERM=linux'), first
	assert ptycore.resize(child.terminal, 30, 100, 800, 480)
	assert !ptycore.resize(child.terminal, 65536, 80, 0, 0)
	input := 'typed ; \$line\n'
	assert C.write(child.terminal, input.str, usize(input.len)) == input.len
	response := collect(child.terminal, 'PTY DONE')!
	assert response.contains('INPUT=typed ; \$line SIZE=30x100'), response
	assert C.waitpid(child.pid, &status, 0) == child.pid && status == 0
	reaped = true
	for args in [ []string{}, ['relative'], ['/bin/echo', 'bad\x00argument'] ] {
		mut refused := false
		ptycore.spawn(args, [], '/', 24, 80, 0, 0) or { refused = true }
		assert refused
	}
	println('Package terminal: literal argv, PTY geometry/input, inherited-fd closure and clean child exit passed')
}

fn main() {
	if os.args.len > 1 && os.args[1] == 'probe' {
		assert C.isatty(0) == 1 && C.isatty(1) == 1 && C.isatty(2) == 1
		assert C.fcntl(os.args[3].int(), C.F_GETFD) < 0
		mut size := [4]u16{}
		C.ioctl(0, u64(u32(C.TIOCGWINSZ)), &size)
		println('${os.args[2]} ${size[0]}x${size[1]} TTY=111 FD=CLOSED TERM=' + os.getenv('TERM'))
		println('PTY READY')
		line := os.input('')
		C.ioctl(0, u64(u32(C.TIOCGWINSZ)), &size)
		println('INPUT=${line} SIZE=${size[0]}x${size[1]}')
		println('PTY DONE')
		return
	}
	check() or { eprintln(err); exit(1) }
}
