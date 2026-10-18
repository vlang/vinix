// SPDX-License-Identifier: GPL-2.0-or-later
module main
import os
#include <fcntl.h>
#include <sys/reboot.h>
#include <unistd.h>
fn C.dup2(int, int) int
fn C.sync()
fn C.reboot(int) int
fn C.sleep(u32) u32
fn C.readlinkat(int, &char, voidptr, usize) isize

fn image_integration_files() ! {
	for pair in [
		['/usr/share/licenses/vinix-packages/ed25519-MIT.txt', $embed_file('../../../tools/packages/signing/LICENSE').to_string()],
		['/usr/share/licenses/vinix-packages/application-sdk-MIT.txt', $embed_file('../../../tools/packages/appsdk/LICENSE').to_string()],
		['/usr/share/vinix/actions/packages-change', $embed_file('../../../tools/accounts/actions/packages-change').to_string()],
		['/usr/share/vinix/actions/packages-launch', $embed_file('../../../tools/accounts/actions/packages-launch').to_string()]] {
		if os.is_link(pair[0]) || os.read_file(pair[0])! != pair[1] || os.stat(pair[0])!.mode & 0o7777 != 0o644 { return error('staged image integration file differs: ' + pair[0]) }
	}
	for pair in [['/usr/bin/vinix-software', '/usr/bin/vinix-desktop'],
		['/usr/share/applications/vinix-packages', '/var/lib/vinix-packages/current/share/applications']] {
		mut bytes := [128]u8{}
		count := C.readlinkat(C.AT_FDCWD, pair[0].str, unsafe { &bytes[0] }, usize(bytes.len))
		if count != pair[1].len || unsafe { tos(&bytes[0], int(count)) } != pair[1] { return error('staged image integration link differs: ' + pair[0]) }
	}
	if os.is_link('/var/lib/vinix-packages') || os.ls('/var/lib/vinix-packages')!.len != 0 { return error('image staging initialized consumer state') }
	println('IMAGE INTEGRATION native staged licenses/actions/launcher/registration and empty consumer state PASS')
}

fn child(path string, args []string, expected int, marker string) ! {
	mut process := os.new_process(path); process.set_args(args); process.set_redirect_stdio_merged()
	process.run(); text := process.stdout_slurp(); process.wait(); code := process.code; process.close(); print(text)
	if code != expected || !text.contains(marker) { return error('staged tool failed: ' + path) }
}

fn check() ! {
	child('/usr/share/package-fixtures/image-integration', [], 0, 'IMAGE INTEGRATION 82')!
	image_integration_files()!
	child('/usr/bin/vinix-package', ['--help'], 0, 'usage: vinix-package')!
	child('/usr/bin/vinix-package', ['--json', 'status'], 0, '"architecture":')!
	child('/usr/sbin/vinix-session', [], 2, 'usage: vinix-session')!
	child('/usr/libexec/vinix/vinix-linux-runner', [], 126, 'usage: vinix-linux-runner')!
	println('IMAGE INTEGRATION native production-staged package/session/Linux-runner execution PASS')
	before := os.read_file('/proc/kernel-resources')!; println('IMAGE INTEGRATION resources before grace:\n' + before)
	C.sleep(6)
	after := os.read_file('/proc/kernel-resources')!; println('IMAGE INTEGRATION resources after grace:\n' + after)
}

fn main() {
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }; fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	println('HWTEST START packages-image-integration')
	mut passed := true; check() or { eprintln(err); passed = false }
	println(if passed { 'HWTEST PASS packages-image-integration' } else { 'HWTEST FAIL packages-image-integration' })
	C.sync(); C.reboot(0x4321fedc); for { C.sleep(1) }
}
