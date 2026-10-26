// SPDX-License-Identifier: GPL-2.0-or-later
// Build a retained signed native publisher, then run real account-seat guests.
module main

import crypto.sha256
import hwhost
import json2
import os
import time
import tests.packages.audioinputs
import tools.packages.pkgcore

const source_trees = ['tools/packages', 'tools/accounts', 'tools/security-events', 'tools/keyring',
	'tools/sandbox', 'build-support/native-compat-tools/compathost', 'tests/qemu-core/fixturehost',
	'tests/native-guest-tools/guesthost', 'tests/linuxkpi/hosttest', 'tests/native-policy-tools/nativepolicy',
	'tests/host-policy/policyhost', 'tests/hardware-platform/hwhost',
	'tests/packages/audio-portal-guest', 'tests/packages/audio-portal-tone', 'tests/packages/audiotest',
	'tests/packages/audioinputs']
const source_files = ['tests/packages/audio-portal-runtime-check.v',
	'tests/packages/audio-portal-retain.v', 'tests/packages/audio-portal-evidence-check.v',
	'tests/packages/audio-portal-wave-check.v', 'build-support/native-compat-tools/main.v',
	'build-support/security-tools/compile-v-core',
	'build-support/run-v-tool.sh', 'build-support/find-v.sh', 'tests/packages/audio-cross-cc.v',
	'tests/packages/audio-input-check.v', 'tests/packages/audio-cross-probe.v']
const generated_files = ['guest-build/init.c', 'tone-build/tone.c',
	'tools/program-0/vinix-package.c', 'tools/program-1/vinix-account.c',
	'tools/program-2/vinix-session.c', 'tools/program-3/vinix-authd.c']

struct Qualification {
	format          int = 1
	architecture    string
	platform        string = 'qemu-native-audio-ordinary-account-seat'
	result          string = 'PASS'
	completed_at    i64
	source_root     string
	source_revision string
	sources         map[string]string
	artifacts       map[string]string
	artifact_paths  map[string]string
}

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn invoke(args []string, log string) !string {
	hwhost.run_tool(args, map[string]string{}, log, 300)!
	return os.read_file(log)
}

fn files(root string) ![]string {
	mut result := []string{}
	for name in os.ls(root)! {
		path := root + '/' + name
		info := os.lstat(path)!
		if info.mode & 0o170000 == 0o040000 {
			for sub in files(path)! { result << name + '/' + sub }
		} else if info.mode & 0o170000 == 0o100000 {
			result << name
		} else {
			return error('source tree contains nonregular entry: ${path}')
		}
	}
	result.sort()
	return result
}

fn source_inventory(root string) !map[string]string {
	mut result := map[string]string{}
	for tree in source_trees {
		for name in files(root + '/' + tree)! {
			if name.ends_with('_test.v') { continue }
			result[tree + '/' + name] = digest(root + '/' + tree + '/' + name)!
		}
	}
	for name in source_files { result[name] = digest(root + '/' + name)! }
	return result
}

fn write_json(path string, values map[string]string) ! {
	os.write_file(path, json2.encode(values) + '\n')!
}

fn retained(original string, out string, name string) !string {
	path := out + '/inputs/' + name
	os.mkdir_all(os.dir(path))!
	expected := digest(original)!
	store := os.dir(out) + '/audio-input-store'
	os.mkdir_all(store)!
	copy := store + '/' + expected
	if !os.exists(copy) { os.cp(original, copy)! }
	if digest(copy)! != expected { return error('input store digest mismatch: ' + name) }
	os.link(copy, path)!
	if digest(original)! != digest(path)! { return error('input copy changed: ${original}') }
	return path
}

fn retain_tree(directory string, prefix string, out string, ancestors []string,
	mut paths map[string]string, mut originals map[string]string) ! {
	canonical := os.real_path(directory)
	if canonical in ancestors || ancestors.len > 32 { return error('cyclic build input: ' + directory) }
	mut chain := ancestors.clone()
	chain << canonical
	for name in os.ls(directory)! {
		path := directory + '/' + name
		key := prefix + '/' + name
		if os.is_dir(path) { retain_tree(path, key, out, chain, mut paths, mut originals)! }
		else {
			real := os.real_path(path)
			if (os.lstat(real)!).mode & 0o170000 != 0o100000 { return error('nonregular build input: ' + path) }
			paths[key] = retained(real, out, key)!
			originals[key] = real
		}
	}
}

fn publisher(root string, host hwhost.Host, out string) !string {
	payload := out + '/inputs/payload'
	os.mkdir_all(payload + '/bin')!
	tone := hwhost.build_program_with_flags(host, root + '/tests/packages/audio-portal-tone', out + '/tone-build', 'tone', ['.'], ['-prod'])!
	os.cp(tone, payload + '/bin/tone')!
	os.chmod(payload + '/bin/tone', 0o755)!
	key := pkgcore.keygen(out + '/inputs/signing-seed')!
	for id in ['tone', 'noaudio'] {
		manifest := pkgcore.Package{
			id:           id
			version:      '1.0.0'
			architecture: host.arch
			name:         'Audio portal fixture'
			license:      'GPL-2.0-or-later'
			kind:         'native'
			entrypoint:   'bin/tone'
			permissions:  if id == 'tone' { ['audio'] } else { []string{} }
		}
		path := out + '/inputs/' + id + '.json'
		os.write_file(path, json2.encode(manifest))!
		pkgcore.pack(path, payload, out + '/inputs/publisher')!
	}
	pkgcore.publish(out + '/inputs/publisher', 'audio-fixture', out + '/inputs/signing-seed', 1, time.now().unix() + 86400)!
	os.write_file(out + '/inputs/public-key', key + '\n')!
	return key
}

fn sandbox_build(root string, host hwhost.Host, out string, compiler string) !string {
	directory := out + '/sandbox-build'
	os.mkdir_all(directory)!
	source := directory + '/sandbox.c'
	invoke([root + '/build-support/security-tools/compile-v-core', 'sandbox', source,
		'--arch', if host.arch == 'aarch64' { 'arm64' } else { 'amd64' }], directory + '/generate.log')!
	mut args := [compiler]
	if host.arch == 'aarch64' {
		sysroot := os.getenv_opt('VINIX_AARCH64_SYSROOT') or { hwhost.shared_path(root, 'build-aarch64-userland/sysroot') }
		args << ['--target=aarch64-linux-musl', '--sysroot=' + sysroot, '-L' + sysroot + '/lib', '-fuse-ld=lld']
	}
	args << ['-static', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-D_GNU_SOURCE',
		'-DVINIX_V_RUNTIME', '-I', out + '/inputs/source/tools/sandbox', source, '-o', directory + '/vinix-sandbox']
	invoke(args, directory + '/build.log')!
	return directory + '/vinix-sandbox'
}

fn cross_inputs(host hwhost.Host, out string, mut paths map[string]string,
	mut originals map[string]string) !string {
	backend_name := os.getenv_opt('VINIX_AUDIO_BACKEND_CC') or { host.arch + '-linux-musl-gcc' }
	backend := if backend_name.contains('/') { os.real_path(backend_name) } else { os.find_abs_path_of_executable(backend_name)! }
	paths['cross-backend'] = retained(backend, out, 'cross-backend')!
	originals['cross-backend'] = os.real_path(backend)
	sysroot := invoke([backend, '-print-sysroot'], out + '/cross-sysroot.log')!.trim_space()
	libgcc := invoke([backend, '-print-libgcc-file-name'], out + '/cross-libgcc.log')!.trim_space()
	if !os.is_abs_path(sysroot) || !os.is_abs_path(libgcc) { return error('cross compiler must report absolute sysroot and libgcc') }
	snapshot := audioinputs.snapshot(sysroot)!
	for name, original in snapshot.files {
		key := 'cross-sysroot/' + name
		paths[key] = retained(original, out, key)!
		originals[key] = original
	}
	for name, values in {'files': snapshot.files, 'links': snapshot.links, 'root': {'root': snapshot.root}} {
		path := out + '/cross-sysroot-' + name + '.json'
		write_json(path, values)!
		paths['cross-sysroot-' + name] = path
	}
	retain_tree(os.dir(libgcc), 'cross-gcc', out, [], mut paths, mut originals)!
	for tool in ['cc1', 'collect2', 'as', 'ld', 'lto-wrapper'] {
		candidate := invoke([backend, '-print-prog-name=' + tool], out + '/cross-' + tool + '.log')!.trim_space()
		path := if candidate.contains('/') { os.real_path(candidate) } else { os.find_abs_path_of_executable(candidate)! }
		paths['cross-' + tool] = retained(path, out, 'cross-' + tool)!
		originals['cross-' + tool] = path
	}
	plugin := invoke([backend, '-print-prog-name=liblto_plugin.so'], out + '/cross-lto-plugin.log')!.trim_space()
	if !os.is_abs_path(plugin) { return error('GCC LTO plugin must have an absolute path') }
	paths['cross-lto-plugin'] = retained(plugin, out, 'cross-lto-plugin')!
	originals['cross-lto-plugin'] = os.real_path(plugin)
	frozen := out + '/inputs/cross-sysroot'
	os.setenv('VINIX_AUDIO_BACKEND_CC', backend, true)
	os.setenv('VINIX_AUDIO_FROZEN_SYSROOT', frozen, true)
	os.setenv('VINIX_AUDIO_FROZEN_GCC', out + '/inputs/cross-gcc', true)
	os.setenv('VINIX_AARCH64_SYSROOT', frozen, true)
	host_cc := os.real_path('/opt/homebrew/opt/llvm/bin/clang')
	paths['adapter-host-cc'] = retained(host_cc, out, 'adapter-host-cc')!
	originals['adapter-host-cc'] = host_cc
	adapter := out + '/cross-cc'
	invoke([host.v, '-prod', '-backend', 'c', '-cc', host_cc,
		'-o', adapter, host.root + '/tests/packages/audio-cross-cc.v'], out + '/cross-adapter-build.log')!
	paths['cross-adapter'] = adapter
	paths['cross-adapter-build'] = out + '/cross-adapter-build.log'
	invoke([host.v, '-os', 'linux', '-arch', if host.arch == 'aarch64' { 'arm64' } else { 'amd64' },
		'-gc', 'none', '-d', 'no_backtrace', '-d', 'no_segfault_handler', '-prod',
		'-o', out + '/cross-probe.c', host.root + '/tests/packages/audio-cross-probe.v'],
		out + '/cross-probe-generate.log')!
	invoke([adapter, '-v', '-static', '-O1', '-w', '-D_GNU_SOURCE', '-fno-stack-protector',
		out + '/cross-probe.c', '-o', out + '/cross-probe', '-lm', '-lpthread'], out + '/cross-search.log')!
	if !os.read_file(out + '/cross-search.log')!.contains('--sysroot=' + frozen) {
		return error('GCC trace did not record frozen sysroot')
	}
	for name in ['cross-probe.c', 'cross-probe', 'cross-probe-generate.log', 'cross-search.log'] { paths[name] = out + '/' + name }
	return adapter
}

fn verify_sysroot(out string) ! {
	root := json2.decode[map[string]string](os.read_file(out + '/cross-sysroot-root.json')!)!['root']
	now := audioinputs.snapshot(root)!
	for name, actual in {'files': now.files, 'links': now.links} {
		before := json2.decode[map[string]string](os.read_file(out + '/cross-sysroot-' + name + '.json')!)!
		if actual != before { return error('original sysroot inventory changed: ' + name) }
	}
}

fn audio_suite(root string, out string, arch string, sandbox string, key string) !hwhost.Suite {
	config := pkgcore.Config{
		architecture: arch
		launch_user:  'sam'
		repositories: [pkgcore.Repository{ id: 'audio-fixture', url: 'file:///usr/share/audio-publisher', public_key: key }]
		policy:       pkgcore.Policy{ offline: true, reserve_bytes: 0 }
	}
	os.write_file(out + '/inputs/config.json', json2.encode(config))!
	mut entries := [
		hwhost.RootFile{ path: 'etc/passwd', text: 'root:x:0:0:root:/root:/bin/sh\n' },
		hwhost.RootFile{ path: 'etc/group', text: 'root:x:0:\ntty:x:5:\n' },
		hwhost.RootFile{ path: 'etc/vinix/auth.conf', text: 'scrypt_ln = 10\n' },
		hwhost.RootFile{ path: 'etc/vinix-packages/config.json', text: json2.encode(config) },
	]
	for name in files(out + '/inputs/publisher')! {
		entries << hwhost.RootFile{ path: 'usr/share/audio-publisher/' + name, text: os.read_file(out + '/inputs/publisher/' + name)! }
	}
	for name in files(root + '/tools/accounts/actions')! {
		entries << hwhost.RootFile{ path: 'usr/share/vinix/actions/' + name, text: os.read_file(root + '/tools/accounts/actions/' + name)! }
	}
	mut scenarios := []hwhost.Scenario{}
	for name in ['basic', 'lifecycle', 'seat'] {
		full := 'packages-audio-' + name
		scenarios << hwhost.Scenario{
			name:         full
			arches:       ['aarch64', 'x86_64']
			about:        'signed native PCM through ordinary real account seat'
			required:     ['HWTEST START ' + full, 'AUDIO SETUP signed tone and noaudio installed PASS',
				'HWTEST PASS ' + full]
			forbidden:    ['AUDIO PAYLOAD FAIL', 'AUDIO LOGIN FAIL']
			ending:       .poweroff
			timeout:      240
			qemu:         ['-audiodev',
				'wav,id=pcm,path={state}/sound.wav,out.frequency=48000,out.channels=2,out.format=s16']
			qemu_aarch64: ['-device', 'virtio-sound-device,audiodev=pcm,streams=1']
			qemu_x86_64:  ['-device', 'intel-hda', '-device', 'hda-output,audiodev=pcm,mixer=off']
		}
	}
	return hwhost.Suite{
		name:         'package-audio-portal'
		guest:        'tests/packages/audio-portal-guest'
		module_paths: ['.', 'tools/accounts', 'tools/security-events', 'tools/keyring']
		programs:     [
			hwhost.Program{ source: 'tools/packages/main.v', path: 'usr/bin/vinix-package', flags: ['-prod'] },
			hwhost.Program{ source: 'tools/accounts/account.v', path: 'usr/sbin/vinix-account', flags: ['-prod'] },
			hwhost.Program{ source: 'tools/accounts/session.v', path: 'usr/sbin/vinix-session', flags: ['-prod'] },
			hwhost.Program{ source: 'tools/accounts/authd.v', path: 'usr/sbin/vinix-authd', flags: ['-prod'] },
		]
		binaries:     [hwhost.RootBinary{ source: sandbox, path: 'usr/bin/vinix-sandbox' }]
		files:        entries
		directories:  ['run', 'home', 'var/log', 'tmp:1777']
		scenarios:    scenarios
	}
}

fn prepare_check(options hwhost.Options, root string, out string, before map[string]string,
	revision string, host hwhost.Host, mut paths map[string]string, mut originals map[string]string) ! {
	variable := if host.arch == 'aarch64' { 'CC_AARCH64' } else { 'CC_AMD64' }
	default_cc := if host.arch == 'aarch64' { 'clang' } else { 'x86_64-linux-musl-gcc' }
	cc_name := os.getenv_opt(variable) or { default_cc }
	compiler := if cc_name.contains('/') {
		os.real_path(cc_name)
	} else {
		os.find_abs_path_of_executable(cc_name)!
	}
	paths['clang'] = retained(compiler, out, 'static-c-compiler')!
	originals['clang'] = os.real_path(compiler)
	os.setenv(variable, compiler, true)
	retain_tree(os.dir(host.v) + '/vlib', 'vlib', out, [], mut paths, mut originals)!
	// These Linux -gc none builds use the C backend and its stdatomic headers.
	// Preserve that dependency and the original compiler snapshot inventory;
	// unrelated TCC binaries and graphics libraries are not build inputs.
	retain_tree(os.dir(host.v) + '/thirdparty/stdatomic', 'v-thirdparty/stdatomic', out,
		[], mut paths, mut originals)!
	for name in ['snapshot.json', 'v.mod'] {
		key := 'v-compiler/' + name
		original := os.dir(host.v) + '/' + name
		paths[key] = retained(original, out, key)!
		originals[key] = original
	}
	frozen_cc := cross_inputs(host, out, mut paths, mut originals)!
	os.setenv(variable, frozen_cc, true)
	if adapter_source := os.getenv_opt('VINIX_AUDIO_CC_SOURCE') {
		paths['cross-adapter-source'] = retained(adapter_source, out, 'cross-adapter.v')!
		originals['cross-adapter-source'] = os.real_path(adapter_source)
	}
	if kernel_evidence := os.getenv_opt('VINIX_AUDIO_KERNEL_EVIDENCE') {
		retain_tree(kernel_evidence, 'kernel-evidence', out, [], mut paths, mut originals)!
		paths['kernel-seal'] = out + '/inputs/kernel-evidence/kernel-seal.json'
	}
	sandbox := sandbox_build(root, host, out, frozen_cc)!
	key := publisher(root, host, out)!
	suite := audio_suite(root, out, host.arch, sandbox, key)!
	extras := hwhost.build_extras(host, suite, out + '/tools')!
	paths['guest'] = hwhost.build_program_with_flags(host, root + '/' + suite.guest,
		out + '/guest-build', 'init', suite.module_paths, ['-prod'])!
	paths['tone'] = out + '/tone-build/tone'
	paths['sandbox'] = sandbox
	paths['sandbox-c'] = out + '/sandbox-build/sandbox.c'
	for index, name in ['package-cli', 'account-cli', 'session-cli', 'authd'] {
		paths[name] = out + '/tools/program-${index}/' + os.file_name(suite.programs[index].path)
	}
	allowed_headers := audioinputs.header_allowlist(out + '/inputs/source', before, originals)
	for name in audioinputs.trace_files() {
		audioinputs.verify_trace(os.read_file(out + '/' + name)!, out, name, allowed_headers)!
		paths['trace/' + name] = out + '/' + name
		paths['trace-object/' + name] = audioinputs.trace_object(out, name)!
	}
	// Fail closed if a generated translation unit introduces another compiler
	// thirdparty dependency outside the explicitly retained C-backend headers.
	mut translation_units := generated_files.clone()
	translation_units << 'sandbox-build/sandbox.c'
	translation_units << 'cross-probe.c'
	for generated in translation_units {
		for line in os.read_lines(out + '/' + generated)! {
			if !line.trim_space().starts_with('#include "') { continue }
			included := line.all_after('"').all_before('"')
			prefix := os.dir(host.v) + '/thirdparty/'
			if !included.starts_with(prefix) { continue }
			dependency_key := 'v-thirdparty/' + included.all_after(prefix)
			if dependency_key !in paths || digest(included)! != digest(paths[dependency_key])! {
				return error('generated C dependency is not retained: ' + included)
			}
		}
	}
	for name in files(out + '/inputs')! {
		if name.starts_with('source/') { continue }
		paths['input/' + name] = out + '/inputs/' + name
	}
	write_json(out + '/original-input-paths.json', originals)!
	paths['input-origins'] = out + '/original-input-paths.json'
	paths['source-revision'] = out + '/repository-head.log'
	paths['source-patch'] = out + '/production.diff'
	finish_check(options, root, out, before, revision, host, suite, extras, mut paths, originals)!
}

fn generated_inventory(out string) !map[string]string {
	mut result := map[string]string{}
	for path in generated_files {
		result[path] = digest(out + '/' + path)!
	}
	return result
}

fn artifact_inventory(paths map[string]string) !map[string]string {
	mut result := map[string]string{}
	for name, path in paths { result[name] = digest(path)! }
	return result
}

fn finish_check(options hwhost.Options, root string, out string, before map[string]string,
	revision string, host hwhost.Host, suite hwhost.Suite, extras string,
	mut paths map[string]string, originals map[string]string) ! {
	generated_before := generated_inventory(out)!
	inputs_before := artifact_inventory(paths)!
	write_json(out + '/generated-before.json', generated_before)!
	write_json(out + '/input-before.json', inputs_before)!
	if source_inventory(root)! != before { return error('producer sources changed during build') }
	mut passed := true
	mut count := 0
	for scenario in suite.scenarios {
		if options.scenarios.len > 0 && scenario.name !in options.scenarios { continue }
		if 'kernel-seal' !in paths { return error('native execution requires VINIX_AUDIO_KERNEL_EVIDENCE') }
		state := out + '/run/' + scenario.name
		outcome := hwhost.run_scenario(host, scenario, hwhost.Run{
			kernel:  paths['kernel']
			guest:   paths['guest']
			extras:  extras
			state:   state
			timeout: 240
			keep:    true
		})
		os.write_file(state + '/outcome.json', json2.encode(outcome) + '\n')!
		println(hwhost.report(host.arch, outcome))
		name := scenario.name.all_after('packages-audio-')
		for key, file in {
			'outcome':  'outcome.json'
			'serial':   'serial.log'
			'wav':      'sound.wav'
			'qemu-log': 'qemu.log'
			'qmp-log':  'qmp.log'
		} {
			paths[name + '-' + key] = state + '/' + file
		}
		passed = passed && outcome.passed && !outcome.interrupted
		count++
		if outcome.interrupted { break }
	}
	after := source_inventory(root)!
	generated_after := generated_inventory(out)!
	mut inputs_after := map[string]string{}
	for name, _ in inputs_before { inputs_after[name] = digest(paths[name])! }
	write_json(out + '/source-after.json', after)!
	write_json(out + '/generated-after.json', generated_after)!
	write_json(out + '/input-after.json', inputs_after)!
	for name, path in originals {
		if digest(path)! != inputs_before[name] {
			return error('external original input changed: ' + name)
		}
	}
	verify_sysroot(out)!
	if before != after || generated_before != generated_after || inputs_before != inputs_after {
		return error('source, generated C or native input changed during execution')
	}
	if !passed || count != 3 {
		return error('requires all three native guest scenarios to pass; raw attempts retained')
	}
	for name in ['source-before', 'source-after', 'generated-before', 'generated-after', 'input-before',
		'input-after'] {
		paths[name] = out + '/' + name + '.json'
	}
	qualification := Qualification{
		architecture:    host.arch
		completed_at:    time.now().unix()
		source_root:     out + '/inputs/source'
		source_revision: revision
		sources:         before
		artifacts:       artifact_inventory(paths)!
		artifact_paths:  paths
	}
	os.write_file(out + '/qualification.json', json2.encode(qualification) + '\n')!
	println('Captured complete native evidence; run the independent audio-portal-retain checker.')
}

fn check() ! {
	options := hwhost.parse_options(os.args[1..])!
	if options.help || options.list {
		println('audio-portal-runtime-check --arch ARCH --kernel PATH --state-dir NEW')
		return
	}
	if options.arch !in ['aarch64', 'x86_64'] || !os.is_file(options.kernel) || !os.is_abs_path(options.state_dir)
		|| os.exists(options.state_dir) || options.failures_only {
		return error('requires architecture, existing kernel, NEW absolute --state-dir and complete retention')
	}
	root := hwhost.find_root(@FILE)!
	out := options.state_dir
	os.mkdir_all(out + '/inputs/source')!
	before := source_inventory(root)!
	for name, _ in before {
		target := out + '/inputs/source/' + name
		os.mkdir_all(os.dir(target))!
		os.cp(root + '/' + name, target)!
	}
	write_json(out + '/source-before.json', before)!
	revision := invoke(['git', '-C', root, 'rev-parse', 'HEAD'], out + '/repository-head.log')!.trim_space()
	invoke(['git', '-C', root, 'diff', '--', 'tools/packages', 'tools/accounts'], out + '/production.diff')!
	found := hwhost.find_host(root, options.arch, options.qemu)!
	host := hwhost.Host{ ...found, v: os.real_path(found.v), qemu: os.real_path(found.qemu),
		firmware: os.real_path(found.firmware), firmware_vars: if found.firmware_vars == '' { '' } else { os.real_path(found.firmware_vars) } }
	mut paths := map[string]string{}
	mut originals := map[string]string{}
	for name, path in {
		'kernel':   options.kernel
		'v':        host.v
		'qemu':     host.qemu
		'firmware': host.firmware
	} {
		paths[name] = retained(path, out, name)!
		originals[name] = os.real_path(path)
	}
	if host.firmware_vars != '' {
		paths['firmware-vars'] = retained(host.firmware_vars, out, 'firmware-vars')!
		originals['firmware-vars'] = os.real_path(host.firmware_vars)
	}
	paths['controller'] = retained(os.executable(), out, 'controller')!
	originals['controller'] = os.real_path(os.executable())
	prepare_check(options, root, out, before, revision, host, mut paths, mut originals)!
}

fn main() {
	check() or {
		eprintln('audio-portal-runtime-check: ${err}')
		exit(1)
	}
}
