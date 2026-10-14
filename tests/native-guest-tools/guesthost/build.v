// SPDX-License-Identifier: GPL-2.0-or-later
module guesthost

import fixturehost
import hosttest
import os
import policyhost

pub fn root() string { return hosttest.root() }

fn resolve(path string) !string { return hosttest.module_resolve(path)! }

fn run(command []string) ! { policyhost.inherited(command)! }

pub fn compile_module(module_path string, object string, arch string, flags []string) ! {
	source := object.all_before_last('.') + '.c'
	run([root() + '/build-support/compile-v-module', resolve(module_path)!, resolve(source)!, '--arch',
		if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-d', 'nofloat'])!
	mut options := flags.filter(it !in ['-static', '-nostdlib', '-pie']
		&& !it.starts_with('-L') && !it.starts_with('-l') && !it.starts_with('-Wl,')
		&& !it.starts_with('-fuse-ld='))
	options << ['-Wno-unused-function', '-Wno-unused-parameter', '-fPIC', '-I', resolve(module_path)!,
		'-c', source, '-o', object]
	run(options)!
}

pub fn compile_init(source string, state string, arch string, fixed_sysroot bool) !string {
	serial := state + '/serial.o'
	native := source.ends_with('.v')
	fixture := if native { state + '/fixture.o' } else { source }
	mut flags := []string{}
	mut link := []string{}
	if arch == 'aarch64' {
		sdk := if fixed_sysroot {
			root() + '/build-aarch64-userland/sysroot'
		} else {
			os.getenv_opt('VINIX_AARCH64_SYSROOT') or { root() + '/build-aarch64-userland/sysroot' }
		}
		flags = [os.getenv_opt('CC') or { 'clang' }, '--target=aarch64-linux-musl', '--sysroot=' + sdk,
			'-static', '-pthread', '-O2', '-fno-stack-protector', '-Wall', '-Wextra', '-Werror']
		link = ['-L' + sdk + '/lib', '-fuse-ld=lld']
	} else {
		flags = [os.getenv_opt('CC_AMD64') or { 'x86_64-linux-musl-gcc' }, '-static', '-pthread',
			'-O2', '-Wall', '-Wextra', '-Werror']
	}
	if native { flags.insert(1, ['-D_GNU_SOURCE', '-fno-strict-aliasing', '-I', os.dir(source)]) }
	compile_module(root() + '/tests/kernel-gaps/serialcore', serial, arch, flags)!
	if native { compile_module(os.dir(source), fixture, arch, flags)! }
	mut objects := [serial, fixture]
	tool := if source == root() + '/tests/application-sandbox/guestfixture/core.v' {
		'sandbox'
	} else if source == root() + '/tests/security-audit/collectorguestfixture/core.v' {
		'audit'
	} else {
		''
	}
	if tool != '' {
		core := state + '/' + tool + '-core.c'
		object := state + '/' + tool + '-core.o'
		security_core(tool, core, arch)!
		run([...flags, '-D_GNU_SOURCE', '-DVINIX_V_RUNTIME', '-I', root() +
			if tool == 'sandbox' { '/tools/sandbox' } else { '/tools/security-audit' }, '-c', core,
			'-o', object])!
		objects << object
	}
	init := state + '/init'
	run([...flags, ...objects, ...link, '-o', init])!
	return init
}

fn security_core(tool string, destination string, arch string) ! {
	module_name := if tool == 'sandbox' { 'sandboxcore' } else { 'auditcore' }
	source := root() + if tool == 'sandbox' {
		'/tools/sandbox/core'
	} else {
		'/tools/security-audit/core'
	}
	work := hosttest.work_dir('', 'vinix-security-v-')!
	defer { hosttest.remove_work_dir(work) or { eprintln(err.msg()) } }
	hosttest.module_copy_tree(source, work + '/' + module_name)!
	hosttest.module_write_text(work + '/v.mod', "Module { name: 'security_core' }\n")!
	hosttest.module_write_text(work + '/entry.v', 'module main\nimport ' + module_name + ' as _\n')!
	v := policyhost.capture(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v',
		root()])!
	mut env := policyhost.environment()
	env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	fixturehost.inherited_command_environment_preferred([v, '-enable-globals', '-shared', '-no-builtin',
		'-no-closures', '-os', 'vinix', '-arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' },
		'-target-libc-headers', '-nofloat', '-gc', 'none', '-manualfree', '-o', destination, '-d',
		'security_no_main', work],
		env, policyhost.caller_arch())!
	checks := if tool == 'sandbox' {
		'\n_Static_assert(sizeof(struct sb_cap_data) == 12, "native sandbox ABI");' +
			'\n_Static_assert(sizeof(sandboxcore__CapHeader) == 8, "native sandbox ABI");' +
			'\n_Static_assert(SB_MAX_PATHS == 127, "native sandbox ABI");' +
			'\n_Static_assert(SB_MAX_ENV == 64, "native sandbox ABI");'
	} else {
		'\n_Static_assert(sizeof(sig_atomic_t) == sizeof(int), "native audit ABI");' +
			'\n_Static_assert(sizeof(struct record) == 120, "native audit ABI");' +
			'\n_Static_assert(PATH_MAX <= 4096, "bounded audit path ABI");'
	}
	hosttest.module_write_text(destination, '#pragma GCC diagnostic ignored "-Wunused-function"\n' +
		'#pragma GCC diagnostic ignored "-Wunused-label"\n#pragma GCC diagnostic ignored "-Wunused-parameter"\n' +
		hosttest.module_read_text(destination)! + checks + '\n')!
}

pub struct Launch {
pub:
	command []string
	env     map[string]string
}

pub fn image(init string, state string) !string {
	rootfs := state + '/rootfs'
	for name in ['sbin', 'dev', 'proc', 'sys', 'tmp', 'root'] { os.mkdir_all(rootfs + '/' + name)! }
	os.cp(init, rootfs + '/sbin/init')!
	os.chmod(rootfs + '/sbin/init', 0o755)!
	archive := state + '/initramfs.tar'
	mut env := policyhost.environment()
	env['COPYFILE_DISABLE'] = '1'
	fixturehost.inherited_command_environment_preferred(['tar', '--format=ustar', '-cf', archive,
		'-C', rootfs, '.'], env, policyhost.caller_arch())!
	return archive
}

pub fn launch(init string, archive string, state string, kernel_dir string, arch string, no_network bool) !Launch {
	return launch_at(init, archive, state, kernel_dir, arch, no_network, root())!
}

pub fn launch_from(init string, archive string, state string, kernel_dir string, arch string, no_network bool, runner_root string) !Launch {
	return launch_at(init, archive, state, kernel_dir, arch, no_network, resolve(runner_root)!)!
}

fn launch_at(_init string, archive string, state string, kernel_dir string, arch string, no_network bool, repo string) !Launch {
	mut env := policyhost.environment()
	kernel := kernel_dir + '/bin/vinix'
	if arch == 'aarch64' {
		// The desktop launcher starts a Python package server even for a bare
		// test init. Build this disposable ISO and own QEMU directly instead.
		iso := state + '/test.iso'
		build := state + '/iso-build'
		cache := repo + '/build-aarch64-iso/limine'
		if os.is_dir(cache) && !os.exists(build + '/limine') {
			os.mkdir_all(build)!
			os.cp_all(cache, build + '/limine', false)!
		}
		env['VINIX_AARCH64_KERNEL'] = kernel
		env['VINIX_AARCH64_INITRAMFS'] = archive
		env['VINIX_AARCH64_ISO'] = iso
		env['VINIX_AARCH64_ISO_BUILD_DIR'] = build
		if policyhost.commands_owned() {
			policyhost.owned_inherited_environment([repo + '/build-support/build-aarch64-iso.sh'], env, policyhost.caller_arch(), '')!
		} else {
			fixturehost.inherited_command_environment_preferred([repo + '/build-support/build-aarch64-iso.sh'], env, policyhost.caller_arch())!
		}
		qemu := os.find_abs_path_of_executable(os.getenv_opt('VINIX_QEMU_BIN') or { 'qemu-system-aarch64' })!
		share := os.dir(os.dir(qemu)) + '/share/qemu'
		code := os.getenv_opt('VINIX_OVMF_CODE') or { share + '/edk2-aarch64-code.fd' }
		variables := os.getenv_opt('VINIX_OVMF_VARS') or { share + '/edk2-arm-vars.fd' }
		if !os.exists(state + '/efivars.fd') { copy_firmware_variables(variables, state + '/efivars.fd')! }
		mut accel := ['-accel', 'tcg', '-cpu', os.getenv_opt('VINIX_QEMU_CPU') or { 'max' }]
		$if macos {
			if os.getenv('USE_TCG') != '1' { accel = ['-accel', 'hvf', '-cpu', 'host'] }
		}
		mut command := [qemu, '-machine', 'virt,gic-version=3', ...accel, '-m', '1024',
			'-smp', os.getenv_opt('VINIX_QEMU_SMP') or { '4' }, '-object', 'rng-random,filename=/dev/urandom,id=vinix-rng',
			'-device', 'virtio-rng-device,rng=vinix-rng', '-drive', 'if=pflash,format=raw,readonly=on,file=' + code,
			'-drive', 'if=pflash,format=raw,file=' + state + '/efivars.fd', '-drive',
			'if=none,format=raw,readonly=on,file=' + iso + ',id=guest-iso', '-device', 'virtio-blk-device,drive=guest-iso',
			'-device', 'virtio-keyboard-device', '-device', 'virtio-tablet-device', '-device', 'ramfb',
			'-display', 'none', '-serial', 'mon:stdio', '-qmp', 'unix:' + state + '/qmp.sock,server=on,wait=off', '-no-reboot']
		if !no_network && os.getenv('VINIX_QEMU_NETWORK') != '0' {
			command << ['-netdev', 'user,id=net0', '-device', 'virtio-net-device,netdev=net0,mac=52:54:00:12:34:56']
		}
		return Launch{command, env}
	}
	iso := state + '/test.iso'
	iso_build := state + '/iso-build'
	cache := repo + '/build-amd64-iso/limine'
	if os.is_dir(cache) && !os.exists(iso_build + '/limine') {
		os.mkdir_all(iso_build)!
		os.cp_all(cache, iso_build + '/limine', false)!
	}
	env['VINIX_AMD64_KERNEL'] = kernel
	env['VINIX_AMD64_INITRAMFS'] = archive
	env['VINIX_AMD64_ISO'] = iso
	env['VINIX_AMD64_ISO_BUILD_DIR'] = iso_build
	if policyhost.commands_owned() {
		policyhost.owned_inherited_environment([repo + '/build-support/build-amd64-iso.sh'], env, policyhost.caller_arch(), '')!
	} else {
		fixturehost.inherited_command_environment_preferred([repo + '/build-support/build-amd64-iso.sh'], env, policyhost.caller_arch())!
	}
	qemu := os.find_abs_path_of_executable(os.getenv_opt('VINIX_QEMU_X86_64') or { 'qemu-system-x86_64' })!
	firmware := os.getenv_opt('VINIX_OVMF_CODE') or { os.dir(os.dir(qemu)) + '/share/qemu/edk2-x86_64-code.fd' }
	mut command := [qemu, '-machine', 'q35,smm=off', '-accel', 'tcg', '-cpu', 'max', '-m', '1024',
		'-smp', '2', '-drive', 'if=pflash,format=raw,unit=0,readonly=on,file=' + firmware, '-cdrom',
		iso, '-display', 'none', '-monitor', 'none', '-qmp',
		'unix:' + state + '/qmp.sock,server=on,wait=off', '-serial', 'mon:stdio', '-no-reboot']
	if no_network { command << ['-nic', 'none'] }
	return Launch{command, env}
}

pub fn guest(source string, prebuilt string, state_arg string, kernel_arg string, arch string,
	expected []string, failures []string, panic_mode bool, no_network bool, timeout int) !int {
	return guest_with_cancel(source, prebuilt, state_arg, kernel_arg, arch, expected, failures, panic_mode, no_network, timeout, unsafe { nil })!
}

pub fn guest_with_cancel(source string, prebuilt string, state_arg string, kernel_arg string, arch string,
	expected []string, failures []string, panic_mode bool, no_network bool, timeout int, cancelled fn () bool) !int {
	if cancelled != unsafe { nil } && cancelled() { return error('Guest run interrupted') }
	if timeout <= 0 || expected.len == 0 || expected.any(it == '') {
		return error('timeout and expected verdicts must be nonempty/positive')
	}
	state := if state_arg == '' {
		hosttest.work_dir('', 'vinix-kernel-gaps-')!
	} else {
		resolve(state_arg)!
	}
	os.mkdir_all(state)!
	kernel_dir := resolve(kernel_arg)!
	if !os.is_file(kernel_dir + '/bin/vinix') {
		return error('Build the requested kernel first: ' + kernel_dir)
	}
	init := if prebuilt == '' {
		compile_init(resolve(source)!, state, arch, false)!
	} else {
		binary := resolve(prebuilt)!
		header := os.read_bytes(binary)!
		valid := header.len >= 20 && header[..6] == [u8(0x7f), `E`, `L`, `F`, 2, 1]
		machine := if header.len >= 20 { int(header[18]) + (int(header[19]) << 8) } else { 0 }
		if !valid || machine != if arch == 'aarch64' { 183 } else { 62 } {
			return error('prebuilt init must be a little-endian ELF64 for the requested architecture')
		}
		if binary != state + '/init' { os.cp(binary, state + '/init')! }
		os.chmod(state + '/init', 0o755)!
		state + '/init'
	}
	archive := image(init, state)!
	if cancelled != unsafe { nil } && cancelled() { return error('Guest run interrupted') }
	configured := launch(init, archive, state, kernel_dir, arch, no_network)!
	if cancelled != unsafe { nil } && cancelled() { return error('Guest run interrupted') }
	positive, negative := verdict_policy(expected, failures, panic_mode)
	println('Guest artifacts: ' + state)
	return boot_from_cancelled(configured.command, configured.env, state, positive, negative, timeout, true, '', cancelled)!
}
