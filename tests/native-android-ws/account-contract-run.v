// SPDX-License-Identifier: GPL-2.0-or-later
// Isolated ART regression and Maps retest using the qualified Maps372 runtime.
module main

import crypto.sha256
import json2
import os
import strconv
import time

#include <sys/clonefile.h>
#include <signal.h>
fn C.clonefile(&char, &char, int) int
fn C.kill(int, int) int

const repo = '/Users/alex/code/vinix'
const baseline = repo + '/build/android-maps/maps372/vm'
const baseline_boot = '176094564fba09181b1a2f334f240dc49f0e5f25032696a84db12c2316d0445c'
const baseline_jar = '3b345e1661ca9f5b616f5abe25c9f4abc1df383204d25333477dae69221a8d21'
const qemu = repo + '/build/qemu-horizontal/bin/qemu-system-aarch64'
const firmware = '/opt/homebrew/share/qemu/edk2-aarch64-code.fd'
const jar_member = 'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'
const modules = ['initramfs.tar', 'qemu-runtime.tar', 'maps335-diagnostics.tar', 'maps350-diagnostics.tar', 'maps372-diagnostics.tar']
const fixture_pass = 'ACCOUNT-ASYNC-PASS credential-insertion-rejected null-type no-callback no-accounts main-queued worker-to-main explicit-handler callback-once same-future done cancel-false result-authenticator-exception repeat timed null-unit'

struct Ownership {
	pid     int
	command string
	started string
}

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut sum := sha256.new()
	mut bytes := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut bytes) or { if err.code() == 0 { break }; return err }
		if n == 0 { break }
		sum.write(bytes[..n])!
	}
	return sum.sum([]u8{}).hex()
}

fn write_json[T](path string, value T) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn checked(argv []string) !string {
	r := os.exec(argv)
	if r.exit_code != 0 { return error(argv[0] + ': ' + r.output) }
	return r.output.trim_space()
}

fn command(root string, label string, argv []string) !string {
	exe := if argv[0].contains('/') { os.real_path(argv[0]) } else { os.find_abs_path_of_executable(argv[0])! }
	exe_hash := digest(exe)!
	started := time.utc().str()
	r := os.exec(argv)
	os.write_file(root + '/commands/' + label + '.log', r.output)!
	write_json(root + '/commands/' + label + '.json', {
		'argv': json2.Any(argv), 'started_utc': json2.Any(started),
		'completed_utc': json2.Any(time.utc().str()), 'exit_code': json2.Any(r.exit_code),
		'executable_sha256': json2.Any(exe_hash)
	})!
	if r.exit_code != 0 { return error(label + ': ' + r.output) }
	if digest(exe)! != exe_hash { return error('command executable changed: ' + exe) }
	return r.output
}

fn inventory(root string, prefix string, mut pins map[string]string) ! {
	for name in os.ls(root + '/' + prefix)! {
		key := if prefix == '' { name } else { prefix + '/' + name }
		path := root + '/' + key
		match os.lstat(path)!.get_filetype() {
			.directory { inventory(root, key, mut pins)! }
			.regular {
				if key.ends_with('.oat') || key.ends_with('.odex') || key.ends_with('.vdex') || key.contains('/dalvik-cache/') {
					return error('compiled cache could shadow framework DEX: ' + key)
				}
				pins[key] = digest(path)!
			}
			.symbolic_link { pins[key] = 'symlink:' + os.readlink(path)! }
			else { return error('unexpected runtime file kind: ' + key) }
		}
	}
}

fn root_check(root string) ! {
	if !root.starts_with('/Users/alex/.local/state/vinix/android/') || root.contains_any(' \n\t')
		|| os.real_path(root) != root || os.is_link(root) { return error('canonical external state path required') }
}

fn prepare(root string, build string, apk string) ! {
	if os.exists(root) || os.is_link(root) { return error('fresh external state required') }
	os.mkdir_all(root + '/commands')!
	root_check(root)!
	receipt := json2.decode[map[string]json2.Any](os.read_file(build + '/build.json')!)!
	jar := build + '/api-impl.jar'
	jar_hash := digest(jar)!
	if jar_hash != receipt['api_impl_sha256']!.str() { return error('new framework JAR differs from build receipt') }
	if digest(baseline + '/boot.img')! != baseline_boot { return error('qualified Maps372 boot differs') }
	mut inputs := map[string]string{}
	for path in [baseline + '/boot.img', baseline + '/efivars.fd', jar, build + '/build.json',
		repo + '/tests/native-android-ws/account-contract-run.v', os.executable(), qemu, firmware] { inputs[path] = digest(path)! }
	if apk != '' {
		inputs[apk] = digest(apk)!
		inputs[repo + '/tests/native-android-ws/account-addition-fixture.v'] = digest(repo + '/tests/native-android-ws/account-addition-fixture.v')!
	}
	for name in ['boot.img', 'efivars.fd'] {
		from := baseline + '/' + name
		to := root + '/' + name
		if C.clonefile(from.str, to.str, 0) != 0 { return error('APFS clone failed: ' + name) }
		if digest(to)! != inputs[from]! { return error('cloned media differs: ' + name) }
	}
	config := command(root, 'read-limine', ['mtype', '-i', baseline + '/boot.img', '::/boot/limine.conf'])!
	module_lines := config.split_into_lines().map(it.trim_space()).filter(it.starts_with('module_path:'))
	if module_lines != modules.map('module_path: boot():/boot/' + it) { return error('unexpected baseline module load order') }
	os.write_file(root + '/limine-before.conf', config)!
	mut module_pins := map[string]string{}
	os.mkdir_all(root + '/scratch')!
	for name in modules {
		archive := root + '/' + name
		command(root, 'extract-' + name, ['mcopy', '-i', baseline + '/boot.img', '::/boot/' + name, archive])!
		module_pins[name] = digest(archive)!
		// initramfs supplies the OS; the Android runtime and ordered overlays
		// form the application tree whose exact file delta is checked below.
		if name != 'initramfs.tar' {
			command(root, 'compose-' + name, ['/usr/bin/tar', '-xf', archive, '-C', root + '/scratch'])!
		}
		if name in ['initramfs.tar', 'qemu-runtime.tar'] { os.rm(archive)! }
	}
	if digest(root + '/scratch/' + jar_member)! != baseline_jar { return error('composed runtime framework is not Framework371') }
	mut before := map[string]string{}
	inventory(root + '/scratch', '', mut before)!
	os.cp(jar, root + '/scratch/' + jar_member)!
	mut changed := [jar_member]
	if apk != '' {
		os.cp(apk, root + '/scratch/opt/android-test/application.apk')!
		os.write_file(root + '/scratch/opt/android-test/popular-id', 'account-contract')!
		os.write_file(root + '/scratch/usr/share/vinix/android-app-label', 'Account contract')!
		changed << ['opt/android-test/application.apk', 'opt/android-test/popular-id', 'usr/share/vinix/android-app-label']
	}
	mut after := map[string]string{}
	inventory(root + '/scratch', '', mut after)!
	if before.len != after.len { return error('runtime file set changed') }
	for name, pin in before {
		if name !in after || ((name in changed) == (pin == after[name]!)) { return error('unexpected runtime delta: ' + name) }
	}
	write_json(root + '/module-before.json', before)!
	write_json(root + '/module-after.json', after)!
	for name in changed {
		os.mkdir_all(os.dir(root + '/overlay/' + name))!
		os.cp(root + '/scratch/' + name, root + '/overlay/' + name)!
	}
	command(root, 'create-account-overlay', ['/usr/bin/tar', '--format=ustar', '-b', '1', '-cf', root + '/account-contract.tar', '-C', root + '/overlay', '.'])!
	overlay_pin := digest(root + '/account-contract.tar')!
	command(root, 'install-account-overlay', ['mcopy', '-o', '-i', root + '/boot.img', root + '/account-contract.tar', '::/boot/account-contract.tar'])!
	os.write_file(root + '/limine-after.conf', config.trim_right('\n') + '\n    module_path: boot():/boot/account-contract.tar\n')!
	command(root, 'install-limine', ['mcopy', '-o', '-i', root + '/boot.img', root + '/limine-after.conf', '::/boot/limine.conf'])!
	if command(root, 'read-back-limine', ['mtype', '-i', root + '/boot.img', '::/boot/limine.conf'])! != os.read_file(root + '/limine-after.conf')! { return error('written module load order differs') }
	command(root, 'read-back-overlay', ['mcopy', '-i', root + '/boot.img', '::/boot/account-contract.tar', root + '/read-back-overlay.tar'])!
	if digest(root + '/read-back-overlay.tar')! != overlay_pin { return error('written account overlay differs') }
	os.mkdir_all(root + '/read-back-overlay')!
	command(root, 'unpack-read-back-overlay', ['/usr/bin/tar', '-xf', root + '/read-back-overlay.tar', '-C', root + '/read-back-overlay'])!
	mut overlay_files := map[string]string{}
	inventory(root + '/read-back-overlay', '', mut overlay_files)!
	if overlay_files.len != changed.len { return error('account overlay file set differs') }
	for name in changed { if overlay_files[name] != after[name] { return error('account overlay file differs: ' + name) } }
	for name, pin in module_pins {
		command(root, 'preserved-' + name, ['mcopy', '-i', root + '/boot.img', '::/boot/' + name, root + '/preserved.tar'])!
		if digest(root + '/preserved.tar')! != pin { return error('original module changed: ' + name) }
		os.rm(root + '/preserved.tar')!
	}
	os.rmdir_all(root + '/overlay')!
	os.rmdir_all(root + '/read-back-overlay')!
	os.rmdir_all(root + '/scratch')!
	for path, pin in inputs { if digest(path)! != pin { return error('input changed while preparing: ' + path) } }
	os.cp(repo + '/tests/native-android-ws/account-contract-run.v', root + '/runner-source.v')!
	if apk != '' {
		os.cp(apk, root + '/fixture.apk')!
		os.cp(repo + '/tests/native-android-ws/account-addition-fixture.v', root + '/fixture-source.v')!
	}
	os.cp(os.executable(), root + '/runner')!
	write_json(root + '/prepare.json', {
		'scope': json2.Any(if apk == '' { 'Maps precredential Add account retest; no authenticator or account store' } else { 'Actual ART unsupported-account future/callback regression' }),
		'kind': json2.Any(if apk == '' { 'maps' } else { 'fixture' }),
		'source_revision': json2.Any(checked(['/usr/bin/git', '-C', repo, 'rev-parse', 'HEAD'])!),
		'input_sha256': json2.decode[json2.Any](json2.encode(inputs))!,
		'preserved_original_module_sha256': json2.decode[json2.Any](json2.encode(module_pins))!,
		'account_overlay_sha256': json2.Any(overlay_pin),
		'prepared_boot_sha256': json2.Any(digest(root + '/boot.img')!),
		'changed_runtime_files': json2.Any(changed)
	})!
	println('ACCOUNT-CONTRACT-PREPARED ' + root)
}

fn identity(pid int) !Ownership {
	if pid <= 1 { return error('invalid process ID') }
	return Ownership{pid: pid, command: checked(['/bin/ps', '-ww', '-p', pid.str(), '-o', 'command='])!, started: checked(['/bin/ps', '-p', pid.str(), '-o', 'lstart='])!}
}

fn owned(root string) !Ownership {
	root_check(root)!
	recorded := json2.decode[Ownership](os.read_file(root + '/ownership.json')!)!
	if strconv.atoi(os.read_file(root + '/qemu.pid')!.trim_space())! != recorded.pid { return error('ownership PID differs') }
	current := identity(recorded.pid)!
	if current != recorded || !current.command.starts_with(qemu + ' ')
		|| !current.command.contains('unix:' + root + '/qmp.sock,server=on,wait=off')
		|| !current.command.ends_with('-pidfile ' + root + '/qemu.pid') { return error('process ownership differs; refusing signal') }
	return current
}

fn start(root string) ! {
	root_check(root)!
	if os.exists(root + '/launch.json') || os.is_link(root + '/launch.json') { return error('guest can be launched once only') }
	for line in checked(['/bin/ps', '-axo', 'pid=,command='])!.split_into_lines() {
		if line.contains(qemu + ' ') && (line.contains('/maps372/') || line.contains('/maps-signin-') || line.contains('/account-contract-')) { return error('another Maps/account guest is live') }
	}
	prepared := json2.decode[map[string]json2.Any](os.read_file(root + '/prepare.json')!)!
	if digest(root + '/boot.img')! != prepared['prepared_boot_sha256']!.str() { return error('prepared image changed') }
	args := ['-qmp', 'unix:' + root + '/qmp.sock,server=on,wait=off', '-machine', 'virt,gic-version=3', '-accel', 'hvf', '-cpu', 'host', '-m', '12288', '-smp', '4', '-object', 'rng-random,filename=/dev/urandom,id=vinix-rng', '-device', 'virtio-rng-device', '-drive', 'if=pflash,format=raw,readonly=on,file=' + firmware, '-drive', 'if=pflash,format=raw,file=' + root + '/efivars.fd', '-drive', 'format=raw,file=' + root + '/boot.img', '-device', 'virtio-keyboard-device', '-device', 'virtio-tablet-device', '-device', 'ramfb', '-netdev', 'user,id=net0', '-device', 'virtio-net-device,netdev=net0', '-object', 'filter-dump,id=capture,netdev=net0,file=' + root + '/network.pcap', '-display', 'none', '-monitor', 'none', '-serial', 'file:' + root + '/serial.log', '-daemonize', '-pidfile', root + '/qemu.pid']
	mut argv := [qemu]
	argv << args
	write_json(root + '/launch.json', {'argv': json2.Any(argv), 'started_utc': json2.Any(time.utc().str())})!
	command(root, 'launch', argv)!
	write_json(root + '/ownership.json', identity(strconv.atoi(os.read_file(root + '/qemu.pid')!.trim_space())!)!)!
	println('ACCOUNT-CONTRACT-STARTED pid=' + owned(root)!.pid.str() + ' state=' + root)
}

fn stop(root string) ! {
	owner := owned(root)!
	if C.kill(owner.pid, C.SIGTERM) != 0 { return error('could not signal owned process') }
	write_json(root + '/stop.json', {'pid': json2.Any(owner.pid), 'signal': json2.Any('SIGTERM'), 'requested_utc': json2.Any(time.utc().str())})!
	println('ACCOUNT-CONTRACT-STOP-SENT pid=' + owner.pid.str())
}

fn fixture_log(log string) !bool {
	for marker in ['APK-SUITE-EXIT id=', 'ANDROID-WS-FAIL', 'java.lang.AssertionError', 'java.lang.VerifyError', 'NoClassDefFoundError', 'UnsatisfiedLinkError', 'Exception in thread', 'ACCOUNT-ASYNC-FAIL', 'VINIX-ACCOUNT-PASSWORD-SENTINEL-2026', 'VINIX-ACCOUNT-USERDATA-SENTINEL-2026'] {
		if log.contains(marker) { return error('ART fixture failure marker: ' + marker) }
	}
	if log.count(fixture_pass) > 1 { return error('duplicate fixture pass marker') }
	return log.contains('APK-SUITE-BEGIN id=account-contract ') && log.count(fixture_pass) == 1
}

fn observe(root string) ! {
	config := json2.decode[map[string]json2.Any](os.read_file(root + '/prepare.json')!)!
	if config['kind']!.str() != 'fixture' { return error('fixture observation requires fixture image') }
	mut passed_at := i64(0)
	begin := time.now().unix()
	for time.now().unix() - begin < 180 {
		owned(root)!
		log := os.read_file(root + '/serial.log') or { '' }
		if fixture_log(log)! {
			if passed_at == 0 { passed_at = time.now().unix() }
			if time.now().unix() - passed_at >= 10 {
				write_json(root + '/fixture-result.json', {'passed': json2.Any(true), 'scope': json2.Any('unsupported account future/callback contract in guest ART'), 'quiet_seconds_after_pass': json2.Any(10), 'serial_sha256': json2.Any(digest(root + '/serial.log')!)})!
				println('ACCOUNT-CONTRACT-ART-PASS ten seconds after exact semantic marker')
				return
			}
		}
		time.sleep(250 * time.millisecond)
	}
	return error('ART fixture timed out')
}

fn ownership_test() ! {
	root := '/Users/alex/.local/state/vinix/android/account-contract-ownership-test-' + os.getpid().str()
	if os.exists(root) { return error('fresh ownership test directory required') }
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	mut sleeper := os.new_process('/bin/sleep')
	sleeper.set_args(['30'])
	sleeper.run()
	defer {
		if sleeper.is_alive() { sleeper.signal_term() }
		sleeper.wait()
		sleeper.close()
	}
	write_json(root + '/ownership.json', identity(sleeper.pid)!)!
	os.write_file(root + '/qemu.pid', sleeper.pid.str() + '\n')!
	mut rejected := false
	stop(root) or { rejected = true }
	if !rejected || !sleeper.is_alive() || os.exists(root + '/stop.json') { return error('unrelated process was not protected') }
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		assert !fixture_log('no begin')!
		assert fixture_log('APK-SUITE-BEGIN id=account-contract backend=vinix-ws\n' + fixture_pass)!
		for suffix in ['\njava.lang.AssertionError late', '\n' + fixture_pass, '\nAPK-SUITE-EXIT id=account-contract code=1', '\nVINIX-ACCOUNT-PASSWORD-SENTINEL-2026', '\nVINIX-ACCOUNT-USERDATA-SENTINEL-2026'] {
			fixture_log('APK-SUITE-BEGIN id=account-contract backend=vinix-ws\n' + fixture_pass + suffix) or { continue }
			panic('late fixture failure accepted')
		}
		ownership_test()!
		println('ACCOUNT-CONTRACT-RUN-SELF-TEST-PASS late errors, sentinels and duplicate markers rejected; unrelated process protected')
		return
	}
	if os.args.len < 3 { eprintln('usage: account-contract-run prepare ROOT BUILD [FIXTURE_APK] | start|stop|status|observe ROOT'); exit(2) }
	root := os.abs_path(os.args[2])
	match os.args[1] {
		'prepare' { if os.args.len !in [4, 5] { exit(2) }; prepare(root, os.abs_path(os.args[3]), if os.args.len == 5 { os.abs_path(os.args[4]) } else { '' }) or { eprintln(err); exit(1) } }
		'start' { start(root) or { eprintln(err); exit(1) } }
		'stop' { stop(root) or { eprintln(err); exit(1) } }
		'status' { println(json2.encode(owned(root) or { eprintln(err); exit(1) })) }
		'observe' { observe(root) or { eprintln(err); exit(1) } }
		else { exit(2) }
	}
}
