// SPDX-License-Identifier: GPL-2.0-or-later
// Add a signed calculator to an independently admitted console runtime.
module main

import crypto.sha256
import hwhost
import json2
import os
import plainiso
import stbi
import time
import tests.packages.winesource
import tests.packages.winegui
import tools.packages.pkgcore
import tools.packages.wineadapter

struct BaselineReceipt {
	artifact_paths map[string]string
	artifacts map[string]string
}

fn digest(path string) !string { return winesource.file_digest(path) }

fn invoke(args []string, log string) ! {
	os.write_file(log + '.argv.json', json2.encode(args))!
	hwhost.run_tool(args, map[string]string{}, log, 600)!
}

fn verify(inputs map[string]string) ! {
	for path, expected in inputs {
		if digest(path)! != expected { return error('GUI input changed: ' + path) }
	}
}

fn copy_input(source string, target string, mut inputs map[string]string) ! {
	inputs[source] = digest(source)!
	os.mkdir_all(os.dir(target))!; os.cp(source, target)!
	if digest(target)! != inputs[source] { return error('GUI copy differs: ' + source) }
}

fn dependencies(binary string, roots []string, extras string, work string, mut inputs map[string]string) ! {
	mut queue := [binary]
	mut seen := map[string]bool{}
	for queue.len > 0 {
		path := queue.pop()
		if path in seen { continue }
		seen[path] = true
		inputs[path] = digest(path)!
		log := work + '/needed-' + os.base(binary) + '-' + seen.len.str() + '.log'
		invoke(['/opt/homebrew/opt/llvm/bin/llvm-readelf', '-d', path], log)!
		for line in os.read_file(log)!.split_into_lines() {
			if !line.contains('(NEEDED)') { continue }
			name := line.all_after('[').all_before(']')
			if name == '' || name.contains('/') { return error('invalid GUI ELF dependency') }
			mut source := ''
			for root in roots {
				for dir in ['/lib/', '/usr/lib/']! {
					if source == '' && os.is_file(root + dir + name) { source = root + dir + name }
				}
			}
			if source == '' { return error('missing GUI dependency: ' + name) }
			target := extras + '/usr/lib/' + name
			if !os.exists(target) { copy_input(source, target, mut inputs)! }
			queue << source
		}
	}
}

fn baseline(retainer string, run string, prepared string, arch string, out string, log string) ! {
	mut args := [retainer, run, prepared, arch, out]
	if arch == 'aarch64' { args << '--forksafe-translator' }
	invoke(args, log)!
}

fn check() ! {
	$if prod {} $else { return error('compile GUI controller with -prod') }
	if os.args.len != 12 { return error('usage: wine-gui-check ARCH OUTPUT BASELINE_RUN PREPARED PE RETAINER KERNEL SYSROOT GCC_RUNTIME X11_STAGE SHELL (V=compiler)') }
	root := hwhost.find_root(@FILE)!
	for path, source in {
		@FILE: $embed_file('wine-gui-check.v').to_string()
		root + '/tests/packages/wine-gui/main.v': $embed_file('wine-gui/main.v').to_string()
		root + '/tests/packages/winegui/frame.v': $embed_file('winegui/frame.v').to_string()
		root + '/tests/packages/winesource/closure.v': $embed_file('winesource/closure.v').to_string()
		root + '/tests/hardware-platform/plainiso/iso.v': plainiso.source()
	} {
		if digest(path)! != sha256.hexhash(source) { return error('compiled GUI source differs: ' + path) }
	}
	arch := os.args[1]
	if arch !in ['x86_64', 'aarch64'] { return error('invalid GUI architecture') }
	work := os.abs_path(os.args[2]); original := os.real_path(os.args[3]); prepared := os.real_path(os.args[4])
	pe_dir := os.real_path(os.args[5]); retainer := os.real_path(os.args[6]); kernel := os.real_path(os.args[7])
	sysroot := os.real_path(os.args[8]); gcc := os.real_path(os.args[9]); x11 := os.real_path(os.args[10])
	shell := os.real_path(os.args[11])
	if os.exists(work) || os.is_link(work) { return error('GUI output must be fresh') }
	mut pe := wineadapter.admit_local_pe_proof(pe_dir, root + '/tests/packages/wine-calculator/program.v', root + '/tests/packages/wine-pe-check.v')!
	defer { pe.close() }
	os.mkdir_all(work)!
	baseline(retainer, original, prepared, arch, work + '/baseline-before', work + '/baseline-before.log')!
	receipt := json2.decode[BaselineReceipt](os.read_file(work + '/baseline-before/wine-' + arch + '.json')!)!
	mut inputs := map[string]string{}
	for key, path in receipt.artifact_paths { inputs[path] = receipt.artifacts[key] }
	for path, hash in pe.artifacts { inputs[path] = hash }
	v := os.getenv_opt('V') or { return error('set V to the compiler') }
	host := hwhost.find_host(root, arch, '')!
	for path in [@FILE, os.executable(), retainer, v, kernel, host.qemu, host.firmware,
		'/opt/homebrew/opt/llvm/bin/clang', '/opt/homebrew/opt/llvm/bin/llvm-readelf',
		root + '/tests/packages/wine-gui/main.v', root + '/tests/packages/winegui/frame.v'] {
		inputs[path] = digest(path)!
	}
	if host.firmware_vars != '' { inputs[host.firmware_vars] = digest(host.firmware_vars)! }
	if arch == 'x86_64' { for _, path in plainiso.inputs(root)! { inputs[path] = digest(path)! } }
	else { inputs[root + '/boot-image/limine-bin/BOOTAA64.EFI'] = digest(root + '/boot-image/limine-bin/BOOTAA64.EFI')! }
	build := work + '/build-guest'; os.mkdir_all(build)!
	mut vargs := [v, '-backend', 'c', '-prod', '-os', 'linux', '-arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' },
		'-gc', 'none', '-manualfree', '-d', 'no_backtrace', '-d', 'no_segfault_handler',
		'-path', '@vlib|' + root + '|@vmodules', '-o', build + '/guest.c', root + '/tests/packages/wine-gui']
	diagnostic := os.getenv('VINIX_GUI_DIAGNOSTIC_NUMERIC_HOSTNAME') == '1'
	if diagnostic { vargs.insert(1, ['-d', 'wine_gui_numeric_hostname']) }
	mut discovery := vargs.clone(); discovery.insert(1, ['-print-watched-files', '-dump-files', build + '/sources-before.txt'])
	invoke(discovery, build + '/discover.log')!
	winesource.capture(build + '/sources-before.txt', mut inputs)!
	os.write_file(work + '/inputs-before-build.json', json2.encode(inputs))!
	vargs.insert(1, ['-dump-files', build + '/sources-built.txt'])
	invoke(vargs, build + '/v.log')!
	winesource.admit(build + '/sources-before.txt', build + '/sources-built.txt', inputs)!
	copy_input(original + '/build-guest/runtime.c', build + '/runtime.c', mut inputs)!
	invoke(['/opt/homebrew/opt/llvm/bin/clang', '--target=' + arch + '-linux-musl', '--sysroot=' + sysroot,
		'--gcc-install-dir=' + gcc, '-fuse-ld=lld', '-static-libgcc', '-O1', '-w', '-D_GNU_SOURCE',
		'-fno-stack-protector', '-Wno-error=incompatible-pointer-types', '-L' + sysroot + '/lib',
		'-L' + sysroot + '/usr/lib', '-Wl,-rpath-link,' + sysroot + '/lib', '-Wl,-rpath-link,' + sysroot + '/usr/lib',
		build + '/guest.c', build + '/runtime.c', '-lm', '-lpthread', '-lX11', '-lXtst', '-o', build + '/guest'], build + '/cc.log')!
	extras := work + '/extras'
	for dir in ['/bin', '/usr/bin', '/usr/sbin', '/lib', '/usr/lib', '/etc/vinix', '/etc/vinix-packages'] { os.mkdir_all(extras + dir)! }
	copy_input(shell, extras + '/bin/sh', mut inputs)!
	dependencies(shell, [sysroot, x11], extras, work, mut inputs)!
	for name in ['usr/sbin/vinix-account', 'usr/sbin/vinix-session', 'usr/bin/vinix-package', 'usr/bin/vinix-sandbox']! {
		path := original + '/extras/' + name
		if path !in inputs { return error('baseline executable was not admitted: ' + name) }
		copy_input(path, extras + '/' + name, mut inputs)!
	}
	for name in ['Xvfb', 'xkbcomp']! {
		copy_input(x11 + '/usr/bin/' + name, extras + '/usr/bin/' + name, mut inputs)!
		dependencies(x11 + '/usr/bin/' + name, [sysroot, x11], extras, work, mut inputs)!
	}
	dependencies(build + '/guest', [sysroot, x11], extras, work, mut inputs)!
	copy_input(sysroot + '/lib/ld-musl-' + arch + '.so.1', extras + '/lib/ld-musl-' + arch + '.so.1', mut inputs)!
	for dir in ['/usr/share/X11/xkb', '/usr/share/fonts/misc']! {
		for path in os.walk_ext(x11 + dir, '') {
			if os.is_file(path) { copy_input(path, extras + path[x11.len..], mut inputs)! }
		}
	}
	payload := work + '/payload'
	copy_input(pe.executable, payload + '/application/bin/program.exe', mut inputs)!
	copy_input(prepared + '/prepared/' + arch + '/application/licenses/application-LICENSE.txt', payload + '/application/licenses/application-LICENSE.txt', mut inputs)!
	mut recipe := json2.decode[map[string]json2.Any](os.read_file(prepared + '/application.json')!)!
	manifest_value := recipe['manifest'] or { return error('application manifest missing') }
	mut manifest := manifest_value.as_map().clone()
	manifest['id'] = 'org.vinix.wine-calculator'; manifest['name'] = 'Wine calculator graphical qualification'
	manifest['permissions'] = [json2.Any('process'), json2.Any('display')]
	recipe['manifest'] = manifest
	os.write_file(work + '/application.json', json2.encode(recipe))!
	publisher := work + '/publisher'; seed := work + '/publisher-seed'
	key := pkgcore.keygen(seed)!
	mut runtime := pkgcore.pack_root(prepared + '/runtime.json', prepared + '/prepared/' + arch, publisher)!
	runtime.close()
	mut application := pkgcore.pack_root(work + '/application.json', payload, publisher)!
	application.close()
	pkgcore.publish(publisher, 'wine-gui', seed, 1, time.now().unix() + 86400)!
	os.write_file(extras + '/etc/vinix/auth.conf', 'scrypt_ln = 10\nscrypt_p = 1\n')!
	os.write_file(extras + '/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{
		architecture: arch, launch_user: 'alex', policy: pkgcore.Policy{offline: true, reserve_bytes: 0},
		repositories: [pkgcore.Repository{id: 'wine-gui', url: 'file://' + publisher, public_key: key}]
	}))!
	service := pkgcore.Service{root: extras}
	mut catalog := service.refresh()!; catalog.close()
	mut state := service.transact('install', ['org.vinix.wine-calculator'], pkgcore.TransactionOptions{})!
	if state.generation != 1 || state.packages.len != 2 { return error('unexpected GUI signed closure') }
	state.close()
	verify(inputs)!
	os.write_file(work + '/inputs.json', json2.encode(inputs))!
	mut generated := map[string]string{}
	generated['application.json'] = digest(work + '/application.json')!
	for dir in [build, extras] {
		for path in os.walk_ext(dir, '', hidden: true) {
			if os.is_file(path) { generated[path[work.len + 1..]] = digest(path)! }
		}
	}
	os.write_file(work + '/generated-before-boot.json', json2.encode(generated))!
	os.write_file(work + '/declaration.json', json2.encode({
		'architecture': arch, 'baseline': original, 'prepared': prepared, 'pe': pe_dir,
		'retainer': retainer, 'kernel': kernel, 'sysroot': sysroot, 'gcc': gcc, 'x11': x11,
		'compiler': v, 'controller': os.executable(), 'source_root': root, 'run': work, 'shell': shell
		'diagnostic': if diagnostic { 'numeric-hostname' } else { '' }
	}))!
	boot_host := if arch == 'x86_64' { hwhost.Host{...host, root: plainiso.prepare(root, work)!} } else { host }
	result := hwhost.run_scenario(boot_host, hwhost.Scenario{
		name: 'packaged-Wine-GUI', arches: [arch], qemu_x86_64: ['-cpu', 'max'], ending: .running,
		required: ['HWTEST PASS packaged-Wine-GUI'], forbidden: ['HWTEST FAIL', 'WINE GUI FAIL', 'Kernel panic']
	}, hwhost.Run{kernel: kernel, guest: build + '/guest', extras: extras, state: work + '/boot', timeout: 600, keep: true})
	os.write_file(work + '/result.json', json2.encode(result))!
	verify(inputs)!
	for path, expected in generated { if digest(work + '/' + path)! != expected { return error('GUI generated output changed: ' + path) } }
	os.write_file(work + '/inputs-verified.json', json2.encode(inputs))!
	if !result.passed || result.interrupted { return error('Wine GUI target failed: ' + result.reason) }
	serial := os.read_file(work + '/boot/serial.log')!
	mut frames := []winegui.Frame{}
	for line in serial.split_into_lines() {
		if line.trim_space().starts_with('WINE GUI FRAME ') { frames << winegui.decode_frame(line.trim_space())! }
	}
	if frames.len != 2 || frames[0].name != 'before' || frames[1].name != 'after'
		|| frames[0].width != frames[1].width || frames[0].height != frames[1].height
		|| frames[0].rgb == frames[1].rgb { return error('Wine GUI captured images differ from contract') }
	for frame in frames {
		stbi.stbi_write_png(work + '/' + frame.name + '.png', frame.width, frame.height, 3, frame.rgb.data, frame.width * 3)!
	}
	baseline(retainer, original, prepared, arch, work + '/baseline-after', work + '/baseline-after.log')!
	mut checked_pe := wineadapter.admit_local_pe_proof(pe_dir, root + '/tests/packages/wine-calculator/program.v', root + '/tests/packages/wine-pe-check.v')!
	checked_pe.close()
	println('WINE GUI PASS ' + arch + ': signed USER32 paint, XTest pointer arithmetic and natural close')
}

fn main() {
	if plainiso.requested() { plainiso.build() or { eprintln(err); exit(1) }; return }
	check() or { eprintln(err); exit(1) }
}
