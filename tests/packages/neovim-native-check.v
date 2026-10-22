// SPDX-License-Identifier: GPL-2.0-or-later
// Build and boot signed Neovim with its actual runtime and ordinary-account PTY.
module main

import crypto.sha256
import hwhost
import json2
import os
import plainiso
import tools.packages.pkgcore

fn digest(path string) !string {
	contents := os.read_file(path)!
	defer { unsafe { contents.free() } }
	return sha256.hexhash(contents)
}

fn invoke(args []string, log string) !string {
	os.write_file(log + '.argv.json', json2.encode(args))!
	mut child := os.new_process(args[0])
	defer { child.close() }
	child.set_args(args[1..]); child.set_redirect_stdio_merged(); child.run()
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	output := child.stdout_slurp()
	child.wait()
	os.write_file(log, output)!
	if child.code != 0 { return error(args[0] + ' failed; see ' + log) }
	return output
}

fn required(options map[string]string, name string) !string {
	value := options[name] or { return error('required ' + name) }
	if value == '' || value.contains('\x00') { return error('empty or invalid ' + name) }
	return os.abs_path(value)
}

fn parse_options(values []string) !map[string]string {
	mut options := map[string]string{}
	for argument in values {
		if !argument.starts_with('--') || !argument.contains('=') { return error('expected --name=value') }
		name := argument.all_before('=')
		value := argument.all_after('=')
		if name !in ['--arch', '--out', '--kernel', '--sandbox', '--sysroot', '--gcc', '--repository', '--update-repository', '--public-key'] {
			return error('unknown option: ' + name)
		}
		if name in options || value == '' || value.contains('\x00') { return error('duplicate or empty option: ' + name) }
		options[name] = value
	}
	return options
}

fn tree_hashes(root string) !map[string]string {
 mut hashes := map[string]string{}
 for directory in ['tools/accounts', 'tools/packages', 'desktop/ptycore', 'tests/hardware-platform/hwhost', 'tests/hardware-platform/plainiso', 'tests/packages/neovim-native'] {
 for path in os.walk_ext(root + '/' + directory, '.v') { if !path.ends_with('_test.v') { hashes[path] = digest(path)! } }
 }
 hashes[root + '/tests/packages/neovim-native-check.v'] = digest(root + '/tests/packages/neovim-native-check.v')!
 return hashes
}

fn verify(hashes map[string]string) ! {
	for path, hash in hashes { if digest(path)! != hash { return error('input changed: ' + path) } }
}

fn verify_sources(root string, expected map[string]string) ! {
	current := tree_hashes(root)!
	if current != expected { return error('source inventory changed before qualification completed') }
}

fn build_program(v string, clang string, sysroot string, gcc string, source_root string, source string,
	name string, arch string, work string, dynamic bool) !string {
	directory := work + '/build-' + name
	os.mkdir_all(directory)!
	cfile := directory + '/' + name + '.c'
	invoke([v, '-backend', 'c', '-prod', '-os', 'linux', '-arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' },
		'-gc', 'none', '-manualfree', '-enable-globals', '-d', 'no_backtrace', '-d', 'no_segfault_handler',
		'-path', '@vlib|' + source_root + '|' + source_root + '/tools/accounts|@vmodules', '-o', cfile, source], directory + '/v.log')!
	// Include the compiler's existing runtime helper implementations; no fixture
	// implementation is added to the generated C.
	vlib := os.dir(v) + '/vlib'
	os.write_file(directory + '/runtime.c', '#include <unistd.h>\n#include <fcntl.h>\n#include <sys/wait.h>\n#define V_OS_EXECUTE_SCOPE\n#include "' +
		vlib + '/os/execute_capture_nix.h"\n#define V_SYNC_THREAD_SCOPE\n#include "' + vlib + '/sync/thread_helper.h"\n')!
	mut flags := [clang, '--target=' + arch + '-linux-musl', '--sysroot=' + sysroot,
		'--gcc-install-dir=' + gcc, '-fuse-ld=lld', '-O1', '-w', '-fno-stack-protector',
		'-Wno-error=incompatible-pointer-types',
		'-D_GNU_SOURCE', '-L' + sysroot + '/lib', '-L' + sysroot + '/usr/lib',
		'-Wl,-rpath-link,' + sysroot + '/lib', '-Wl,-rpath-link,' + sysroot + '/usr/lib']
	if !dynamic { flags << '-static' } else { flags << '-static-libgcc' }
	flags << [cfile, directory + '/runtime.c', '-lm', '-lpthread']
	if dynamic { flags << '-lX11' }
	flags << ['-o', directory + '/' + name]
	invoke(flags, directory + '/cc.log')!
	return directory + '/' + name
}

fn check() ! {
	$if prod {} $else { return error('compile native-check with -prod') }
	root := hwhost.find_root(@FILE)!
	if digest(root + '/tests/packages/neovim-native-check.v')! != sha256.hexhash($embed_file('neovim-native-check.v').to_string()) {
		return error('controller source changed after compilation')
	}
	options := parse_options(os.args[1..])!
	arch := options['--arch'] or { 'aarch64' }
	if arch !in ['aarch64', 'x86_64'] { return error('unsupported architecture') }
	work := required(options, '--out')!
	if os.exists(work) { return error('output directory already exists') }
	os.mkdir_all(work)!
	host := hwhost.find_host(root, arch, '')!
	os.setenv('VEXE', host.v, true)
	os.setenv('V_MACOS_V3_CALLER_VEXE_PRESENT', '1', true)
	os.setenv('V_MACOS_V3_CALLER_VEXE', host.v, true)
	os.setenv('V_MACOS_V3_CALLER_VCHILD_PRESENT', '0', true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	kernel := required(options, '--kernel')!
	sandbox := required(options, '--sandbox')!
	sysroot := required(options, '--sysroot')!
	gcc := required(options, '--gcc')!
	repository := required(options, '--repository')!
	update_repository := required(options, '--update-repository')!
	key := os.read_file(required(options, '--public-key')!)!.trim_space()
	clang := os.find_abs_path_of_executable(os.getenv_opt('CLANG') or { '/opt/homebrew/opt/llvm/bin/clang' })!
	sources := tree_hashes(root)!
	mut inputs := sources.clone()
	for path in [os.executable(), host.v, clang, kernel, host.qemu, host.firmware, sandbox,
		os.dir(host.v) + '/vlib/os/execute_capture_nix.h', os.dir(host.v) + '/vlib/sync/thread_helper.h',
		required(options, '--public-key')!] { inputs[path] = digest(path)! }
	if host.firmware_vars != '' { inputs[host.firmware_vars] = digest(host.firmware_vars)! }
	if arch == 'x86_64' { for _, path in plainiso.inputs(root)! { inputs[path] = digest(path)! } }
	else {
		loader := os.getenv_opt('VINIX_LIMINE_BOOTAA64') or { hwhost.shared_path(root, 'boot-image/limine-bin/BOOTAA64.EFI') }
		for path in [loader, root + '/build-support/limine.conf',
			os.find_abs_path_of_executable('mformat')!, os.find_abs_path_of_executable('mmd')!, os.find_abs_path_of_executable('mcopy')!] {
			inputs[path] = digest(path)!
		}
	}
	for directory in [sysroot + '/usr/include', gcc, repository, update_repository] {
		for path in os.walk_ext(directory, '') { if os.is_file(path) { inputs[path] = digest(path)! } }
	}
	for name in ['libc.a', 'crt1.o', 'crti.o', 'crtn.o'] { path := sysroot + '/usr/lib/' + name; inputs[path] = digest(path)! }
	source := work + '/source'
	for name in ['tools/accounts', 'tools/packages', 'desktop/ptycore'] {
		os.mkdir_all(source + '/' + os.dir(name))!
		invoke(['cp', '-Rp', root + '/' + name, source + '/' + name], work + '/copy-' + os.base(name) + '.log')!
	}
	os.mkdir_all(source + '/tests/packages/neovim-native')!
	for name in ['neovim-native-check.v', 'neovim-native/main.v'] { os.cp(root + '/tests/packages/' + name, source + '/tests/packages/' + name)! }
	os.write_file(work + '/inputs-before-build.json', json2.encode(inputs))!
	verify(inputs)!
	verify_sources(root, sources)!
	extras := work + '/extras'
	for directory in ['/usr/bin', '/usr/sbin', '/etc/vinix', '/etc/vinix-packages', '/var/lib/vinix-packages'] { os.mkdir_all(extras + directory)! }
	os.write_file(extras + '/etc/vinix/auth.conf', 'scrypt_ln = 10\nscrypt_p = 1\n')!
	os.cp(sandbox, extras + '/usr/bin/vinix-sandbox')!
	os.mkdir_all(extras + '/usr/share/neovim-update')!
	for name in ['index.json', 'index.sig'] { os.cp(update_repository + '/' + name, extras + '/usr/share/neovim-update/' + name)! }
	os.write_file(extras + '/usr/share/neovim-update/public-key', key)!
	account := build_program(host.v, clang, sysroot, gcc, source, source + '/tools/accounts/account.v', 'vinix-account', arch, work, false)!
	os.cp(account, extras + '/usr/sbin/vinix-account')!
	session := build_program(host.v, clang, sysroot, gcc, source, source + '/tools/accounts/session.v', 'vinix-session', arch, work, false)!
	os.cp(session, extras + '/usr/sbin/vinix-session')!
	package := build_program(host.v, clang, sysroot, gcc, source, source + '/tools/packages/main.v', 'vinix-package', arch, work, false)!
	os.cp(package, extras + '/usr/bin/vinix-package')!
	guest := build_program(host.v, clang, sysroot, gcc, source, source + '/tests/packages/neovim-native/main.v', 'guest', arch, work, false)!
	config := pkgcore.Config{architecture: arch, launch_user: 'alex', policy: pkgcore.Policy{offline: true, reserve_bytes: 0},
		repositories: [pkgcore.Repository{id: 'neovim-fixture', url: 'file://' + repository, public_key: key}]}
	os.write_file(extras + '/etc/vinix-packages/config.json', json2.encode(config))!
	service := pkgcore.Service{root: extras}
	mut catalog := service.refresh()!; catalog.close()
	mut state := service.transact('install', ['org.neovim.editor'], pkgcore.TransactionOptions{})!; state.close()
	// The publisher secret is never an input or a member of the guest image.
	for path in os.walk_ext(work, '') {
		if os.is_file(path) && (!path.ends_with('.json') || path.ends_with('.argv.json')) {
			inputs[path] = digest(path)!
		}
	}
	os.write_file(work + '/inputs.json', json2.encode(inputs))!
	scenario := hwhost.Scenario{name: 'packaged-Neovim', arches: [arch], qemu_x86_64: ['-cpu', 'max'],
		required: ['Neovim signed-musl fixed-runtime Lua-LPEG Vimscript-syntax ordinary-uid outside-write-refused PASS',
			'Neovim real-PTY input resize exact-save ordinary-owner live-uninstall lease-held natural-exit gc PASS',
			'Neovim signed-runtime update-1.1 rollback-1.0 exact-Lua-reopen offline PASS',
			'Neovim offline-cache reinstall exact-reopen data-preserving-uninstall pipe-refusal PASS', 'HWTEST PASS packaged-Neovim'],
		forbidden: ['HWTEST FAIL', 'Kernel panic'], ending: .running}
	runtime_host := if arch == 'x86_64' { hwhost.Host{...host, root: plainiso.prepare(root, work)!} } else { host }
	verify(inputs)!
	verify_sources(root, sources)!
	outcome := hwhost.run_scenario(runtime_host, scenario, hwhost.Run{kernel: kernel, guest: guest, extras: extras,
		state: work + '/boot', timeout: 1200, keep: true})
	os.write_file(work + '/result.json', json2.encode(outcome))!
	verify(inputs)!
	verify_sources(root, sources)!
	os.write_file(work + '/inputs-verified.json', json2.encode(inputs))!
	mut outputs := map[string]string{}
	for path in os.walk_ext(work, '') {
		if os.is_file(path) && !path.contains('/rootfs/') && (!path.contains('/iso-root/') || path.ends_with('/boot/limine.conf')) && !path.starts_with(extras + '/') {
			outputs[path[work.len + 1..]] = digest(path)!
		}
	}
	os.write_file(work + '/outputs.json', json2.encode(outputs))!
	if !outcome.passed || outcome.interrupted || outcome.reason != '' { return error('native Neovim qualification failed: ' + outcome.reason) }
	println('NEOVIM NATIVE PASS ' + arch + ': ' + work)
}

fn main() {
	if plainiso.requested() { plainiso.build() or { eprintln(err); exit(1) }; return }
	check() or { eprintln(err); exit(1) }
}
