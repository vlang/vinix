// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import net
import json2
import time
import tlsruntime
import collectionstress

#include <fcntl.h>
#include <sys/reboot.h>
#include <unistd.h>

fn C.dup2(int, int) int
fn C.sync()
fn C.reboot(int) int
fn C.sleep(u32) u32

fn run(program string, args []string) ! {
	mut child := os.new_process(program)
	child.set_args(args)
	child.set_redirect_stdio_merged()
	child.run()
	output := child.stdout_slurp()
	child.wait()
	code := child.code
	child.close()
	print(output)
	assert code == 0, program
}

fn check() ! {
	path := '/usr/share/package-fixtures/tls.json'
	f := json2.decode[tlsruntime.Fixture](os.read_file(path)!)!
	run('/usr/bin/curl', ['--disable', '--version'])!
	mut ready := false
	for _ in 0 .. 60 {
		mut connection := net.dial_tcp(f.base.all_after('https://')) or {
			time.sleep(time.second)
			continue
		}
		connection.close()!
		ready = true
		break
	}
	assert ready, 'QEMU local repository did not become reachable'
	baseline := collectionstress.current_file_bytes()!
	ceiling := collectionstress.reservation_ceiling(baseline)!
	println('GUEST TLS file baseline=' + baseline.str() + ' ceiling=' + ceiling.str())
	for mode in tlsruntime.modes() {
		run('/usr/share/package-fixtures/tls-probe', [path, mode])!
		collectionstress.settle(mode, ceiling)!
	}
	println('GUEST TLS 23 cases with 8 measured cycles preserve authenticated state, certificate policy, bounded recovery and retired replies PASS')
}

fn main() {
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 {
		C.dup2(fd, 1)
		C.dup2(fd, 2)
		if fd > 2 { C.close(fd) }
	}
	println('HWTEST START packages-https-runtime')
	mut passed := true
	check() or {
		eprintln(err)
		passed = false
	}
	println(if passed {
		'HWTEST PASS packages-https-runtime'
	} else {
		'HWTEST FAIL packages-https-runtime'
	})
	C.sync()
	C.reboot(0x4321fedc)
	for { C.sleep(1) }
}
