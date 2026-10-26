// SPDX-License-Identifier: GPL-2.0-or-later
// Build a retained signed native publisher, then run real account-seat guests.
module main

import crypto.sha256
import hwhost
import json2
import os
import time
import tests.packages.audioinputs
import tests.packages.audioprepare
import tools.packages.pkgcore

const source_trees = ['tools/packages', 'tools/accounts', 'tools/security-events', 'tools/keyring',
	'tools/sandbox', 'build-support/native-compat-tools/compathost', 'tests/qemu-core/fixturehost',
	'tests/native-guest-tools/guesthost', 'tests/linuxkpi/hosttest', 'tests/native-policy-tools/nativepolicy',
	'tests/host-policy/policyhost', 'tests/hardware-platform/hwhost',
	'tests/packages/audio-portal-guest', 'tests/packages/audio-portal-tone', 'tests/packages/audiotest',
	'tests/packages/audioinputs', 'tests/packages/audioprepare']
const source_files = ['tests/packages/audio-portal-runtime-check.v',
	'tests/packages/audio-portal-retain.v', 'tests/packages/audio-portal-evidence-check.v',
	'tests/packages/audio-portal-wave-check.v', 'build-support/native-compat-tools/main.v',
	'build-support/security-tools/compile-v-core',
	'build-support/run-v-tool.sh', 'build-support/find-v.sh', 'tests/packages/audio-cross-cc.v',
	'tests/packages/audio-input-check.v', 'tests/packages/audio-cross-probe.v',
	'tests/packages/audio-portal-prepare-check.v', 'build-support/limine.conf']
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

// The external digest is the review checkpoint. Resume executes no serialized
// command or scenario table: it uses the compiled scenarios below.
struct PreparedHost {
	qemu string
	firmware string
	firmware_vars string
}

struct Preparation {
	format int = 1
	architecture string
	state_root string
	source_root string
	source_revision string
	sources map[string]string
	generated map[string]string
	inputs map[string]string
	artifact_paths map[string]string
	original_paths map[string]string
	scenarios []string
	extras_root string
	host PreparedHost
	environment map[string]string
	tree []audioprepare.Entry
}

struct PreparedKernel {
	elf_path string
	elf_sha256 string
}

struct PreparedKernelSeal {
	format int
	kernels map[string]PreparedKernel
}

const reviewed_kernel_seal = '839ad75dd1ec376a8cae4e75dc1cfbddc913406dc3e136e8d4f4a412657f9b73'
const runtime_tools = ['cp', 'tar', 'mformat', 'mmd', 'mcopy']

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
		scenarios:    audio_scenarios()
	}
}

fn audio_scenarios() []hwhost.Scenario {
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
	return scenarios
}

fn prepare_check(options hwhost.Options, root string, out string, before map[string]string,
	revision string, host hwhost.Host, prepare_only bool, mut paths map[string]string, mut originals map[string]string) ! {
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
	if prepare_only {
		seal_preparation(options, root, out, before, revision, host, extras, mut paths, mut originals)!
		return
	}
	finish_check(options, root, out, before, revision, host, suite, extras, false, mut paths, originals)!
}

fn selected_scenarios(names []string) ![]string {
	mut selected := []string{}
	for scenario in audio_scenarios() {
		if names.len == 0 || scenario.name in names { selected << scenario.name }
	}
	if names.len > 0 && selected.len != names.len { return error('unknown or duplicate audio scenario') }
	return selected
}

fn ordinary_under(out string, path string) ! {
	if !path.starts_with(out + '/') || path != os.real_path(path) {
		return error('prepared artifact must be inside canonical state: ' + path)
	}
	audioprepare.regular(path)!
}

fn prepared_elf(path string) ! {
	audioprepare.regular(path)!
	mut file := os.open(path)!
	defer { file.close() }
	mut header := []u8{len: 64}
	if file.read(mut header)! != 64 || header[..7] != [u8(127), `E`, `L`, `F`, 2, 1, 1]
		|| header[16] != 2 || header[17] != 0 || header[18] != 183 || header[19] != 0 {
		return error('prepared program must be an AArch64 ET_EXEC ELF: ' + path)
	}
}

fn prepared_extras(p Preparation) ! {
	out := p.state_root
	if p.extras_root != out + '/tools/root' { return error('unexpected prepared extras root') }
	mut expected := map[string]string{
		'etc/passwd': 'root:x:0:0:root:/root:/bin/sh\n'
		'etc/group': 'root:x:0:\ntty:x:5:\n'
		'etc/vinix/auth.conf': 'scrypt_ln = 10\n'
		'etc/vinix-packages/config.json': os.read_file(out + '/inputs/config.json')!
	}
	for pair in ['inputs/publisher|usr/share/audio-publisher', 'inputs/source/tools/accounts/actions|usr/share/vinix/actions'] {
		parts := pair.split('|')
		for name in files(out + '/' + parts[0])! {
			expected[parts[1] + '/' + name] = os.read_file(out + '/' + parts[0] + '/' + name)!
		}
	}
	mut binaries := map[string]string{}
	for pair in ['package-cli|usr/bin/vinix-package', 'account-cli|usr/sbin/vinix-account',
		'session-cli|usr/sbin/vinix-session', 'authd|usr/sbin/vinix-authd', 'sandbox|usr/bin/vinix-sandbox'] {
		parts := pair.split('|')
		binaries[parts[1]] = p.artifact_paths[parts[0]]
	}
	mut directories := map[string]bool{'': true, 'run': true, 'home': true, 'var': true, 'var/log': true, 'tmp': true}
	for path in expected.keys() {
		mut parent := os.dir(path)
		for parent != '.' { directories[parent] = true; parent = os.dir(parent) }
	}
	for path in binaries.keys() {
		mut parent := os.dir(path)
		for parent != '.' { directories[parent] = true; parent = os.dir(parent) }
	}
	entries := audioprepare.capture(p.extras_root, [])!
	if entries.len != expected.len + binaries.len + directories.len { return error('prepared extras coverage differs') }
	for entry in entries {
		if entry.kind == 'directory' {
			if entry.path !in directories || entry.mode != u32(if entry.path == 'tmp' { 0o1777 } else { 0o755 }) {
				return error('unexpected prepared extras directory or mode: ' + entry.path)
			}
		} else if entry.path in binaries {
			if entry.mode != 0o755 || entry.sha256 != digest(binaries[entry.path])! { return error('prepared binary differs: ' + entry.path) }
		} else if entry.path !in expected || entry.mode != 0o644 || os.read_file(p.extras_root + '/' + entry.path)! != expected[entry.path] {
			return error('prepared root file differs: ' + entry.path)
		}
	}
	config := json2.decode[pkgcore.Config](expected['etc/vinix-packages/config.json'])!
	key := os.read_file(out + '/inputs/public-key')!.trim_space()
	expected_config := pkgcore.Config{architecture: 'aarch64', launch_user: 'sam',
		repositories: [pkgcore.Repository{id: 'audio-fixture', url: 'file:///usr/share/audio-publisher', public_key: key}],
		policy: pkgcore.Policy{offline: true, reserve_bytes: 0}}
	if key.len != 64 || !key.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
		|| config != expected_config {
		return error('prepared package configuration differs')
	}
}

fn validate_preparation(out string, expected_sha string) !Preparation {
	if !os.is_abs_path(out) || os.real_path(out) != out { return error('requires canonical absolute prepared state') }
	if expected_sha.len != 64 || !expected_sha.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
		|| audioprepare.digest(out + '/preparation.json')! != expected_sha { return error('prepared receipt digest differs from reviewed digest') }
	p := json2.decode[Preparation](os.read_file(out + '/preparation.json')!)!
	if p.format != 1 || p.architecture != 'aarch64' || p.state_root != out
		|| p.source_root != hwhost.find_root(@FILE)! || p.source_revision.len != 40
		|| p.scenarios.len == 0 || selected_scenarios(p.scenarios)! != p.scenarios {
		return error('prepared identity, source root or scenario selection differs')
	}
	for name in ['run', 'source-after.json', 'generated-after.json', 'input-after.json', 'qualification.json'] {
		path := out + '/' + name
		if os.exists(path) || os.is_link(path) { return error('prepared state already contains execution results: ' + name) }
	}
	audioprepare.verify(out, p.tree, ['preparation.json'])!
	if source_inventory(p.source_root)! != p.sources || source_inventory(out + '/inputs/source')! != p.sources
		|| json2.decode[map[string]string](os.read_file(out + '/source-before.json')!)! != p.sources
		|| os.read_file(out + '/repository-head.log')!.trim_space() != p.source_revision
		|| p.sources['tests/packages/audio-portal-runtime-check.v'] != sha256.sum($embed_file('audio-portal-runtime-check.v').to_string().bytes()).hex() {
		return error('prepared source closure differs')
	}
	for _, path in p.artifact_paths { ordinary_under(out, path)! }
	if p.inputs.len != p.artifact_paths.len || artifact_inventory(p.artifact_paths)! != p.inputs
		|| generated_inventory(out)! != p.generated
		|| json2.decode[map[string]string](os.read_file(out + '/input-before.json')!)! != p.inputs
		|| json2.decode[map[string]string](os.read_file(out + '/generated-before.json')!)! != p.generated
		|| json2.decode[map[string]string](os.read_file(out + '/original-input-paths.json')!)! != p.original_paths {
		return error('prepared input/generated maps differ')
	}
	for name, path in p.original_paths {
		if name !in p.inputs || !os.is_abs_path(path) || os.real_path(path) != path { return error('unbound prepared original: ' + name) }
	}
	for name in ['kernel', 'v', 'qemu', 'firmware', 'firmware-vars', 'controller', 'clang',
		'cross-backend', 'cross-cc1', 'cross-collect2', 'cross-as', 'cross-ld', 'cross-lto-wrapper',
		'cross-lto-plugin', 'adapter-host-cc', 'runtime/BOOTAA64.EFI'] {
		if name !in p.original_paths { return error('missing prepared original: ' + name) }
	}
	for name, _ in p.artifact_paths {
		if name.starts_with('vlib/') || name.starts_with('v-thirdparty/') || name.starts_with('v-compiler/')
			|| name.starts_with('cross-sysroot/') || name.starts_with('cross-gcc/')
			|| name.starts_with('kernel-evidence/') || name.starts_with('runtime/') {
			if name !in p.original_paths { return error('missing prepared original: ' + name) }
		}
	}
	for name in ['guest', 'tone', 'sandbox', 'package-cli', 'account-cli', 'session-cli', 'authd', 'cross-probe'] {
		prepared_elf(p.artifact_paths[name])!
	}
	for key, relative in {
		'guest': 'guest-build/init', 'tone': 'tone-build/tone', 'sandbox': 'sandbox-build/vinix-sandbox',
		'package-cli': 'tools/program-0/vinix-package', 'account-cli': 'tools/program-1/vinix-account',
		'session-cli': 'tools/program-2/vinix-session', 'authd': 'tools/program-3/vinix-authd',
		'cross-probe': 'cross-probe', 'input-origins': 'original-input-paths.json',
		'source-revision': 'repository-head.log', 'source-patch': 'production.diff'
	} {
		if p.artifact_paths[key] != out + '/' + relative { return error('prepared artifact location differs: ' + key) }
	}
	if p.inputs['controller'] != audioprepare.digest(os.executable())!
		|| p.artifact_paths['kernel-seal'] != out + '/inputs/kernel-evidence/kernel-seal.json'
		|| p.inputs['kernel-seal'] != reviewed_kernel_seal { return error('controller or reviewed kernel seal differs') }
	seal := json2.decode[PreparedKernelSeal](os.read_file(p.artifact_paths['kernel-seal'])!)!
	build := seal.kernels['aarch64']
	if seal.format != 1 || build.elf_path != 'kernel-aarch64/bin/vinix'
		|| digest(out + '/inputs/kernel-evidence/' + build.elf_path)! != build.elf_sha256
		|| p.inputs['kernel'] != build.elf_sha256 { return error('prepared kernel differs from reviewed seal') }
	allowed := audioinputs.header_allowlist(out + '/inputs/source', p.sources, p.original_paths)
	for name in audioinputs.trace_files() {
		if p.artifact_paths['trace/' + name] != out + '/' + name
			|| p.artifact_paths['trace-object/' + name] != audioinputs.trace_object(out, name)! {
			return error('prepared trace/object binding differs: ' + name)
		}
		audioinputs.verify_trace(os.read_file(out + '/' + name)!, out, name, allowed)!
	}
	if p.host.qemu != p.original_paths['qemu'] || p.host.firmware != p.artifact_paths['firmware']
		|| p.host.firmware_vars != p.artifact_paths['firmware-vars']
		|| audioprepare.digest(p.host.qemu)! != p.inputs['qemu']
		|| p.environment.len != 3 || p.environment['PATH'] != out + '/runtime-bin'
		|| p.environment['VINIX_LIMINE_BOOTAA64'] != p.artifact_paths['runtime/BOOTAA64.EFI']
		|| p.environment['VINIX_HWTEST_TCG'] !in ['', '1'] { return error('prepared runtime binding differs') }
	for name in runtime_tools {
		path := out + '/runtime-bin/' + name
		if p.artifact_paths['runtime/' + name] != path || (os.lstat(path)!).mode & 0o7777 != 0o755 {
			return error('prepared runtime executable differs: ' + name)
		}
	}
	prepared_extras(p)!
	return p
}

fn seal_preparation(options hwhost.Options, root string, out string, before map[string]string,
	revision string, host hwhost.Host, extras string, mut paths map[string]string,
	mut originals map[string]string) ! {
	if host.arch != 'aarch64' { return error('two-phase execution currently requires AArch64') }
	loader := os.getenv_opt('VINIX_LIMINE_BOOTAA64') or { hwhost.shared_path(root, 'boot-image/limine-bin/BOOTAA64.EFI') }
	paths['runtime/BOOTAA64.EFI'] = retained(os.real_path(loader), out, 'runtime/BOOTAA64.EFI')!
	originals['runtime/BOOTAA64.EFI'] = os.real_path(loader)
	os.mkdir(out + '/runtime-bin')!
	for name in runtime_tools {
		original := os.real_path(os.find_abs_path_of_executable(name)!)
		path := out + '/runtime-bin/' + name
		os.cp(original, path)!
		os.chmod(path, 0o755)!
		paths['runtime/' + name] = path
		originals['runtime/' + name] = original
	}
	write_json(out + '/original-input-paths.json', originals)!
	generated := generated_inventory(out)!
	inputs := artifact_inventory(paths)!
	write_json(out + '/generated-before.json', generated)!
	write_json(out + '/input-before.json', inputs)!
	if source_inventory(root)! != before { return error('producer sources changed during preparation') }
	for name, path in originals { if digest(path)! != inputs[name] { return error('original changed during preparation: ' + name) } }
	verify_sysroot(out)!
	p := Preparation{
		architecture: host.arch, state_root: out, source_root: root, source_revision: revision,
		sources: before, generated: generated, inputs: inputs, artifact_paths: paths,
		original_paths: originals, scenarios: selected_scenarios(options.scenarios)!, extras_root: extras,
		host: PreparedHost{qemu: originals['qemu'], firmware: paths['firmware'], firmware_vars: paths['firmware-vars']},
		environment: {'PATH': out + '/runtime-bin', 'VINIX_LIMINE_BOOTAA64': paths['runtime/BOOTAA64.EFI'],
			'VINIX_HWTEST_TCG': if os.getenv('VINIX_HWTEST_TCG') == '' { '' } else { '1' }},
		tree: audioprepare.capture(out, ['preparation.json'])!
	}
	os.write_file(out + '/preparation.json', json2.encode(p) + '\n')!
	sha := audioprepare.digest(out + '/preparation.json')!
	validate_preparation(out, sha)!
	println('AUDIO PREPARATION PASS ' + sha + ' (no guest executed)')
}

fn prepared_command(resume bool, out string, expected_sha string) ! {
	p := validate_preparation(out, expected_sha)!
	if !resume { println('AUDIO PREPARATION VERIFIED ' + expected_sha + ' (read-only; no guest executed)'); return }
	for name, path in p.original_paths {
		if audioprepare.digest(path)! != p.inputs[name] { return error('external original changed before resume: ' + name) }
	}
	verify_sysroot(out)!
	// This exclusive claim survives every failure. A used preparation cannot boot again.
	os.mkdir(out + '/run')!
	mut previous := map[string]string{}
	mut present := map[string]bool{}
	for key, value in p.environment {
		if old := os.getenv_opt(key) { previous[key] = old; present[key] = true }
		os.setenv(key, value, true)
	}
	defer {
		for key, _ in p.environment {
			if present[key] { os.setenv(key, previous[key], true) } else { os.unsetenv(key) }
		}
	}
	host := hwhost.Host{root: out + '/inputs/source', arch: p.architecture, v: p.artifact_paths['v'],
		qemu: p.host.qemu, firmware: p.host.firmware, firmware_vars: p.host.firmware_vars}
	mut paths := p.artifact_paths.clone()
	finish_check(hwhost.Options{scenarios: p.scenarios}, p.source_root, out, p.sources,
		p.source_revision, host, hwhost.Suite{scenarios: audio_scenarios()}, p.extras_root,
		true, mut paths, p.original_paths) or {
		if audioprepare.digest(out + '/preparation.json')! != expected_sha { return error('preparation receipt changed during execution') }
		audioprepare.verify(out, p.tree, ['preparation.json', 'run', 'source-after.json',
			'generated-after.json', 'input-after.json', 'qualification.json'])!
		return err
	}
	if audioprepare.digest(out + '/preparation.json')! != expected_sha { return error('preparation receipt changed during execution') }
	audioprepare.verify(out, p.tree, ['preparation.json', 'run', 'source-after.json',
		'generated-after.json', 'input-after.json', 'qualification.json'])!
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
	prepared bool, mut paths map[string]string, originals map[string]string) ! {
	generated_before := generated_inventory(out)!
	inputs_before := artifact_inventory(paths)!
	if !prepared {
		write_json(out + '/generated-before.json', generated_before)!
		write_json(out + '/input-before.json', inputs_before)!
	}
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
	arguments := os.args[1..]
	if arguments.len > 0 && arguments[0] in ['--resume', '--verify-prepared'] {
		if arguments.len != 4 || arguments[2] != '--prepared-sha256' {
			return error('use --verify-prepared|--resume CANONICAL_STATE --prepared-sha256 REVIEWED_SHA256; no overrides')
		}
		prepared_command(arguments[0] == '--resume', arguments[1], arguments[3])!
		return
	}
	mut ordinary := []string{}
	mut prepare_only := false
	for argument in arguments {
		if argument == '--prepare-only' {
			if prepare_only { return error('duplicate --prepare-only') }
			prepare_only = true
		} else { ordinary << argument }
	}
	options := hwhost.parse_options(ordinary)!
	if options.help || options.list {
		println('audio-portal-runtime-check [--prepare-only] --arch ARCH --kernel PATH --state-dir NEW')
		println('audio-portal-runtime-check --verify-prepared|--resume STATE --prepared-sha256 REVIEWED_SHA256')
		return
	}
	if options.arch !in ['aarch64', 'x86_64'] || !os.is_file(options.kernel) || !os.is_abs_path(options.state_dir)
		|| os.exists(options.state_dir) || options.failures_only {
		return error('requires architecture, existing kernel, NEW absolute --state-dir and complete retention')
	}
	if prepare_only && options.arch != 'aarch64' { return error('--prepare-only currently requires AArch64') }
	if prepare_only {
		parent := os.dir(options.state_dir)
		if parent != os.real_path(parent) || (os.lstat(parent)!).mode & 0o170000 != 0o040000
			|| options.state_dir != os.join_path(parent, os.base(options.state_dir)) {
			return error('--prepare-only requires a new state below an existing canonical ordinary parent')
		}
		evidence := os.getenv('VINIX_AUDIO_KERNEL_EVIDENCE')
		if evidence == '' || audioprepare.digest(evidence + '/kernel-seal.json')! != reviewed_kernel_seal {
			return error('--prepare-only requires reviewed SO_PEERLOGIN kernel evidence')
		}
		seal := json2.decode[PreparedKernelSeal](os.read_file(evidence + '/kernel-seal.json')!)!
		if audioprepare.digest(options.kernel)! != seal.kernels['aarch64'].elf_sha256 {
			return error('--prepare-only kernel differs from reviewed AArch64 kernel')
		}
	}
	selected_scenarios(options.scenarios)!
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
	prepare_check(options, root, out, before, revision, host, prepare_only, mut paths, mut originals)!
}

fn main() {
	check() or {
		eprintln('audio-portal-runtime-check: ${err}')
		exit(1)
	}
}
