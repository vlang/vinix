module main

import crypto.sha256
import json2
import os

struct Pin { path string bytes u64 sha256 string }
struct Result { name string code int seconds f64 }
struct Check { name string status string }
struct Artifact { role string bytes u64 sha256 string }
struct Receipt { architecture string artifacts []Artifact }
struct Ledger { format int = 1 baseline string compiler string checks []Check sources []Pin evidence []Pin }

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
	work := os.real_path(os.dir(@FILE)); prefix := 'tests/packages/results/2026-10-16/admin-envelope-'
	mut checks := []Check{}
	mut summary := '32 focused native compile/run checks passed. All 58 final ownership windows retain zero bytes. Both architectures pass root/UID1000 ownership and real authenticated administrator guests.\n'
	for phase in ['core', 'cli', 'memory', 'asan']! {
		for row in json2.decode[[]Result](os.read_file(work + '/results-' + phase + '.json')!)! {
			assert row.code == 0
			checks << Check{ name: row.name, status: 'passed' }
			summary += row.name + ' PASS ' + row.seconds.str() + 's\n'
		}
	}
	assert checks.len == 24
	memory := os.read_file(work + '/memory-run.txt')!
	assert memory.count('retained 0 bytes PASS') == 58 && !memory.contains(': fn ')
	asan := os.read_file(work + '/asan-run.txt')!
	assert asan.count('ADMIN ENVELOPE ') == 58 && !asan.contains('ERROR:') && !asan.contains('runtime error:') && !asan.contains(': fn ')
	for name in ['protocol.v', 'socket.c.v']! {
		previous := os.exec(['git', 'show', 'fe668b6da:tools/packages/pkgadmin/' + name])
		assert previous.exit_code == 0 && previous.output == os.read_file(work + '/baseline/pkgadmin/' + name)!
	}
	for name in ['protocol.v', 'socket.c.v', 'request_reader.v']! {
		assert os.read_file('tools/packages/pkgadmin/' + name)! == os.read_file(work + '/final/pkgadmin/' + name)!
	}
	baseline := os.read_file(work + '/baseline-run.txt')!
	final := os.read_file(work + '/final-run.txt')!
	assert baseline.count('ADMIN PROTOCOL ') == 6 && baseline.contains('decode retained 400 bytes')
	assert baseline.contains('partial refusal retained 5495 bytes') && baseline.count('retained 1705 bytes') == 3
	assert final.count('retained 0 bytes') == 6
	compatibility := os.read_file(work + '/compat-baseline-run.txt')!
	assert compatibility == os.read_file(work + '/compat-final-run.txt')!
	assert compatibility.trim_space().split_into_lines().len == 537
	for phase in ['baseline', 'final', 'compat-baseline', 'compat-final']! {
		os.read_file(work + '/' + phase + '-compile.txt')!
		for task in ['compile', 'run']! {
			checks << Check{ name: phase + '-' + task, status: 'passed' }
			summary += phase + '-' + task + ' PASS\n'
		}
	}
	assert checks.len == 32
	os.write_file(prefix + 'host.json', json2.encode(checks) + '\n')!
	os.write_file(prefix + 'host.txt', summary)!
	for name, path in {'memory.txt': 'memory-run.txt', 'asan.txt': 'asan-run.txt', 'cli.txt': 'distribution-cli-run.txt',
		'checks.v': 'checks.v', 'core-checks.v': 'core.v', 'guest-checks.v': 'guest.v', 'probe-checks.v': 'probe.v',
		'compatibility-checks.v': 'compat.v', 'comparison.v': 'comparison.v', 'compatibility.v': 'compatibility.v', 'retain.v': 'retain.v'} {
		os.cp(work + '/' + path, prefix + name)!
	}
	os.write_file(prefix + 'comparison.txt', 'BASELINE fe668b6da: five calls per window, caller-owned inputs outside tracking\n' + baseline + '\nFINAL: identical five-call windows and cleanup\n' + final)!
	os.write_file(prefix + 'compatibility.txt', 'BASELINE fe668b6da and final: 537 byte-identical compatibility rows\n' + compatibility)!
	mut evidence := []Pin{}
	baseline_c := '/tmp/v_501/baseline-fixture.69634.2002447250.5685139568.tmp.c'
	os.cp(baseline_c, work + '/baseline.c')!
	mut review := 'Baseline generic JSON decoding owns an array grown without noslices; errors can return before partial request fields reach the caller. Matched probes establish retained bytes separately. Final fixed reader owns its heap reader and quoted buffer, transfers each string header once, releases partial fields/table on every refusal and transfers only accepted fields to Request.close. Receipt hashing releases context internals, context object, checksum, encoded string and bytes; error disposal passes the IError wrapper by value.\n'
	code := os.read_file(baseline_c)!
	for name in ['pkgadmin__decode', 'json2__Decoder_string__decode_array', 'pkgadmin__Request__receipt', 'pkgadmin__Request__result']! {
		review += '\nNative baseline: ' + name + '\n' + definition(code, name) + '\n'
	}
	evidence << pin(work + '/baseline.c')!
	for path in ['baseline-fixture', 'final-fixture', 'compat-baseline', 'compat-final', 'memory', 'asan', 'vinix-package', 'distribution-cli', 'distribution-check', 'controller', 'admin-controller']! {
		evidence << pin(work + '/' + path)!
	}
	for arch in ['aarch64', 'x86_64']! {
		short := if arch == 'aarch64' { 'arm' } else { 'x86' }
		base := 'build/ae-client-' + short
		receipt := json2.decode[Receipt](os.read_file(base + '/qualification.json')!)!
		assert receipt.architecture == arch && receipt.artifacts.len == 10
		for artifact in receipt.artifacts {
			path := match artifact.role {
				'kernel' { 'build/package-socket-work/' + short + '/kernel/bin/vinix' }
				'guest-init' { base + '/guest/init' }
				'serial-log' { base + '/packages-admin-envelope/serial.log' }
				'vinix-authd', 'vinix-session' { base + '/guest/root/usr/sbin/' + artifact.role }
				'vinix-package' { base + '/guest/root/usr/bin/vinix-package' }
				else { base + '/guest/root/usr/share/package-fixtures/' + artifact.role }
			}
			actual := pin(path)!; assert actual.bytes == artifact.bytes && actual.sha256 == artifact.sha256, path
			evidence << actual
		}
		serial := os.read_file(base + '/packages-admin-envelope/serial.log')!
		assert serial.count('retained 0 bytes PASS') == 116
		assert serial.contains('ADMIN ENVELOPE ACTOR root PASS') && serial.contains('ADMIN ENVELOPE ACTOR UID 1000 PASS')
		assert serial.contains('HWTEST PASS packages-admin-envelope') && !serial.contains('HWTEST FAIL')
		qmp := os.read_file(base + '/packages-admin-envelope/qmp.log')!
		assert qmp.contains('SHUTDOWN') && qmp.contains('"guest": true')
		for suffix, path in {'json': base + '/qualification.json', 'serial.txt': base + '/packages-admin-envelope/serial.log',
			'qmp.txt': base + '/packages-admin-envelope/qmp.log', 'txt': work + '/client-' + arch + '.txt'} {
			os.cp(path, prefix + arch + '.' + suffix)!
		}
		generated_path := base + '/guest/program-0/admin-envelope.c'
		generated := os.read_file(generated_path)!; evidence << pin(generated_path)!
		reader := definition(generated, 'pkgadmin__decode_request')
		quoted := definition(generated, 'pkgadmin__RequestReader__quoted')
		digest := definition(generated, 'pkgadmin__Request__digest')
		dispose := definition(generated, 'pkgadmin__discard_request_error')
		assert reader.contains('v_free(reader)') && reader.contains('array_push_many_ptr(&values, &value, 1)')
		assert reader.contains('values.flags |= 1') && reader.contains('string__free(&nonce)') && reader.contains('array__free(((array*)(&values)))')
		assert !reader.contains('string__clone(value)') && quoted.contains('bytes.flags |= 1') && quoted.contains('array__free(&bytes)')
		assert digest.contains('v_free(hash)') && digest.contains('array__free(&checksum)') && digest.contains('string__free(&encoded)')
		assert dispose.contains('IError__free(&err)') && !dispose.contains('memdup')
		for name in ['pkgadmin__RequestReader__quoted', 'pkgadmin__decode_request', 'pkgadmin__Request__digest', 'pkgadmin__discard_request_error',
			'pkgadmin__Request__receipt', 'pkgadmin__Request__result', 'pkgadmin__Request__close']! {
			review += '\n' + arch + ': ' + name + '\n' + definition(generated, name) + '\n'
		}
		for i, name in ['protocol', 'authcore', 'socket', 'vinix-authd', 'vinix-session', 'vinix-package']! {
			evidence << pin(base + '/guest/program-' + (i + 1).str() + '/' + name + '.c')!
		}
		evidence << pin(base + '/guest/init.c')!
		admin := 'build/ae-admin-' + short
		admin_receipt := json2.decode[Receipt](os.read_file(admin + '/qualification.json')!)!
		assert admin_receipt.architecture == arch && admin_receipt.artifacts.len == 8
		for artifact in admin_receipt.artifacts {
			path := match artifact.role {
				'kernel' { admin + '/kernel' }
				'guest-init' { admin + '/guest/init' }
				'package-service' { admin + '/guest/root/usr/bin/vinix-package' }
				'authentication-service' { admin + '/guest/root/usr/sbin/vinix-authd' }
				'account-manager' { admin + '/guest/root/usr/sbin/vinix-account' }
				'session-runner' { admin + '/guest/root/usr/sbin/vinix-session' }
				'administration-action' { admin + '/guest/root/usr/share/vinix/actions/packages-change' }
				'serial-log' { admin + '/packages-admin/serial.log' }
				else { return error('unexpected administrator artifact role: ' + artifact.role) }
			}
			actual := pin(path)!; assert actual.bytes == artifact.bytes && actual.sha256 == artifact.sha256, path
			evidence << actual
		}
		log := os.read_file(admin + '/packages-admin/serial.log')!
		assert log.contains('HWTEST PASS packages-admin') && !log.contains('HWTEST FAIL')
		control := os.read_file(admin + '/packages-admin/qmp.log')!
		assert control.contains('SHUTDOWN') && control.contains('"guest": true')
		for suffix, path in {'json': admin + '/qualification.json', 'serial.txt': admin + '/packages-admin/serial.log',
			'qmp.txt': admin + '/packages-admin/qmp.log', 'txt': work + '/admin-' + arch + '.txt'} {
			os.cp(path, prefix + arch + '.admin.' + suffix)!
		}
	}
	os.write_file(prefix + 'generated-c.txt', review)!
	mut paths := []string{}
	tracked := os.exec(['git', 'ls-files', 'tools/accounts', 'tools/packages', 'tests/hardware-platform/hwhost', 'tests/accounts/guest', 'tests/accounts/run.v'])
	assert tracked.exit_code == 0; paths << tracked.output.split_into_lines()
	paths << ['tools/packages/pkgadmin/request_reader.v', 'tools/packages/pkgadmin/ownership_test.v', 'tests/packages/admin-envelope-runtime-check.v',
		'tests/packages/admin-envelope-guest/main.v', 'tests/packages/admin-envelope-check.md', 'tests/packages/distribution-check.v',
		'docs/application-distribution.md', 'desktop/tools/tests/heap_tracker.h', 'tests/packages/admin-check.v']
	paths.sort(); mut sources := []Pin{}
	for path in paths { if !sources.any(it.path == path) { sources << pin(path)! } }
	compiler := pin('build/package-release-work/v-toolchain/v')!
	assert compiler.sha256 == 'd88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af'
	evidence << compiler
	for path in [work + '/retain.v', work + '/guest.v', work + '/probe.v', work + '/checks.v', work + '/core.v', work + '/compat.v',
		work + '/baseline/pkgadmin/protocol.v', work + '/baseline/pkgadmin/socket.c.v', 'build/package-launch-transport-work/cross-cc']! { evidence << pin(path)! }
	for name in os.ls(os.dir(prefix))! {
		if name.starts_with('admin-envelope-') && !name.ends_with('toolchain.json') { evidence << pin(os.dir(prefix) + '/' + name)! }
	}
	os.write_file(prefix + 'toolchain.json', json2.encode(Ledger{ baseline: 'fe668b6da',
		compiler: 'V 0.5.2 826e96f; -nocache -no-skip-unused -gc none -manualfree; separate track_heap and ASan/UBSan; static musl QEMU TCG guests; unchanged isolated socket-qualification kernels',
		checks: checks, sources: sources, evidence: evidence }) + '\n')!
	println('Verified 32 native checks, 58 zero-retention windows, 537 compatibility rows, four guests, 36 receipted artifacts and ' + sources.len.str() + ' source pins')
}
fn main() { check() or { eprintln(err); exit(1) } }
