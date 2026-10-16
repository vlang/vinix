module main
import crypto.sha256
import json2
import os
struct Pin { path string bytes u64 sha256 string }
struct Check { name string code int seconds f64 }
struct Artifact { role string bytes u64 sha256 string }
struct Receipt { architecture string seconds f64 platform string boots int artifacts []Artifact }
struct Proof { format int image string files []Artifact }
struct Ledger { format int = 1 scope string checks []Check sources []Pin evidence []Pin }
fn pin(path string) !Pin {
	mut file := os.open(path)!; defer { file.close() }
	mut hash := sha256.new(); mut buffer := []u8{len: 1024 * 1024}; mut digest := []u8{len: sha256.size}
	defer { unsafe { hash.free(); free(hash); buffer.free(); digest.free() } }
	mut bytes := u64(0)
	for {
		count := file.read(mut buffer) or { if err is os.Eof { break }; return err }
		if count == 0 { break }; hash.write(unsafe { buffer[..count] })!; bytes += u64(count)
	}
	hash.checksum_into(mut digest)
	return Pin{ path: path, bytes: bytes, sha256: digest.hex() }
}
fn main() {
	work := os.real_path(os.dir(@FILE)); installed_attempt := os.args[1]; persistent_attempt := os.args[2]
	prefix := 'tests/packages/results/2026-10-16/software-installed-'
	checks := json2.decode[[]Check](os.read_file(work + '/host.json')!)!
	assert checks.len == 9 && checks.all(it.code == 0)
	mut summary := 'Nine native controller/hash checks, eight actual installed-root boots and eight ext2 subtree regression boots passed. The normal kernel installer formats each blank 4 GiB system disk as VJFS. Subsequent boots retain the complete root and maintain the native SDK catalog through ordinary Software.\n'
	for check in checks { summary += check.name + ' PASS ' + check.seconds.str() + 's\n' }
	os.cp(work + '/host.json', prefix + 'host.json')!
	for name in ['host.v', 'guest.v', 'retain.v', 'hash-probe.v', 'hash-check.v']! { os.cp(work + '/' + name, prefix + name)! }
	os.cp(work + '/hash-run.txt', prefix + 'hash.txt')!
	mut evidence := []Pin{}; mut count := 0
	for architecture in ['aarch64', 'x86_64']! {
		short := if architecture == 'aarch64' { 'arm' } else { 'x86' }
		for mode in ['installed', 'persistent']! {
			installed := mode == 'installed'
			attempt := if installed { installed_attempt } else { persistent_attempt }
			base := 'build/psi-' + mode + '-' + attempt + '-' + short; root := base + '/guest/root'
			receipt := json2.decode[Receipt](os.read_file(base + '/qualification.json')!)!
			assert receipt.architecture == architecture && receipt.boots == 4
			assert receipt.platform == if installed { 'qemu-vjfs-installed-root' } else { 'qemu-ext2-retained-subtrees' }
			prior := json2.decode[Receipt](os.read_file('tests/packages/results/2026-10-16/software-persistence-' + architecture + '.json')!)!
			assert receipt.artifacts.filter(it.role == 'kernel')[0].sha256 == prior.artifacts.filter(it.role == 'kernel')[0].sha256
			for artifact in receipt.artifacts {
				path := match artifact.role {
					'kernel' { base + '/kernel' }
					'guest-init' { base + '/guest/init' }
					'initial-blank-system-disk' { base + '/initial.raw' }
					'final-installed-system-disk' { base + '/native/system.vjfs' }
					'initial-ext2' { base + '/initial.ext2' }
					'final-ext2' { base + '/native/packages.ext2' }
					'input-build-record' { 'build/package-native-catalog-work/inputs/build.json' }
					'serial-log' { base + '/native/serial.log' }
					'qmp-log' { base + '/native/qmp.log' }
					else {
						if artifact.role.starts_with('serial-log-') { base + '/native/serial-' + artifact.role.all_after_last('-') + '.log' }
						else if artifact.role.starts_with('input/') { base + '/verified-inputs/usr/share/native-catalog/' + artifact.role[6..] }
						else if artifact.role.starts_with('image/') { root + '/' + artifact.role[6..] }
						else { root + '/' + artifact.role }
					}
				}
				actual := pin(path)!; assert actual.bytes == artifact.bytes && actual.sha256 == artifact.sha256, path
				evidence << actual; count++
			}
			suffix := architecture + if installed { '' } else { '.persistent' }
			for boot in 1 .. 5 {
				serial := base + '/native/' + if boot == 1 { 'serial.log' } else { 'serial-' + boot.str() + '.log' }
				text := os.read_file(serial)!
				assert text.contains(if installed { 'PACKAGE INSTALLED BOOT ' } else { 'PACKAGE COLD BOOT ' } + boot.str() + ' ')
				assert text.contains('HWTEST PASS packages-software-' + if installed { 'installed' } else { 'persistence' })
				assert !text.contains('HWTEST FAIL') && !text.contains('V panic:')
				if installed {
					assert text.contains('initramfs: Unpacking...') == (boot == 1)
					assert !text.contains('sysdisk: updating the system on')
					if architecture == 'aarch64' { assert text.contains(if boot == 1 { 'sysdisk: installed; later boots start from the disk' } else { 'sysdisk: running from the system on' }) }
				}
				for secret in ['alex has a password', 'sam has another', 'incorrect fixture password']! { assert !text.contains(secret) }
				os.cp(serial, prefix + suffix + '.boot-' + boot.str() + '.serial.txt')!
			}
			qmp := os.read_file(base + '/native/qmp.log')!
			assert qmp.split_into_lines().filter(it.contains('"event": "SHUTDOWN"') && it.contains('"guest": true')).len == 4
			for name in os.ls(base + '/software-source')! {
				expected := if name == 'main.v' { 'tests/packages/software_image_fixture.v' }
					else if name == 'terminal_fixture.v' { 'tests/packages/software_terminal_fixture.v' } else { 'desktop/' + name }
				assert pin(base + '/software-source/' + name)!.sha256 == pin(expected)!.sha256, expected
			}
			assert os.read_file(base + '/publisher/image-config.json')! == os.read_file(root + '/etc/vinix-packages/config.json')!
			stage := os.read_file(base + '/stage.log')!
			assert stage.contains('Published authenticated offline image repositories') && stage.contains('Initialized reviewed image package configuration')
			if installed {
				assert !os.exists(base + '/format.log')
				proof_path := root + '/usr/share/package-fixtures/installed-image.json'
				proof := json2.decode[Proof](os.read_file(proof_path)!)!
				assert proof.format == 1 && proof.image == 'vinix-packages-installed-sdk-1' && proof.files.len == 9
				for item in proof.files {
					actual := pin(if item.role == '/sbin/init' { base + '/guest/init' } else { root + item.role })!
					assert item.bytes == actual.bytes && item.sha256 == actual.sha256
				}
				os.cp(proof_path, prefix + architecture + '.image.json')!
			}
			for ending, source in {'json': base + '/qualification.json', 'qmp.txt': base + '/native/qmp.log', 'stage.txt': base + '/stage.log', 'txt': work + '/' + mode + '-' + architecture + '-' + attempt + '.txt'} {
				os.cp(source, prefix + suffix + '.' + ending)!
			}
			for source in [base + '/guest/init.c', base + '/guest/program-2/image-repositories.c', base + '/software-build/software-image.c',
				base + '/software-build/build.log', base + '/publisher/image-config.json', base + '/package-stage']! { evidence << pin(source)! }
			summary += architecture + ' ' + mode + ' four boots PASS ' + receipt.seconds.str() + 's\n'
			println('Verified ' + architecture + ' ' + mode + ' receipt, complete disk digests, four shutdowns and workflow markers')
		}
	}
	os.write_file(prefix + 'host.txt', summary)!
	mut paths := []string{}
	tracked := os.exec(['git', 'ls-files', 'tools/packages', 'tools/accounts', 'tests/accounts/guest', 'tests/hardware-platform/hwhost', 'desktop/packagecore', 'desktop/workflowcore'])
	assert tracked.exit_code == 0; paths << tracked.output.split_into_lines()
	paths << ['tests/accounts/guest/package_installed_image.v', 'tests/packages/native-catalog-check.v',
		'tests/packages/software-installed-check.md', 'tests/packages/software-persistence-check.md', 'tests/packages/software_image_fixture.v',
		'tests/packages/software_terminal_fixture.v', 'docs/application-distribution.md', 'roadmap.md']
	for name in os.ls('desktop')! { if name.starts_with('software_') && name.ends_with('.v') { paths << 'desktop/' + name } }
	paths << 'build/vmodules/ui2/v.mod'
	for name in os.ls('build/vmodules/ui2/ui')! { if name.ends_with('.v') && !name.ends_with('_test.v') { paths << 'build/vmodules/ui2/ui/' + name } }
	paths.sort(); mut sources := []Pin{}
	for path in paths { if !sources.any(it.path == path) { sources << pin(path)! } }
	for name in ['host', 'guest', 'controller', 'hash-check']! { evidence << pin(work + '/' + name)! }
	compiler := pin('build/package-release-work/v-toolchain/v')!
	assert compiler.sha256 == 'd88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af'; evidence << compiler
	for path in ['build/package-launch-transport-work/cross-cc', '/opt/homebrew/bin/aarch64-linux-musl-gcc', '/opt/homebrew/bin/x86_64-linux-musl-gcc',
		'tests/packages/results/2026-10-16/software-persistence-toolchain.json']! { evidence << pin(path)! }
	for name in os.ls(os.dir(prefix))! { if name.starts_with('software-installed-') && !name.ends_with('toolchain.json') { evidence << pin(os.dir(prefix) + '/' + name)! } }
	os.write_file(prefix + 'toolchain.json', json2.encode(Ledger{ scope: 'V 0.5.2 826e96f; stream SHA-256 with 1 MiB buffer; exact unchanged kernels from ext2 identity qualification; normal blank-disk VJFS installation; real headless Software controller; eight installed-root boots plus eight ext2 subtree regression boots; no host consumer-state edits, guest tool replacements or filesystem repair; kernel/firmware test boot media and broader catalog/graphical/physical-device work remain explicit',
		checks: checks, sources: sources, evidence: evidence }) + '\n')!
	println('Verified nine controller/hash checks, sixteen boots, ' + count.str() + ' receipt artifacts and ' + sources.len.str() + ' source pins')
}
