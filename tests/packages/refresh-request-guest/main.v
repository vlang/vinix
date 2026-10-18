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

fn child(path string, marker string, ceiling u64) ! {
	mut process := os.new_process(path); process.set_redirect_stdio_merged()
	process.run(); text := process.stdout_slurp(); process.wait(); code := process.code; process.close(); print(text)
	if code != 0 || (marker != '' && !text.contains(marker)) { return error('native refresh fixture failed: ' + path) }
	collectionstress.settle(path, ceiling)!
}

fn check() ! {
	baseline := collectionstress.current_file_bytes()!
	ceiling := collectionstress.reservation_ceiling(baseline)!
	println('REFRESH REQUEST file baseline=' + baseline.str() + ' ceiling=' + ceiling.str())
	for architecture in ['aarch64', 'x86_64']! {
		for explicit in [false, true]! {
			for mode in ['fresh', 'cached', 'migrate', 'empty', 'bad-cache', 'bad-history', 'signature', 'syntax', 'schema',
				'expired', 'floor', 'equivocation', 'ambiguous', 'missing-index', 'missing-signature', 'offline', 'busy']! {
				os.setenv('VINIX_REFRESH_CASE', architecture + (if explicit { ' explicit ' } else { ' service ' }) + mode, true)
				child('/usr/share/package-fixtures/request', 'REFRESH REQUEST selected case PASS', ceiling)!
			}
		}
		for mode in ['bad-config', 'invalid-root']! {
			os.setenv('VINIX_REFRESH_CASE', architecture + ' service ' + mode, true)
			child('/usr/share/package-fixtures/request', 'REFRESH REQUEST selected case PASS', ceiling)!
		}
	}
	os.unsetenv('VINIX_REFRESH_CASE')
	println('REFRESH REQUEST 72 cases with 64 measured calls after 8 warmups PASS')
	child('/usr/share/package-fixtures/lifetime', 'REFRESH REQUEST independently owned', ceiling)!
	child('/usr/share/package-fixtures/workspace', 'REFRESH PUBLICATION catalog 64 refused calls retained 0', ceiling)!
	child('/usr/share/package-fixtures/service', '', ceiling)!
	child('/usr/share/package-fixtures/copy', '', ceiling)!
}

fn main() {
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }; fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	println('HWTEST START packages-refresh-request')
	mut passed := true; check() or { eprintln(err); passed = false }
	println(if passed { 'HWTEST PASS packages-refresh-request' } else { 'HWTEST FAIL packages-refresh-request' })
	C.sync(); C.reboot(0x4321fedc); for { C.sleep(1) }
}
