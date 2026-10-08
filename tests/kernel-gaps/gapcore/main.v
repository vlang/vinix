// SPDX-License-Identifier: GPL-2.0-or-later
module gapcore

import androidhost as ah
import json2

fn generator_function(module_id string, name string) !string {
	return method(module_id, '__getitem__', [v(ah.Value(name))], {}, 'owner')!.text()
}

fn compile_init(args map[string]ah.Value, root string, state string, init string, arch string) ! {
	module_id := invoke('runpy.run_path', [v(ah.Value(join(root, 'tests/kernel-gaps/compile-v-fixture.py')!))], {}, 'owner')!.text()
	serial := join(state, 'serial.o')!
	source := resolve(ah.field(args, 'source').text())!
	native_source := path_method(source, 'suffix', [], {}, 'path')!.text() == '.v'
	fixture := if native_source { join(state, 'fixture.o')! } else { source }
	mut command := []string{}
	if arch == 'aarch64' {
		sysroot_text := environment('VINIX_AARCH64_SYSROOT', join(root, 'build-aarch64-userland/sysroot')!)!
		sysroot := invoke('Path', [v(ah.Value(sysroot_text))], {}, 'path')!.text()
		command = [environment('CC', 'clang')!, '--target=aarch64-linux-musl', '--sysroot=' + sysroot,
			'-static', '-pthread', '-O2', '-fno-stack-protector', '-Wall', '-Wextra', '-Werror',
			serial, fixture, '-L' + join(sysroot, 'lib')!, '-fuse-ld=lld', '-o', init]
	} else {
		command = [environment('CC_AMD64', 'x86_64-linux-musl-gcc')!, '-static', '-pthread', '-O2',
			'-Wall', '-Wextra', '-Werror', serial, fixture, '-o', init]
	}
	parent := path_method(source, 'parent', [], {}, 'path')!.text()
	if native_source { command.insert(1, ['-D_GNU_SOURCE', '-fno-strict-aliasing', '-I', parent]) }
	prefix := command[..command.index(serial)].clone()
	compile_serial := generator_function(module_id, 'compile_serial')!
	method(compile_serial, '__call__', [p(serial), v(ah.Value(arch)),
		v(ah.Value(prefix.map(ah.Value(it))))], {}, 'owner')!
	if native_source {
		compile_module := generator_function(module_id, 'compile_module')!
		method(compile_module, '__call__', [p(parent), p(fixture), v(ah.Value(arch)),
			v(ah.Value(prefix.map(ah.Value(it))))], {}, 'owner')!
	}
	mut tool, include := '', ''
	resolved := resolve(ah.field(args, 'source').text())!
	if resolved == join(root, 'tests/application-sandbox/guestfixture/core.v')! {
		tool = 'sandbox'
		include = 'tools/sandbox'
	} else if resolved == join(root, 'tests/security-audit/collectorguestfixture/core.v')! {
		tool = 'audit'
		include = 'tools/security-audit'
	}
	if tool != '' {
		core := join(state, tool + '-core.c')!
		obj := path_method(core, 'with_suffix', [v(ah.Value('.o'))], {}, 'path')!.text()
		security_module := invoke('runpy.run_path', [v(ah.Value(join(root, 'build-support/security-tools/compile-v-core.py')!))], {}, 'owner')!.text()
		generate := generator_function(security_module, 'generate')!
		method(generate, '__call__', [v(ah.Value(tool)), p(core),
			v(ah.Value(if arch == 'aarch64' { 'arm64' } else { 'amd64' })),
			ah.Value([ah.Value('tuple'), ah.Value([ah.Value('security_no_main')])])], {}, 'owner')!
		run([...prefix, '-D_GNU_SOURCE', '-DVINIX_V_RUNTIME', '-I', join(root, include)!, '-c',
			core, '-o', obj], null())!
		command.insert(command.index('-o'), obj)
	}
	run(command, null())!
}

fn tar_body(id string, rootfs string) ! {
	method(id, 'add', [p(rootfs)], {
		'arcname': v(ah.Value('.'))
	}, 'value')!
}

fn archive(path string, rootfs string) ! {
	format := call('tarfile.USTAR_FORMAT')!
	id := invoke('tarfile.open', [p(path), v(ah.Value('w'))], {
		'format': v(format)
	}, 'owner')!.text()
	entered := method(id, '__enter__', [], {}, 'owner')!.text()
	mut failed := false
	mut failure := IError(none)
	tar_body(entered, rootfs) or {
		failed = true
		failure = err
	}
	detail := if failed { error_detail(failure) } else { null() }
	suppressed := flag(callback('context_exit', {
		'id':    ah.Value(id)
		'error': detail
	})!)
	if failed && !suppressed { return failure }
}

fn main_policy(args map[string]ah.Value) !ah.Value {
	root := ah.field(args, 'root').text()
	arch := ah.field(args, 'arch').text()
	if flag(call('operator.le', owner('timeout'), v(ah.Value(0)))!) || ah.field(args, 'expect').items().any(it.text() == '') {
		parser_error('timeout and expected verdicts must be nonempty/positive')!
	}
	state_arg := ah.field(args, 'state_dir')
	state_text := if state_arg is json2.Null {
		invoke('tempfile.mkdtemp', [], {
			'prefix': v(ah.Value('vinix-kernel-gaps-'))
		}, 'value')!.text()
	} else {
		state_arg.text()
	}
	state := resolve(state_text)!
	mkdir(state)!
	kernel := join(resolve(ah.field(args, 'kernel_dir').text())!, 'bin/vinix')!
	if !flag(path_method(kernel, 'is_file', [], {}, 'value')!) {
		parser_error('Build the requested kernel first: ' + kernel)!
	}
	init := join(state, 'init')!
	prebuilt_arg := ah.field(args, 'prebuilt_init')
	if prebuilt_arg !is json2.Null {
		prebuilt := resolve(prebuilt_arg.text())!
		header := path_method(prebuilt, 'read_bytes', [], {}, 'bytes')!.text()
		// read_bytes() is deliberately not shortened before the library call.
		valid := header.len >= 12 && header[..12] == '7f454c460201'
		machine_hex := if header.len > 36 {
			header[36..if header.len < 40 { header.len } else { 40 }]
		} else {
			''
		}
		machine := call('builtins.int.from_bytes', b(machine_hex), v(ah.Value('little')))!
		if !valid || integer(machine) != if arch == 'aarch64' { 183 } else { 62 } {
			parser_error('prebuilt init must be a little-endian ELF64 for the requested architecture')!
		}
		if prebuilt != resolve(init)! { call('shutil.copyfile', p(prebuilt), p(init))! }
		path_method(init, 'chmod', [v(ah.Value(0o755))], {}, 'value')!
	} else {
		compile_init(args, root, state, init, arch)!
	}
	rootfs := join(state, 'rootfs')!
	for directory in ['sbin', 'dev', 'proc', 'sys', 'tmp', 'root'] {
		mkdir(join(rootfs, directory)!)!
	}
	call('shutil.copy2', p(init), p(join(rootfs, 'sbin/init')!))!
	initramfs := join(state, 'initramfs.tar')!
	archive(initramfs, rootfs)!
	mut env := call('os.environ.copy')!.object()
	mut command := []string{}
	if arch == 'aarch64' {
		env['VINIX_KERNEL_DIR'] = ah.Value(resolve(ah.field(args, 'kernel_dir').text())!)
		env['VINIX_INITRAMFS'] = ah.Value(initramfs)
		env['VINIX_BOOT_DISK'] = ah.Value(join(state, 'boot.img')!)
		env['VINIX_EFIVARS'] = ah.Value(join(state, 'efivars.fd')!)
		env['VINIX_QEMU_HOST_SOURCE'] = ah.Value('0')
		env['VINIX_QEMU_PACKAGE_STORE'] = ah.Value(join(state, 'packages.tar')!)
		env['VINIX_QEMU_AUDIO'] = ah.Value('off')
		env['VINIX_QEMU_EXTRA'] = ah.Value('-qmp unix:' + join(state, 'qmp.sock')! + ',server=on,wait=off')
		if flag(ah.field(args, 'no_network')) { env['VINIX_QEMU_NETWORK'] = ah.Value('0') }
		if call('platform.system')!.text() != 'Darwin' && 'USE_TCG' !in env {
			env['USE_TCG'] = ah.Value('1')
		}
		command = [join(root, 'scripts/run-aarch64.sh')!, '--no-build', '--serial', '--no-persist',
			'--mem=1024', '--guest-init=' + init]
	} else {
		iso := join(state, 'test.iso')!
		iso_build := join(state, 'iso-build')!
		cache := join(root, 'build-amd64-iso/limine')!
		if flag(path_method(cache, 'is_dir', [], {}, 'value')!) && !flag(path_method(join(iso_build, 'limine')!, 'exists', [], {}, 'value')!) {
			mkdir(iso_build)!
			call('shutil.copytree', p(cache), p(join(iso_build, 'limine')!))!
		}
		env['VINIX_AMD64_KERNEL'] = ah.Value(kernel)
		env['VINIX_AMD64_INITRAMFS'] = ah.Value(initramfs)
		env['VINIX_AMD64_ISO'] = ah.Value(iso)
		env['VINIX_AMD64_ISO_BUILD_DIR'] = ah.Value(iso_build)
		run([join(root, 'build-support/build-amd64-iso.sh')!], ah.Value(env))!
		qemu := call('shutil.which', v(ah.Value(environment('VINIX_QEMU_X86_64', 'qemu-system-x86_64')!)))!
		if qemu is json2.Null || qemu.text() == '' {
			parser_error('qemu-system-x86_64 is missing')!
		}
		base := path_method(path_method(qemu.text(), 'parent', [], {}, 'path')!.text(), 'parent', [], {}, 'path')!.text()
		firmware := invoke('Path', [v(ah.Value(environment('VINIX_OVMF_CODE', join(base, 'share/qemu/edk2-x86_64-code.fd')!)!))], {}, 'path')!.text()
		command = [qemu.text(), '-machine', 'q35,smm=off', '-accel', 'tcg', '-cpu', 'max', '-m',
			'1024', '-smp', '2', '-drive', 'if=pflash,format=raw,unit=0,readonly=on,file=' + firmware,
			'-cdrom', iso, '-display', 'none', '-monitor', 'none', '-qmp',
			'unix:' + join(state, 'qmp.sock')! + ',server=on,wait=off', '-serial', 'mon:stdio',
			'-no-reboot']
		if flag(ah.field(args, 'no_network')) { command << ['-nic', 'none'] }
	}
	print_text('Guest artifacts: ' + state)!
	policy := callback('main_policy', {})!.text()
	return callback('boot', {
		'command': ah.Value(command.map(ah.Value(it)))
		'env':     ah.Value(env)
		'state':   ah.Value(state)
		'policy':  ah.Value(policy)
	})!
}

fn hypervisor(args map[string]ah.Value) !ah.Value {
	root := ah.field(args, 'root').text()
	mut command := [ah.field(args, 'python').text(), join(root, 'tests/kernel-gaps/run.py')!, '--source',
		join(root, 'tests/hypervisor/guestfixture/core.v')!, '--arch', ah.field(args, 'arch').text(),
		'--kernel-dir', ah.field(args, 'kernel_dir').text(), '--timeout',
		ah.field(args, 'timeout').text(), '--expect', 'HYPERVISOR GUEST PASS', '--fail',
		'HYPERVISOR FAIL:']
	if ah.field(args, 'state_dir') !is json2.Null {
		command << ['--state-dir', ah.field(args, 'state_dir').text()]
	}
	if flag(ah.field(args, 'require_vmx')) { command << ['--expect', 'HYPERVISOR EXECUTION PASS'] }
	return call('subprocess.call', v(ah.Value(command.map(ah.Value(it)))))!
}

fn public_policy() !ah.Value {
	failures := callback('unpack', {
		'owner': ah.Value('failures')
	})!.text()
	rejected := invoke('operator.add', [
		v(ah.Value([ah.Value('FATAL EXCEPTION'), ah.Value('FAIL:')])),
		owner(failures),
	], {}, 'owner')!.text()
	panic_mode := flag(call('builtins.bool', owner('panic'))!)
	if panic_mode {
		expected := callback('unpack', {
			'owner': ah.Value('expected')
		})!.text()
		positive := invoke('operator.add', [v(ah.Value([ah.Value('KERNEL PANIC')])), owner(expected)], {}, 'owner')!.text()
		negative := method(rejected, '__iadd__', [v(ah.Value([
			ah.Value('USERSPACE ENTERED'),
			ah.Value('INIT ENTERED'),
			ah.Value('Entering userspace'),
		]))], {}, 'owner')!.text()
		return ah.Value([ah.Value({
			'owner_result': ah.Value(positive)
		}), ah.Value({
			'owner_result': ah.Value(negative)
		})])
	}
	expected := method('expected', 'copy', [], {}, 'owner')!.text()
	negative := invoke('operator.add', [v(ah.Value([ah.Value('KERNEL PANIC')])), owner(rejected)], {}, 'owner')!.text()
	return ah.Value([ah.Value({
		'owner_result': ah.Value(expected)
	}), ah.Value({
		'owner_result': ah.Value(negative)
	})])
}

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	args := ah.field(row, 'arguments').object()
	return match ah.field(row, 'operation').text() {
		'main' { main_policy(args)! }
		'policy' { public_policy()! }
		'boot' { boot(args)! }
		'stop' {
			stop(ah.field(args, 'pid'), ah.field(args, 'master'), ah.field(args, 'state').text(), true)!
			null()
		}
		'drain' {
			drain(ah.field(args, 'master'))!
			null()
		}
		'hypervisor' { hypervisor(args)! }
		else { return error('unknown isolated guest operation') }
	}
}
