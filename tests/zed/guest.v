// SPDX-License-Identifier: GPL-2.0-or-later
// Real Zed/compositor guest. No application rendering is substituted by the test.
module main

import os
import time

#include <sys/mman.h>
#include <unistd.h>

fn C.syscall(int, ...) i64
fn C.mmap(voidptr, usize, int, int, int, i64) voidptr
fn C.mprotect(voidptr, usize, int) int
fn C.munmap(voidptr, usize) int
fn C.__builtin___clear_cache(voidptr, voidptr)

type JitFunction = fn () int

fn barrier_worker() {
	for _ in 0 .. 100 {
		assert C.syscall(283, 32, 0, 0) == 0
	}
}

fn check_sync_core() {
	assert C.syscall(283, 0, 0, 0) == 96
	assert C.syscall(283, 0, 1, 0) == -1 && C.errno == 22
	assert C.syscall(283, 32, 0, 0) == -1 && C.errno == 1
	assert C.syscall(283, 64, 0, 0) == 0
	assert C.syscall(283, 1, 0, 0) == -1 && C.errno == 22
	mut workers := []thread{}
	for _ in 0 .. 4 { workers << spawn barrier_worker() }
	workers.wait()
	// Publish real AArch64 code, then execute it after the cross-CPU barrier.
	page := C.mmap(unsafe { nil }, 16384, 3, 0x22, -1, 0)
	assert i64(page) != -1
	unsafe {
		mut code := &u32(page)
		code[0] = 0x52800540 // mov w0, #42
		code[1] = 0xd65f03c0 // ret
		C.__builtin___clear_cache(page, voidptr(usize(page) + 8))
		assert C.mprotect(page, 16384, 5) == 0
		assert C.syscall(283, 32, 0, 0) == 0
		function := JitFunction(page)
		assert function() == 42
	}
	assert C.munmap(page, 16384) == 0
	println('ZED CHECK: membarrier ABI, 400 concurrent rendezvous and native JIT execution PASS')
}

fn main() {
	check_sync_core()
	for path in ['/tmp', '/run/user/0', '/root', '/dev/shm', '/var/log', '/var/lib/xkb',
		'/tmp/.X11-unix'] {
		os.mkdir_all(path) or { panic(err) }
	}
	for path in ['/tmp', '/dev/shm', '/tmp/.X11-unix'] { os.chmod(path, 0o1777) or { panic(err) } }
	os.setenv('HOME', '/root', true)
	os.setenv('PATH', '/usr/bin:/bin:/usr/sbin:/sbin', true)
	os.setenv('TERM', 'linux', true)
	os.setenv('LD_LIBRARY_PATH', '/usr/lib:/lib:/usr/lib/xorg/modules', true)
	os.write_file('/root/.vinix-user', 'version=1\nname=56696e6978\nkdf=scrypt\nn=16384\nr=8\np=1\nsalt=00112233445566778899aabbccddeeff\nhash=00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff\n') or { panic(err) }
	os.chmod('/root/.vinix-user', 0o600) or { panic(err) }
	os.write_file('/root/hello.v', "module main\n\nfn main() {\n\tprintln('Hello from Zed on Vinix!')\n}\n") or { panic(err) }
	println('ZED GUEST: starting Vinix desktop with Zed')
	mut desktop := os.new_process('/usr/bin/vinix-desktop')
	desktop.set_args(['--open=Zed'])
	desktop.run()
	mut seen := map[string]int{}
	for {
		time.sleep(2 * time.second)
		for name in os.ls('/tmp') or { []string{} } {
			if !name.starts_with('vinix-zed-') || !name.ends_with('.log') { continue }
			path := '/tmp/${name}'
			log := os.read_file(path) or { continue }
			previous := seen[path]
			if log.len > previous {
				println('ZED HOST LOG:\n' + log[previous..])
				seen[path] = log.len
			}
		}
		log_path := '/root/.local/share/zed/logs/Zed.log'
		if log := os.read_file(log_path) {
			if log.len > seen[log_path] {
				println('ZED APPLICATION LOG:\n' + log[seen[log_path]..])
				seen[log_path] = log.len
			}
		}
	}
}
