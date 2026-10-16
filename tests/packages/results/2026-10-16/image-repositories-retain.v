module main
import crypto.sha256
import json2
import os
struct Pin { path string bytes u64 sha256 string }
struct Result { name string code int seconds f64 }
struct Artifact { role string bytes u64 sha256 string }
struct Receipt { architecture string seconds f64 artifacts []Artifact }
struct Ledger { format int = 1 scope string checks []Result sources []Pin evidence []Pin }
fn pin(path string) !Pin {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	mut hash := sha256.new(); mut digest := []u8{len: sha256.size}
	defer { unsafe { hash.free(); free(hash); digest.free() } }
	hash.write(bytes)!; hash.checksum_into(mut digest)
	return Pin{ path: path, bytes: u64(bytes.len), sha256: digest.hex() }
}
fn main() {
	work := os.real_path(os.dir(@FILE)); prefix := 'tests/packages/results/2026-10-16/image-repositories-'
	mut checks := []Result{}
	mut summary := '32 focused native compile/run checks and four production-staged image guests passed. Complete signed offline bundles are captured and published by the production V staging tool without consumer-state initialization or trust edits.\n'
	for phase in ['core', 'asan', 'cache', 'cli', 'controller', 'stage']! {
		for row in json2.decode[[]Result](os.read_file(work + '/results-' + phase + '.json')!)! {
			assert row.code == 0; checks << row
			summary += row.name + ' PASS ' + row.seconds.str() + 's\n'
		}
	}
	assert checks.len == 32
	asan := os.read_file(work + '/asan-run.txt')!
	assert asan.contains('PACKAGE IMAGE BUNDLE captured signed closure atomic publication offline dependency install both architectures PASS')
	assert !asan.contains('ERROR:') && !asan.contains('runtime error:')
	os.write_file(prefix + 'host.json', json2.encode(checks) + '\n')!
	for name, source in {'core.txt': 'image_repositories-run.txt', 'asan.txt': 'asan-run.txt', 'cli.txt': 'distribution-cli-run.txt',
		'host.v': 'host.v', 'guest.v': 'guest.v', 'retain.v': 'retain.v'} { os.cp(work + '/' + source, prefix + name)! }
	mut preflight := ''
	for name in ['option-refusal', 'environment-refusal', 'option-precedence', 'empty-option']! { preflight += name + ':\n' + os.read_file(work + '/' + name + '.txt')! + '\n' }
	os.write_file(prefix + 'preflight.txt', preflight)!
	mut evidence := []Pin{}; mut count := 0
	for architecture in ['aarch64', 'x86_64']! {
		short := if architecture == 'aarch64' { 'arm' } else { 'x86' }
		for mode in ['image', 'software']! {
			base := 'build/pir-' + mode + '-2-' + short; root := base + '/guest/root'
			receipt := json2.decode[Receipt](os.read_file(base + '/qualification.json')!)!
			assert receipt.architecture == architecture && receipt.artifacts.len > 40
			for artifact in receipt.artifacts {
				path := match artifact.role {
					'kernel' { base + '/kernel' }
					'guest-init' { base + '/guest/init' }
					'input-build-record' { 'build/package-native-catalog-work/inputs/build.json' }
					'serial-log' { base + '/native/serial.log' }
					'qmp-log' { base + '/native/qmp.log' }
					else {
						if artifact.role.starts_with('input/') { base + '/verified-inputs/usr/share/native-catalog/' + artifact.role[6..] }
						else if artifact.role.starts_with('image/') { root + '/' + artifact.role[6..] }
						else { root + '/' + artifact.role }
					}
				}
				actual := pin(path)!; assert actual.bytes == artifact.bytes && actual.sha256 == artifact.sha256, path
				evidence << actual; count++
			}
			serial := os.read_file(base + '/native/serial.log')!
			scenario := if mode == 'image' { 'packages-native-image' } else { 'packages-software-image' }
			assert serial.contains('HWTEST PASS ' + scenario) && serial.contains('PACKAGE IMAGE BUNDLE production-staged signed repository before first refresh PASS')
			assert !serial.contains('HWTEST FAIL') && !serial.contains('V panic:')
			if mode == 'software' {
				for marker in ['SOFTWARE IMAGE ordinary-admin real-refresh cancel bad-password review install progress native-window-1-2 document-grant PASS',
					'SOFTWARE IMAGE standard-account denied-administration own-isolated-launch private-data PASS',
					'SOFTWARE IMAGE reviewed-update rollback retained-memo PASS',
					'SOFTWARE IMAGE updates rollback uninstall registration cached-reinstall retained-memo PASS',
					'SOFTWARE IMAGE unchanged-staged-trust root-owned-state separate-user-data clean-runtime PASS']! { assert serial.contains(marker) }
				for secret in ['alex has a password', 'sam has another', 'incorrect fixture password']! { assert !serial.contains(secret) }
				for name in os.ls(base + '/software-source')! {
					expected := if name == 'main.v' { 'tests/packages/software_image_fixture.v' }
						else if name == 'terminal_fixture.v' { 'tests/packages/software_terminal_fixture.v' } else { 'desktop/' + name }
					assert pin(base + '/software-source/' + name)!.sha256 == pin(expected)!.sha256, expected
				}
				evidence << pin(base + '/software-build/software-image.c')!
				evidence << pin(base + '/software-build/build.log')!
			} else {
				assert serial.contains('PACKAGE NATIVE CATALOG upgrade rollback uninstall-registration offline-cache-reinstall retained-private-data PASS')
				assert serial.contains('PACKAGE IMAGE CONFIG unchanged staged configuration real native apps upgrade rollback offline reinstall PASS')
			}
			qmp := os.read_file(base + '/native/qmp.log')!
			assert qmp.contains('SHUTDOWN') && qmp.contains('"guest": true')
			assert os.read_file(base + '/publisher/image-config.json')! == os.read_file(root + '/etc/vinix-packages/config.json')!
			stage := os.read_file(base + '/stage.log')!
			assert stage.contains('Published authenticated offline image repositories') && stage.contains('Initialized reviewed image package configuration')
			suffix := architecture + if mode == 'software' { '.software' } else { '' }
			for ending, input in {'json': base + '/qualification.json', 'serial.txt': base + '/native/serial.log',
				'qmp.txt': base + '/native/qmp.log', 'stage.txt': base + '/stage.log', 'txt': work + '/' + mode + '-' + architecture + '-2.txt'} {
				os.cp(input, prefix + suffix + '.' + ending)!
			}
			for path in [base + '/guest/init.c', base + '/guest/program-2/image-repositories.c', base + '/publisher/image-config.json', base + '/package-stage']! { evidence << pin(path)! }
			summary += architecture + ' ' + scenario + ' PASS ' + receipt.seconds.str() + 's\n'
		}
	}
	os.write_file(prefix + 'host.txt', summary)!
	mut paths := []string{}
	tracked := os.exec(['git', 'ls-files', 'tools/packages', 'tools/accounts', 'tests/accounts/guest', 'tests/hardware-platform/hwhost', 'desktop/packagecore', 'desktop/workflowcore', 'build-support/cachekey'])
	assert tracked.exit_code == 0; paths << tracked.output.split_into_lines()
	paths << ['tools/packages/pkgcore/image_repositories.v', 'tools/packages/pkgcore/image_repositories_test.v',
		'tests/packages/native-catalog-check.v', 'tests/packages/image-repositories-check.md', 'tests/packages/image-configuration-check.md',
		'tests/packages/software-image-check.md', 'tests/packages/software_image_fixture.v', 'tests/packages/software_terminal_fixture.v', 'docs/application-distribution.md', 'roadmap.md']
	for name in os.ls('desktop')! { if name.starts_with('software_') && name.ends_with('.v') { paths << 'desktop/' + name } }
	paths << 'build/vmodules/ui2/v.mod'
	for name in os.ls('build/vmodules/ui2/ui')! { if name.ends_with('.v') && !name.ends_with('_test.v') { paths << 'build/vmodules/ui2/ui/' + name } }
	paths.sort(); mut sources := []Pin{}
	for path in paths { if !sources.any(it.path == path) { sources << pin(path)! } }
	for name in ['host', 'guest', 'controller', 'image_repositories', 'asan', 'cache', 'vinix-package', 'distribution-cli', 'package-stage']! { evidence << pin(work + '/' + name)! }
	compiler := pin('build/package-release-work/v-toolchain/v')!
	assert compiler.sha256 == 'd88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af'
	evidence << compiler
	for path in ['build/package-launch-transport-work/cross-cc', '/opt/homebrew/bin/aarch64-linux-musl-gcc', '/opt/homebrew/bin/x86_64-linux-musl-gcc']! { evidence << pin(path)! }
	for name in os.ls(os.dir(prefix))! { if name.starts_with('image-repositories-') && !name.ends_with('toolchain.json') { evidence << pin(os.dir(prefix) + '/' + name)! } }
	os.write_file(prefix + 'toolchain.json', json2.encode(Ledger{ scope: 'V 0.5.2 826e96f; bounded owned image bundles; manualfree host fixtures plus ASan/UBSan; production V staging; both CLI and headless Software image workflows on both architectures; unchanged isolated socket-qualification kernels',
		checks: checks, sources: sources, evidence: evidence }) + '\n')!
	println('Verified 32 native checks, four guests, ' + count.str() + ' receipt artifacts and ' + sources.len.str() + ' source pins')
}
