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

fn child(path string, marker string) ! {
	mut process := os.new_process(path); process.set_redirect_stdio_merged()
	process.run(); text := process.stdout_slurp(); process.wait(); code := process.code; process.close(); print(text)
	if code != 0 || (marker != '' && !text.contains(marker)) { return error('native collection request fixture failed: ' + path) }
}

fn check() ! {
	// Scope fixture construction/assertions to one child; only the complete
	// collection call is tracked. Native repetition is explicitly bounded to 8.
	for architecture in ['aarch64', 'x86_64']! {
		for snapshot in [false, true]! {
			for mode in ['fresh', 'retained', 'reclaim', 'leased', 'unsafe-root', 'unsafe-stage',
				'bad-number', 'object-directory', 'bad-current', 'bad-previous', 'busy-before-config']! {
				os.setenv('VINIX_COLLECTION_CASE', architecture + (if snapshot { ' explicit ' } else { ' service ' }) + mode, true)
				child('/usr/share/package-fixtures/request', 'COLLECTION REQUEST selected case PASS')!
			}
		}
		for mode in ['bad-config', 'invalid-root']! {
			os.setenv('VINIX_COLLECTION_CASE', architecture + ' service ' + mode, true)
			child('/usr/share/package-fixtures/request', 'COLLECTION REQUEST selected case PASS')!
		}
	}
	os.unsetenv('VINIX_COLLECTION_CASE')
	println('COLLECTION REQUEST 48 selected cases with 8 measured calls each PASS')
	child('/usr/share/package-fixtures/retirement', 'COLLECTION RETIREMENT 128 successful removals')!
	child('/usr/share/package-fixtures/limit', 'Package collection: 128 obsolete generations')!
	child('/usr/share/package-fixtures/service', '')!
}

fn main() {
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }; fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	println('HWTEST START packages-collection-request')
	mut passed := true; check() or { eprintln(err); passed = false }
	println(if passed { 'HWTEST PASS packages-collection-request' } else { 'HWTEST FAIL packages-collection-request' })
	C.sync(); C.reboot(0x4321fedc); for { C.sleep(1) }
}
