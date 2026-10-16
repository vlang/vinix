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
	work := os.real_path(os.dir(@FILE)); prefix := 'tests/packages/results/2026-10-16/software-image-'
	checks := json2.decode[[]Result](os.read_file(work + '/host.json')!)!
	assert checks.len == 7 && checks.all(it.code == 0)
	mut summary := 'Seven focused host compile/run checks and both fresh Software image guests passed. Actual Software controller and headless UI trees use real staged package, administrator and isolated-launch services. Physical presentation, graphical login and persistent storage are outside this check.\n'
	for row in checks { summary += row.name + ' PASS ' + row.seconds.str() + 's\n' }
	os.cp(work + '/host.json', prefix + 'host.json')!
	for name in ['host.v', 'guest.v', 'retain.v']! { os.cp(work + '/' + name, prefix + name)! }
	mut evidence := []Pin{}
	mut count := 0
	for architecture in ['aarch64', 'x86_64']! {
		short := if architecture == 'aarch64' { 'arm' } else { 'x86' }
		base := 'build/psi-3-' + short; root := base + '/guest/root'
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
			actual := pin(path)!
			assert actual.bytes == artifact.bytes && actual.sha256 == artifact.sha256, path
			evidence << actual; count++
		}
		serial := os.read_file(base + '/native/serial.log')!
		for marker in ['HWTEST PASS packages-software-image',
			'SOFTWARE IMAGE ordinary-admin real-refresh cancel bad-password review install progress native-window-1-2 document-grant PASS',
			'SOFTWARE IMAGE standard-account denied-administration own-isolated-launch private-data PASS',
			'SOFTWARE IMAGE reviewed-update rollback retained-memo PASS',
			'SOFTWARE IMAGE updates rollback uninstall registration cached-reinstall retained-memo PASS',
			'SOFTWARE IMAGE unchanged-staged-trust root-owned-state separate-user-data clean-runtime PASS']! { assert serial.contains(marker), marker }
		for secret in ['alex has a password', 'sam has another', 'incorrect fixture password']! { assert !serial.contains(secret) }
		assert !serial.contains('HWTEST FAIL') && !serial.contains('V panic:')
		qmp := os.read_file(base + '/native/qmp.log')!
		assert qmp.contains('SHUTDOWN') && qmp.contains('"guest": true')
		assert os.read_file(base + '/publisher/image-config.json')! == os.read_file(root + '/etc/vinix-packages/config.json')!
		for name, input in {'json': base + '/qualification.json', 'serial.txt': base + '/native/serial.log',
			'qmp.txt': base + '/native/qmp.log', 'stage.txt': base + '/stage.log', 'txt': work + '/' + architecture + '-3.txt'} {
			os.cp(input, prefix + architecture + '.' + name)!
		}
		for path in [base + '/guest/init.c', base + '/guest/program-1/vinix-authd.c', base + '/software-build/software-image.c',
			base + '/software-build/build.log', base + '/publisher/image-config.json', base + '/package-stage']! { evidence << pin(path)! }
		// Check the copied controller input against the exact repository sources.
		for name in os.ls(base + '/software-source')! {
			expected := if name == 'main.v' { 'tests/packages/software_image_fixture.v' }
				else if name == 'terminal_fixture.v' { 'tests/packages/software_terminal_fixture.v' } else { 'desktop/' + name }
			assert pin(base + '/software-source/' + name)!.sha256 == pin(expected)!.sha256, expected
		}
		summary += architecture + ' packages-software-image PASS ' + receipt.seconds.str() + 's\n'
	}
	os.write_file(prefix + 'host.txt', summary)!
	mut paths := []string{}
	tracked := os.exec(['git', 'ls-files', 'tools/packages', 'tools/accounts', 'tests/accounts/guest', 'tests/hardware-platform/hwhost', 'desktop/packagecore', 'desktop/workflowcore'])
	assert tracked.exit_code == 0; paths << tracked.output.split_into_lines()
	paths << ['tests/accounts/guest/package_software_image.v', 'tests/packages/software_image_fixture.v', 'tests/packages/software_terminal_fixture.v',
		'tests/packages/native-catalog-check.v', 'tests/packages/software-image-check.md', 'docs/application-distribution.md', 'roadmap.md']
	for name in os.ls('desktop')! { if name.starts_with('software_') && name.ends_with('.v') { paths << 'desktop/' + name } }
	paths << 'build/vmodules/ui2/v.mod'
	for name in os.ls('build/vmodules/ui2/ui')! { if name.ends_with('.v') && !name.ends_with('_test.v') { paths << 'build/vmodules/ui2/ui/' + name } }
	paths.sort(); mut sources := []Pin{}
	for path in paths { if !sources.any(it.path == path) { sources << pin(path)! } }
	for path in [work + '/host', work + '/guest', work + '/boot', work + '/suite', 'build/package-image-configuration-work/software-controller',
		'build/package-release-work/v-toolchain/v', 'build/package-launch-transport-work/cross-cc',
		'/opt/homebrew/bin/aarch64-linux-musl-gcc', '/opt/homebrew/bin/x86_64-linux-musl-gcc']! { evidence << pin(path)! }
	for name in os.ls(os.dir(prefix))! {
		if name.starts_with('software-image-') && !name.ends_with('toolchain.json') { evidence << pin(os.dir(prefix) + '/' + name)! }
	}
	os.write_file(prefix + 'toolchain.json', json2.encode(Ledger{ scope: 'V 0.5.2 826e96f; both fresh production-staged initramfs images; actual Software controller and headless ui2 trees; real ordinary-account services; no graphical login or physical presentation claim',
		checks: checks, sources: sources, evidence: evidence }) + '\n')!
	println('Verified seven host checks, both guests, ' + count.str() + ' receipt artifacts and ' + sources.len.str() + ' source pins')
}
