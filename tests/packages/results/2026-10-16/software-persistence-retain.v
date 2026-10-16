module main
import crypto.sha256
import json2
import os
struct Pin { path string bytes u64 sha256 string }
struct Check { name string code int seconds f64 }
struct Artifact { role string bytes u64 sha256 string }
struct Receipt { architecture string seconds f64 platform string boots int artifacts []Artifact }
struct Ledger { format int = 1 scope string checks []Check sources []Pin evidence []Pin }
fn pin(path string) !Pin {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	mut hash := sha256.new(); mut digest := []u8{len: sha256.size}
	defer { unsafe { hash.free(); free(hash); digest.free() } }
	hash.write(bytes)!; hash.checksum_into(mut digest)
	return Pin{ path: path, bytes: u64(bytes.len), sha256: digest.hex() }
}
fn main() {
	work := os.real_path(os.dir(@FILE)); attempt := os.args[1]
	prefix := 'tests/packages/results/2026-10-16/software-persistence-'
	checks := json2.decode[[]Check](os.read_file(work + '/host.json')!)!
	assert checks.len == 6 && checks.all(it.code == 0)
	mut summary := 'Six host controller checks and eight ordinary Software cold boots on two ext2 volumes passed. The same account/trust/package/home subtrees survive four orderly boots per architecture; tools still boot from initramfs.\n'
	for check in checks { summary += check.name + ' PASS ' + check.seconds.str() + 's\n' }
	os.cp(work + '/host.json', prefix + 'host.json')!
	for name in ['host.v', 'guest.v', 'retain.v', 'kernel.v']! { os.cp(work + '/' + name, prefix + name)! }
	mut evidence := []Pin{}; mut count := 0
	mut baseline := []Pin{}
	for architecture in ['aarch64', 'x86_64']! {
		short := if architecture == 'aarch64' { 'arm' } else { 'x86' }
		path := 'build/psp-4-' + short + '/native/serial-2.log'
		assert os.read_file(path)!.contains('unsafe unpublished package stage .stage-4')
		os.cp(path, prefix + architecture + '.baseline.serial.txt')!
		baseline << pin(path)!
		baseline << pin('build/package-socket-work/' + short + '/kernel/bin/vinix')!
	}
	measured := 'build/psp-debug2-arm/native/serial-2.log'
	assert os.read_file(measured)!.contains('stage admission: uid=0 parent=0/0/54 relative=0/5/146/0/16832 absolute=0/5/146/0/16832')
	os.cp(measured, prefix + 'device-diagnostic.txt')!
	baseline << pin(measured)!
	os.write_file(prefix + 'baseline.json', json2.encode(baseline) + '\n')!
	evidence << baseline
	for architecture in ['aarch64', 'x86_64']! {
		short := if architecture == 'aarch64' { 'arm' } else { 'x86' }
		base := 'build/psp-' + attempt + '-' + short; root := base + '/guest/root'
		receipt := json2.decode[Receipt](os.read_file(base + '/qualification.json')!)!
		assert receipt.architecture == architecture && receipt.platform == 'qemu-ext2-retained-subtrees' && receipt.boots == 4
		for artifact in receipt.artifacts {
			path := match artifact.role {
				'kernel' { base + '/kernel' }
				'guest-init' { base + '/guest/init' }
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
		for boot in 1 .. 5 {
			serial := base + '/native/' + if boot == 1 { 'serial.log' } else { 'serial-' + boot.str() + '.log' }
			text := os.read_file(serial)!
			assert text.contains('PACKAGE COLD BOOT ' + boot.str() + ' ') && text.contains('HWTEST PASS packages-software-persistence')
			assert !text.contains('HWTEST FAIL') && !text.contains('V panic:')
			for secret in ['alex has a password', 'sam has another', 'incorrect fixture password']! { assert !text.contains(secret) }
			os.cp(serial, prefix + architecture + '.boot-' + boot.str() + '.serial.txt')!
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
		for ending, source in {'json': base + '/qualification.json', 'qmp.txt': base + '/native/qmp.log', 'stage.txt': base + '/stage.log', 'txt': work + '/' + architecture + '-' + attempt + '.txt'} {
			os.cp(source, prefix + architecture + '.' + ending)!
		}
		for source in [base + '/guest/init.c', base + '/guest/program-2/image-repositories.c', base + '/software-build/software-image.c',
			base + '/software-build/build.log', base + '/publisher/image-config.json', base + '/package-stage']! { evidence << pin(source)! }
		isolated := work + '/kernel-' + short + '/kernel'
		assert pin(isolated + '/fs/ext2/ext2.v')!.sha256 == pin('kernel/fs/ext2/ext2.v')!.sha256
		for path in ['/fs/ext2/ext2.v', '/GNUmakefile', '/obj/blob.c']! { evidence << pin(isolated + path)! }
		os.cp(work + '/kernel-' + architecture + '.txt', prefix + architecture + '.kernel.txt')!
		summary += architecture + ' four cold boots PASS ' + receipt.seconds.str() + 's\n'
	}
	os.write_file(prefix + 'host.txt', summary)!
	mut paths := []string{}
	tracked := os.exec(['git', 'ls-files', 'kernel', 'tools/packages', 'tools/accounts', 'tests/accounts/guest', 'tests/hardware-platform/hwhost', 'desktop/packagecore', 'desktop/workflowcore'])
	assert tracked.exit_code == 0; paths << tracked.output.split_into_lines()
	paths << ['tests/accounts/guest/package_software_persistence.v', 'tests/packages/native-catalog-check.v',
		'tests/packages/software-persistence-check.md', 'tests/packages/software-image-check.md', 'tests/packages/software_image_fixture.v',
		'tests/packages/software_terminal_fixture.v', 'docs/application-distribution.md', 'roadmap.md']
	for name in os.ls('desktop')! { if name.starts_with('software_') && name.ends_with('.v') { paths << 'desktop/' + name } }
	paths << 'build/vmodules/ui2/v.mod'
	for name in os.ls('build/vmodules/ui2/ui')! { if name.ends_with('.v') && !name.ends_with('_test.v') { paths << 'build/vmodules/ui2/ui/' + name } }
	paths.sort(); mut sources := []Pin{}
	for path in paths {
		if sources.any(it.path == path) { continue }
		actual := pin(path)!
		if path.starts_with('kernel/') {
			for short in ['arm', 'x86']! { assert pin(work + '/kernel-' + short + '/' + path)!.sha256 == actual.sha256, path }
		}
		sources << actual
	}
	for name in ['host', 'guest', 'controller']! { evidence << pin(work + '/' + name)! }
	compiler := pin('build/package-release-work/v-toolchain/v')!
	assert compiler.sha256 == 'd88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af'; evidence << compiler
	for path in ['build/package-launch-transport-work/cross-cc', '/opt/homebrew/bin/aarch64-linux-musl-gcc', '/opt/homebrew/bin/x86_64-linux-musl-gcc', '/opt/homebrew/opt/e2fsprogs/sbin/mke2fs']! { evidence << pin(path)! }
	for name in os.ls(os.dir(prefix))! { if name.starts_with('software-persistence-') && !name.ends_with('toolchain.json') { evidence << pin(os.dir(prefix) + '/' + name)! } }
	os.write_file(prefix + 'toolchain.json', json2.encode(Ledger{ scope: 'V 0.5.2 826e96f; isolated kernels with ext2 populated-inode device identity fix; production V image staging; actual headless Software controller; two ext2 disks with four orderly boots each; no host consumer-state edits or filesystem repair; initramfs OS/tools, not installed OS boot',
		checks: checks, sources: sources, evidence: evidence }) + '\n')!
	println('Verified six controller checks, eight cold boots, ' + count.str() + ' receipt artifacts and ' + sources.len.str() + ' source pins')
}
