module main
import crypto.sha256
import json2
import os
struct Pin { path string bytes u64 sha256 string }
struct Artifact { role string bytes u64 sha256 string }
struct Receipt { architecture string scenario string artifacts []Artifact }
struct Ledger { format int = 1 scope string compiler Pin sources []Pin artifacts []Pin }
fn pin(path string) !Pin {
	bytes := os.read_bytes(path)!
	return Pin{ path: path, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}
fn main() {
	work := os.real_path(os.dir(@FILE)); guest := os.real_path('build/par-2')
	prefix := 'tests/packages/results/2026-10-16/apple-runtime-'
	receipt := json2.decode[Receipt](os.read_file(guest + '/qualification.json')!)!
	assert receipt.architecture == 'aarch64' && receipt.scenario == 'packages-apple' && receipt.artifacts.len == 11
	paths := {'kernel': guest + '/kernel', 'guest-init': guest + '/guest/init',
		'package-service': guest + '/guest/root/usr/bin/vinix-package',
		'account-manager': guest + '/guest/root/usr/sbin/vinix-account',
		'session-runner': guest + '/guest/root/usr/sbin/vinix-session',
		'run-ios': guest + '/guest/root/usr/share/apple-fixtures/run-ios',
		'launcher': guest + '/guest/root/usr/share/apple-fixtures/launcher',
		'sandbox': guest + '/guest/root/usr/bin/vinix-sandbox',
		'Mach-O-1': guest + '/image-v1.macho', 'Mach-O-2': guest + '/image-v2.macho',
		'serial-log': guest + '/packages-apple/serial.log'}
	mut artifacts := []Pin{}
	for file in receipt.artifacts {
		actual := pin(paths[file.role])!
		assert actual.bytes == file.bytes && actual.sha256 == file.sha256, file.role
		artifacts << actual
	}
	assert pin(guest + '/run-ios')!.sha256 == receipt.artifacts.filter(it.role == 'run-ios')[0].sha256
	serial := os.read_file(guest + '/packages-apple/serial.log')!
	assert serial.contains('HWTEST PASS packages-apple') && serial.count('PACKAGE APPLE ') == 2
	assert !serial.contains('V panic:') && !serial.contains('pledge "') && !serial.contains('HWTEST FAIL')
	qmp := os.read_file(guest + '/packages-apple/qmp.log')!
	assert qmp.contains('SHUTDOWN') && qmp.contains('"guest": true')
	checks := json2.decode[[]json2.Any](os.read_file(work + '/host.json')!)!; assert checks.len == 8
	assert os.read_file(work + '/launch_ownership-run.txt')!.contains('1000 plan/close cycles each retained 0 bytes')
	for suffix, source in {
		'aarch64.json': guest + '/qualification.json', 'aarch64.serial.txt': guest + '/packages-apple/serial.log',
		'aarch64.qmp.txt': guest + '/packages-apple/qmp.log', 'host.json': work + '/host.json',
		'ownership.txt': work + '/launch_ownership-run.txt', 'x86_64.json': work + '/x86-stage.json',
		'host.v': work + '/host.v', 'guest.v': work + '/guest.v', 'finish.v': work + '/finish.v', 'retain.v': work + '/retain.v' } {
		os.cp(source, prefix + suffix)!
		artifacts << pin(prefix + suffix)!
	}
	for path in [work + '/apple_context-compile.txt', work + '/apple_context-run.txt', work + '/context-compile.txt',
		work + '/context-run.txt', work + '/launch_ownership-compile.txt', work + '/launch_ownership-run.txt',
		work + '/sanitizer-compile.txt', work + '/sanitizer-run.txt', work + '/list-aarch64.txt', work + '/list-x86_64.txt',
		work + '/reject-x86_64.txt', work + '/reject-inputs.txt', work + '/x86-stage.txt',
		guest + '/runtime-v.log', guest + '/runtime-cc.log', guest + '/run-ios.c',
		work + '/x86-root/usr/bin/vinix-package', work + '/x86-root/usr/sbin/vinix-session', work + '/x86-root/usr/libexec/vinix/vinix-linux-runner'] {
		artifacts << pin(path)!
	}
	mut source_paths := []string{}
	for directory in ['tools/packages', 'tools/accounts', 'compat/ios', 'tests/accounts/guest', 'tests/packages/applefixture', 'tests/hardware-platform/hwhost'] {
		source_paths << os.walk_ext(directory, '.v')
	}
	for suffix in ['.h', '.S'] { source_paths << os.walk_ext('compat/ios', suffix) }
	source_paths << ['tests/packages/apple-runtime-check.v', 'tests/packages/apple-runtime-probe.v', 'tests/packages/apple-runtime-check.md',
		'tools/packages/SDK.md', 'tools/packages/README.md', 'docs/application-distribution.md', 'roadmap.md',
		'LICENSE', 'build/package-release-work/v-toolchain/LICENSE', 'build-support/musl/COPYRIGHT']
	source_paths.sort(); mut sources := []Pin{}
	for path in source_paths { sources << pin(path)! }
	compiler := pin(os.real_path('build/package-release-work/v-toolchain/v'))!
	assert compiler.sha256 == 'd88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af'
	os.write_file(prefix + 'toolchain.json', json2.encode(Ledger{
		scope: 'AArch64 signed Mach-O/package boundary; eight host checks, four controller checks and x86-64 production tooling build; no graphical/Foundation/keychain API qualification',
		compiler: compiler, sources: sources, artifacts: artifacts }) + '\n')!
	println('Verified 11 guest artifacts, normal guest shutdown, eight host checks, target build logs and ' + sources.len.str() + ' source pins')
}
