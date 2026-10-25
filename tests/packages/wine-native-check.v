// SPDX-License-Identifier: GPL-2.0-or-later
// Local signed Wine qualification. Publisher notices remain explicit inputs.
module main

import crypto.sha256
import hwhost
import json2
import os
import plainiso
import time
import tools.packages.pkgcore

fn digest(path string) !string {
	contents := os.read_file(path)!
	defer { unsafe { contents.free() } }
	return sha256.hexhash(contents)
}

fn invoke(arguments []string, log string) ! {
	os.write_file(log + '.argv.json', json2.encode(arguments))!
	mut child := os.new_process(arguments[0])
	defer { child.close() }
	child.set_args(arguments[1..])
	child.set_redirect_stdio_merged()
	child.run()
	C.close(child.stdio_fd[0])
	child.stdio_fd[0] = -1
	output := child.stdout_slurp()
	child.wait()
	defer { unsafe { output.free() } }
	os.write_file(log, output)!
	if child.code != 0 { return error('Wine qualification producer failed: ' + log) }
}

fn build_program(v string, sysroot string, gcc string, source string, arch string, work string, name string) !string {
	directory := work + '/build-' + name
	os.mkdir_all(directory)!
	root := hwhost.find_root(@FILE)!
	cfile := directory + '/' + name + '.c'
	invoke([v, '-backend', 'c', '-prod', '-os', 'linux', '-arch',
		if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-gc', 'none', '-manualfree',
		'-enable-globals', '-d', 'no_backtrace', '-d', 'no_segfault_handler', '-path',
		'@vlib|' + root + '|' + root + '/tools/accounts|@vmodules', '-o', cfile, source], directory + '/v.log')!
	vlib := os.dir(v) + '/vlib'
	os.write_file(directory + '/runtime.c', '#include <unistd.h>\n#include <fcntl.h>\n#include <sys/wait.h>\n#define V_OS_EXECUTE_SCOPE\n#include "' +
		vlib + '/os/execute_capture_nix.h"\n#define V_SYNC_THREAD_SCOPE\n#include "' + vlib + '/sync/thread_helper.h"\n')!
	invoke(['/opt/homebrew/opt/llvm/bin/clang', '--target=' + arch + '-linux-musl',
		'--sysroot=' + sysroot, '--gcc-install-dir=' + gcc, '-fuse-ld=lld', '-O1', '-w',
		'-fno-stack-protector', '-static', '-D_GNU_SOURCE', '-Wno-error=incompatible-pointer-types',
		cfile, directory + '/runtime.c', '-lm', '-lpthread', '-o', directory + '/' + name], directory + '/cc.log')!
	return directory + '/' + name
}

fn verify(inputs map[string]string) ! {
	for path, expected in inputs {
		if digest(path)! != expected { return error('Wine qualification input changed: ' + path) }
	}
}

fn check() ! {
	$if prod {
	} $else {
		return error('compile Wine native controller with -prod for embedded source admission')
	}
	if digest(@FILE)! != sha256.hexhash($embed_file('wine-native-check.v').to_string()) {
		return error('compiled Wine native controller source differs')
	}
	if os.args.len != 9 {
		return error('usage: wine-native-check ARCH OUTPUT PREPARED_BUILD KERNEL ASSEMBLED_STAGE SYSROOT GCC_RUNTIME SANDBOX')
	}
	arch := os.args[1]
	if arch !in ['aarch64', 'x86_64'] { return error('invalid Wine guest architecture') }
	work := os.abs_path(os.args[2])
	prepared := os.real_path(os.args[3])
	kernel := os.real_path(os.args[4])
	stage := os.real_path(os.args[5])
	sysroot := os.real_path(os.args[6])
	gcc := os.real_path(os.args[7])
	sandbox := os.real_path(os.args[8])
	if os.exists(work) { return error('Wine native output already exists') }
	os.mkdir_all(work)!
	root := hwhost.find_root(@FILE)!
	host := hwhost.find_host(root, arch, '')!
	mut inputs := map[string]string{}
	image_inputs := if arch == 'x86_64' { plainiso.inputs(root)! } else { map[string]string{} }
	for _, path in image_inputs { inputs[path] = digest(path)! }
	mut arm_loader := ''
	if arch == 'aarch64' {
		selected := os.getenv('VINIX_LIMINE_BOOTAA64')
		defer { unsafe { selected.free() } }
		arm_loader = os.real_path(if selected != '' {
			selected
		} else {
			hwhost.shared_path(root, 'boot-image/limine-bin/BOOTAA64.EFI')
		})
		inputs[arm_loader] = digest(arm_loader)!
		// Make the boot helper consume exactly the loader admitted above.
		os.setenv('VINIX_LIMINE_BOOTAA64', arm_loader, true)
		if host.firmware_vars == '' { return error('ARM firmware variable store is required') }
	} else if host.firmware_vars != '' {
		return error('x86 firmware variable store must be empty')
	}
	mut translator_original := ''
	mut translator_busybox := ''
	if arch == 'aarch64' {
		patch := json2.decode[map[string]string](os.read_file(prepared + '/translator-patch.json')!)!
		translator_original = os.real_path(patch['input'])
		translator_busybox = os.dir(os.dir(os.dir(translator_original))) + '/usr/libexec/vinix-x86_64/root/bin/busybox'
		inputs[translator_original] = digest(translator_original)!
		inputs[translator_busybox] = digest(translator_busybox)!
	}
	for path in [os.executable(), host.v, kernel, host.qemu, host.firmware, @FILE,
		root + '/tests/packages/wine-native/main.v', '/opt/homebrew/opt/llvm/bin/clang',
		'/opt/homebrew/bin/ld.lld', sandbox] {
		inputs[path] = digest(path)!
	}
	if host.firmware_vars != '' { inputs[host.firmware_vars] = digest(host.firmware_vars)! }
	for directory in [root + '/tools/packages', root + '/tools/accounts',
		root + '/tests/hardware-platform/hwhost', root + '/tests/hardware-platform/plainiso',
		os.dir(host.v) + '/vlib', os.dir(host.v) + '/thirdparty', sysroot + '/usr/include',
		sysroot + '/usr/lib', sysroot + '/lib', gcc, prepared] {
		for path in os.walk_ext(directory, '') {
			if os.is_file(path) { inputs[path] = digest(path)! }
		}
	}
	for name in ['usr/sbin/vinix-account', 'usr/sbin/vinix-session'] {
		inputs[stage + '/' + name] = digest(stage + '/' + name)!
	}
	os.write_file(work + '/inputs-before-build.json', json2.encode(inputs))!
	guest := build_program(host.v, sysroot, gcc, root + '/tests/packages/wine-native/main.v', arch, work, 'guest')!
	// Rebuild the package CLI from the captured tree. The archived account tools
	// are separate inputs; their stage's package CLI may predate runtime policy.
	package_cli := build_program(host.v, sysroot, gcc, root + '/tools/packages/main.v', arch, work, 'package')!
	// An owned local test key signs the real runtime. It is never copied into
	// the guest image or printed. This does not enroll a production publisher.
	publisher := work + '/publisher'
	seed := work + '/publisher-seed'
	key := pkgcore.keygen(seed)!
	for role in ['runtime', 'application']! {
		recipe_file := prepared + '/' + role + '.json'
		mut packed := pkgcore.pack_root(recipe_file, prepared + '/prepared/' + arch, publisher)!
		packed.close()
	}
	pkgcore.publish(publisher, 'wine-fixture', seed, 1, time.now().unix() + 86400)!
	extras := work + '/extras'
	for directory in ['/usr/bin', '/usr/sbin', '/etc/vinix', '/etc/vinix-packages',
		'/var/lib/vinix-packages'] {
		os.mkdir_all(extras + directory)!
	}
	for name in ['usr/sbin/vinix-account', 'usr/sbin/vinix-session'] {
		os.cp(stage + '/' + name, extras + '/' + name)!
	}
	os.cp(package_cli, extras + '/usr/bin/vinix-package')!
	os.cp(sandbox, extras + '/usr/bin/vinix-sandbox')!
	if arch == 'aarch64' {
		os.mkdir_all(extras + '/usr/libexec/wine-qualification')!
		os.cp(translator_original, extras + '/usr/libexec/wine-qualification/qemu-original')!
		os.cp(translator_busybox, extras + '/usr/libexec/wine-qualification/busybox')!
	}
	os.write_file(extras + '/etc/vinix/auth.conf', 'scrypt_ln = 10\nscrypt_p = 1\n')!
	config := pkgcore.Config{
		architecture: arch
		launch_user:  'alex'
		policy:       pkgcore.Policy{ offline: true, reserve_bytes: 0 }
		repositories: [pkgcore.Repository{ id: 'wine-fixture', url: 'file://' + publisher, public_key: key }]
	}
	os.write_file(extras + '/etc/vinix-packages/config.json', json2.encode(config))!
	service := pkgcore.Service{ root: extras }
	mut catalog := service.refresh()!
	catalog.close()
	mut state := service.transact('install', ['org.vinix.wine-win64-probe'], pkgcore.TransactionOptions{})!
	state.close()
	verify(inputs)!
	os.write_file(work + '/inputs.json', json2.encode(inputs))!
	mut generated := map[string]string{}
	for program in ['guest', 'package']! {
		for name in [program, program + '.c', 'runtime.c', 'v.log', 'v.log.argv.json', 'cc.log',
			'cc.log.argv.json'] {
			path := 'build-' + program + '/' + name
			generated[path] = digest(work + '/' + path)!
		}
	}
	for name in ['usr/bin/vinix-package', 'usr/sbin/vinix-account', 'usr/sbin/vinix-session',
		'usr/bin/vinix-sandbox', 'etc/vinix/auth.conf', 'etc/vinix-packages/config.json']! {
		generated['extras/' + name] = digest(extras + '/' + name)!
	}
	if arch == 'aarch64' {
		for name in ['qemu-original', 'busybox']! {
			generated['extras/usr/libexec/wine-qualification/' + name] = digest(extras + '/usr/libexec/wine-qualification/' + name)!
		}
	}
	os.write_file(work + '/generated-before-boot.json', json2.encode(generated))!
	os.write_file(work + '/declaration.json', json2.encode({
		'architecture':        arch
		'source_root':         root
		'run':                 work
		'prepared':            prepared
		'prepared_namespace':  prepared
		'compiler':            host.v
		'kernel':              kernel
		'qemu':                host.qemu
		'firmware':            host.firmware
		'firmware_vars':       host.firmware_vars
		'arm_loader':          arm_loader
		'stage':               stage
		'sysroot':             sysroot
		'gcc_runtime':         gcc
		'sandbox':             sandbox
		'controller':          os.executable()
		'iso_xorriso':         image_inputs['iso-xorriso']
		'iso_bootx64':         image_inputs['iso-BOOTX64.EFI']
		'iso_limine_cd':       image_inputs['iso-limine-uefi-cd.bin']
		'translator_original': translator_original
		'translator_busybox':  translator_busybox
	}))!
	scenario := hwhost.Scenario{
		name:        'packaged-Wine'
		arches:      [arch]
		qemu_x86_64: ['-cpu', 'max']
		required:    [
			'Wine signed-real-Win64 ordinary-private-prefix socket lease Windows-API outside-write-refused natural-exit PASS',
			'HWTEST PASS packaged-Wine',
		]
		forbidden:   ['HWTEST FAIL', 'Kernel panic', 'KERNEL PANIC', 'FATAL EXCEPTION']
		ending:      .running
	}
	runtime_host := if arch == 'x86_64' {
		hwhost.Host{ ...host, root: plainiso.prepare(root, work)! }
	} else {
		host
	}
	outcome := hwhost.run_scenario(runtime_host, scenario, hwhost.Run{ kernel: kernel, guest: guest, extras: extras, state: work + '/boot', timeout: 600, keep: true })
	os.write_file(work + '/result.json', json2.encode(outcome))!
	verify(inputs)!
	for path, expected in generated {
		if digest(work + '/' + path)! != expected {
			return error('Wine generated output changed: ' + path)
		}
	}
	os.write_file(work + '/inputs-verified.json', json2.encode(inputs))!
	if digest(@FILE)! != sha256.hexhash($embed_file('wine-native-check.v').to_string()) {
		return error('compiled Wine native controller source changed')
	}
	if !outcome.passed || outcome.interrupted || outcome.reason != '' {
		return error('native Wine failed: ' + outcome.reason)
	}
	println('WINE NATIVE PASS ' + arch + ': ' + work)
}

fn main() {
	if plainiso.requested() {
		plainiso.build() or {
			eprintln(err)
			exit(1)
		}
		return
	}
	check() or {
		eprintln(err)
		exit(1)
	}
}
