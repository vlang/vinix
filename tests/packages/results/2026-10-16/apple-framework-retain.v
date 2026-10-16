module main
import crypto.sha256
import json2
import os
struct Pin { path string bytes u64 sha256 string }
struct Artifact { role string bytes u64 sha256 string }
struct Receipt { architecture string scenario string coverage []string artifacts []Artifact }
struct Check { name string status int }
struct Ledger { format int = 1 scope string baseline string compiler Pin sources []Pin artifacts []Pin }
fn pin(path string) !Pin {
	bytes := os.read_bytes(path)!
	return Pin{ path: path, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}
fn main() {
	work := os.real_path(os.dir(@FILE)); guest := os.real_path('build/paf-3')
	prefix := 'tests/packages/results/2026-10-16/apple-framework-'
	receipt := json2.decode[Receipt](os.read_file(guest + '/qualification.json')!)!
	assert receipt.architecture == 'aarch64' && receipt.scenario == 'packages-apple' && receipt.artifacts.len == 11 && receipt.coverage.len == 3
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
		if file.role.starts_with('Mach-O-') { assert file.bytes == 32768 }
		artifacts << actual
	}
	assert pin(guest + '/run-ios')!.sha256 == receipt.artifacts.filter(it.role == 'run-ios')[0].sha256
	serial := os.read_file(guest + '/packages-apple/serial.log')!
	assert serial.contains('HWTEST PASS packages-apple') && serial.count('PACKAGE APPLE FRAMEWORK counter=') == 5
	for count in [1, 2, 3, 4] { assert serial.count('PACKAGE APPLE FRAMEWORK counter=' + count.str() + ' paths files keychain PASS') == if count == 1 { 2 } else { 1 } }
	assert serial.contains('entitlement damaged-store refusal PASS')
	assert !serial.contains('V panic:') && !serial.contains('pledge "') && !serial.contains('HWTEST FAIL') && !serial.contains('still owned at shutdown')
	qmp := os.read_file(guest + '/packages-apple/qmp.log')!
	assert qmp.contains('SHUTDOWN') && qmp.contains('"guest": true')
	checks := json2.decode[[]Check](os.read_file(work + '/host.json')!)!
	assert checks.len == 7 && checks.all(it.status == 0)
	assert os.read_file(work + '/temporary-directory-run.txt')!.contains('IOS-TEMP-DIRECTORY-NATIVE:')
	assert os.read_file(work + '/sanitizer-run.txt')!.contains('two drained runtimes')
	controller := json2.decode[[]Check](os.read_file(work + '/controller.json')!)!
	assert controller.len == 4 && controller.filter(it.status == 0).len == 2 && controller.filter(it.status == 2).len == 2
	before := os.real_path('build/paf-1')
	baseline := json2.decode[Ledger](os.read_file('tests/packages/results/2026-10-16/apple-runtime-toolchain.json')!)!
	base_c := pin(os.real_path('build/par-2/run-ios.c'))!
	assert base_c.sha256 == baseline.artifacts.filter(it.path.ends_with('/build/par-2/run-ios.c'))[0].sha256
	assert pin(before + '/run-ios.c')!.sha256 == base_c.sha256
	assert os.read_file(before + '/packages-apple/serial.log')!.contains('V panic: iOS: unsupported application temporary directory')
	artifacts << pin(before + '/run-ios')!
	artifacts << pin(before + '/run-ios.c')!
	for suffix, source in {
		'aarch64.json': guest + '/qualification.json', 'aarch64.serial.txt': guest + '/packages-apple/serial.log',
		'aarch64.qmp.txt': guest + '/packages-apple/qmp.log', 'before.serial.txt': before + '/packages-apple/serial.log',
		'host.json': work + '/host.json', 'controller.json': work + '/controller.json',
		'temporary-directory.txt': work + '/temporary-directory-run.txt', 'sanitizer.txt': work + '/sanitizer-run.txt',
		'check.v': work + '/check.v', 'guest.v': work + '/guest.v', 'finish.v': work + '/finish.v', 'retain.v': work + '/retain.v' } {
		os.cp(source, prefix + suffix)!; artifacts << pin(prefix + suffix)!
	}
	for name in ['fixture-build', 'fixture-run', 'controller-build', 'temporary-directory-build', 'temporary-directory-run',
		'sanitizer-build', 'sanitizer-run', 'list-aarch64', 'list-x86_64', 'reject-x86_64', 'reject-inputs'] { artifacts << pin(work + '/' + name + '.txt')! }
	for path in [guest + '/runtime-v.log', guest + '/runtime-cc.log', guest + '/run-ios.c', guest + '/guest/init.c',
		work + '/fixture-test', work + '/controller', work + '/temp-test', work + '/temp-sanitize',
		'build/package-launch-transport-work/cross-cc', '/opt/homebrew/bin/aarch64-linux-musl-gcc', '/opt/homebrew/bin/qemu-system-aarch64'] { artifacts << pin(path)! }
	mut source_paths := []string{}
	for directory in ['tools/packages', 'tools/accounts', 'tools/keyring', 'tools/security-events', 'compat/ios', 'tests/accounts/guest', 'tests/packages/applefixture', 'tests/hardware-platform/hwhost'] { source_paths << os.walk_ext(directory, '.v') }
	for suffix in ['.h', '.S'] { source_paths << os.walk_ext('compat/ios', suffix) }
	source_paths << ['tests/packages/apple-runtime-check.v', 'tests/packages/apple-runtime-probe.v', 'tests/packages/apple-runtime-check.md',
		'tools/packages/SDK.md', 'tools/packages/README.md', 'docs/application-distribution.md', 'roadmap.md',
		'LICENSE', 'build/package-release-work/v-toolchain/LICENSE', 'build-support/musl/COPYRIGHT']
	source_paths.sort(); mut sources := []Pin{}
	for path in source_paths { sources << pin(path)! }
	compiler := pin(os.real_path('build/package-release-work/v-toolchain/v'))!
	assert compiler.sha256 == 'd88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af'
	os.write_file(prefix + 'toolchain.json', json2.encode(Ledger{
		scope: 'AArch64 signed Mach-O Foundation paths/file writes and Security generic-password persistence, maintenance, entitlement/corruption refusals; seven host and four controller checks; no graphical or x86-64 runtime qualification',
		baseline: '75cda4b57; pre-fix generated C matches apple-runtime-toolchain.json',
		compiler: compiler, sources: sources, artifacts: artifacts }) + '\n')!
	println('Verified 11 guest artifacts, five Mach-O successes, damaged-store refusal, pre-fix runtime failure, seven host checks, four controller guards and ' + sources.len.str() + ' source pins')
}
