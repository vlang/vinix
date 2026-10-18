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
	if code != 0 || (marker != '' && !text.contains(marker)) { return error('native collection stress fixture failed: ' + path) }
	collectionstress.settle(path, ceiling)!
}

fn check() ! {
	// Give each case its own creator account, and observe grace-period
	// retirement before constructing the next filesystem-heavy fixture.
	baseline := collectionstress.current_file_bytes()!
	ceiling := collectionstress.reservation_ceiling(baseline)!
	println('COLLECTION STRESS file baseline=' + baseline.str() + ' ceiling=' + ceiling.str())
	for architecture in ['aarch64', 'x86_64']! {
		for snapshot in [false, true]! {
			for mode in ['fresh', 'retained', 'reclaim', 'leased', 'unsafe-root', 'unsafe-stage',
				'bad-number', 'object-directory', 'bad-current', 'bad-previous', 'busy-before-config']! {
				os.setenv('VINIX_COLLECTION_CASE', architecture + (if snapshot { ' explicit ' } else { ' service ' }) + mode, true)
				child('/usr/share/package-fixtures/request', 'COLLECTION REQUEST selected case PASS', ceiling)!
			}
		}
		for mode in ['bad-config', 'invalid-root']! {
			os.setenv('VINIX_COLLECTION_CASE', architecture + ' service ' + mode, true)
			child('/usr/share/package-fixtures/request', 'COLLECTION REQUEST selected case PASS', ceiling)!
		}
	}
	os.unsetenv('VINIX_COLLECTION_CASE')
	println('COLLECTION STRESS 48 cases with 64 measured calls after 8 warmups PASS')
	child('/usr/share/package-fixtures/retirement-0', 'COLLECTION RETIREMENT', ceiling)!
	child('/usr/share/package-fixtures/retirement-1', 'COLLECTION RETIREMENT', ceiling)!
	child('/usr/share/package-fixtures/retirement-2', 'COLLECTION RETIREMENT', ceiling)!
	child('/usr/share/package-fixtures/retirement-3', 'COLLECTION RETIREMENT', ceiling)!
	child('/usr/share/package-fixtures/retirement-4', 'COLLECTION RETIREMENT', ceiling)!
	child('/usr/share/package-fixtures/retirement-5', 'COLLECTION RETIREMENT', ceiling)!
	println('COLLECTION STRESS all six retirement cases in separate processes PASS')
	child('/usr/share/package-fixtures/limit', 'Package collection: 128 obsolete generations', ceiling)!
	child('/usr/share/package-fixtures/service', '', ceiling)!
}

fn main() {
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }; fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	println('HWTEST START packages-collection-stress')
	mut passed := true; check() or { eprintln(err); passed = false }
	println(if passed { 'HWTEST PASS packages-collection-stress' } else { 'HWTEST FAIL packages-collection-stress' })
	C.sync(); C.reboot(0x4321fedc); for { C.sleep(1) }
}
