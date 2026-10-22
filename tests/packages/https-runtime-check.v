// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import time
import json2
import crypto.sha256
import hwhost
import tlsruntime
import tools.packages.pkgcore

struct Pin {
	path   string
	sha256 string
}

struct Check {
	name      string
	argv      []string
	seconds   f64
	artifacts []Pin
}

struct Receipt {
	format int = 1
	inputs []Pin
	checks []Check
}

fn pin(path string) !Pin {
	return Pin{ path: os.abs_path(path), sha256: sha256.sum(os.read_bytes(path)!).hex() }
}

fn verify(pins []Pin) ! {
	for item in pins {
		if pin(item.path)! != item { return error('qualification input changed: ' + item.path) }
	}
}

fn run(name string, args []string, work string, binary string) !Check {
	if args.len == 0 { return error('missing command for ' + name) }
	mut child := os.new_process(args[0])
	child.set_args(args[1..])
	child.set_redirect_stdio_merged()
	start := time.now()
	child.run()
	output := child.stdout_slurp()
	child.wait()
	code := child.code
	child.close()
	log := work + '/' + name + '.txt'
	os.write_file(log, output)!
	if code != 0 || output.contains('V panic:') || output.contains('ERROR: AddressSanitizer') || output.contains('runtime error:') {
		return error('qualification command failed: ' + name + ' (exit ' + code.str() + '); see ' + log)
	}
	println(name + ' PASS')
	return Check{
		name:      name
		argv:      args
		seconds:   f64(time.since(start).milliseconds()) / 1000
		artifacts: [
			pin(log)!,
			pin(binary)!,
		]
	}
}

fn option(args []string, name string) !string {
	for i, arg in args { if arg == name && i + 1 < args.len { return os.abs_path(args[i + 1]) } }
	return error('required option: ' + name)
}

fn certificate(work string, mut checks []Check) ! {
	os.mkdir_all(work)!
	os.write_file(work + '/certificate.cnf', '[req]\nprompt=no\ndistinguished_name=subject\nx509_extensions=extensions\n' +
		'[subject]\nCN=Vinix guest TLS fixture\n[extensions]\nbasicConstraints=critical,CA:TRUE\n' +
		'keyUsage=critical,digitalSignature,keyEncipherment,keyCertSign\nextendedKeyUsage=serverAuth\nsubjectAltName=IP:127.0.0.1,IP:10.0.2.2\n')!
	openssl := os.find_abs_path_of_executable('openssl')!
	checks << run('certificate', [openssl, 'req', '-new', '-x509', '-newkey', 'rsa:2048', '-nodes',
		'-days', '2', '-config', work + '/certificate.cnf', '-keyout', work + '/key.pem', '-out',
		work + '/ca.pem'], work, work + '/ca.pem')!
	os.chmod(work + '/key.pem', 0o600)!
}

fn ready(path string, mut server os.Process) !string {
	for _ in 0 .. 500 {
		if os.exists(path) { return os.read_file(path) }
		if !server.is_alive() { return error('TLS fixture exited before binding') }
		time.sleep(10 * time.millisecond)
	}
	return error('TLS fixture did not bind')
}

fn curl_files(root string, arch string) ![]hwhost.RootBinary {
	mut paths := ['usr/bin/curl', 'lib/ld-musl-' + arch + '.so.1']
	mut selected := map[string]bool{}
	mut result := []hwhost.RootBinary{}
	readelf := os.find_abs_path_of_executable(arch + '-linux-musl-readelf')!
	for index := 0; index < paths.len; index++ {
		path := paths[index]
		if path in selected { continue }
		selected[path] = true
		source := os.real_path(root + '/' + path)
		if !os.is_file(source) { return error('missing curl dependency: ' + source) }
		result << hwhost.RootBinary{ source: source, path: path }
		mut child := os.new_process(readelf)
		child.set_args(['-d', source])
		child.set_redirect_stdio_merged()
		child.run()
		text := child.stdout_slurp()
		child.wait()
		code := child.code
		child.close()
		if code != 0 { return error('curl dependency inspection failed: ' + text) }
		for line in text.split_into_lines() {
			if !line.contains('(NEEDED)') { continue }
			name := line.all_after('[').all_before(']')
			if name == '' || name.contains('/') { return error('invalid curl dependency: ' + name) }
			mut found := false
			for directory in ['lib', 'usr/lib']! {
				candidate := directory + '/' + name
				if os.is_file(root + '/' + candidate) {
					paths << candidate
					found = true
					break
				}
			}
			if !found { return error('missing curl dependency ' + name) }
		}
	}
	return result
}

fn check_requests(text string, repetitions int) ! {
	if repetitions !in [1, 2] { return error('invalid request repetition count') }
	mut counts := map[string]int{}
	mut setups := map[string]int{}
	for line in text.split_into_lines() {
		fields := line.fields()
		if fields.len != 4 || fields[0] !in tlsruntime.modes() {
			return error('invalid TLS fixture request: ' + line)
		}
		if fields[1] == 'setup' { setups[fields[0]]++ } else { counts[fields[0]]++ }
	}
	for mode in tlsruntime.modes() {
		if counts[mode] != repetitions * (tlsruntime.cycles + tlsruntime.warmups) * tlsruntime.requests(mode) {
			return error('unexpected TLS request count: ' + mode)
		}
		if setups[mode] != if mode.starts_with('fetch-') { 0 } else { 2 * repetitions } {
			return error('unexpected TLS setup count: ' + mode)
		}
	}
}

fn check() ! {
	if os.args.len < 3 {
		return error('usage: https-runtime-check host NEW_WORK | ARCH CURL_ROOT --kernel KERNEL --state-dir NEW_WORK [hwhost options]')
	}
	kind := os.args[1]
	if kind !in ['host', 'aarch64', 'x86_64']! {
		return error('unsupported TLS qualification target: ' + kind)
	}
	root := os.dir(os.dir(os.dir(@FILE)))
	work := if kind == 'host' {
		os.abs_path(os.args[2])
	} else {
		option(os.args, '--state-dir')! + '-tls'
	}
	if os.exists(work) || os.is_link(work) {
		return error('TLS qualification requires a new work directory: ' + work)
	}
	os.mkdir_all(work + '/repository')!
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	v := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	os.setenv('VEXE', v, true)
	// The macOS dispatcher preserves its invoking checkout through these
	// markers; a relocated executable must use the reviewed libraries beside it.
	os.setenv('V_MACOS_V3_CALLER_VEXE_PRESENT', '1', true)
	os.setenv('V_MACOS_V3_CALLER_VEXE', v, true)
	os.setenv('V_MACOS_V3_CALLER_VCHILD_PRESENT', '0', true)
	mut inputs := [pin(v)!, pin(os.find_abs_path_of_executable('openssl')!)!,
		pin(root + '/desktop/tools/tests/heap_tracker.h')!]
	compiler_root := os.dir(v)
	inputs << pin(compiler_root + '/v.mod')!
	for directory in ['vlib', 'thirdparty']! {
		for extension in ['.v', '.c', '.h', '.S', '.o', '.a']! {
			for path in os.walk_ext(compiler_root + '/' + directory, extension) {
				inputs << pin(path)!
			}
		}
	}
	for directory in ['tools/packages', 'tools/accounts', 'compat/ios/plist',
		'tests/packages/tlsruntime', 'tests/packages/collectionstress', 'tests/hardware-platform/hwhost']! {
		for path in os.walk_ext(root + '/' + directory, '.v') {
			if !path.ends_with('_test.v') { inputs << pin(path)! }
		}
	}
	for path in [@FILE, root + '/tests/packages/https-runtime-probe.v',
		root + '/tests/packages/https-runtime-server.v',
		root + '/tests/packages/https-runtime-guest/main.v']! {
		inputs << pin(path)!
	}
	mut checks := []Check{}
	certificate(work, mut checks)!
	certificate(work + '/untrusted', mut checks)!
	flags := ['-nocache', '-no-skip-unused', '-cc', 'clang', '-gc', 'none', '-manualfree', '-cflags',
		'-O1', '-path',
		'@vlib|@vmodules|' + root + '|' + root + '/tools/accounts|' + root + '/tests/packages|' + root + '/tests/hardware-platform']
	checks << run('server-compile', [v, ...flags, '-o', work + '/server',
		root + '/tests/packages/https-runtime-server.v'], work, work + '/server')!
	text := 'authenticated guest HTTPS payload\n'.repeat(1024)
	os.write_file(work + '/repository/payload', text)!
	os.write_file(work + '/requests.txt', '')!
	os.mkdir_all(work + '/source/share')!
	os.write_file(work + '/source/share/payload', text)!
	os.write_file(work + '/manifest.json', json2.encode(pkgcore.Package{ id: 'app', name: 'Guest TLS é🚀', version: '1.0.0', architecture: 'all', kind: 'data', license: 'MIT' }))!
	package := pkgcore.pack(work + '/manifest.json', work + '/source', work + '/repository')!
	key := pkgcore.keygen(work + '/seed')!
	pkgcore.publish(work + '/repository', 'tls-runtime', work + '/seed', 1, time.now().unix() + 86400)!
	mut server := os.new_process(work + '/server')
	server.set_args([work + '/ca.pem', work + '/key.pem', work + '/repository', work + '/ready',
		work + '/requests.txt'])
	server.run()
	defer {
		if server.is_alive() { server.signal_kill() }
		server.wait()
		server.close()
	}
	base := ready(work + '/ready', mut server)!
	f := tlsruntime.Fixture{
		base:         base
		wrong_host:   base.replace('127.0.0.1', 'localhost')
		architecture: 'aarch64'
		work:         work + '/client'
		ca:           work + '/ca.pem'
		untrusted:    work + '/untrusted/ca.pem'
		key:          key
		text:         text
		payload:      package.files[0]
		index:        os.read_file(work + '/repository/index.json')!
		signature:    os.read_file(work + '/repository/index.sig')!
	}
	if kind == 'host' {
		inputs << pin('/usr/bin/curl')!
		os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
		os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
		for sanitized in [false, true]! {
			name := if sanitized { 'probe-sanitize' } else { 'probe' }
			binary := work + '/' + name
			extra := if sanitized {
				['-d', 'no_segfault_handler', '-cflags',
					'-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags',
					'-fsanitize=address,undefined']
			} else {
				[]string{}
			}
			checks << run(name + '-compile', [v, ...flags, '-d', 'track_heap', ...extra, '-o',
				binary, root + '/tests/packages/https-runtime-probe.v'], work, binary)!
			fixture := work + '/' + name + '.json'
			os.write_file(fixture, json2.encode(tlsruntime.Fixture{ ...f, work: work + '/' + name + '-root' }))!
			for mode in tlsruntime.modes() {
				checks << run(name + '-' + mode, [binary, fixture, mode], work, binary)!
				if !os.read_file(work + '/' + name + '-' + mode + '.txt')!.contains('GUEST TLS ' + mode + ' retained 0 tracked bytes') {
					return error('missing zero retained heap result: ' + name + '-' + mode)
				}
			}
		}
		check_requests(os.read_file(work + '/requests.txt')!, 2)!
	} else {
		if os.args.len <= 3 { return error('missing guest qualification options') }
		kernel := option(os.args, '--kernel')!
		inputs << pin(kernel)!
		for program in [kind + '-linux-musl-gcc', kind + '-linux-musl-readelf', 'qemu-system-' + kind]! {
			inputs << pin(os.find_abs_path_of_executable(program)!)!
		}
		binaries := curl_files(os.abs_path(os.args[2]), kind)!
		for binary in binaries { inputs << pin(binary.source)! }
		os.write_file(work + '/curl-files.json', json2.encode(binaries))!
		guest_fixture := tlsruntime.Fixture{
			...f
			base:         base.replace('127.0.0.1', '10.0.2.2')
			wrong_host:   base.replace('127.0.0.1', 'tls-wrong.fixture')
			architecture: kind
			work:         '/tmp/tls-runtime'
			ca:           '/usr/share/package-fixtures/ca.pem'
			untrusted:    '/usr/share/package-fixtures/untrusted.pem'
		}
		os.write_file(work + '/fixture.json', json2.encode(guest_fixture))!
		mut required := ['HWTEST START packages-https-runtime', 'HWTEST PASS packages-https-runtime',
			'GUEST TLS 23 cases with 8 measured cycles preserve authenticated state, certificate policy, bounded recovery and retired replies PASS']
		for mode in tlsruntime.modes() {
			required << 'GUEST TLS ' + mode + ' retained 0 tracked bytes'
			required << 'COLLECTION STRESS settled ' + mode + ':'
		}
		suite := hwhost.Suite{
			name:         'package-https-runtime'
			guest:        'tests/packages/https-runtime-guest'
			module_paths: ['.', 'tools/accounts', 'tests/packages']
			programs:     [hwhost.Program{
				source: 'tests/packages/https-runtime-probe.v'
				path:   'usr/share/package-fixtures/tls-probe'
				flags:  [
					'-manualfree',
					'-d',
					'track_heap',
				]
			}]
			binaries:     binaries
			directories:  ['tmp:1777']
			files:        [
				hwhost.RootFile{ path: 'usr/share/package-fixtures/tls.json', text: json2.encode(guest_fixture) },
				hwhost.RootFile{ path: 'usr/share/package-fixtures/ca.pem', text: os.read_file(f.ca)! },
				hwhost.RootFile{ path: 'usr/share/package-fixtures/untrusted.pem', text: os.read_file(f.untrusted)! },
				hwhost.RootFile{ path: 'etc/hosts', text: '127.0.0.1 localhost\n10.0.2.2 tls-wrong.fixture\n' },
			]
			scenarios:    [hwhost.Scenario{
				name:         'packages-https-runtime'
				arches:       ['aarch64', 'x86_64']
				about:        'Real guest curl/OpenSSL, signed HTTPS refresh/install and bounded recovery against a local repository'
				qemu_aarch64: ['-device', 'e1000,netdev=tls0', '-netdev', 'user,id=tls0']
				qemu_x86_64:  ['-nic', 'user,model=e1000']
				timeout:      1200
				ending:       .poweroff
				required:     required
				forbidden:    ['HWTEST FAIL', 'V panic:', 'Out of memory']
			}]
		}
		start := time.now()
		status := hwhost.run_suite(suite, os.args[3..], @FILE)
		if status != 0 { return error('guest TLS qualification failed') }
		state := option(os.args, '--state-dir')!
		checks << Check{
			name:      'guest-' + kind
			argv:      os.args.clone()
			seconds:   f64(time.since(start).milliseconds()) / 1000
			artifacts: [pin(state + '/packages-https-runtime/serial.log')!,
				pin(state + '/packages-https-runtime/qemu.log')!, pin(state + '/guest/init')!,
				pin(state + '/guest/program-0/tls-probe')!]
		}
		check_requests(os.read_file(work + '/requests.txt')!, 1)!
	}
	verify(inputs)!
	os.write_file(work + '/qualification.json', json2.encode(Receipt{ inputs: inputs, checks: checks }) + '\n')!
	println('GUEST TLS ' + kind + ' exact request counts and unchanged qualification inputs PASS')
}

fn main() {
	check() or {
		eprintln(err)
		exit(1)
	}
}
