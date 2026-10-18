// SPDX-License-Identifier: GPL-2.0-or-later
module main
import os
import collectionstress
#include <fcntl.h>
#include <sys/reboot.h>
#include <unistd.h>
fn C.dup2(int, int) int
fn C.sync()
fn C.reboot(int) int
fn C.sleep(u32) u32
fn check() ! {
	baseline := collectionstress.current_file_bytes()!
	ceiling := collectionstress.reservation_ceiling(baseline)!
	println('HTTPS OWNER file baseline=' + baseline.str() + ' ceiling=' + ceiling.str())
	for name in ['owner', 'core']! {
		mut child := os.new_process('/usr/share/package-fixtures/' + name)
		child.set_args(['--producer', '/usr/share/package-fixtures/producer']); child.set_redirect_stdio_merged()
		child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close(); print(output)
		if code != 0 { return error('HTTPS ownership/output assertions failed') }
		collectionstress.settle(name, ceiling)!
	}
}
fn main() {
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }; fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	println('HWTEST START packages-https-owner')
	mut passed := true; check() or { eprintln(err); passed = false }
	println(if passed { 'HWTEST PASS packages-https-owner' } else { 'HWTEST FAIL packages-https-owner' })
	C.sync(); C.reboot(0x4321fedc); for { C.sleep(1) }
}
