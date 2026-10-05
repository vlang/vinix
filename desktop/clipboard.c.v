// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct ClipboardChild {
	pid    int
	output int
}

fn desktop_spawn_clipboard(url string) ?ClipboardChild {
	mut pipe := [2]i32{}
	if C.pipe(&pipe[0]) != 0 {
		return none
	}
	desktop_set_cloexec(pipe[0], true)
	desktop_set_cloexec(pipe[1], true)
	desktop_set_nonblocking(pipe[0], true)
	argv := [c'curl', c'--fail', c'--silent', c'--noproxy', c'*', c'--max-time', c'3',
		c'--max-filesize', c'65536', &char(url.str), &char(unsafe { nil })]
	envp := [c'PATH=/usr/bin:/bin', &char(unsafe { nil })]
	defer {
		unsafe {
			argv.free()
			envp.free()
		}
	}
	pid := C.fork()
	if pid < 0 {
		C.close(pipe[0])
		C.close(pipe[1])
		return none
	}
	if pid == 0 {
		C.dup2(pipe[1], 1)
		// A clipboard helper must not keep app pipes or display devices alive.
		for fd := 3; fd < 4096; fd++ {
			C.close(fd)
		}
		C.execve(c'/usr/bin/curl', argv.data, envp.data)
		C._exit(127)
	}
	C.close(pipe[1])
	return ClipboardChild{ pid: pid, output: pipe[0] }
}
