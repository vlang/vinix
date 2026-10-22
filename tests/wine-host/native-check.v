// SPDX-License-Identifier: GPL-2.0-or-later
// Build and boot authenticated X11 with the real signed package/account tools.
module main

import crypto.sha256
import hwhost
import json2
import os
import plainiso
import time
import tools.packages.pkgcore

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

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
	return os.abs_path(options[name] or { return error('required ' + name) })
}

fn tree_hashes(root string) !map[string]string {
	mut hashes := map[string]string{}
	for directory in ['tools/accounts', 'tools/packages', 'build-support/xorg-server/winehost',
		'build-support/native-compat-tools/compathost', 'tests/wine-host', 'tests/hardware-platform/hwhost',
		'tests/hardware-platform/plainiso'] {
		for path in os.walk_ext(root + '/' + directory, '.v') {
			if !path.ends_with('_test.v') { hashes[path] = digest(path)! }
		}
	}
	for name in ['build-support/xorg-server/wine-host-v-abi.h', 'build-support/xorg-server/build-wine-host.sh',
		'build-support/xorg-server/compile-v-host', 'build-support/native-compat-tools/main.v'] {
		hashes[root + '/' + name] = digest(root + '/' + name)!
	}
	return hashes
}

fn verify(hashes map[string]string) ! {
	for path, hash in hashes { if digest(path)! != hash { return error('input changed: ' + path) } }
}

fn copy_needed(binary string, sysroot string, destination string, readelf string, work string, mut inputs map[string]string) ! {
	mut pending := [binary]
	mut seen := map[string]bool{}
	for pending.len > 0 {
		path := pending.pop()
		if path in seen { continue }
		seen[path] = true
		inputs[path] = digest(path)!
		output := invoke([readelf, '-d', path], work + '/needed-' + seen.len.str() + '-' + os.base(binary) + '.log')!
		for line in output.split_into_lines() {
			if !line.contains('(NEEDED)') { continue }
			name := line.all_after('[').all_before(']')
			if name == '' || name.contains('/') { return error('invalid ELF dependency') }
			mut source := ''
			for directory in [sysroot + '/lib', sysroot + '/usr/lib'] {
				if os.is_file(directory + '/' + name) { source = directory + '/' + name; break }
			}
			if source == '' { return error('missing ELF dependency ' + name) }
			if !os.exists(destination + '/' + name) { os.cp(source, destination + '/' + name)! }
			pending << source
		}
	}
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
	if digest(root + '/tests/wine-host/native-check.v')! != sha256.sum($embed_file('native-check.v').to_string().bytes()).hex() {
		return error('controller source changed after compilation')
	}
	mut options := map[string]string{}
	for argument in os.args[1..] {
		if !argument.starts_with('--') || !argument.contains('=') { return error('expected --name=value') }
		options[argument.all_before('=')] = argument.all_after('=')
	}
	arch := options['--arch'] or { 'aarch64' }
	if arch !in ['aarch64', 'x86_64'] { return error('unsupported architecture') }
	work := required(options, '--out')!
	if os.exists(work) { return error('output directory already exists') }
	os.mkdir_all(work)!
	host := hwhost.find_host(root, arch, '')!
	kernel := required(options, '--kernel')!
	rootfs := required(options, '--rootfs')!
	sysroot := required(options, '--sysroot')!
	userland := required(options, '--userland')!
	x11 := required(options, '--x11')!
	shell := required(options, '--shell')!
	host_tool := required(options, '--host-tool')!
	clang := os.find_abs_path_of_executable(os.getenv_opt('CLANG') or { '/opt/homebrew/opt/llvm/bin/clang' })!
	readelf := os.find_abs_path_of_executable(os.getenv_opt('READELF') or { '/opt/homebrew/opt/llvm/bin/llvm-readelf' })!
	gcc_parent := userland + '/usr/lib/gcc/' + arch + '-alpine-linux-musl'
	mut versions := os.ls(gcc_parent)!
	versions.sort()
	if versions.len == 0 { return error('missing musl compiler runtime') }
	gcc := gcc_parent + '/' + versions.last()
	mut inputs := tree_hashes(root)!
	for path in [os.executable(), host.v, clang, readelf, kernel, host.qemu, host.firmware, host_tool,
		os.dir(host.v) + '/vlib/os/execute_capture_nix.h', os.dir(host.v) + '/vlib/sync/thread_helper.h'] {
		inputs[path] = digest(path)!
	}
	if host.firmware_vars != '' { inputs[host.firmware_vars] = digest(host.firmware_vars)! }
	if arch == 'x86_64' { for _, path in plainiso.inputs(root)! { inputs[path] = digest(path)! } }
	for directory in [sysroot + '/usr/include', gcc] {
		for path in os.walk_ext(directory, '') { if os.is_file(path) { inputs[path] = digest(path)! } }
	}
	for name in ['libc.a', 'crt1.o', 'crti.o', 'crtn.o'] {
		path := sysroot + '/usr/lib/' + name
		inputs[path] = digest(path)!
	}
	source := work + '/source'
	os.mkdir_all(source + '/tools')!
	for name in ['tools/accounts', 'tools/packages'] { invoke(['cp', '-Rp', root + '/' + name, source + '/' + name], work + '/copy-' + os.base(name) + '.log')! }
	os.mkdir_all(source + '/tests/wine-host/native')!
	os.cp(root + '/tests/wine-host/native/main.v', source + '/tests/wine-host/native/main.v')!
	os.cp(root + '/tests/wine-host/native-check.v', source + '/tests/wine-host/native-check.v')!
	os.write_file(work + '/inputs-before-build.json', json2.encode(inputs))!
	extras := work + '/extras'
	os.mkdir_all(extras)!
	invoke(['cp', '-Rp', rootfs + '/.', extras], work + '/copy-rootfs.log')!
	for path in os.walk_ext(rootfs, '') { if os.is_file(path) { inputs[path] = digest(path)! } }
	for directory in ['/bin', '/usr/bin', '/usr/sbin', '/usr/lib', '/lib', '/usr/share/vinix/actions', '/usr/share/X11'] { os.mkdir_all(extras + directory)! }
	os.cp(shell, extras + '/bin/sh')!
	inputs[shell] = digest(shell)!
	invoke(['cp', '-Rp', x11 + '/usr/share/X11/xkb', extras + '/usr/share/X11/xkb'], work + '/copy-xkb.log')!
	for path in os.walk_ext(x11 + '/usr/share/X11/xkb', '') { if os.is_file(path) { inputs[path] = digest(path)! } }
	os.cp(x11 + '/usr/bin/xkbcomp', extras + '/usr/bin/xkbcomp')!
	inputs[x11 + '/usr/bin/xkbcomp'] = digest(x11 + '/usr/bin/xkbcomp')!
	for name in ['account', 'session', 'authd'] {
		binary := build_program(host.v, clang, sysroot, gcc, source, source + '/tools/accounts/' + name + '.v', 'vinix-' + name, arch, work, false)!
		os.cp(binary, extras + '/usr/sbin/vinix-' + name)!
	}
	package := build_program(host.v, clang, sysroot, gcc, source, source + '/tools/packages/main.v', 'vinix-package', arch, work, false)!
	os.cp(package, extras + '/usr/bin/vinix-package')!
	guest := build_program(host.v, clang, sysroot, gcc, source, source + '/tests/wine-host/native/main.v', 'guest', arch, work, true)!
	os.setenv('VINIX_X11_SYSROOT', sysroot, true)
	bridge := work + '/vinix-wine-host'
	invoke([host_tool, 'x11-build', arch, x11, userland, '--output=' + bridge], work + '/host-build.log')!
	os.cp(bridge, extras + '/usr/bin/vinix-wine-host')!
	os.cp(x11 + '/usr/bin/Xvfb', extras + '/usr/bin/Xvfb')!
	inputs[x11 + '/usr/bin/Xvfb'] = digest(x11 + '/usr/bin/Xvfb')!
	for binary in [guest, bridge, x11 + '/usr/bin/Xvfb', x11 + '/usr/bin/xkbcomp', shell] {
		copy_needed(binary, sysroot, extras + '/usr/lib', readelf, work, mut inputs)!
	}
	loader := '/lib/ld-musl-' + arch + '.so.1'
	os.cp(sysroot + loader, extras + loader)!
	inputs[sysroot + loader] = digest(sysroot + loader)!
	if os.exists(extras + '/var/lib/vinix-packages') { os.rmdir_all(extras + '/var/lib/vinix-packages')! }
	os.mkdir_all(extras + '/etc/vinix-packages')!
	publisher := work + '/publisher'
	os.mkdir_all(publisher + '/payload/bin')!
	os.mkdir_all(publisher + '/payload/lib')!
	os.cp(guest, publisher + '/payload/bin/client')!
	os.chmod(publisher + '/payload/bin/client', 0o755)!
	copy_needed(guest, sysroot, publisher + '/payload/lib', readelf, work, mut inputs)!
	key := pkgcore.keygen(publisher + '/seed')!
	manifest := pkgcore.Package{ id: 'org.fixture.x11', version: '1.0.0', architecture: arch,
		name: 'Authenticated X11 fixture', license: 'MIT', kind: 'native', entrypoint: 'bin/client',
		arguments: ['--signed-child'], permissions: ['display', 'files'] }
	os.write_file(publisher + '/manifest.json', json2.encode(manifest))!
	mut packed := pkgcore.pack(publisher + '/manifest.json', publisher + '/payload', publisher + '/repository')!
	packed.close()
	pkgcore.publish(publisher + '/repository', 'trusted', publisher + '/seed', 1, time.now().unix() + 3600)!
	config := pkgcore.Config{ architecture: arch, policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 },
		repositories: [pkgcore.Repository{ id: 'trusted', url: 'file://' + publisher + '/repository', public_key: key }] }
	os.write_file(extras + '/etc/vinix-packages/config.json', json2.encode(config))!
	service := pkgcore.Service{ root: extras }
	mut catalog := service.refresh()!; catalog.close()
	mut state := service.transact('install', ['org.fixture.x11'], pkgcore.TransactionOptions{})!; state.close()
	os.write_file(extras + '/usr/share/vinix/actions/packages-launch',
		'description=Launch a signed application without account groups\nauth=account\nexec=/usr/sbin/vinix-session\narg=package-launch\ninput=secret\n')!
	// The seed stays in publisher/, outside every guest filesystem and archive.
	for path in os.walk_ext(work, '') {
		if os.is_file(path) && !path.starts_with(work + '/publisher/') && !path.ends_with('.json') { inputs[path] = digest(path)! }
	}
	os.write_file(work + '/inputs.json', json2.encode(inputs))!
	scenario := hwhost.Scenario{ name: 'hosted-X11', arches: [arch],
		qemu_x86_64: ['-cpu', 'max', '-vga', 'std'],
		required: ['signed-X11 ordinary-groups transport sandbox-context literal-document PASS',
			'real-Xvfb correct-cookie accepted wrong+missing-cookie refused PASS',
			'signed-X11 framebuffer colored-window damage-observed PASS',
			'real-Xvfb second-account authority+socket refused PASS',
			'signed-X11 bridge-closed server-reaped live-child-lease-held PASS',
			'signed-X11 natural-child-exit lease-released PASS', 'HWTEST PASS hosted-X11'],
		forbidden: ['HWTEST FAIL', 'Kernel panic'], ending: .running }
	runtime_host := if arch == 'x86_64' { hwhost.Host{ ...host, root: plainiso.prepare(root, work)! } } else { host }
	outcome := hwhost.run_scenario(runtime_host, scenario, hwhost.Run{
		kernel: kernel, guest: guest, extras: extras, state: work + '/boot', timeout: 1200, keep: true })
	os.write_file(work + '/result.json', json2.encode(outcome))!
	verify(inputs)!
	os.write_file(work + '/inputs-verified.json', json2.encode(inputs))!
	mut outputs := map[string]string{}
	for path in os.walk_ext(work, '') {
		if os.is_file(path) && !path.starts_with(work + '/publisher/') && !path.contains('/rootfs/') &&
			(!path.contains('/iso-root/') || path.ends_with('/boot/limine.conf')) && !path.starts_with(extras + '/') {
			outputs[path[work.len + 1..]] = digest(path)!
		}
	}
	os.write_file(work + '/outputs.json', json2.encode(outputs))!
	if !outcome.passed || outcome.interrupted || outcome.reason != '' { return error('native hosted-X11 qualification failed: ' + outcome.reason) }
	println('HOSTED X11 NATIVE PASS ' + arch + ': ' + work)
}

fn main() {
	if plainiso.requested() { plainiso.build() or { eprintln(err); exit(1) }; return }
	check() or { eprintln(err); exit(1) }
}
