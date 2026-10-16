module main
import crypto.sha256
import json2
import os
struct Pin { path string bytes u64 sha256 string }
struct Artifact { role string bytes u64 sha256 string }
struct Receipt { architecture string scenario string coverage []string artifacts []Artifact }
struct Check { name string seconds f64 }
struct HostReceipt { compiler_sha256 string checks []Check }
struct Build { artifacts []Pin }
struct Ledger { format int = 1 scope string compiler Pin sources []Pin artifacts []Pin }
fn pin(path string) !Pin { bytes := os.read_bytes(path)!; return Pin{ path: path, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() } }
fn main() {
	work := os.real_path(os.dir(@FILE)); guest := os.real_path('build/pap-1'); host := work + '/h1'
	prefix := 'tests/packages/results/2026-10-16/apple-profile-'
	receipt := json2.decode[Receipt](os.read_file(guest + '/qualification.json')!)!
	assert receipt.architecture == 'aarch64' && receipt.scenario == 'packages-apple' && receipt.artifacts.len == 11 && receipt.coverage.len == 4
	paths := {'kernel': guest + '/kernel', 'guest-init': guest + '/guest/init',
		'package-service': guest + '/guest/root/usr/bin/vinix-package', 'account-manager': guest + '/guest/root/usr/sbin/vinix-account',
		'session-runner': guest + '/guest/root/usr/sbin/vinix-session', 'run-ios': guest + '/guest/root/usr/share/apple-fixtures/run-ios',
		'launcher': guest + '/guest/root/usr/share/apple-fixtures/launcher', 'sandbox': guest + '/guest/root/usr/bin/vinix-sandbox',
		'Mach-O-1': guest + '/image-v1.macho', 'Mach-O-2': guest + '/image-v2.macho', 'serial-log': guest + '/packages-apple/serial.log'}
	mut artifacts := []Pin{}
	for item in receipt.artifacts { actual := pin(paths[item.role])!; assert actual.bytes == item.bytes && actual.sha256 == item.sha256, item.role; artifacts << actual }
	previous := json2.decode[Receipt](os.read_file('tests/packages/results/2026-10-16/apple-framework-aarch64.json')!)!
	for role in ['kernel', 'sandbox', 'run-ios'] { assert receipt.artifacts.filter(it.role == role)[0].sha256 == previous.artifacts.filter(it.role == role)[0].sha256 }
	serial := os.read_file(guest + '/packages-apple/serial.log')!
	assert serial.contains('HWTEST PASS packages-apple') && serial.count('PACKAGE APPLE PROFILE version=') == 2 && serial.count('PACKAGE APPLE FRAMEWORK counter=') == 5
	for version in ['1.0.0', '1.1.0'] { assert serial.contains('PACKAGE APPLE PROFILE version=' + version + ' runtime=' + version + ' architecture=aarch64 sha256=') }
	assert serial.contains('entitlement damaged-store refusal PASS') && !serial.contains('HWTEST FAIL') && !serial.contains('V panic:') && !serial.contains('pledge "')
	qmp := os.read_file(guest + '/packages-apple/qmp.log')!; assert qmp.contains('SHUTDOWN') && qmp.contains('"guest": true')
	checks := json2.decode[HostReceipt](os.read_file(host + '/qualification.json')!)!; assert checks.checks.len == 15
	assert checks.compiler_sha256 == pin('build/package-release-work/v-toolchain/v')!.sha256
	build := json2.decode[Build](os.read_file(work + '/x86-stage.json')!)!; assert build.artifacts.len == 3
	for file in build.artifacts { actual := pin(file.path)!; assert actual.sha256 == file.sha256 && actual.bytes == file.bytes; artifacts << actual }
	for suffix, source in {
		'host.json': host + '/qualification.json', 'lifecycle.txt': host + '/apple_profile-run.txt', 'headers.txt': host + '/apple_headers-run.txt',
		'aarch64.json': guest + '/qualification.json', 'aarch64.serial.txt': guest + '/packages-apple/serial.log', 'aarch64.qmp.txt': guest + '/packages-apple/qmp.log',
		'x86_64.json': work + '/x86-stage.json', 'guest.v': work + '/guest.v', 'finish.v': work + '/finish.v', 'retain.v': work + '/retain.v' } {
		os.cp(source, prefix + suffix)!; artifacts << pin(prefix + suffix)!
	}
	for check in checks.checks { artifacts << pin(host + '/' + check.name + '.txt')! }
	for name in ['list-aarch64', 'list-x86_64', 'reject-x86_64', 'reject-inputs', 'x86-stage'] { artifacts << pin(work + '/' + name + '.txt')! }
	assert os.read_file(work + '/list-aarch64.txt')!.contains('packages-apple') && os.read_file(work + '/list-x86_64.txt')!.trim_space() == ''
	assert os.read_file(work + '/reject-x86_64.txt')!.contains('only on AArch64') && os.read_file(work + '/reject-inputs.txt')!.contains('VINIX_HWTEST_TCG=1')
	for path in [host + '/vinix-package', host + '/apple_headers', host + '/apple_profile', host + '/apple_headers-sanitize', host + '/apple_profile-sanitize',
		work + '/controller', work + '/stage', guest + '/guest/init.c', guest + '/guest/build.log', 'build/package-launch-transport-work/cross-cc',
		'/opt/homebrew/bin/aarch64-linux-musl-gcc', '/opt/homebrew/bin/x86_64-linux-musl-gcc', '/opt/homebrew/bin/qemu-system-aarch64'] { artifacts << pin(path)! }
	mut source_paths := []string{}
	for directory in ['tools/packages', 'tools/accounts', 'tools/keyring', 'tools/security-events', 'compat/ios', 'tests/accounts/guest', 'tests/packages/applefixture', 'tests/packages/elffixture', 'tests/hardware-platform/hwhost'] { source_paths << os.walk_ext(directory, '.v') }
	for suffix in ['.h', '.S'] { source_paths << os.walk_ext('compat/ios', suffix) }
	source_paths << ['tests/packages/apple-profile-check.v', 'tests/packages/apple-profile-check.md', 'tests/packages/apple-runtime-check.v', 'tests/packages/apple-runtime-probe.v',
		'tests/packages/apple-runtime-check.md', 'tools/packages/SDK.md', 'tools/packages/README.md', 'docs/application-distribution.md', 'roadmap.md',
		'LICENSE', 'build/package-release-work/v-toolchain/LICENSE', 'build-support/musl/COPYRIGHT']
	source_paths.sort(); mut sources := []Pin{}; for path in source_paths { sources << pin(path)! }
	compiler := pin(os.real_path('build/package-release-work/v-toolchain/v'))!; assert compiler.sha256 == 'd88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af'
	os.write_file(prefix + 'toolchain.json', json2.encode(Ledger{
		scope: 'Apple AArch64-only publisher profile; fifteen host checks including CLI, lifecycle, structural/XML/binary admission and sanitizers; signed AArch64 profile/runtime guest, four controller guards and x86-64 production tooling build; no general graphical/Apple/Wine catalog qualification',
		compiler: compiler, sources: sources, artifacts: artifacts }) + '\n')!
	println('Verified fifteen host checks, eleven guest artifacts, two profile locks, five Mach-O successes, normal shutdown, x86-64 staging and ' + sources.len.str() + ' source pins')
}
