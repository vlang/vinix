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
	if code != 0 || (marker != '' && !text.contains(marker)) { return error('native activation fixture failed: ' + path) }
	collectionstress.settle(path, ceiling)!
}
fn check() ! {
	baseline := collectionstress.current_file_bytes()!
	ceiling := collectionstress.reservation_ceiling(baseline)!
	println('ACTIVATION REQUEST file baseline=' + baseline.str() + ' ceiling=' + ceiling.str())
	for architecture in ['aarch64', 'x86_64']! {
		for explicit in [false, true]! {
			for mode in ['install', 'upgrade', 'install-kept', 'repair', 'damaged-repair', 'remove', 'file-download',
				'offline-missing', 'stale-review', 'rollback', 'rollback-unavailable', 'rollback-revoked']! {
				os.setenv('VINIX_ACTIVATION_CASE', architecture + (if explicit { ' explicit ' } else { ' service ' }) + mode, true)
				child('/usr/share/package-fixtures/request', 'ACTIVATION REQUEST selected case PASS', ceiling)!
			}
		}
		for mode in ['upgrade-noop', 'blocked-remove', 'empty-deploy', 'resume-download', 'missing-source', 'disk-refusal', 'interrupted',
			'prepare-damage', 'published-damage', 'bad-state', 'bad-cache', 'bad-history', 'unsafe-stage', 'counter-exhausted',
			'busy', 'bad-config', 'invalid-root', 'deployment-legacy', 'deployment-lock', 'deployment-empty', 'deployment-stale', 'deployment-malformed']! {
			os.setenv('VINIX_ACTIVATION_CASE', architecture + ' service ' + mode, true)
			child('/usr/share/package-fixtures/request', 'ACTIVATION REQUEST selected case PASS', ceiling)!
		}
	}
	os.unsetenv('VINIX_ACTIVATION_CASE')
	println('ACTIVATION REQUEST 92 cases with 64 measured calls after 2 warmups PASS')
	child('/usr/share/package-fixtures/lifetime', 'ACTIVATION REQUEST independent nested replies', ceiling)!
	for name in ['service', 'rollback', 'empty', 'admission']! { child('/usr/share/package-fixtures/' + name, '', ceiling)! }
}
fn main() {
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }; fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	println('HWTEST START packages-activation-request')
	mut passed := true; check() or { eprintln(err); passed = false }
	println(if passed { 'HWTEST PASS packages-activation-request' } else { 'HWTEST FAIL packages-activation-request' })
	C.sync(); C.reboot(0x4321fedc); for { C.sleep(1) }
}
