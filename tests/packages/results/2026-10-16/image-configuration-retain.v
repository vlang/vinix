module main
import crypto.sha256
import json2
import os
struct Pin { path string bytes u64 sha256 string }
struct Result { name string code int seconds f64 }
struct Artifact { role string bytes u64 sha256 string }
struct Receipt { architecture string artifacts []Artifact }
struct Ledger { format int = 1 compiler string checks []Result sources []Pin evidence []Pin }
fn pin(path string) !Pin {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	mut hash := sha256.new(); mut digest := []u8{len: sha256.size}
	defer { unsafe { hash.free(); free(hash); digest.free() } }
	hash.write(bytes)!; hash.checksum_into(mut digest)
	return Pin{ path: path, bytes: u64(bytes.len), sha256: digest.hex() }
}
fn check() ! {
	work := os.real_path(os.dir(@FILE)); prefix := 'tests/packages/results/2026-10-16/image-configuration-'
	mut checks := []Result{}
	mut summary := '33 focused native compile/run checks passed. Production-staged native images and the existing explicit-enrollment catalog scenario pass on both architectures, with clean QMP shutdown. Staged configuration stays byte-identical through real native install, updates, rollback and offline cache reinstall.\n'
	for phase in ['core', 'image-final', 'asan', 'cli', 'stage', 'cache']! {
		for row in json2.decode[[]Result](os.read_file(work + '/results-' + phase + '.json')!)! {
			assert row.code == 0; checks << row
			summary += row.name + ' PASS ' + row.seconds.str() + 's\n'
		}
	}
	assert checks.len == 33
	assert os.read_file(work + '/image-final-run.txt')!.contains('PACKAGE IMAGE CONFIG signed catalog install remove rollback both architectures PASS')
	asan := os.read_file(work + '/asan-run.txt')!
	assert asan.contains('PACKAGE IMAGE CONFIG signed catalog install remove rollback both architectures PASS') && !asan.contains('ERROR:') && !asan.contains('runtime error:')
	os.write_file(prefix + 'host.json', json2.encode(checks) + '\n')!
	os.write_file(prefix + 'host.txt', summary)!
	for name, source in {'core.txt': 'image-final-run.txt', 'asan.txt': 'asan-run.txt', 'cli.txt': 'distribution-cli-run.txt',
		'host.v': 'host.v', 'guest.v': 'guest.v', 'retain.v': 'retain.v'} { os.cp(work + '/' + source, prefix + name)! }
	os.write_file(prefix + 'preflight.txt', 'Explicit --config input:\n' + os.read_file(work + '/stage-option-preflight.txt')!
		+ '\nVINIX_PACKAGE_IMAGE_CONFIG input:\n' + os.read_file(work + '/stage-environment-preflight.txt')!)!
	mut evidence := []Pin{}
	mut count := 0
	for architecture in ['aarch64', 'x86_64']! {
		short := if architecture == 'aarch64' { 'arm' } else { 'x86' }
		for phase in ['image', 'legacy']! {
			base := 'build/pic-' + phase + if phase == 'image' { '-2-' } else { '-' } + short
			root := base + '/guest/root'
			inputs := if phase == 'image' { base + '/verified-inputs' } else { root }
			receipt := json2.decode[Receipt](os.read_file(base + '/qualification.json')!)!
			assert receipt.architecture == architecture && receipt.artifacts.len >= 25
			for artifact in receipt.artifacts {
				path := match artifact.role {
					'kernel' { base + '/kernel' }
					'guest-init' { base + '/guest/init' }
					'input-build-record' { 'build/package-native-catalog-work/inputs/build.json' }
					'serial-log' { base + '/native/serial.log' }
					'qmp-log' { base + '/native/qmp.log' }
					else {
						if artifact.role.starts_with('input/') { inputs + '/usr/share/native-catalog/' + artifact.role[6..] }
						else if artifact.role.starts_with('image/') { root + '/' + artifact.role[6..] }
						else { root + '/' + artifact.role }
					}
				}
				actual := pin(path)!; assert actual.bytes == artifact.bytes && actual.sha256 == artifact.sha256, path
				evidence << actual; count++
			}
			serial := os.read_file(base + '/native/serial.log')!
			name := if phase == 'image' { 'packages-native-image' } else { 'packages-native-catalog' }
			assert serial.contains('HWTEST PASS ' + name) && !serial.contains('HWTEST FAIL') && !serial.contains('V panic:')
			assert serial.contains('PACKAGE NATIVE CATALOG upgrade rollback uninstall-registration offline-cache-reinstall retained-private-data PASS')
			qmp := os.read_file(base + '/native/qmp.log')!
			assert qmp.contains('SHUTDOWN') && qmp.contains('"guest": true')
			suffix := architecture + if phase == 'legacy' { '.legacy' } else { '' }
			for ending, path in {'json': base + '/qualification.json', 'serial.txt': base + '/native/serial.log',
				'qmp.txt': base + '/native/qmp.log', 'txt': work + '/' + phase + '-' + architecture + '.txt'} {
				os.cp(path, prefix + suffix + '.' + ending)!
			}
			evidence << pin(base + '/guest/init.c')!
			if phase == 'image' {
				assert serial.contains('PACKAGE IMAGE CONFIG booted with staged trust policy and launch account before first refresh PASS')
				assert serial.contains('PACKAGE IMAGE CONFIG unchanged staged configuration real native apps upgrade rollback offline reinstall PASS')
				assert os.read_file(base + '/publisher/image-config.json')! == os.read_file(root + '/etc/vinix-packages/config.json')!
				os.cp(base + '/stage.log', prefix + architecture + '.stage.txt')!
				evidence << pin(base + '/publisher/image-config.json')!
				evidence << pin(root + '/usr/share/package-fixtures/image-configuration')!
				evidence << pin(base + '/guest/program-1/image-configuration.c')!
				evidence << pin(base + '/package-stage')!
			}
		}
	}
	mut paths := []string{}
	tracked := os.exec(['git', 'ls-files', 'tools/packages', 'tools/accounts', 'tests/accounts/guest', 'tests/hardware-platform/hwhost', 'build-support/cachekey'])
	assert tracked.exit_code == 0; paths << tracked.output.split_into_lines()
	paths << ['tools/packages/pkgcore/image_configuration.v', 'tools/packages/pkgcore/image_configuration_test.v', 'tests/packages/native-catalog-check.v',
		'tests/packages/image-configuration-check.md', 'tests/packages/distribution-check.v', 'docs/application-distribution.md', 'roadmap.md']
	paths.sort(); mut sources := []Pin{}
	for path in paths { if !sources.any(it.path == path) { sources << pin(path)! } }
	for name in ['host', 'guest', 'controller', 'image-final', 'asan', 'cache-key', 'vinix-package', 'package-stage', 'distribution-cli', 'distribution-check']! {
		evidence << pin(work + '/' + name)!
	}
	compiler := pin('build/package-release-work/v-toolchain/v')!
	assert compiler.sha256 == 'd88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af'
	evidence << compiler
	for path in ['build/package-launch-transport-work/cross-cc', '/opt/homebrew/bin/aarch64-linux-musl-gcc', '/opt/homebrew/bin/x86_64-linux-musl-gcc']! { evidence << pin(path)! }
	for name in os.ls(os.dir(prefix))! {
		if name.starts_with('image-configuration-') && !name.ends_with('toolchain.json') { evidence << pin(os.dir(prefix) + '/' + name)! }
	}
	os.write_file(prefix + 'toolchain.json', json2.encode(Ledger{ compiler: 'V 0.5.2 826e96f; native manualfree fixtures and separate ASan/UBSan; desktop cache assertions; production V staging and static musl target tools; unchanged isolated socket-qualification kernels',
		checks: checks, sources: sources, evidence: evidence }) + '\n')!
	println('Verified 33 native checks, four guests, ' + count.str() + ' receipted artifacts and ' + sources.len.str() + ' source pins')
}
fn main() { check() or { eprintln(err); exit(1) } }
