// Build with -nocache -cflags -O2; -prod removes V assertions.
import crypto.sha256
import json2
import os

const root = '/Users/alex/code/vinix/'
const area = '/Volumes/VinixLinuxCompatPressure1012/'
const output = root + 'tests/linux-compat/results/2026-10-12/'

struct Evidence {
	architecture string
	context string
	artifacts map[string]string
	rootfs_overrides map[string]string
}

fn digest(path string) string { return sha256.sum(os.read_bytes(path) or { panic(err) }).hex() }
fn publish(source string, name string) ! {
	bytes := os.read_bytes(source)!
	if os.exists(output + name) { assert os.read_bytes(output + name)! == bytes }
	else { os.write_file_array(output + name, bytes)! }
}
fn evidence(name string, record Evidence) ! {
	bytes := (json2.encode(record, prettify: true) + '\n').bytes()
	if os.exists(output + name) { assert os.read_bytes(output + name)! == bytes }
	else { os.write_file_array(output + name, bytes)! }
}
fn published_kernel(arch string) string {
	raw := os.read_file(output + 'sysrq-after-' + arch + '.json') or { panic(err) }
	data := json2.decode[json2.Any](raw) or { panic(err) }
	return data.as_map()['kernel_sha256'] or { panic('missing published kernel') }.str()
}

fn check_assertions() {
	mut child := os.new_process('/Volumes/VinixLinuxCompatNext1011/tmp/assert-check')
	child.set_redirect_stdio()
	child.run()
	message := child.stdout_slurp() + child.stderr_slurp()
	child.wait()
	assert child.code == 1 && message.contains('receipt audit failure must be fatal')
	child.close()
}

fn audit_policy(arch string, suffix string) ! {
	state := area + 'jit-policy2-' + suffix
	receipt := json2.decode[json2.Any](os.read_file(state + '/receipt.json')!)!.as_map()
	assert receipt['architecture']!.str() == arch
	assert receipt['kernel_sha256']!.str() == digest(state + '/kernel/bin/vinix')
	assert receipt['kernel_sha256']!.str() == published_kernel(arch)
	rows := receipt['results']!.as_array()
	assert rows.len == 1
	row := rows[0].as_map()
	assert row['name']!.str() == 'jit' && row['exit_code']!.int() == 0
	assert row['source_sha256']!.str() == digest(root + 'tests/linux-compat/jitfixture/core.v')
	assert row['source_sha256']!.str() == digest(state + '/sources/jitfixture/core.v')
	assert row['init_sha256']!.str() == digest(state + '/jit/init')
	assert row['iso_sha256']!.str() == digest(state + '/jit/test.iso')
	log := os.read_file(state + '.log')!
	for marker in ['LINUX JIT PASS: ordinary-user approval, read-only runtime and default W^X',
		'LINUX JIT PASS: administrator revocation rejects future requests', 'LINUX JIT: PASS',
		'Linux compatibility guest suite: PASS'] { assert log.contains(marker) }
	assert !log.contains('LINUX JIT FAIL') && !log.contains('KERNEL PANIC') && !log.contains('FATAL EXCEPTION')
	publish(state + '/receipt.json', 'jit-policy-' + arch + '.json')!
	publish(state + '.log', 'jit-policy-' + arch + '.log')!
}

fn audit_app(kind string, arch string, suffix string) ! {
	state := if kind == 'firefox' { area + 'jit-firefox4g-' + suffix }
		else { '/tmp/vinix-linux-jit-1012/java-user-' + suffix }
	build := area + 'jit-driver3-' + suffix
	raw := os.read_file(state + '/guest-report.json')!
	report := json2.decode[json2.Any](raw)!.as_map()
	receipt := json2.decode[json2.Any](os.read_file(state + '/application-inputs.json')!)!.as_map()
	inputs := receipt['inputs']!.as_map_of_strings()
	assert receipt['architecture']!.str() == arch && receipt['execution_path']!.str() == 'native-' + arch
	assert receipt['uid']!.int() == 1000 && receipt['exit_code']!.int() == 0
	assert receipt['memory_mib']!.int() == if kind == 'firefox' { 4096 } else { 2048 }
	assert receipt['cases']!.str() == kind && receipt['jit_runtimes']!.as_array().map(it.str()) == [kind]
	assert report['uid']!.int() == 1000 && report['gid']!.int() == 1000
	assert report['context']!.str() == 'vinix-guest' && report['execution_path']!.str() == 'native-' + arch
	assert !report['complete_lifecycle_qualified']!.bool()
	assert report['requested_jit_runtimes']!.as_array().map(it.str()) == [kind]
	assert inputs['kernel'] == published_kernel(arch) && inputs['kernel'] == inputs['snapshot_kernel']
	assert inputs['kernel'] == digest(state + '/kernel/bin/vinix')
	assert inputs['guest_report'] == sha256.sum(raw.trim_space().bytes()).hex()
	assert inputs['workloads'] == report['suite_sha256']!.str()
	assert inputs['workloads'] == digest(state + '/rootfs/usr/bin/linux-compat-workloads')
	assert inputs['runtime-probe'] == report['runtime_probe_sha256']!.str()
	assert inputs['runtime-probe'] == digest(state + '/rootfs/usr/share/linux-compat/runtime')
	assert inputs['guest_credentials'] == digest(state + '/rootfs/etc/linux-compat-uid')
	assert os.read_file(state + '/rootfs/etc/linux-compat-uid')! == '1000\n'
	assert inputs['guest_options'] == digest(state + '/rootfs/etc/linux-compat-options')
	assert inputs['guest_jit_mounts'] == digest(state + '/rootfs/etc/linux-compat-jit-mounts')
	assert inputs['init_source'] == digest(state + '/sources/appinitfixture/core.v')
	assert inputs['init_source'] == digest(root + 'tests/linux-compat/appinitfixture/core.v')
	assert inputs['rootfs_manifest'] == digest(state + '/rootfs-inputs.json')
	assert os.read_bytes(state + '/init')! == os.read_bytes(state + '/rootfs/sbin/init')!
	mut overrides := map[string]string{}
	for path in ['/sbin/init', '/usr/bin/linux-compat-workloads', '/usr/share/linux-compat/runtime',
		'/etc/linux-compat-uid', '/etc/linux-compat-options', '/etc/linux-compat-jit-mounts'] {
		overrides[path] = digest(state + '/rootfs' + path)
	}
	manifest := json2.decode[map[string]string](os.read_file(state + '/rootfs-inputs.json')!)!
	for path, value in manifest {
		if path in overrides { continue }
		file := state + '/rootfs' + path
		if value.starts_with('link:') { assert os.is_link(file) && os.readlink(file)! == value.all_after('link:'); continue }
		fields := value.split(':')
		assert fields.len >= 2 && (os.stat(file)!.mode & 0o7777).str() == fields[1]
		if fields[0] == 'file' { assert fields.len == 3 && digest(file) == fields[2] }
		else { assert fields[0] == 'directory' && os.is_dir(file) }
	}
	build_receipt := json2.decode[json2.Any](os.read_file(build + '/build.json')!)!.as_map()
	assert build_receipt['architecture']!.str() == arch && build_receipt['libc']!.str() == 'musl'
	assert build_receipt['executable_sha256']!.str() == inputs['workloads']
	for path, hash in build_receipt['inputs']!.as_map_of_strings() {
		assert digest(if path == 'generated_c' { build + '/workloads.c' } else { root + path }) == hash
	}
	assert '-nocache' in build_receipt['commands']!.as_array()[0].as_array().map(it.str())
	verdicts := report['results']!.as_array()
	assert verdicts.len == 1 && verdicts[0].as_map()['name']!.str() == kind
	assert verdicts[0].as_map()['status']!.str() == 'passed'
	mounts := report['jit_mounts']!.as_array()
	assert mounts.len == 1 && mounts[0].as_map()['runtime']!.str() == kind
	mountpoint := os.read_file(state + '/rootfs/etc/linux-compat-jit-mounts')!.trim_space()
	assert mountpoint == if kind == 'firefox' { '/usr/lib/firefox-esr' } else { '/usr/lib/jvm/java-21-openjdk' }
	fields := mounts[0].as_map()['mountinfo']!.str().fields()
	assert fields[4] == mountpoint && ['ro', 'nosuid', 'nodev', 'wxallowed'].all(it in fields[5].split(','))
	assert 'noexec' !in fields[5].split(',')
	commands := report['commands']!.as_array()
	assert commands.len == if kind == 'firefox' { 2 } else { 5 }
	for command in commands {
		row := command.as_map()
		argv := row['argv']!.as_array().map(it.str())
		assert argv[0].starts_with(mountpoint + '/') && !argv.any(it.contains('no-sandbox') || it.contains('disable-sandbox'))
		assert row['executable_sha256']!.str() == digest(state + '/rootfs' + argv[0])
		assert row['environment_overrides']!.as_map_of_strings() == {'VINIX_ALLOW_WX': '1'}
		assert row['environment_unset']!.as_array().len == 0
		assert row['exit_code']!.int() == 0 && !row['timed_out']!.bool() && !row['output_limited']!.bool()
	}
	if kind == 'firefox' {
		browsers := report['browsers']!.as_array()
		assert browsers.len == 1
		browser := browsers[0].as_map()
		assert browser['name']!.str() == 'firefox'
		callback := browser['javascript_callback']!.str()
		assert callback.starts_with('GET /result/') && callback.ends_with('/42 HTTP/1.1')
		nonce := callback.all_after('GET /result/').all_before('/42 HTTP/1.1')
		assert nonce.len == 64 && nonce.bytes().all(it in '0123456789abcdef'.bytes())
		page := '<!doctype html><meta charset="utf-8"><style>body{background:#fff}#verdict{color:#06c;font-size:48px}</style>'
			+ '<p id="verdict">pending</p><script>const answer=6*7;document.getElementById("verdict").textContent=answer;'
			+ 'const proof=new Image();proof.src="/result/' + nonce + '/"+answer;document.body.appendChild(proof);</script>'
		assert browser['page_sha256']!.str() == sha256.sum(page.bytes()).hex()
		assert browser['screenshot_sha256']!.str().len == 64
		assert commands[1].as_map()['stderr']!.str() == '*** You are running in headless mode.\n'
	} else {
		assert commands[2].as_map()['stdout']!.str().contains('on Vinix: PASS')
		assert commands[4].as_map()['stdout']!.str().contains('on Vinix: PASS')
	}
	serial := os.read_file(state + '/serial.log')!
	assert serial.contains('LINUX JIT MOUNT: ' + mountpoint + ' ro,nosuid,nodev,wxallowed')
	assert serial.contains('LINUX APPLICATIONS: PASS') && !serial.contains('LINUX APPLICATIONS FAIL')
	assert !serial.contains('KERNEL PANIC') && !serial.contains('FATAL EXCEPTION')
	mut artifacts := {'audit': digest(@FILE), 'compiler': digest('/Users/alex/code/v/v'),
		'controller': digest(area + 'apps-jit2-controller'), 'controller_source': digest(root + 'tests/linux-compat/run-apps.v'),
		'kernel': digest(state + '/kernel/bin/vinix'), 'init': digest(state + '/init'),
		'archive': digest(state + '/initramfs.tar'), 'iso': digest(state + '/test.iso'),
		'rootfs_manifest': digest(state + '/rootfs-inputs.json'), 'report': digest(state + '/guest-report.json'),
		'inputs': digest(state + '/application-inputs.json'), 'driver_build': digest(build + '/build.json'),
		'generated_c': digest(build + '/workloads.c'), 'serial': digest(state + '/serial.log')}
	staged := if kind == 'firefox' { '/Volumes/VinixLinuxCompatNext1011/firefox-inputs-x86' }
		else { '/tmp/vinix-linux-jit-1012/java-inputs-' + suffix }
	for url, hash in json2.decode[map[string]string](os.read_file(staged + '/inputs.json')!)! {
		file := if url == 'stager_source' { '/tmp/vinix-linux-runtime-stage.v' }
			else if url.ends_with('APKINDEX.tar.gz') { staged + '/' + (if url.contains('/main/') { 'main' } else { 'community' }) + '/APKINDEX.tar.gz' }
			else { staged + '/archives/' + url.all_after_last('/') }
		assert digest(file) == hash
	}
	artifacts['package_inputs'] = digest(staged + '/inputs.json')
	name := 'jit-' + kind + '-' + arch
	evidence(name + '-evidence.json', Evidence{arch,
		'UID/GID 1000; scoped read-only administrator-approved executable mount; per-child W^X request; native guest workload; assertion-enabled audit', artifacts, overrides})!
	for file, label in {'guest-report.json': '.json', 'application-inputs.json': '-inputs.json',
		'serial.log': '.log', 'rootfs-inputs.json': '-rootfs.json'} { publish(state + '/' + file, name + label)! }
	publish(build + '/build.json', 'jit-driver-' + arch + '.json')!
	publish(staged + '/inputs.json', name + '-packages.json')!
}

fn main() {
	assert os.args.len == 2 && os.args[1] in ['policy', 'firefox', 'java']
	check_assertions()
	if os.args[1] == 'policy' {
		for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} { audit_policy(arch, suffix)! }
	} else if os.args[1] == 'firefox' { audit_app('firefox', 'x86_64', 'x86')! }
	else { for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} { audit_app('java', arch, suffix)! } }
	println('JIT ' + os.args[1] + ' guest evidence: verified')
}
