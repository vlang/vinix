// SPDX-License-Identifier: GPL-2.0-or-later
module agxhost

fn C.fork() i32

fn vm_open_descriptors() int {
	mut count := 0
	for fd in 0 .. 256 { if C.fcntl(fd, C.F_GETFD) >= 0 { count++ } }
	return count
}

fn test_vm_socket_owners_retire_on_success_and_connect_failure() {
	before := vm_open_descriptors()
	for _ in 0 .. 100 {
		port := vm_available_port() or { panic(err) }
		assert port.int() > 0 && port.int() <= 65535
		assert !(vm_quit_monitor('/tmp/vinix-agx-absent-monitor') or { panic(err) })
	}
	assert vm_open_descriptors() == before
}

fn test_vm_child_retirement_reaps_an_exited_child() {
	before := vm_open_descriptors()
	for _ in 0 .. 100 {
		pid := C.fork()
		assert pid >= 0
		if pid == 0 { C._exit(0) }
		vm_stop_child(pid, -1, false) or { panic(err) }
		mut status := i32(0)
		assert C.waitpid(pid, &status, C.WNOHANG) < 0
		assert C.errno == C.ECHILD
	}
	assert vm_open_descriptors() == before
}

fn test_vm_select_rejects_large_descriptors_without_touching_the_fd_set() {
	vm_socket_ready(C.FD_SETSIZE, false, vm_now() + 1) or {
		assert err.msg() == 'filedescriptor out of range in select()'
		return
	}
	assert false
}
