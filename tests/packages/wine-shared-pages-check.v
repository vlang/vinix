// SPDX-License-Identifier: GPL-2.0-or-later
// Diagnostic only: native versus translated shared-file mappings on 16 KiB ARM.
module main

import crypto.sha256
import hwhost
import json2
import os
import tests.packages.winesource

fn digest(path string) !string { return winesource.file_digest(path) }

fn invoke(args []string, log string) ! {
	os.write_file(log + '.argv.json', json2.encode(args))!
	hwhost.run_tool(args, map[string]string{}, log, 300)!
}

fn run() ! {
	if os.args.len != 9 { return error('usage: wine-shared-pages-check OUTPUT KERNEL ARM_SYSROOT ARM_GCC X86_SYSROOT X86_GCC TRANSLATOR CLANG (V=compiler)') }
	root := os.real_path(os.dir(@FILE) + '/../..'); work := os.abs_path(os.args[1])
	if os.exists(work) || os.is_link(work) { return error('shared-page output must be fresh') }
	for path, source in { @FILE: $embed_file('wine-shared-pages-check.v').to_string(),
		root + '/tests/packages/wine-shared-pages/main.v': $embed_file('wine-shared-pages/main.v').to_string() } {
		if digest(path)! != sha256.hexhash(source) { return error('compiled shared-page source differs') }
	}
	v := os.getenv_opt('V') or { return error('set V to compiler') }
	kernel := os.real_path(os.args[2]); translator := os.real_path(os.args[7]); clang := os.real_path(os.args[8])
	if digest(translator)! != '21bbd59fb9be632214a1c0fcc73624bf568ea525dd11762513a1faa0334eca83' { return error('requires exact fork-safe translator') }
	host := hwhost.find_host(root, 'aarch64', '')!
	mut inputs := map[string]string{}
	for path in [@FILE, root + '/tests/packages/wine-shared-pages/main.v', os.executable(), v, kernel, translator,
		clang, host.qemu, host.firmware, host.firmware_vars, root + '/boot-image/limine-bin/BOOTAA64.EFI'] {
		if path != '' { inputs[path] = digest(path)! }
	}
	os.mkdir_all(work)!
	extras := work + '/extras'; os.mkdir_all(extras)!
	for index, arch in ['aarch64', 'x86_64'] {
		build := work + '/build-' + arch; os.mkdir_all(build)!
		mut command := [v, '-backend', 'c', '-prod', '-os', 'linux', '-arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' },
			'-gc', 'none', '-manualfree', '-d', 'no_backtrace', '-d', 'no_segfault_handler', '-o', build + '/probe.c', root + '/tests/packages/wine-shared-pages']
		mut discovery := command.clone(); discovery.insert(1, ['-print-watched-files', '-dump-files', build + '/sources-before.txt'])
		invoke(discovery, build + '/discover.log')!
		winesource.capture(build + '/sources-before.txt', mut inputs)!
		os.write_file(work + '/inputs-before-' + arch + '.json', json2.encode(inputs))!
		command.insert(1, ['-dump-files', build + '/sources-built.txt']); invoke(command, build + '/v.log')!
		winesource.admit(build + '/sources-before.txt', build + '/sources-built.txt', inputs)!
		name := if arch == 'aarch64' { 'probe-native' } else { 'probe-x86' }
		invoke([clang, '--target=' + arch + '-linux-musl', '--sysroot=' + os.args[3 + index * 2], '--gcc-install-dir=' + os.args[4 + index * 2],
			'-fuse-ld=lld', '-static', '-O2', '-w', '-D_GNU_SOURCE', '-fno-stack-protector', build + '/probe.c', '-lm', '-lpthread', '-o', extras + '/' + name], build + '/cc.log')!
	}
	os.cp(translator, extras + '/qemu-x86_64')!; os.chmod(extras + '/qemu-x86_64', 0o755)!
	for path, expected in inputs { if digest(path)! != expected { return error('shared-page input changed before boot') } }
	os.write_file(work + '/inputs.json', json2.encode(inputs))!
	mut generated := map[string]string{}
	for path in os.walk_ext(work, '', hidden: true) {
		if os.is_file(path) { generated[path[work.len + 1..]] = digest(path)! }
	}
	os.write_file(work + '/generated-before-boot.json', json2.encode(generated))!
	outcome := hwhost.run_scenario(host, hwhost.Scenario{name: 'shared-page-diagnostic', arches: ['aarch64'], ending: .running,
		required: ['SHARED-PAGES PASS native pagesize=16384 six ordinary mapping controls; diagnostic only',
			'SHARED-PAGES PASS translated pagesize=4096 six ordinary mapping controls; diagnostic only', 'HWTEST PASS shared-page-diagnostic'],
		forbidden: ['HWTEST FAIL', 'SHARED-PAGES FAIL', 'Kernel panic']},
		hwhost.Run{kernel: kernel, guest: extras + '/probe-native', extras: extras, state: work + '/boot', timeout: 120, keep: true})
	os.write_file(work + '/result.json', json2.encode(outcome))!
	for path, expected in inputs { if digest(path)! != expected { return error('shared-page input changed after boot') } }
	for path, expected in generated { if digest(work + '/' + path)! != expected { return error('shared-page generated output changed') } }
	os.write_file(work + '/inputs-verified.json', json2.encode(inputs))!
	os.write_file(work + '/scope.txt', 'Ordinary native/translated mapping diagnostic on selected kernel and exact fork-safe translator. Selected tools and actual V source closure only; complete C headers/libraries/compiler closure, pledge/unveil, Wine execution, package admission and hermetic builds are not qualified. No W+X waiver; translator starts as uid/gid 1000.\n')!
	if !outcome.passed || outcome.interrupted { return error('shared-page diagnostic failed: ' + outcome.reason) }
	println('SHARED PAGE DIAGNOSTIC PASS native/translated twelve controls; no Wine or package qualification')
}

fn main() { run() or { eprintln(err); exit(1) } }
