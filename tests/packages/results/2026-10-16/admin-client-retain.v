module main
import crypto.sha256
import json2
import os
struct Pin { path string bytes u64 sha256 string }
struct Result { name string code int seconds f64 }
struct Artifact { role string bytes u64 sha256 string }
struct Receipt { architecture string artifacts []Artifact }
struct Ledger { format int = 1 baseline string compiler string checks []Result sources []Pin evidence []Pin }
fn pin(path string) !Pin {
	bytes := os.read_bytes(path)!; defer { unsafe { bytes.free() } }
	mut hash := sha256.new(); mut digest := []u8{len: sha256.size}
	defer { unsafe { hash.free(); free(hash); digest.free() } }
	hash.write(bytes)!; hash.checksum_into(mut digest)
	return Pin{ path: path, bytes: u64(bytes.len), sha256: digest.hex() }
}
fn definition(source string, name string) string {
	mut at := source.index(name + '(') or { panic(name) }
	for {
		line := source.index_after('\n', at) or { panic(name) }
		if source[at..line].ends_with(' {') {
			end := source.index_after('\n}', line) or { panic(name) }
			return source[at..end + 2]
		}
		at = source.index_after(name + '(', line) or { panic(name) }
	}
	return ''
}
fn check() ! {
	work := os.real_path(os.dir(@FILE)); prefix := 'tests/packages/results/2026-10-16/admin-client-'
	mut checks := []Result{}
	mut summary := '34 focused native compile/run checks passed. Final native fixture: 29 zero-retention windows. Target fixtures: 72 zero-retention windows per architecture, including 14 complete ordinary clients against a root service. Original diagnostic cases reproduce three SIGSEGV outcomes per architecture; final errors retain their messages safely.\n'
	for phase in ['core', 'cli', 'baseline', 'memory', 'asan']! {
		for row in json2.decode[[]Result](os.read_file(work + '/results-' + phase + '.json')!)! {
			assert row.code == 0
			checks << row
			summary += row.name + ' PASS ' + row.seconds.str() + 's\n'
		}
	}
	assert checks.len == 34
	original := os.exec(['git', 'show', '25a97b08a:tools/packages/main.v'])
	assert original.exit_code == 0 && original.output == os.read_file(work + '/original-main.v')!
	baseline := os.read_file(work + '/baseline-run.txt')!
	assert baseline.count('retained 360 bytes') == 8 && baseline.count('retained 625 bytes') == 1
	assert baseline.count('retained 0 bytes') == 12
	memory := os.read_file(work + '/memory-run.txt')!
	assert memory.count('retained 0 bytes') == 29 && !memory.contains(': fn ')
	asan := os.read_file(work + '/asan-run.txt')!
	assert !asan.contains('ERROR:') && !asan.contains('runtime error:') && !asan.contains(': fn ')
	os.write_file(prefix + 'host.json', json2.encode(checks) + '\n')!
	os.write_file(prefix + 'host.txt', summary)!
	for name, path in {'memory.txt': 'memory-run.txt', 'asan.txt': 'asan-run.txt', 'baseline.txt': 'baseline-run.txt',
		'cli.txt': 'distribution-cli-run.txt', 'checks.v': 'check.v', 'core-checks.v': 'core.v', 'guest-checks.v': 'guest.v',
		'extraction.v': 'prepare.v', 'retain.v': 'retain.v'} { os.cp(work + '/' + path, prefix + name)! }
	mut evidence := []Pin{}
	for path in ['baseline-fixture', 'memory-fixture', 'asan-fixture', 'vinix-package', 'distribution-cli', 'distribution-check',
		'controller', 'admin-controller', 'original-main.v', 'baseline/pkgadmin/client.c.v', 'baseline/pkgadmin/client_ownership_test.v']! {
		evidence << pin(work + '/' + path)!
	}
	mut review := 'Baseline is mechanically extracted from 25a97b08a main.v. Its diagnostic string is freed before the returned MessageError is read; three real target refusal paths record SIGSEGV. Its authentication input arrays and heap-promoted wrappers account for retained bytes measured separately. Final passes reply validation by value, transferring the diagnostic owner to the error; client frames stay on stack and close owned fields. Password failure storage and scratch use non-elidable erasure; accepted password storage transfers to an owned frame.\n'
	for arch in ['aarch64', 'x86_64']! {
		short := if arch == 'aarch64' { 'arm' } else { 'x86' }
		for phase in ['baseline', 'client']! {
			base := 'build/admc-' + phase + '-3-' + short
			suffix := if phase == 'baseline' { arch + '.baseline' } else { arch }
			receipt := json2.decode[Receipt](os.read_file(base + '/qualification.json')!)!
			assert receipt.architecture == arch && receipt.artifacts.len == 10
			for artifact in receipt.artifacts {
				path := match artifact.role {
					'kernel' { 'build/package-socket-work/' + short + '/kernel/bin/vinix' }
					'guest-init' { base + '/guest/init' }
					'serial-log' { base + '/packages-admin-client/serial.log' }
					'vinix-authd', 'vinix-session' { base + '/guest/root/usr/sbin/' + artifact.role }
					'vinix-package' { base + '/guest/root/usr/bin/vinix-package' }
					else { base + '/guest/root/usr/share/package-fixtures/' + artifact.role }
				}
				actual := pin(path)!; assert actual.bytes == artifact.bytes && actual.sha256 == artifact.sha256, path
				evidence << actual
			}
			serial := os.read_file(base + '/packages-admin-client/serial.log')!
			assert serial.contains('HWTEST PASS packages-admin-client') && !serial.contains('HWTEST FAIL')
			assert serial.contains('ADMIN CLIENT ACTOR root PASS') && serial.contains('ADMIN CLIENT ACTOR UID 1000 PASS')
			if phase == 'baseline' {
				assert serial.count('baseline approval diagnostic use-after-free SIGSEGV confirmed') == 3
				assert serial.contains('status 37 retained 1545 bytes') && serial.contains('approval interrupted retained 1085 bytes')
				assert serial.count('retained 300 bytes') == 16
			} else { assert serial.count('retained 0 bytes') == 72 }
			qmp := os.read_file(base + '/packages-admin-client/qmp.log')!
			assert qmp.contains('SHUTDOWN') && qmp.contains('"guest": true')
			for ending, path in {'json': base + '/qualification.json', 'serial.txt': base + '/packages-admin-client/serial.log',
				'qmp.txt': base + '/packages-admin-client/qmp.log', 'txt': work + '/' + phase + '-' + arch + '.txt'} {
				os.cp(path, prefix + suffix + '.' + ending)!
			}
			generated_path := base + '/guest/program-0/admin-client.c'
			generated := os.read_file(generated_path)!; evidence << pin(generated_path)!
			client := definition(generated, 'pkgadmin__run_with_socket')
			password := definition(generated, 'pkgadmin__read_password')
			if phase == 'baseline' {
				assert client.contains('string__free(&diagnostic)') && client.contains('memdup(&__esc_')
			} else {
				assert !client.contains('memdup(&__esc_') && client.contains('pkgadmin__check_approval(reply, nonce)')
				assert client.contains('authproto__Frame__close(&run_request)') && client.contains('authproto__Frame__close(&describe_request)')
				assert client.contains('pkgadmin__Listener__accept_root(&listener)')
				approval := definition(generated, 'pkgadmin__check_approval')
				assert !approval.contains('string__free(&diagnostic)') && !approval.contains('memdup(&__esc_')
				assert password.contains('pkgadmin__erase_password(password.data, password.len)') && password.contains('pkgadmin__erase_password((void*)(&byte), 1)')
				erase := definition(generated, 'pkgadmin__erase_password'); assert erase.contains('explicit_bzero')
				review += '\n' + arch + ' final approval and credential erasure:\n' + approval + '\n' + erase + '\n'
			}
			review += '\n' + arch + ' ' + phase + ' client:\n' + client + '\nPassword reader:\n' + password + '\n'
			for i, name in ['protocol', 'streams', 'admin-socket', 'vinix-authd', 'vinix-session', 'vinix-package']! {
				evidence << pin(base + '/guest/program-' + (i + 1).str() + '/' + name + '.c')!
			}
			evidence << pin(base + '/guest/init.c')!
		}
		admin := 'build/admc-admin-3-' + short
		receipt := json2.decode[Receipt](os.read_file(admin + '/qualification.json')!)!
		assert receipt.architecture == arch && receipt.artifacts.len == 8
		for artifact in receipt.artifacts {
			path := match artifact.role {
				'kernel' { admin + '/kernel' }
				'guest-init' { admin + '/guest/init' }
				'package-service' { admin + '/guest/root/usr/bin/vinix-package' }
				'authentication-service' { admin + '/guest/root/usr/sbin/vinix-authd' }
				'account-manager' { admin + '/guest/root/usr/sbin/vinix-account' }
				'session-runner' { admin + '/guest/root/usr/sbin/vinix-session' }
				'administration-action' { admin + '/guest/root/usr/share/vinix/actions/packages-change' }
				'serial-log' { admin + '/packages-admin/serial.log' }
				else { return error('unexpected administrator artifact: ' + artifact.role) }
			}
			actual := pin(path)!; assert actual.bytes == artifact.bytes && actual.sha256 == artifact.sha256, path
			evidence << actual
		}
		log := os.read_file(admin + '/packages-admin/serial.log')!
		assert log.contains('HWTEST PASS packages-admin') && !log.contains('HWTEST FAIL')
		control := os.read_file(admin + '/packages-admin/qmp.log')!
		assert control.contains('SHUTDOWN') && control.contains('"guest": true')
		for ending, path in {'json': admin + '/qualification.json', 'serial.txt': admin + '/packages-admin/serial.log',
			'qmp.txt': admin + '/packages-admin/qmp.log', 'txt': work + '/admin-' + arch + '.txt'} {
			os.cp(path, prefix + arch + '.admin.' + ending)!
		}
	}
	os.write_file(prefix + 'generated-c.txt', review)!
	mut paths := []string{}
	tracked := os.exec(['git', 'ls-files', 'tools/accounts', 'tools/packages', 'tests/hardware-platform/hwhost', 'tests/accounts/guest', 'tests/accounts/run.v'])
	assert tracked.exit_code == 0; paths << tracked.output.split_into_lines()
	paths << ['tests/packages/admin-client-runtime-check.v', 'tests/packages/admin-client-guest/main.v', 'tests/packages/admin-client-check.md',
		'tests/packages/distribution-check.v', 'docs/application-distribution.md', 'desktop/tools/tests/heap_tracker.h', 'tests/packages/admin-check.v']
	paths.sort(); mut sources := []Pin{}
	for path in paths { if !sources.any(it.path == path) { sources << pin(path)! } }
	compiler := pin('build/package-release-work/v-toolchain/v')!
	assert compiler.sha256 == 'd88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af'
	evidence << compiler; evidence << pin('build/package-launch-transport-work/cross-cc')!
	for name in os.ls(os.dir(prefix))! {
		if name.starts_with('admin-client-') && !name.ends_with('toolchain.json') { evidence << pin(os.dir(prefix) + '/' + name)! }
	}
	os.write_file(prefix + 'toolchain.json', json2.encode(Ledger{ baseline: '25a97b08a', checks: checks, sources: sources, evidence: evidence,
		compiler: 'V 0.5.2 826e96f; -nocache -no-skip-unused -gc none -manualfree; separate track_heap and ASan/UBSan; static musl QEMU TCG guests; unchanged isolated socket-qualification kernels' }) + '\n')!
	println('Verified 34 native checks, 29 local windows, 72 target windows per architecture, six guests, 56 receipted artifacts and ' + sources.len.str() + ' source pins')
}
fn main() { check() or { eprintln(err); exit(1) } }
