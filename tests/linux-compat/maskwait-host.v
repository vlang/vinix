// SPDX-License-Identifier: GPL-2.0-or-later
// Local qualification controller. Support contains the retained native guest
// modules, compiler/sysroot and launcher used by the preceding signal audits.
// Set VINIX_COMPAT_SUPPORT to that restored tree and VINIX_V_COMPILER to V.
module main

import crypto.sha256
import guesthost
import json2
import os

fn digest(path string) string { return sha256.sum(os.read_bytes(path) or { panic(err) }).hex() }
fn execute(args []string, folder string, log string) ! {
	os.write_file(log + '.command.json', json2.encode(args, prettify: true) + '\n')!
	mut p := os.new_process(args[0])
	p.set_args(args[1..]); p.set_work_folder(folder); p.set_redirect_stdio_merged(); p.run()
	out := p.stdout_slurp(); p.wait(); code := p.code; p.close()
	os.write_file(log, out)!; os.write_file(log + '.status', code.str() + '\n')!
	if code != 0 { return error('Command failed: ' + log + '\n' + out) }
}
fn pins(paths []string) map[string]string {
	mut result := map[string]string{}
	for path in paths { result[path] = digest(path) }
	return result
}
fn stable(before map[string]string) ! {
	for path, pin in before { if digest(path) != pin { return error('Changed input: ' + path) } }
}
fn compile_probe(root string, support string, state string, arch string) ! {
	os.mkdir_all(state)!
	mut inputs := pins([@FILE, os.executable(), support + '/generate-module',
		root + '/tests/linux-compat/maskwaitfixture/core.v',
		root + '/tests/linux-compat/maskwaitreferenceinit/core.v', support + '/frozen/serialcore/core.v'])
	cc := if arch == 'aarch64' { os.find_abs_path_of_executable('clang')! } else { os.find_abs_path_of_executable('x86_64-linux-musl-gcc')! }
	inputs[cc] = digest(cc)
	mut flags := [cc]
	if arch == 'aarch64' {
		flags << ['--gcc-install-dir=' + support + '/sdk/usr/lib/gcc/aarch64-alpine-linux-musl/14.2.0',
			'--target=aarch64-linux-musl', '--sysroot=' + support + '/sdk', '-fno-stack-protector']
	}
	flags << ['-static', '-O2', '-D_GNU_SOURCE', '-fno-strict-aliasing', '-Wall', '-Wextra', '-Werror']
	for name, source in {'serial': support + '/frozen/serialcore', 'fixture': root + '/tests/linux-compat/maskwaitfixture', 'reference': root + '/tests/linux-compat/maskwaitreferenceinit'} {
		execute([support + '/generate-module', source, state + '/' + name + '.c', '--arch',
			if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-d', 'nofloat'], root, state + '/generate-' + name + '.log')!
		execute([...flags, '-Wno-unused-function', '-Wno-unused-parameter', '-fPIC', '-I', source,
			'-c', state + '/' + name + '.c', '-o', state + '/' + name + '.o'], root, state + '/compile-' + name + '.log')!
	}
	for name, object in {'probe': 'fixture', 'reference-init': 'reference'} {
		mut args := [...flags, state + '/serial.o', state + '/' + object + '.o']
		if arch == 'aarch64' { args << ['-L' + support + '/sdk/lib', '-fuse-ld=lld'] }
		args << ['-o', state + '/' + name]
		execute(args, root, state + '/link-' + name + '.log')!
	}
	stable(inputs)!
	os.write_file(state + '/receipt.json', json2.encode({'architecture': json2.Any(arch),
		'inputs': json2.decode[json2.Any](json2.encode(inputs))!,
		'outputs': json2.decode[json2.Any](json2.encode(pins([state + '/probe', state + '/reference-init'])))!}, prettify: true) + '\n')!
}
fn build_kernel(root string, state string, arch string) ! {
	os.mkdir_all(state)!
	compiler := os.getenv('VINIX_V_COMPILER')
	if compiler == '' { return error('VINIX_V_COMPILER required') }
	mut paths := [@FILE, os.executable(), compiler]
	for path in os.walk_ext(root + '/kernel', '') {
		if os.is_file(path) && !path.contains('/obj/') && !path.contains('/bin/')
			&& !path.contains('/cc-runtime-') { paths << path }
	}
	inputs := pins(paths)
	os.write_file(state + '/inputs.json', json2.encode(inputs, prettify: true) + '\n')!
	// Generate the host sampler explicitly: its native compile needs the
	// macOS SDK even though the kernel itself targets freestanding ELF.
	if arch == 'x86_64' {
		execute([compiler, '-gc', 'none', '-cc', '/Library/Developer/CommandLineTools/usr/bin/clang',
			'-cflags', '-isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk',
			'-path', root + '/tests/native-generators|' + root + '/tools|' + root + '/build-support|@vlib',
			'-o', state + '/native-generators', root + '/tests/native-generators/main.v'], root, state + '/host-generator.log')!
		os.mkdir_all(root + '/kernel/obj')!
		execute([state + '/native-generators', 'sampler', 'obj/heap_benchmark.c'], root + '/kernel', state + '/sampler.log')!
	}
	execute(['/usr/bin/make', 'ARCH=' + arch, 'V=' + compiler,
		'CC=/Library/Developer/CommandLineTools/usr/bin/clang', 'AR=/opt/homebrew/opt/llvm/bin/llvm-ar',
		'LD_AARCH64=/opt/homebrew/bin/ld.lld', 'LD_X86_64=/opt/homebrew/bin/ld.lld',
		'PROD=true', '-j1', 'LIMINE_MP=1', 'ALLOC_TRACK=0', 'KERNEL_LINK_SEED=42'], root + '/kernel', state + '/build.log')!
	stable(inputs)!
	os.mkdir_all(state + '/kernel/bin')!
	os.cp(root + '/kernel/bin/vinix', state + '/kernel/bin/vinix')!
	os.cp(root + '/kernel/obj/blob.c', state + '/blob.c')!
	os.write_file(state + '/outputs.json', json2.encode(pins([state + '/kernel/bin/vinix', state + '/blob.c']), prettify: true) + '\n')!
}
fn native(probe string, kernel string, support string, state string, arch string) ! {
	os.mkdir_all(state + '/kernel/bin')!
	for name in ['sbin', 'dev', 'proc', 'sys', 'tmp', 'root'] { os.mkdir_all(state + '/rootfs/' + name)! }
	os.cp(probe, state + '/rootfs/sbin/init')!; os.chmod(state + '/rootfs/sbin/init', 0o755)!
	os.cp(kernel + '/bin/vinix', state + '/kernel/bin/vinix')!
	inputs := pins([@FILE, os.executable(), probe, kernel + '/bin/vinix'])
	os.write_file(state + '/inputs.json', json2.encode(inputs, prettify: true) + '\n')!
	os.setenv('COPYFILE_DISABLE', '1', true); os.setenv('VINIX_QEMU_SMP', '4', true)
	for key in ['VINIX_CMDLINE', 'VINIX_QEMU_BIN', 'VINIX_QEMU_X86_64', 'VINIX_OVMF_CODE', 'VINIX_OVMF_VARS', 'VINIX_QEMU_CPU', 'VINIX_QEMU_NETWORK'] { os.unsetenv(key) }
	execute(['/usr/bin/tar', '--format=ustar', '-cf', state + '/initramfs.tar', '-C', state + '/rootfs', '.'], state, state + '/image.log')!
	launch := guesthost.launch_from(state + '/rootfs/sbin/init', state + '/initramfs.tar', state, state + '/kernel', arch, true, support + '/launch-root')!
	os.write_file(state + '/qemu.command.json', json2.encode(launch.command, prettify: true) + '\n')!
	// A baseline is expected to report semantic mismatches. Complete all cases
	// before interpreting success/failure using the separate log checker.
	result := guesthost.boot_session(launch.command, launch.env, state, guesthost.SessionPolicy{
		pass: 'LINUX MASKWAIT SUMMARY:'
		failures: ['LINUX MASKWAIT FAIL:', 'KERNEL PANIC', 'FATAL EXCEPTION']
		settle: 1
		log: state + '/live.log'
	}, 240, true)!
	stable(inputs)!
	os.write_file(state + '/receipt.json', json2.encode({'architecture': json2.Any(arch),
		'probe': digest(probe), 'kernel': digest(kernel + '/bin/vinix'),
		'finished': result.finished, 'passed': result.passed, 'status': result.status,
		'serial': digest(state + '/serial.log')}, prettify: true) + '\n')!
	if !result.finished || !result.passed || result.status != 0 { return error('Guest did not complete') }
}
fn main() {
	if os.args.len < 6 { eprintln('Usage: maskwait-host compile|build|native ROOT SUPPORT FRESH-STATE ARCH [PROBE KERNEL-DIR]'); exit(2) }
	mode, root, support, state, arch := os.args[1], os.real_path(os.args[2]), os.real_path(os.args[3]), os.args[4], os.args[5]
	if arch !in ['aarch64', 'x86_64'] || os.exists(state) { eprintln('Architecture invalid or state already exists'); exit(2) }
	match mode {
		'compile' { compile_probe(root, support, state, arch) or { panic(err) } }
		'build' { build_kernel(root, state, arch) or { panic(err) } }
		'native' {
			if os.args.len != 8 { panic('PROBE KERNEL-DIR required') }
			native(os.args[6], os.args[7], support, state, arch) or { panic(err) }
		}
		else { panic('Unknown mode') }
	}
	println(mode + ': PASS ' + arch)
}
